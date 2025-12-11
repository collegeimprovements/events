defprotocol FnTypes.Recoverable do
  @fallback_to_any true
  @moduledoc """
  Protocol for defining error recovery strategies.

  This protocol enables any error type to declare its own recovery behavior,
  including whether it can be retried, what strategy to use, and timing parameters.

  ## Why Use This Protocol?

  Instead of hard-coding recovery rules in middleware:

      # Hard-coded (inflexible)
      def retriable?(%{type: type}) when type in [:timeout, :rate_limit], do: true

  Each error type declares its own recovery strategy:

      # Protocol-based (extensible)
      defimpl FnTypes.Recoverable, for: MyApp.PaymentError do
        def recoverable?(%{code: :soft_decline}), do: true
        def recoverable?(_), do: false
      end

  ## Recovery Strategies

  - `:retry` - Immediate retry (fixed delay)
  - `:retry_with_backoff` - Exponential backoff with jitter
  - `:wait_until` - Wait for specific time (e.g., rate limit reset)
  - `:circuit_break` - Trip the circuit breaker
  - `:fail_fast` - Don't retry, fail immediately
  - `:fallback` - Use fallback value/behavior

  ## Usage with Middleware

  The retry middleware uses this protocol to determine behavior:

      case Recoverable.recoverable?(error) do
        false -> {:error, error}
        true ->
          delay = Recoverable.retry_delay(error, attempt)
          # ... retry logic
      end

  ## Implementing for Custom Errors

      defmodule MyApp.ExternalAPIError do
        defstruct [:code, :retry_after, :message]
      end

      defimpl FnTypes.Recoverable, for: MyApp.ExternalAPIError do
        def recoverable?(%{code: code}) when code in [:timeout, :rate_limit], do: true
        def recoverable?(_), do: false

        def strategy(%{code: :rate_limit}), do: :wait_until
        def strategy(%{code: :timeout}), do: :retry
        def strategy(_), do: :fail_fast

        def retry_delay(%{retry_after: seconds}, _attempt) when is_integer(seconds) do
          seconds * 1000
        end
        def retry_delay(_, attempt), do: exponential_backoff(attempt)

        def max_attempts(%{code: :rate_limit}), do: 5
        def max_attempts(_), do: 3

        def trips_circuit?(%{code: :timeout}), do: true
        def trips_circuit?(_), do: false

        defp exponential_backoff(attempt) do
          min(1000 * :math.pow(2, attempt - 1), 30_000) |> round()
        end
      end

  ## Telemetry Integration

  Recovery decisions emit telemetry events for observability:

      [:events, :recoverable, :decision]
      - measurements: %{attempt: 1, delay_ms: 2000}
      - metadata: %{error: error, strategy: :retry_with_backoff, recoverable: true}
  """

  @type strategy ::
          :retry
          | :retry_with_backoff
          | :wait_until
          | :circuit_break
          | :fail_fast
          | :fallback

  @type severity :: :transient | :degraded | :critical | :permanent

  @doc """
  Determines if an error can potentially be recovered from.

  Returns `true` if the error represents a transient condition that may
  succeed on retry. Returns `false` for permanent failures like validation
  errors or not found errors.

  ## Examples

      Recoverable.recoverable?(timeout_error)      #=> true
      Recoverable.recoverable?(validation_error)   #=> false
      Recoverable.recoverable?(rate_limit_error)   #=> true
  """
  @spec recoverable?(t) :: boolean()
  def recoverable?(error)

  @doc """
  Returns the recommended recovery strategy for this error.

  ## Strategies

  - `:retry` - Retry immediately or with fixed delay
  - `:retry_with_backoff` - Exponential backoff with jitter
  - `:wait_until` - Wait for a specific time (use with `retry_delay/2`)
  - `:circuit_break` - Trip circuit breaker, don't retry
  - `:fail_fast` - Don't attempt recovery
  - `:fallback` - Use fallback value instead of retrying

  ## Examples

      Recoverable.strategy(timeout_error)     #=> :retry
      Recoverable.strategy(rate_limit_error)  #=> :wait_until
      Recoverable.strategy(service_down)      #=> :circuit_break
  """
  @spec strategy(t) :: strategy()
  def strategy(error)

  @doc """
  Calculates the delay before the next retry attempt.

  Returns delay in milliseconds. For `:wait_until` strategy, this should
  return the time until the resource is available (e.g., rate limit reset).

  ## Parameters

  - `error` - The error struct
  - `attempt` - Current attempt number (1-indexed)

  ## Examples

      Recoverable.retry_delay(error, 1)  #=> 1000   (1 second)
      Recoverable.retry_delay(error, 2)  #=> 2000   (2 seconds with backoff)
      Recoverable.retry_delay(error, 3)  #=> 4000   (4 seconds with backoff)

      # Rate limit with Retry-After header
      Recoverable.retry_delay(rate_limit_error, 1)  #=> 60000  (from header)
  """
  @spec retry_delay(t, attempt :: pos_integer()) :: non_neg_integer()
  def retry_delay(error, attempt)

  @doc """
  Returns the maximum number of retry attempts for this error type.

  After this many attempts, the error should be considered permanent
  and not retried further.

  ## Examples

      Recoverable.max_attempts(timeout_error)     #=> 3
      Recoverable.max_attempts(rate_limit_error)  #=> 5
      Recoverable.max_attempts(validation_error)  #=> 1  (no retries)
  """
  @spec max_attempts(t) :: pos_integer()
  def max_attempts(error)

  @doc """
  Determines if this error should trip the circuit breaker.

  Some errors indicate systemic issues that should trigger circuit breaker
  protection (e.g., service unavailable). Others are isolated failures that
  shouldn't affect the circuit state (e.g., validation errors, not found).

  ## Examples

      Recoverable.trips_circuit?(service_unavailable)  #=> true
      Recoverable.trips_circuit?(timeout_error)        #=> true
      Recoverable.trips_circuit?(validation_error)     #=> false
      Recoverable.trips_circuit?(not_found_error)      #=> false
  """
  @spec trips_circuit?(t) :: boolean()
  def trips_circuit?(error)

  @doc """
  Returns the severity level of this error.

  Severity helps determine logging level, alerting, and escalation:

  - `:transient` - Temporary issue, likely to self-resolve (DEBUG/INFO)
  - `:degraded` - Service degraded but functional (WARNING)
  - `:critical` - Major issue affecting functionality (ERROR)
  - `:permanent` - Unrecoverable error (ERROR)

  ## Examples

      Recoverable.severity(timeout_error)      #=> :transient
      Recoverable.severity(rate_limit_error)   #=> :degraded
      Recoverable.severity(service_down)       #=> :critical
      Recoverable.severity(validation_error)   #=> :permanent
  """
  @spec severity(t) :: severity()
  def severity(error)

  @doc """
  Returns a fallback value to use when recovery isn't possible.

  For errors with `:fallback` strategy, this provides the default
  value to return instead of the error. Returns `nil` if no fallback
  is available.

  ## Examples

      Recoverable.fallback(cache_miss)    #=> {:ok, nil}
      Recoverable.fallback(timeout)       #=> nil
      Recoverable.fallback(stale_data)    #=> {:ok, cached_value}
  """
  @spec fallback(t) :: {:ok, term()} | nil
  def fallback(error)
end
