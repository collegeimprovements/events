defmodule Events.APIClient.Middleware.CircuitBreaker do
  @moduledoc """
  Circuit breaker for protecting against cascading failures.

  Implements the circuit breaker pattern with three states:
  - **Closed**: Normal operation, requests pass through
  - **Open**: Failures exceeded threshold, requests fail immediately
  - **Half-Open**: Testing if service recovered, limited requests allowed

  ## Usage

      # Start a circuit breaker
      CircuitBreaker.start_link(name: :stripe_api)

      # Execute with circuit breaker protection
      CircuitBreaker.call(:stripe_api, fn ->
        Req.get("https://api.stripe.com/v1/customers")
      end)

  ## Configuration

  - `:failure_threshold` - Failures before opening (default: 5)
  - `:success_threshold` - Successes in half-open to close (default: 2)
  - `:reset_timeout` - Time before half-open in ms (default: 30000)
  - `:call_timeout` - Timeout for wrapped calls in ms (default: 10000)

  ## State Machine

      Closed  ──[failures >= threshold]──>  Open
         ^                                    │
         │                                    │
         └──[successes >= threshold]──  Half-Open  <──[reset_timeout]──┘

  ## Telemetry Events

  - `[:api_client, :circuit_breaker, :state_change]` - State transitions
  - `[:api_client, :circuit_breaker, :call]` - Call attempts
  """

  use GenServer
  require Logger

  alias Events.Recoverable

  @type state :: :closed | :open | :half_open
  @type name :: atom()

  @type opts :: [
          name: name(),
          failure_threshold: pos_integer(),
          success_threshold: pos_integer(),
          reset_timeout: pos_integer(),
          call_timeout: pos_integer()
        ]

  @default_failure_threshold 5
  @default_success_threshold 2
  @default_reset_timeout 30_000
  @default_call_timeout 10_000

  defstruct [
    :name,
    :failure_threshold,
    :success_threshold,
    :reset_timeout,
    :call_timeout,
    :reset_timer,
    state: :closed,
    failure_count: 0,
    success_count: 0,
    last_failure_time: nil
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts a circuit breaker process.

  ## Options

  - `:name` - Process name (required)
  - `:failure_threshold` - Failures before opening (default: 5)
  - `:success_threshold` - Successes in half-open to close (default: 2)
  - `:reset_timeout` - Time before half-open in ms (default: 30000)
  - `:call_timeout` - Timeout for wrapped calls in ms (default: 10000)

  ## Examples

      CircuitBreaker.start_link(name: :stripe_api)
      CircuitBreaker.start_link(name: :github_api, failure_threshold: 10)
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a function with circuit breaker protection.

  Returns `{:error, :circuit_open}` if the circuit is open.

  ## Examples

      CircuitBreaker.call(:stripe_api, fn ->
        Req.get("https://api.stripe.com/v1/customers")
      end)
  """
  @spec call(name(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def call(name, fun) when is_function(fun, 0) do
    case allow_request?(name) do
      :ok ->
        execute_call(name, fun)

      {:error, :circuit_open} = error ->
        error
    end
  end

  @doc """
  Checks if the circuit allows requests.

  ## Examples

      CircuitBreaker.allow_request?(:stripe_api)
      #=> :ok | {:error, :circuit_open}
  """
  @spec allow_request?(name()) :: :ok | {:error, :circuit_open}
  def allow_request?(name) do
    GenServer.call(name, :allow_request?)
  end

  @doc """
  Records a successful call.

  ## Examples

      CircuitBreaker.record_success(:stripe_api)
  """
  @spec record_success(name()) :: :ok
  def record_success(name) do
    GenServer.cast(name, :success)
  end

  @doc """
  Records a failed call.

  ## Examples

      CircuitBreaker.record_failure(:stripe_api)
  """
  @spec record_failure(name()) :: :ok
  def record_failure(name) do
    GenServer.cast(name, :failure)
  end

  @doc """
  Gets the current state of the circuit breaker.

  ## Examples

      CircuitBreaker.get_state(:stripe_api)
      #=> %{state: :closed, failure_count: 2, success_count: 0}
  """
  @spec get_state(name()) :: map()
  def get_state(name) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Resets the circuit breaker to closed state.

  ## Examples

      CircuitBreaker.reset(:stripe_api)
  """
  @spec reset(name()) :: :ok
  def reset(name) do
    GenServer.call(name, :reset)
  end

  @doc """
  Returns a child spec for supervision.

  ## Examples

      children = [
        {CircuitBreaker, name: :stripe_api},
        {CircuitBreaker, name: :github_api, failure_threshold: 10}
      ]
  """
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
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
    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      success_threshold: Keyword.get(opts, :success_threshold, @default_success_threshold),
      reset_timeout: Keyword.get(opts, :reset_timeout, @default_reset_timeout),
      call_timeout: Keyword.get(opts, :call_timeout, @default_call_timeout)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:allow_request?, _from, %{state: :closed} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:allow_request?, _from, %{state: :open} = state) do
    {:reply, {:error, :circuit_open}, state}
  end

  def handle_call(:allow_request?, _from, %{state: :half_open} = state) do
    # Allow limited requests in half-open state
    {:reply, :ok, state}
  end

  def handle_call(:get_state, _from, state) do
    reply = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      failure_threshold: state.failure_threshold,
      success_threshold: state.success_threshold
    }

    {:reply, reply, state}
  end

  def handle_call(:reset, _from, state) do
    cancel_timer(state.reset_timer)
    new_state = transition_to(:closed, %{state | reset_timer: nil})
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:success, %{state: :closed} = state) do
    {:noreply, state}
  end

  def handle_cast(:success, %{state: :half_open} = state) do
    new_count = state.success_count + 1

    new_state =
      if new_count >= state.success_threshold do
        cancel_timer(state.reset_timer)
        transition_to(:closed, %{state | reset_timer: nil})
      else
        %{state | success_count: new_count}
      end

    {:noreply, new_state}
  end

  def handle_cast(:success, %{state: :open} = state) do
    # Ignore successes while open (shouldn't happen normally)
    {:noreply, state}
  end

  def handle_cast(:failure, %{state: :closed} = state) do
    new_count = state.failure_count + 1

    new_state =
      if new_count >= state.failure_threshold do
        timer = schedule_reset(state.reset_timeout)
        transition_to(:open, %{state | reset_timer: timer, last_failure_time: now()})
      else
        %{state | failure_count: new_count, last_failure_time: now()}
      end

    {:noreply, new_state}
  end

  def handle_cast(:failure, %{state: :half_open} = state) do
    # Single failure in half-open reopens the circuit
    timer = schedule_reset(state.reset_timeout)
    new_state = transition_to(:open, %{state | reset_timer: timer, last_failure_time: now()})
    {:noreply, new_state}
  end

  def handle_cast(:failure, %{state: :open} = state) do
    # Ignore failures while open
    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_timeout, %{state: :open} = state) do
    new_state = transition_to(:half_open, %{state | reset_timer: nil})
    {:noreply, new_state}
  end

  def handle_info(:reset_timeout, state) do
    {:noreply, %{state | reset_timer: nil}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp execute_call(name, fun) do
    try do
      result = fun.()

      case result do
        {:ok, _} ->
          record_success(name)
          result

        {:error, error} ->
          # Only record failure if the error should trip the circuit
          # Validation errors, not found, etc. should not affect circuit state
          if Recoverable.trips_circuit?(error) do
            record_failure(name)
          end

          result
      end
    rescue
      error ->
        # Exceptions should trip the circuit (unexpected failures)
        if Recoverable.trips_circuit?(error) do
          record_failure(name)
        end

        {:error, error}
    catch
      :exit, reason ->
        record_failure(name)
        {:error, {:exit, reason}}
    end
  end

  defp transition_to(new_state, state) do
    emit_telemetry(:state_change, state.name, %{
      from: state.state,
      to: new_state,
      failure_count: state.failure_count
    })

    Logger.debug(
      "[CircuitBreaker] #{state.name}: #{state.state} -> #{new_state} (failures: #{state.failure_count})"
    )

    %{state | state: new_state, failure_count: 0, success_count: 0}
  end

  defp schedule_reset(timeout) do
    Process.send_after(self(), :reset_timeout, timeout)
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp now do
    System.monotonic_time(:millisecond)
  end

  defp emit_telemetry(event, name, measurements) do
    :telemetry.execute(
      [:api_client, :circuit_breaker, event],
      measurements,
      %{circuit_breaker: name}
    )
  end
end
