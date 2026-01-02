defprotocol FnTypes.Protocols.Recoverable do
  @fallback_to_any true

  @moduledoc """
  Protocol for determining error recoverability and retry strategies.

  Implement this protocol for your error types to enable intelligent
  retry behavior in `FnTypes.Retry` and related modules.

  ## Strategies

  - `:retry` - Simple retry without delay
  - `:retry_with_backoff` - Retry with exponential backoff
  - `:wait_until` - Wait for a specific condition
  - `:circuit_break` - Trip the circuit breaker
  - `:fail_fast` - Don't retry, fail immediately
  - `:fallback` - Use a fallback value

  ## Severity Levels

  - `:transient` - Temporary issue, likely to succeed on retry
  - `:degraded` - Partial failure, may need special handling
  - `:critical` - Serious error, requires attention
  - `:permanent` - Won't recover, don't retry
  """

  @type strategy ::
          :retry
          | :retry_with_backoff
          | :wait_until
          | :circuit_break
          | :fail_fast
          | :fallback

  @type severity :: :transient | :degraded | :critical | :permanent

  @doc "Returns whether the error is recoverable."
  @spec recoverable?(t) :: boolean()
  def recoverable?(error)

  @doc "Returns the recommended recovery strategy."
  @spec strategy(t) :: strategy()
  def strategy(error)

  @doc "Returns the retry delay in milliseconds for the given attempt."
  @spec retry_delay(t, attempt :: pos_integer()) :: non_neg_integer()
  def retry_delay(error, attempt)

  @doc "Returns the maximum number of retry attempts."
  @spec max_attempts(t) :: pos_integer()
  def max_attempts(error)

  @doc "Returns whether this error should trip a circuit breaker."
  @spec trips_circuit?(t) :: boolean()
  def trips_circuit?(error)

  @doc "Returns the severity level of the error."
  @spec severity(t) :: severity()
  def severity(error)

  @doc "Returns a fallback value if available."
  @spec fallback(t) :: {:ok, term()} | nil
  def fallback(error)
end
