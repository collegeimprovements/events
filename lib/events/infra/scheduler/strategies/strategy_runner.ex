defmodule Events.Infra.Scheduler.Strategies.StrategyRunner do
  @moduledoc """
  Unified GenServer that manages all scheduler strategies.

  Provides a single process that handles circuit breaker, rate limiter,
  and error classifier operations. This decouples the executor from
  specific strategy implementations.

  ## Architecture

  Instead of having separate GenServers for CircuitBreaker and RateLimiter,
  StrategyRunner consolidates them into a single process with pluggable
  strategy implementations via behaviours.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        strategies: [
          circuit_breaker: Events.Infra.Scheduler.Strategies.CircuitBreaker.Default,
          rate_limiter: Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket,
          error_classifier: Events.Infra.Scheduler.Strategies.ErrorClassifier.Default
        ],
        circuit_breaker_opts: [...],
        rate_limiter_opts: [...],
        error_classification: [...]

  ## Usage

      # Check circuit before execution
      case StrategyRunner.circuit_allow?(:external_api) do
        :ok -> execute_job()
        {:error, :circuit_open} -> skip_job()
      end

      # Acquire rate limit token
      case StrategyRunner.rate_acquire(:queue, :api) do
        :ok -> execute_job()
        {:error, :rate_limited, retry_after} -> reschedule(retry_after)
      end

      # Classify error for retry
      StrategyRunner.classify_error(error)
      StrategyRunner.next_action(error, attempt)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.Config

  @type state :: %{
          circuit_breaker: %{module: module(), state: term()},
          rate_limiter: %{module: module(), state: term()},
          error_classifier: %{module: module(), state: term()},
          tick_interval: pos_integer()
        }

  @default_tick_interval 1_000

  # ============================================
  # Client API - Circuit Breaker
  # ============================================

  @doc """
  Starts the strategy runner.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks if a circuit allows execution.

  Returns `:ok` or `{:error, :circuit_open}`.
  """
  @spec circuit_allow?(atom(), atom()) :: :ok | {:error, :circuit_open}
  def circuit_allow?(circuit_name, name \\ __MODULE__) do
    GenServer.call(name, {:circuit_allow?, circuit_name})
  end

  @doc """
  Records a successful execution for a circuit.
  """
  @spec circuit_success(atom(), atom()) :: :ok
  def circuit_success(circuit_name, name \\ __MODULE__) do
    GenServer.cast(name, {:circuit_success, circuit_name})
  end

  @doc """
  Records a failed execution for a circuit.
  """
  @spec circuit_failure(atom(), term(), atom()) :: :ok
  def circuit_failure(circuit_name, error, name \\ __MODULE__) do
    GenServer.cast(name, {:circuit_failure, circuit_name, error})
  end

  @doc """
  Gets the current state of a circuit.
  """
  @spec circuit_state(atom(), atom()) :: map() | nil
  def circuit_state(circuit_name, name \\ __MODULE__) do
    GenServer.call(name, {:circuit_state, circuit_name})
  end

  @doc """
  Gets all circuit states.
  """
  @spec circuit_all_states(atom()) :: map()
  def circuit_all_states(name \\ __MODULE__) do
    GenServer.call(name, :circuit_all_states)
  end

  @doc """
  Resets a circuit to closed state.
  """
  @spec circuit_reset(atom(), atom()) :: :ok
  def circuit_reset(circuit_name, name \\ __MODULE__) do
    GenServer.call(name, {:circuit_reset, circuit_name})
  end

  @doc """
  Registers a new circuit with options.
  """
  @spec circuit_register(atom(), keyword(), atom()) :: :ok
  def circuit_register(circuit_name, opts, name \\ __MODULE__) do
    GenServer.call(name, {:circuit_register, circuit_name, opts})
  end

  # ============================================
  # Client API - Rate Limiter
  # ============================================

  @doc """
  Attempts to acquire a rate limit token.

  Returns `:ok` or `{:error, :rate_limited, retry_after_ms}`.
  """
  @spec rate_acquire(atom(), atom() | module(), atom()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def rate_acquire(scope, key \\ nil, name \\ __MODULE__) do
    GenServer.call(name, {:rate_acquire, scope, key})
  end

  @doc """
  Checks if a token is available without consuming it.
  """
  @spec rate_check(atom(), atom() | module(), atom()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def rate_check(scope, key \\ nil, name \\ __MODULE__) do
    GenServer.call(name, {:rate_check, scope, key})
  end

  @doc """
  Returns current rate limiter status.
  """
  @spec rate_status(atom()) :: map()
  def rate_status(name \\ __MODULE__) do
    GenServer.call(name, :rate_status)
  end

  @doc """
  Acquires rate limit tokens for a job.
  """
  @spec rate_acquire_for_job(map(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def rate_acquire_for_job(job, name \\ __MODULE__) do
    GenServer.call(name, {:rate_acquire_for_job, job})
  end

  # ============================================
  # Client API - Error Classifier
  # ============================================

  @doc """
  Classifies an error and returns retry behavior.
  """
  @spec classify_error(term(), atom()) :: ErrorClassifierStrategy.classification()
  def classify_error(error, name \\ __MODULE__) do
    GenServer.call(name, {:classify_error, error})
  end

  @doc """
  Determines if an error is retryable.
  """
  @spec error_retryable?(term(), atom()) :: boolean()
  def error_retryable?(error, name \\ __MODULE__) do
    GenServer.call(name, {:error_retryable?, error})
  end

  @doc """
  Determines if an error is terminal.
  """
  @spec error_terminal?(term(), atom()) :: boolean()
  def error_terminal?(error, name \\ __MODULE__) do
    GenServer.call(name, {:error_terminal?, error})
  end

  @doc """
  Calculates retry delay for an error.
  """
  @spec error_retry_delay(term(), pos_integer(), atom()) :: non_neg_integer()
  def error_retry_delay(error, attempt, name \\ __MODULE__) do
    GenServer.call(name, {:error_retry_delay, error, attempt})
  end

  @doc """
  Determines the next action for an error.

  Returns `{:retry, delay}`, `:dead_letter`, or `:discard`.
  """
  @spec next_action(term(), pos_integer(), atom()) ::
          {:retry, non_neg_integer()} | :dead_letter | :discard
  def next_action(error, attempt, name \\ __MODULE__) do
    GenServer.call(name, {:next_action, error, attempt})
  end

  @doc """
  Checks if an error should trip circuit breakers.
  """
  @spec error_trips_circuit?(term(), atom()) :: boolean()
  def error_trips_circuit?(error, name \\ __MODULE__) do
    GenServer.call(name, {:error_trips_circuit?, error})
  end

  # ============================================
  # Combined Operations
  # ============================================

  @doc """
  Checks all strategies before job execution.

  Returns `:ok` if all checks pass, or the first error.
  """
  @spec pre_execute_check(map(), atom() | nil, atom()) ::
          :ok | {:error, :circuit_open} | {:error, :rate_limited, pos_integer()}
  def pre_execute_check(job, circuit_name, name \\ __MODULE__) do
    GenServer.call(name, {:pre_execute_check, job, circuit_name})
  end

  @doc """
  Records job result with all relevant strategies.
  """
  @spec record_result(atom() | nil, {:ok, term()} | {:error, term()}, atom()) :: :ok
  def record_result(circuit_name, result, name \\ __MODULE__) do
    GenServer.cast(name, {:record_result, circuit_name, result})
  end

  @doc """
  Returns child spec for supervision.
  """
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())
    strategies = Keyword.get(conf, :strategies, [])

    # Initialize each strategy
    circuit_breaker = init_circuit_breaker(strategies, conf)
    rate_limiter = init_rate_limiter(strategies, conf)
    error_classifier = init_error_classifier(strategies, conf)

    tick_interval = Keyword.get(conf, :strategy_tick_interval, @default_tick_interval)

    # Start tick timer
    if tick_interval > 0 do
      Process.send_after(self(), :tick, tick_interval)
    end

    state = %{
      circuit_breaker: circuit_breaker,
      rate_limiter: rate_limiter,
      error_classifier: error_classifier,
      tick_interval: tick_interval
    }

    Logger.debug("[StrategyRunner] Initialized with strategies: " <>
      "circuit_breaker=#{circuit_breaker.module}, " <>
      "rate_limiter=#{rate_limiter.module}, " <>
      "error_classifier=#{error_classifier.module}")

    {:ok, state}
  end

  # Circuit Breaker handlers
  @impl GenServer
  def handle_call({:circuit_allow?, circuit_name}, _from, state) do
    result = state.circuit_breaker.module.allow?(circuit_name, state.circuit_breaker.state)

    {reply, new_state} =
      case result do
        {:ok, cb_state} ->
          {:ok, put_in(state.circuit_breaker.state, cb_state)}

        {:error, :circuit_open, cb_state} ->
          {{:error, :circuit_open}, put_in(state.circuit_breaker.state, cb_state)}
      end

    {:reply, reply, new_state}
  end

  def handle_call({:circuit_state, circuit_name}, _from, state) do
    result = state.circuit_breaker.module.get_state(circuit_name, state.circuit_breaker.state)
    {:reply, result, state}
  end

  def handle_call(:circuit_all_states, _from, state) do
    result = state.circuit_breaker.module.get_all_states(state.circuit_breaker.state)
    {:reply, result, state}
  end

  def handle_call({:circuit_reset, circuit_name}, _from, state) do
    {:ok, cb_state} = state.circuit_breaker.module.reset(circuit_name, state.circuit_breaker.state)
    new_state = put_in(state.circuit_breaker.state, cb_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:circuit_register, circuit_name, opts}, _from, state) do
    {:ok, cb_state} = state.circuit_breaker.module.register(circuit_name, opts, state.circuit_breaker.state)
    new_state = put_in(state.circuit_breaker.state, cb_state)
    {:reply, :ok, new_state}
  end

  # Rate Limiter handlers
  def handle_call({:rate_acquire, scope, key}, _from, state) do
    case state.rate_limiter.module.acquire(scope, key, state.rate_limiter.state) do
      {:ok, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, :ok, new_state}

      {:error, :rate_limited, retry_after, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, {:error, :rate_limited, retry_after}, new_state}

      {:error, :not_configured, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:rate_check, scope, key}, _from, state) do
    case state.rate_limiter.module.check(scope, key, state.rate_limiter.state) do
      {:ok, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, :ok, new_state}

      {:error, :rate_limited, retry_after, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, {:error, :rate_limited, retry_after}, new_state}

      {:error, :not_configured, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:rate_status, _from, state) do
    result = state.rate_limiter.module.status(state.rate_limiter.state)
    {:reply, result, state}
  end

  def handle_call({:rate_acquire_for_job, job}, _from, state) do
    case state.rate_limiter.module.acquire_for_job(job, state.rate_limiter.state) do
      {:ok, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, :ok, new_state}

      {:error, :rate_limited, retry_after, rl_state} ->
        new_state = put_in(state.rate_limiter.state, rl_state)
        {:reply, {:error, :rate_limited, retry_after}, new_state}
    end
  end

  # Error Classifier handlers
  def handle_call({:classify_error, error}, _from, state) do
    {classification, ec_state} = state.error_classifier.module.classify(error, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, classification, new_state}
  end

  def handle_call({:error_retryable?, error}, _from, state) do
    {result, ec_state} = state.error_classifier.module.retryable?(error, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, result, new_state}
  end

  def handle_call({:error_terminal?, error}, _from, state) do
    {result, ec_state} = state.error_classifier.module.terminal?(error, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, result, new_state}
  end

  def handle_call({:error_retry_delay, error, attempt}, _from, state) do
    {delay, ec_state} = state.error_classifier.module.retry_delay(error, attempt, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, delay, new_state}
  end

  def handle_call({:next_action, error, attempt}, _from, state) do
    {action, ec_state} = state.error_classifier.module.next_action(error, attempt, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, action, new_state}
  end

  def handle_call({:error_trips_circuit?, error}, _from, state) do
    {result, ec_state} = state.error_classifier.module.trips_circuit?(error, state.error_classifier.state)
    new_state = put_in(state.error_classifier.state, ec_state)
    {:reply, result, new_state}
  end

  # Combined handlers
  def handle_call({:pre_execute_check, job, circuit_name}, _from, state) do
    state = check_circuit_and_rate(job, circuit_name, state)
    {:reply, state.check_result, Map.delete(state, :check_result)}
  end

  @impl GenServer
  def handle_cast({:circuit_success, circuit_name}, state) do
    {:ok, cb_state} = state.circuit_breaker.module.record_success(circuit_name, state.circuit_breaker.state)
    new_state = put_in(state.circuit_breaker.state, cb_state)
    {:noreply, new_state}
  end

  def handle_cast({:circuit_failure, circuit_name, error}, state) do
    {:ok, cb_state} = state.circuit_breaker.module.record_failure(circuit_name, error, state.circuit_breaker.state)
    new_state = put_in(state.circuit_breaker.state, cb_state)
    {:noreply, new_state}
  end

  def handle_cast({:record_result, circuit_name, result}, state) do
    new_state =
      case result do
        {:ok, _} when not is_nil(circuit_name) ->
          {:ok, cb_state} = state.circuit_breaker.module.record_success(circuit_name, state.circuit_breaker.state)
          put_in(state.circuit_breaker.state, cb_state)

        {:error, error} when not is_nil(circuit_name) ->
          {trips, ec_state} = state.error_classifier.module.trips_circuit?(error, state.error_classifier.state)
          state = put_in(state.error_classifier.state, ec_state)

          if trips do
            {:ok, cb_state} = state.circuit_breaker.module.record_failure(circuit_name, error, state.circuit_breaker.state)
            put_in(state.circuit_breaker.state, cb_state)
          else
            state
          end

        _ ->
          state
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    # Call tick on strategies that support it
    state = tick_circuit_breaker(state)
    state = tick_rate_limiter(state)

    # Schedule next tick
    if state.tick_interval > 0 do
      Process.send_after(self(), :tick, state.tick_interval)
    end

    {:noreply, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp init_circuit_breaker(strategies, conf) do
    module = Keyword.get(
      strategies,
      :circuit_breaker,
      Events.Infra.Scheduler.Strategies.CircuitBreaker.Default
    )

    # Get circuit breaker config
    circuits = Keyword.get(conf, :circuit_breakers, [])
    circuit_opts = Keyword.get(conf, :circuit_breaker_opts, [])
    opts = Keyword.merge(circuit_opts, circuits: circuits)

    {:ok, state} = module.init(opts)
    %{module: module, state: state}
  end

  defp init_rate_limiter(strategies, conf) do
    module = Keyword.get(
      strategies,
      :rate_limiter,
      Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket
    )

    rate_limits = Keyword.get(conf, :rate_limits, [])
    opts = [rate_limits: rate_limits]

    {:ok, state} = module.init(opts)
    %{module: module, state: state}
  end

  defp init_error_classifier(strategies, conf) do
    module = Keyword.get(
      strategies,
      :error_classifier,
      Events.Infra.Scheduler.Strategies.ErrorClassifier.Default
    )

    error_classification = Keyword.get(conf, :error_classification, [])
    opts = [error_classification: error_classification]

    {:ok, state} = module.init(opts)
    %{module: module, state: state}
  end

  defp check_circuit_and_rate(job, circuit_name, state) do
    # Check circuit breaker first
    case check_circuit(circuit_name, state) do
      {:ok, state} ->
        # Then check rate limiter
        case state.rate_limiter.module.acquire_for_job(job, state.rate_limiter.state) do
          {:ok, rl_state} ->
            state
            |> put_in([:rate_limiter, :state], rl_state)
            |> Map.put(:check_result, :ok)

          {:error, :rate_limited, retry_after, rl_state} ->
            state
            |> put_in([:rate_limiter, :state], rl_state)
            |> Map.put(:check_result, {:error, :rate_limited, retry_after})
        end

      {:error, :circuit_open, state} ->
        Map.put(state, :check_result, {:error, :circuit_open})
    end
  end

  defp check_circuit(nil, state), do: {:ok, state}

  defp check_circuit(circuit_name, state) do
    case state.circuit_breaker.module.allow?(circuit_name, state.circuit_breaker.state) do
      {:ok, cb_state} ->
        {:ok, put_in(state.circuit_breaker.state, cb_state)}

      {:error, :circuit_open, cb_state} ->
        {:error, :circuit_open, put_in(state.circuit_breaker.state, cb_state)}
    end
  end

  defp tick_circuit_breaker(state) do
    if function_exported?(state.circuit_breaker.module, :tick, 1) do
      {:ok, cb_state} = state.circuit_breaker.module.tick(state.circuit_breaker.state)
      put_in(state.circuit_breaker.state, cb_state)
    else
      state
    end
  end

  defp tick_rate_limiter(state) do
    if function_exported?(state.rate_limiter.module, :tick, 1) do
      {:ok, rl_state} = state.rate_limiter.module.tick(state.rate_limiter.state)
      put_in(state.rate_limiter.state, rl_state)
    else
      state
    end
  end
end
