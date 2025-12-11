defmodule Events.Infra.Scheduler.Strategies.CircuitBreaker.Default do
  @moduledoc """
  Default three-state circuit breaker implementation.

  Implements the standard circuit breaker pattern with closed, open, and
  half-open states.

  ## States

  - **Closed**: Normal operation, jobs execute. Failure count tracked.
  - **Open**: Threshold exceeded, jobs skip immediately. Reset timer active.
  - **Half-Open**: Testing recovery, limited executions allowed.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        circuit_breaker_strategy: Events.Infra.Scheduler.Strategies.CircuitBreaker.Default,
        circuit_breaker_opts: [
          failure_threshold: 5,       # Failures before opening
          success_threshold: 2,       # Successes to close from half-open
          reset_timeout: {30, :seconds},  # Time before half-open
          half_open_limit: 3          # Max concurrent in half-open
        ]

  ## Telemetry Events

  - `[:scheduler, :circuit_breaker, :state_change]` - State transitions
  - `[:scheduler, :circuit_breaker, :trip]` - Circuit opened
  - `[:scheduler, :circuit_breaker, :reset]` - Circuit closed
  """

  @behaviour Events.Infra.Scheduler.Strategies.CircuitBreakerStrategy

  require Logger

  alias Events.Infra.Scheduler.Config

  @default_failure_threshold 5
  @default_success_threshold 2
  @default_reset_timeout 30_000
  @default_half_open_limit 3

  defstruct [
    :name,
    :failure_threshold,
    :success_threshold,
    :reset_timeout,
    :half_open_limit,
    :reset_at,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    half_open_count: 0,
    last_failure_at: nil,
    last_error: nil,
    total_failures: 0,
    total_successes: 0
  ]

  @type circuit :: %__MODULE__{}

  # ============================================
  # Behaviour Implementation
  # ============================================

  @impl true
  def init(opts) do
    circuits = build_circuits_from_opts(opts)
    {:ok, %{circuits: circuits, opts: opts}}
  end

  @impl true
  def allow?(circuit_name, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        # Unknown circuit, allow by default
        {:ok, state}

      circuit ->
        # Check if reset timeout has elapsed for open circuits
        circuit = maybe_transition_to_half_open(circuit)
        state = put_circuit(state, circuit_name, circuit)

        case circuit.state do
          :closed ->
            {:ok, state}

          :open ->
            {:error, :circuit_open, state}

          :half_open ->
            if circuit.half_open_count < circuit.half_open_limit do
              new_circuit = %{circuit | half_open_count: circuit.half_open_count + 1}
              {:ok, put_circuit(state, circuit_name, new_circuit)}
            else
              {:error, :circuit_open, state}
            end
        end
    end
  end

  @impl true
  def record_success(circuit_name, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:ok, state}

      %{state: :closed} = circuit ->
        new_circuit = %{circuit | total_successes: circuit.total_successes + 1}
        {:ok, put_circuit(state, circuit_name, new_circuit)}

      %{state: :half_open} = circuit ->
        new_count = circuit.success_count + 1

        new_circuit = %{
          circuit
          | success_count: new_count,
            total_successes: circuit.total_successes + 1
        }

        new_circuit =
          if new_count >= circuit.success_threshold do
            emit_reset(circuit_name)
            transition_to(:closed, new_circuit)
          else
            new_circuit
          end

        {:ok, put_circuit(state, circuit_name, new_circuit)}

      %{state: :open} = circuit ->
        # Ignore successes while open
        {:ok, put_circuit(state, circuit_name, circuit)}
    end
  end

  @impl true
  def record_failure(circuit_name, error, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:ok, state}

      %{state: :closed} = circuit ->
        new_count = circuit.failure_count + 1

        new_circuit = %{
          circuit
          | failure_count: new_count,
            total_failures: circuit.total_failures + 1,
            last_failure_at: DateTime.utc_now(),
            last_error: error
        }

        new_circuit =
          if new_count >= circuit.failure_threshold do
            reset_at = DateTime.add(DateTime.utc_now(), circuit.reset_timeout, :millisecond)
            emit_trip(circuit_name, new_count, error)
            transition_to(:open, %{new_circuit | reset_at: reset_at})
          else
            new_circuit
          end

        {:ok, put_circuit(state, circuit_name, new_circuit)}

      %{state: :half_open} = circuit ->
        # Single failure in half-open reopens
        reset_at = DateTime.add(DateTime.utc_now(), circuit.reset_timeout, :millisecond)

        new_circuit = %{
          circuit
          | total_failures: circuit.total_failures + 1,
            last_failure_at: DateTime.utc_now(),
            last_error: error,
            reset_at: reset_at
        }

        emit_trip(circuit_name, circuit.failure_threshold, error)
        new_circuit = transition_to(:open, new_circuit)
        {:ok, put_circuit(state, circuit_name, new_circuit)}

      %{state: :open} = circuit ->
        # Ignore failures while open
        {:ok, put_circuit(state, circuit_name, circuit)}
    end
  end

  @impl true
  def get_state(circuit_name, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        nil

      circuit ->
        %{
          name: circuit.name,
          state: circuit.state,
          failure_count: circuit.failure_count,
          success_count: circuit.success_count,
          failure_threshold: circuit.failure_threshold,
          success_threshold: circuit.success_threshold,
          total_failures: circuit.total_failures,
          total_successes: circuit.total_successes,
          last_failure_at: circuit.last_failure_at,
          last_error: circuit.last_error,
          reset_at: circuit.reset_at
        }
    end
  end

  @impl true
  def get_all_states(state) do
    state.circuits
    |> Map.new(fn {name, circuit} ->
      {name,
       %{
         state: circuit.state,
         failure_count: circuit.failure_count,
         success_count: circuit.success_count,
         total_failures: circuit.total_failures,
         total_successes: circuit.total_successes
       }}
    end)
  end

  @impl true
  def reset(circuit_name, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:ok, state}

      circuit ->
        emit_reset(circuit_name)
        new_circuit = transition_to(:closed, %{circuit | reset_at: nil})
        {:ok, put_circuit(state, circuit_name, new_circuit)}
    end
  end

  @impl true
  def register(circuit_name, opts, state) do
    circuit = build_circuit(circuit_name, opts)
    {:ok, put_circuit(state, circuit_name, circuit)}
  end

  @impl true
  def tick(state) do
    # Check for circuits that need to transition to half-open
    updated_circuits =
      state.circuits
      |> Enum.map(fn {name, circuit} ->
        {name, maybe_transition_to_half_open(circuit)}
      end)
      |> Map.new()

    {:ok, %{state | circuits: updated_circuits}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_circuits_from_opts(opts) do
    circuits = Keyword.get(opts, :circuits, [])

    Map.new(circuits, fn {name, circuit_opts} ->
      {name, build_circuit(name, circuit_opts)}
    end)
  end

  defp build_circuit(name, opts) do
    %__MODULE__{
      name: name,
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      success_threshold: Keyword.get(opts, :success_threshold, @default_success_threshold),
      reset_timeout: normalize_timeout(Keyword.get(opts, :reset_timeout, @default_reset_timeout)),
      half_open_limit: Keyword.get(opts, :half_open_limit, @default_half_open_limit)
    }
  end

  defp normalize_timeout(ms) when is_integer(ms), do: ms
  defp normalize_timeout({n, unit}), do: Config.to_ms({n, unit})

  defp get_circuit(state, name), do: Map.get(state.circuits, name)

  defp put_circuit(state, name, circuit) do
    %{state | circuits: Map.put(state.circuits, name, circuit)}
  end

  defp maybe_transition_to_half_open(%{state: :open, reset_at: reset_at} = circuit)
       when not is_nil(reset_at) do
    if DateTime.compare(DateTime.utc_now(), reset_at) in [:gt, :eq] do
      transition_to(:half_open, %{circuit | reset_at: nil, half_open_count: 0})
    else
      circuit
    end
  end

  defp maybe_transition_to_half_open(circuit), do: circuit

  defp transition_to(new_state, circuit) do
    emit_state_change(circuit.name, circuit.state, new_state)

    Logger.info(
      "[CircuitBreaker.Default] #{circuit.name}: #{circuit.state} -> #{new_state} " <>
        "(failures: #{circuit.failure_count}, successes: #{circuit.success_count})"
    )

    %{circuit | state: new_state, failure_count: 0, success_count: 0}
  end

  # ============================================
  # Telemetry
  # ============================================

  defp emit_state_change(circuit_name, from_state, to_state) do
    :telemetry.execute(
      [:scheduler, :circuit_breaker, :state_change],
      %{system_time: System.system_time()},
      %{circuit: circuit_name, from: from_state, to: to_state}
    )
  end

  defp emit_trip(circuit_name, failure_count, error) do
    :telemetry.execute(
      [:scheduler, :circuit_breaker, :trip],
      %{failure_count: failure_count},
      %{circuit: circuit_name, error: error}
    )
  end

  defp emit_reset(circuit_name) do
    :telemetry.execute(
      [:scheduler, :circuit_breaker, :reset],
      %{system_time: System.system_time()},
      %{circuit: circuit_name}
    )
  end
end
