defmodule Events.Infra.Scheduler.CircuitBreaker do
  @moduledoc """
  Circuit breaker facade for scheduler jobs.

  This module provides backward-compatible API that delegates to
  `Events.Infra.Scheduler.Strategies.StrategyRunner`.

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

  ## Circuit States

  - **Closed**: Normal operation, jobs execute
  - **Open**: Threshold exceeded, jobs skip immediately
  - **Half-Open**: Testing recovery, limited executions allowed

  ## Telemetry Events

  - `[:scheduler, :circuit_breaker, :state_change]` - State transitions
  - `[:scheduler, :circuit_breaker, :trip]` - Circuit opened due to failures
  - `[:scheduler, :circuit_breaker, :reset]` - Circuit closed after recovery
  - `[:scheduler, :circuit_breaker, :reject]` - Job rejected (circuit open)

  ## Strategy-Based Architecture

  The actual circuit breaker logic is now implemented via pluggable strategies.
  See `Events.Infra.Scheduler.Strategies.CircuitBreakerStrategy` for details.

  To use a custom circuit breaker strategy:

      config :events, Events.Infra.Scheduler,
        strategies: [
          circuit_breaker: MyApp.CustomCircuitBreaker
        ]
  """

  alias Events.Infra.Scheduler.Strategies.StrategyRunner

  @type state :: :closed | :open | :half_open
  @type circuit_name :: atom()

  @type circuit_opts :: [
          failure_threshold: pos_integer(),
          success_threshold: pos_integer(),
          reset_timeout: pos_integer() | {pos_integer(), atom()},
          half_open_limit: pos_integer()
        ]

  # ============================================
  # Public API (delegates to StrategyRunner)
  # ============================================

  @doc """
  Checks if a circuit allows execution.

  Returns `:ok` if the circuit is closed or half-open (with capacity).
  Returns `{:error, :circuit_open}` if the circuit is open.
  """
  @spec allow?(circuit_name()) :: :ok | {:error, :circuit_open}
  def allow?(circuit_name) do
    StrategyRunner.circuit_allow?(circuit_name)
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
    StrategyRunner.circuit_success(circuit_name)
  end

  @doc """
  Records a failed execution for a circuit.
  """
  @spec record_failure(circuit_name(), term()) :: :ok
  def record_failure(circuit_name, error \\ nil) do
    StrategyRunner.circuit_failure(circuit_name, error)
  end

  @doc """
  Gets the current state of a circuit.
  """
  @spec get_state(circuit_name()) :: map() | nil
  def get_state(circuit_name) do
    StrategyRunner.circuit_state(circuit_name)
  end

  @doc """
  Gets all circuit states.
  """
  @spec get_all_states() :: map()
  def get_all_states do
    StrategyRunner.circuit_all_states()
  end

  @doc """
  Resets a circuit to closed state.
  """
  @spec reset(circuit_name()) :: :ok
  def reset(circuit_name) do
    StrategyRunner.circuit_reset(circuit_name)
  end

  @doc """
  Registers a new circuit with options.
  """
  @spec register(circuit_name(), circuit_opts()) :: :ok
  def register(circuit_name, opts \\ []) do
    StrategyRunner.circuit_register(circuit_name, opts)
  end

  # ============================================
  # Private Helpers
  # ============================================

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
    StrategyRunner.error_trips_circuit?(error)
  end

  defp emit_reject(circuit_name) do
    :telemetry.execute(
      [:scheduler, :circuit_breaker, :reject],
      %{system_time: System.system_time()},
      %{circuit: circuit_name}
    )
  end
end
