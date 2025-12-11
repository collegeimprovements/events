defmodule FnTypes.Protocols.Recoverable.Helpers do
  @moduledoc """
  Convenience functions for working with the Recoverable protocol.

  These helpers provide common patterns for error recovery:
  - Retry loops with protocol-based configuration
  - Recovery decision making
  - Telemetry integration

  ## Usage

      alias FnTypes.Protocols.Recoverable.Helpers

      # Execute with automatic retry
      Helpers.with_retry(fn -> make_api_call() end)

      # Get recovery decision
      Helpers.recovery_decision(error, attempt: 2)
      #=> {:retry, delay: 2000, remaining: 1}

      # Check if should continue retrying
      Helpers.should_retry?(error, attempt: 2)
      #=> true
  """

  alias FnTypes.Protocols.Recoverable

  @type recovery_decision ::
          {:retry, keyword()}
          | {:wait, keyword()}
          | {:circuit_break, keyword()}
          | {:fail, keyword()}
          | {:fallback, term()}

  @doc """
  Makes a recovery decision based on the error and current attempt.

  Returns a tagged tuple with the decision and relevant options:

  - `{:retry, delay: ms, remaining: n}` - Retry after delay
  - `{:wait, delay: ms, remaining: n}` - Wait for specific time
  - `{:circuit_break, reason: error}` - Trip circuit breaker
  - `{:fail, reason: error}` - Don't recover, fail
  - `{:fallback, value: term}` - Use fallback value

  ## Options

  - `:attempt` - Current attempt number (default: 1)

  ## Examples

      Helpers.recovery_decision(timeout_error, attempt: 1)
      #=> {:retry, delay: 1000, remaining: 2}

      Helpers.recovery_decision(rate_limit_error, attempt: 3)
      #=> {:wait, delay: 60000, remaining: 2}

      Helpers.recovery_decision(validation_error)
      #=> {:fail, reason: validation_error}
  """
  @spec recovery_decision(term(), keyword()) :: recovery_decision()
  def recovery_decision(error, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)

    cond do
      not Recoverable.recoverable?(error) ->
        {:fail, reason: error}

      attempt >= Recoverable.max_attempts(error) ->
        {:fail, reason: error, exhausted: true}

      true ->
        strategy = Recoverable.strategy(error)
        delay = Recoverable.retry_delay(error, attempt)
        remaining = Recoverable.max_attempts(error) - attempt

        case strategy do
          :fail_fast ->
            {:fail, reason: error}

          :circuit_break ->
            {:circuit_break, reason: error}

          :fallback ->
            case Recoverable.fallback(error) do
              {:ok, value} -> {:fallback, value: value}
              nil -> {:fail, reason: error}
            end

          :wait_until ->
            {:wait, delay: delay, remaining: remaining}

          strategy when strategy in [:retry, :retry_with_backoff] ->
            {:retry, delay: delay, remaining: remaining}
        end
    end
  end

  @doc """
  Determines if retry should be attempted for the given error and attempt.

  ## Examples

      Helpers.should_retry?(timeout_error, attempt: 1)  #=> true
      Helpers.should_retry?(timeout_error, attempt: 5)  #=> false
      Helpers.should_retry?(validation_error)           #=> false
  """
  @spec should_retry?(term(), keyword()) :: boolean()
  def should_retry?(error, opts \\ []) do
    case recovery_decision(error, opts) do
      {:retry, _} -> true
      {:wait, _} -> true
      _ -> false
    end
  end

  @doc """
  Executes a function with automatic retry based on Recoverable protocol.

  ## Options

  - `:max_attempts` - Override max attempts (default: from protocol)
  - `:on_retry` - Callback `fn error, attempt, delay -> :ok end`
  - `:on_error` - Callback `fn error, attempt -> :ok end`
  - `:delay` - Override delay entirely (useful for tests, set to 0 for instant)
  - `:delay_multiplier` - Scale delay (0.0 = instant, 1.0 = normal)

  ## Examples

      Helpers.with_retry(fn -> http_request() end)

      Helpers.with_retry(
        fn -> http_request() end,
        on_retry: fn error, attempt, delay ->
          Logger.warning("Retry \#{attempt}, waiting \#{delay}ms: \#{inspect(error)}")
        end
      )

      # For testing - no delays
      Helpers.with_retry(fn -> flaky_call() end, delay: 0)
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) do
    do_retry(fun, 1, opts)
  end

  defp do_retry(fun, attempt, opts) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        on_error = Keyword.get(opts, :on_error)
        if on_error, do: on_error.(error, attempt)

        max_override = Keyword.get(opts, :max_attempts)
        max_attempts = max_override || Recoverable.max_attempts(error)

        case recovery_decision(error, attempt: attempt) do
          {:retry, delay: delay, remaining: _} when attempt < max_attempts ->
            on_retry = Keyword.get(opts, :on_retry)
            if on_retry, do: on_retry.(error, attempt, delay)

            actual_delay = apply_delay_opts(delay, opts)
            if actual_delay > 0, do: Process.sleep(actual_delay)
            do_retry(fun, attempt + 1, opts)

          {:wait, delay: delay, remaining: _} when attempt < max_attempts ->
            on_retry = Keyword.get(opts, :on_retry)
            if on_retry, do: on_retry.(error, attempt, delay)

            actual_delay = apply_delay_opts(delay, opts)
            if actual_delay > 0, do: Process.sleep(actual_delay)
            do_retry(fun, attempt + 1, opts)

          {:fallback, value: value} ->
            {:ok, value}

          _ ->
            {:error, error}
        end
    end
  end

  @doc """
  Returns a summary of recovery information for an error.

  Useful for logging and debugging.

  ## Examples

      Helpers.recovery_info(error)
      #=> %{
      #=>   recoverable: true,
      #=>   strategy: :retry_with_backoff,
      #=>   max_attempts: 3,
      #=>   trips_circuit: false,
      #=>   severity: :transient
      #=> }
  """
  @spec recovery_info(term()) :: map()
  def recovery_info(error) do
    %{
      recoverable: Recoverable.recoverable?(error),
      strategy: Recoverable.strategy(error),
      max_attempts: Recoverable.max_attempts(error),
      trips_circuit: Recoverable.trips_circuit?(error),
      severity: Recoverable.severity(error),
      initial_delay: Recoverable.retry_delay(error, 1)
    }
  end

  @doc """
  Emits telemetry event for recovery decision.

  Event: `[:events, :recoverable, :decision]`

  ## Measurements

  - `:attempt` - Current attempt number
  - `:delay_ms` - Delay before retry (0 if not retrying)
  - `:duration_ms` - Time since first attempt (if provided)

  ## Metadata

  - `:error` - The error value
  - `:strategy` - Recovery strategy
  - `:decision` - Decision type (:retry, :wait, :fail, etc.)
  - `:recoverable` - Whether error is recoverable
  - `:severity` - Error severity
  """
  @spec emit_telemetry(term(), keyword()) :: :ok
  def emit_telemetry(error, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    decision = recovery_decision(error, opts)

    {decision_type, decision_opts} =
      case decision do
        {type, opts} -> {type, opts}
      end

    delay = Keyword.get(decision_opts, :delay, 0)

    measurements = %{
      attempt: attempt,
      delay_ms: delay
    }

    measurements =
      case Keyword.get(opts, :start_time) do
        nil -> measurements
        start -> Map.put(measurements, :duration_ms, System.monotonic_time(:millisecond) - start)
      end

    metadata = %{
      error: error,
      strategy: Recoverable.strategy(error),
      decision: decision_type,
      recoverable: Recoverable.recoverable?(error),
      severity: Recoverable.severity(error)
    }

    :telemetry.execute([:events, :recoverable, :decision], measurements, metadata)
  end

  @doc """
  Groups a list of errors by their recovery strategy.

  Useful for batch processing where different errors need different handling.

  ## Examples

      errors = [timeout_error, validation_error, rate_limit_error]
      Helpers.group_by_strategy(errors)
      #=> %{
      #=>   retry: [timeout_error],
      #=>   fail_fast: [validation_error],
      #=>   wait_until: [rate_limit_error]
      #=> }
  """
  @spec group_by_strategy([term()]) :: %{Recoverable.strategy() => [term()]}
  def group_by_strategy(errors) do
    Enum.group_by(errors, &Recoverable.strategy/1)
  end

  @doc """
  Partitions errors into recoverable and non-recoverable.

  ## Examples

      {recoverable, permanent} = Helpers.partition_recoverable(errors)
  """
  @spec partition_recoverable([term()]) :: {[term()], [term()]}
  def partition_recoverable(errors) do
    Enum.split_with(errors, &Recoverable.recoverable?/1)
  end

  # Applies delay options for testing purposes
  # Options:
  #   - :delay - Override delay entirely (useful for tests)
  #   - :delay_multiplier - Scale delay (0.0 = instant, 1.0 = normal)
  defp apply_delay_opts(delay, opts) do
    cond do
      override = Keyword.get(opts, :delay) ->
        override

      multiplier = Keyword.get(opts, :delay_multiplier) ->
        round(delay * multiplier)

      true ->
        delay
    end
  end
end
