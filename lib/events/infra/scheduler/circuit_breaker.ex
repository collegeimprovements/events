defmodule Events.Infra.Scheduler.CircuitBreaker do
  @moduledoc """
  Circuit breaker for scheduler jobs.

  Protects against cascading failures by tracking job failures per circuit
  and preventing execution when failure thresholds are exceeded.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        circuit_breakers: [
          external_api: [
            failure_threshold: 5,
            success_threshold: 2,
            reset_timeout: {30, :seconds}
          ],
          payment_gateway: [
            failure_threshold: 3,
            reset_timeout: {1, :minute}
          ]
        ]

  ## Usage with Decorator

      @decorate scheduled(
        cron: "0 * * * *",
        circuit_breaker: :external_api
      )
      def sync_data do
        ExternalApi.sync()
      end

  ## Usage with Worker

      defmodule MyApp.PaymentWorker do
        use Events.Infra.Scheduler.Worker

        @impl true
        def schedule do
          [
            cron: "*/5 * * * *",
            circuit_breaker: :payment_gateway,
            circuit_breaker_opts: [failure_threshold: 3]
          ]
        end
      end

  ## Circuit States

  - **Closed**: Normal operation, jobs execute
  - **Open**: Threshold exceeded, jobs skip immediately
  - **Half-Open**: Testing recovery, limited executions allowed

  ## Telemetry Events

  - `[:scheduler, :circuit_breaker, :state_change]` - State transitions
  - `[:scheduler, :circuit_breaker, :trip]` - Circuit opened due to failures
  - `[:scheduler, :circuit_breaker, :reset]` - Circuit closed after recovery
  - `[:scheduler, :circuit_breaker, :reject]` - Job rejected (circuit open)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.Config
  alias Events.Protocols.Recoverable

  @type state :: :closed | :open | :half_open
  @type circuit_name :: atom()

  @type circuit_opts :: [
          failure_threshold: pos_integer(),
          success_threshold: pos_integer(),
          reset_timeout: pos_integer() | {pos_integer(), atom()},
          half_open_limit: pos_integer()
        ]

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
    :reset_timer,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    half_open_count: 0,
    last_failure_at: nil,
    last_error: nil,
    total_failures: 0,
    total_successes: 0
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts the circuit breaker registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks if a circuit allows execution.

  Returns `:ok` if the circuit is closed or half-open (with capacity).
  Returns `{:error, :circuit_open}` if the circuit is open.
  """
  @spec allow?(circuit_name()) :: :ok | {:error, :circuit_open}
  def allow?(circuit_name) do
    GenServer.call(__MODULE__, {:allow?, circuit_name})
  end

  @doc """
  Wraps job execution with circuit breaker protection.

  If the circuit is open, returns `{:error, :circuit_open}` without executing.
  Otherwise, executes the function and records success/failure.
  """
  @spec call(circuit_name(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def call(circuit_name, fun) when is_function(fun, 0) do
    case allow?(circuit_name) do
      :ok ->
        execute_with_tracking(circuit_name, fun)

      {:error, :circuit_open} = error ->
        emit_reject(circuit_name)
        error
    end
  end

  @doc """
  Records a successful execution for a circuit.
  """
  @spec record_success(circuit_name()) :: :ok
  def record_success(circuit_name) do
    GenServer.cast(__MODULE__, {:success, circuit_name})
  end

  @doc """
  Records a failed execution for a circuit.
  """
  @spec record_failure(circuit_name(), term()) :: :ok
  def record_failure(circuit_name, error \\ nil) do
    GenServer.cast(__MODULE__, {:failure, circuit_name, error})
  end

  @doc """
  Gets the current state of a circuit.
  """
  @spec get_state(circuit_name()) :: map() | nil
  def get_state(circuit_name) do
    GenServer.call(__MODULE__, {:get_state, circuit_name})
  end

  @doc """
  Gets all circuit states.
  """
  @spec get_all_states() :: map()
  def get_all_states do
    GenServer.call(__MODULE__, :get_all_states)
  end

  @doc """
  Resets a circuit to closed state.
  """
  @spec reset(circuit_name()) :: :ok
  def reset(circuit_name) do
    GenServer.call(__MODULE__, {:reset, circuit_name})
  end

  @doc """
  Registers a new circuit with options.
  """
  @spec register(circuit_name(), circuit_opts()) :: :ok
  def register(circuit_name, opts \\ []) do
    GenServer.call(__MODULE__, {:register, circuit_name, opts})
  end

  @doc """
  Returns child spec for supervision.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(opts) do
    circuits = build_circuits_from_config(opts)
    {:ok, %{circuits: circuits}}
  end

  @impl true
  def handle_call({:allow?, circuit_name}, _from, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        # Unknown circuit, allow by default
        {:reply, :ok, state}

      circuit ->
        case circuit.state do
          :closed ->
            {:reply, :ok, state}

          :open ->
            {:reply, {:error, :circuit_open}, state}

          :half_open ->
            if circuit.half_open_count < circuit.half_open_limit do
              new_circuit = %{circuit | half_open_count: circuit.half_open_count + 1}
              new_state = put_circuit(state, circuit_name, new_circuit)
              {:reply, :ok, new_state}
            else
              {:reply, {:error, :circuit_open}, state}
            end
        end
    end
  end

  def handle_call({:get_state, circuit_name}, _from, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:reply, nil, state}

      circuit ->
        reply = %{
          name: circuit.name,
          state: circuit.state,
          failure_count: circuit.failure_count,
          success_count: circuit.success_count,
          failure_threshold: circuit.failure_threshold,
          success_threshold: circuit.success_threshold,
          total_failures: circuit.total_failures,
          total_successes: circuit.total_successes,
          last_failure_at: circuit.last_failure_at,
          last_error: circuit.last_error
        }

        {:reply, reply, state}
    end
  end

  def handle_call(:get_all_states, _from, state) do
    reply =
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

    {:reply, reply, state}
  end

  def handle_call({:reset, circuit_name}, _from, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:reply, :ok, state}

      circuit ->
        cancel_timer(circuit.reset_timer)
        new_circuit = transition_to(:closed, %{circuit | reset_timer: nil})
        new_state = put_circuit(state, circuit_name, new_circuit)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:register, circuit_name, opts}, _from, state) do
    circuit = build_circuit(circuit_name, opts)
    new_state = put_circuit(state, circuit_name, circuit)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:success, circuit_name}, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:noreply, state}

      %{state: :closed} = circuit ->
        new_circuit = %{circuit | total_successes: circuit.total_successes + 1}
        {:noreply, put_circuit(state, circuit_name, new_circuit)}

      %{state: :half_open} = circuit ->
        new_count = circuit.success_count + 1

        new_circuit = %{
          circuit
          | success_count: new_count,
            total_successes: circuit.total_successes + 1
        }

        new_circuit =
          if new_count >= circuit.success_threshold do
            cancel_timer(circuit.reset_timer)
            transition_to(:closed, %{new_circuit | reset_timer: nil})
          else
            new_circuit
          end

        {:noreply, put_circuit(state, circuit_name, new_circuit)}

      %{state: :open} = circuit ->
        # Ignore successes while open
        {:noreply, put_circuit(state, circuit_name, circuit)}
    end
  end

  def handle_cast({:failure, circuit_name, error}, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:noreply, state}

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
            timer = schedule_reset(circuit.reset_timeout, circuit_name)
            emit_trip(circuit_name, new_count, error)
            transition_to(:open, %{new_circuit | reset_timer: timer})
          else
            new_circuit
          end

        {:noreply, put_circuit(state, circuit_name, new_circuit)}

      %{state: :half_open} = circuit ->
        # Single failure in half-open reopens
        timer = schedule_reset(circuit.reset_timeout, circuit_name)

        new_circuit = %{
          circuit
          | total_failures: circuit.total_failures + 1,
            last_failure_at: DateTime.utc_now(),
            last_error: error
        }

        emit_trip(circuit_name, circuit.failure_threshold, error)
        new_circuit = transition_to(:open, %{new_circuit | reset_timer: timer})
        {:noreply, put_circuit(state, circuit_name, new_circuit)}

      %{state: :open} = circuit ->
        # Ignore failures while open
        {:noreply, put_circuit(state, circuit_name, circuit)}
    end
  end

  @impl true
  def handle_info({:reset_timeout, circuit_name}, state) do
    case get_circuit(state, circuit_name) do
      nil ->
        {:noreply, state}

      %{state: :open} = circuit ->
        new_circuit = transition_to(:half_open, %{circuit | reset_timer: nil, half_open_count: 0})
        {:noreply, put_circuit(state, circuit_name, new_circuit)}

      circuit ->
        {:noreply, put_circuit(state, circuit_name, %{circuit | reset_timer: nil})}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_circuits_from_config(opts) do
    config_circuits = Keyword.get(opts, :circuits, [])

    # Also load from application config
    app_config = Config.get()
    app_circuits = Keyword.get(app_config, :circuit_breakers, [])

    all_circuits = Keyword.merge(app_circuits, config_circuits)

    Map.new(all_circuits, fn {name, circuit_opts} ->
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

  defp execute_with_tracking(circuit_name, fun) do
    try do
      result = fun.()

      case result do
        {:ok, _} ->
          record_success(circuit_name)
          result

        {:error, error} ->
          if should_trip_circuit?(error) do
            record_failure(circuit_name, error)
          end

          result

        :ok ->
          record_success(circuit_name)
          {:ok, :ok}

        other ->
          # Treat unexpected returns as success
          record_success(circuit_name)
          {:ok, other}
      end
    rescue
      error ->
        if should_trip_circuit?(error) do
          record_failure(circuit_name, error)
        end

        {:error, {:exception, error, __STACKTRACE__}}
    catch
      :exit, reason ->
        record_failure(circuit_name, {:exit, reason})
        {:error, {:exit, reason}}

      :throw, value ->
        record_failure(circuit_name, {:throw, value})
        {:error, {:throw, value}}
    end
  end

  defp should_trip_circuit?(error) do
    # Use the Recoverable protocol if implemented
    try do
      Recoverable.trips_circuit?(error)
    rescue
      _ -> true
    end
  end

  defp transition_to(new_state, circuit) do
    emit_state_change(circuit.name, circuit.state, new_state)

    Logger.info(
      "[Scheduler.CircuitBreaker] #{circuit.name}: #{circuit.state} -> #{new_state} " <>
        "(failures: #{circuit.failure_count}, successes: #{circuit.success_count})"
    )

    %{circuit | state: new_state, failure_count: 0, success_count: 0}
  end

  defp schedule_reset(timeout, circuit_name) do
    Process.send_after(self(), {:reset_timeout, circuit_name}, timeout)
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
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

  defp emit_reject(circuit_name) do
    :telemetry.execute(
      [:scheduler, :circuit_breaker, :reject],
      %{system_time: System.system_time()},
      %{circuit: circuit_name}
    )
  end
end
