defmodule Events.Infra.Scheduler.Strategies.CircuitBreakerStrategy do
  @moduledoc """
  Behaviour for circuit breaker strategies.

  Enables pluggable circuit breaker implementations without tight coupling
  to the executor. Implement this behaviour to provide custom circuit
  breaker logic.

  ## Built-in Implementations

  - `Events.Infra.Scheduler.Strategies.CircuitBreaker.Default` - Standard three-state circuit breaker
  - `Events.Infra.Scheduler.Strategies.CircuitBreaker.Noop` - Pass-through (no circuit breaking)

  ## Configuration

      config :events, Events.Infra.Scheduler,
        circuit_breaker_strategy: Events.Infra.Scheduler.Strategies.CircuitBreaker.Default,
        circuit_breaker_opts: [
          failure_threshold: 5,
          success_threshold: 2,
          reset_timeout: {30, :seconds}
        ]

  ## Implementing a Custom Strategy

      defmodule MyApp.AdaptiveCircuitBreaker do
        @behaviour Events.Infra.Scheduler.Strategies.CircuitBreakerStrategy

        @impl true
        def allow?(circuit_name, state) do
          # Custom logic to determine if circuit allows execution
        end

        @impl true
        def record_success(circuit_name, state) do
          # Record successful execution
        end

        @impl true
        def record_failure(circuit_name, error, state) do
          # Record failed execution
        end
      end
  """

  @type circuit_name :: atom()
  @type state :: :closed | :open | :half_open
  @type circuit_state :: map()
  @type opts :: keyword()

  @doc """
  Initializes the circuit breaker strategy.

  Called once when the scheduler starts. Returns initial state that will
  be passed to subsequent callbacks.
  """
  @callback init(opts()) :: {:ok, circuit_state()} | {:error, term()}

  @doc """
  Checks if the circuit allows execution.

  Returns `:ok` if the circuit is closed or half-open with capacity.
  Returns `{:error, :circuit_open}` if the circuit is open.
  """
  @callback allow?(circuit_name(), circuit_state()) ::
              {:ok, circuit_state()} | {:error, :circuit_open, circuit_state()}

  @doc """
  Records a successful execution for a circuit.

  May transition circuit from half-open to closed.
  """
  @callback record_success(circuit_name(), circuit_state()) :: {:ok, circuit_state()}

  @doc """
  Records a failed execution for a circuit.

  May transition circuit from closed to open, or half-open to open.
  """
  @callback record_failure(circuit_name(), term(), circuit_state()) :: {:ok, circuit_state()}

  @doc """
  Gets the current state of a specific circuit.

  Returns a map with circuit information for monitoring.
  """
  @callback get_state(circuit_name(), circuit_state()) :: map() | nil

  @doc """
  Gets states of all circuits.

  Returns a map of circuit names to their states.
  """
  @callback get_all_states(circuit_state()) :: map()

  @doc """
  Resets a circuit to closed state.

  Used for manual recovery or testing.
  """
  @callback reset(circuit_name(), circuit_state()) :: {:ok, circuit_state()}

  @doc """
  Registers a new circuit with options.

  Allows dynamic circuit creation at runtime.
  """
  @callback register(circuit_name(), opts(), circuit_state()) :: {:ok, circuit_state()}

  @doc """
  Called periodically to perform maintenance tasks.

  Use for cleanup, metrics emission, or state persistence.
  """
  @callback tick(circuit_state()) :: {:ok, circuit_state()}

  @optional_callbacks [tick: 1]
end
