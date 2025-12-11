defprotocol FnTypes.Protocols.Recoverable do
  @fallback_to_any true

  @moduledoc """
  Backwards-compatibility alias for `FnTypes.Recoverable`.

  > **Deprecated**: Use `FnTypes.Recoverable` instead.
  > This module exists for backwards compatibility and delegates to the new location.

  See `FnTypes.Recoverable` for full documentation.
  """

  @type strategy ::
          :retry
          | :retry_with_backoff
          | :wait_until
          | :circuit_break
          | :fail_fast
          | :fallback

  @type severity :: :transient | :degraded | :critical | :permanent

  @doc "**Deprecated**: Use `FnTypes.Recoverable.recoverable?/1` instead."
  @spec recoverable?(t) :: boolean()
  def recoverable?(error)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.strategy/1` instead."
  @spec strategy(t) :: strategy()
  def strategy(error)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.retry_delay/2` instead."
  @spec retry_delay(t, attempt :: pos_integer()) :: non_neg_integer()
  def retry_delay(error, attempt)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.max_attempts/1` instead."
  @spec max_attempts(t) :: pos_integer()
  def max_attempts(error)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.trips_circuit?/1` instead."
  @spec trips_circuit?(t) :: boolean()
  def trips_circuit?(error)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.severity/1` instead."
  @spec severity(t) :: severity()
  def severity(error)

  @doc "**Deprecated**: Use `FnTypes.Recoverable.fallback/1` instead."
  @spec fallback(t) :: {:ok, term()} | nil
  def fallback(error)
end

# Note: Protocol implementations remain in lib/events/protocols/impls/recoverable/
# They implement FnTypes.Protocols.Recoverable which is still the canonical protocol
# used throughout the codebase during the transition period.
