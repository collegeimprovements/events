if Code.ensure_loaded?(Postgrex.Error) do
  defimpl FnTypes.Protocols.Recoverable, for: Postgrex.Error do
  @moduledoc """
  Recoverable implementation for Postgrex errors.

  Maps Postgres error codes to recovery strategies:

  | Error Code              | Recoverable? | Strategy           | Circuit Trip |
  |-------------------------|--------------|--------------------| -------------|
  | deadlock_detected       | ✓            | :retry             | ✗            |
  | serialization_failure   | ✓            | :retry             | ✗            |
  | lock_not_available      | ✓            | :retry_with_backoff| ✗            |
  | connection_exception    | ✓            | :retry_with_backoff| ✓            |
  | admin_shutdown          | ✓            | :circuit_break     | ✓            |
  | crash_shutdown          | ✓            | :circuit_break     | ✓            |
  | cannot_connect_now      | ✓            | :retry_with_backoff| ✓            |
  | unique_violation        | ✗            | :fail_fast         | ✗            |
  | foreign_key_violation   | ✗            | :fail_fast         | ✗            |
  | check_violation         | ✗            | :fail_fast         | ✗            |
  | not_null_violation      | ✗            | :fail_fast         | ✗            |
  | other                   | ✗            | :fail_fast         | ✗            |
  """

  alias FnTypes.Protocols.Recoverable.Backoff

  # Transient errors that can be retried immediately
  @transient_codes [:deadlock_detected, :serialization_failure]

  # Errors that need backoff before retry
  @backoff_codes [:lock_not_available, :connection_exception, :cannot_connect_now]

  # Server-side issues that should trip circuit breaker
  @circuit_tripping_codes [:admin_shutdown, :crash_shutdown, :connection_exception]

  # All recoverable codes
  @recoverable_codes @transient_codes ++ @backoff_codes ++ [:admin_shutdown, :crash_shutdown]

  @impl true
  def recoverable?(%Postgrex.Error{postgres: %{code: code}}) when code in @recoverable_codes do
    true
  end

  def recoverable?(%Postgrex.Error{}), do: false

  @impl true
  def strategy(%Postgrex.Error{postgres: %{code: code}}) when code in @transient_codes do
    :retry
  end

  def strategy(%Postgrex.Error{postgres: %{code: code}}) when code in @backoff_codes do
    :retry_with_backoff
  end

  def strategy(%Postgrex.Error{postgres: %{code: code}})
      when code in [:admin_shutdown, :crash_shutdown] do
    :circuit_break
  end

  def strategy(%Postgrex.Error{}), do: :fail_fast

  @impl true
  def retry_delay(%Postgrex.Error{postgres: %{code: code}}, _attempt)
      when code in @transient_codes do
    # Quick retry for deadlocks - just need to break the cycle
    Backoff.fixed(1, delay: 50)
  end

  def retry_delay(%Postgrex.Error{postgres: %{code: :lock_not_available}}, attempt) do
    # Lock contention - exponential backoff
    Backoff.exponential(attempt, base: 100, max: 2_000)
  end

  def retry_delay(%Postgrex.Error{postgres: %{code: code}}, attempt)
      when code in [:connection_exception, :cannot_connect_now] do
    # Connection issues - longer backoff
    Backoff.exponential(attempt, base: 500, max: 10_000)
  end

  def retry_delay(%Postgrex.Error{}, _attempt), do: 0

  @impl true
  def max_attempts(%Postgrex.Error{postgres: %{code: code}}) when code in @transient_codes do
    5
  end

  def max_attempts(%Postgrex.Error{postgres: %{code: :lock_not_available}}) do
    3
  end

  def max_attempts(%Postgrex.Error{postgres: %{code: code}})
      when code in [:connection_exception, :cannot_connect_now] do
    3
  end

  def max_attempts(%Postgrex.Error{postgres: %{code: code}})
      when code in [:admin_shutdown, :crash_shutdown] do
    2
  end

  def max_attempts(%Postgrex.Error{}), do: 1

  @impl true
  def trips_circuit?(%Postgrex.Error{postgres: %{code: code}})
      when code in @circuit_tripping_codes do
    true
  end

  def trips_circuit?(%Postgrex.Error{}), do: false

  @impl true
  def severity(%Postgrex.Error{postgres: %{code: code}}) when code in @transient_codes do
    :transient
  end

  def severity(%Postgrex.Error{postgres: %{code: code}}) when code in @backoff_codes do
    :degraded
  end

  def severity(%Postgrex.Error{postgres: %{code: code}})
      when code in [:admin_shutdown, :crash_shutdown] do
    :critical
  end

  def severity(%Postgrex.Error{}), do: :permanent

  @impl true
  def fallback(%Postgrex.Error{}), do: nil
  end
end
