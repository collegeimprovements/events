defimpl Events.Recoverable, for: Events.Errors.Error do
  @moduledoc """
  Recoverable implementation for the core Events.Errors.Error struct.

  This implementation handles recovery strategies based on the error type:

  | Type                | Recoverable? | Strategy           | Max Attempts |
  |---------------------|--------------|--------------------| -------------|
  | :timeout            | ✓            | :retry             | 3            |
  | :rate_limit         | ✓            | :wait_until        | 5            |
  | :service_unavailable| ✓            | :circuit_break     | 2            |
  | :network            | ✓            | :retry_with_backoff| 3            |
  | :external           | ✓            | :retry_with_backoff| 3            |
  | :validation         | ✗            | :fail_fast         | 1            |
  | :not_found          | ✗            | :fail_fast         | 1            |
  | :unauthorized       | ✗            | :fail_fast         | 1            |
  | :forbidden          | ✗            | :fail_fast         | 1            |
  | :conflict           | ✗            | :fail_fast         | 1            |
  | :bad_request        | ✗            | :fail_fast         | 1            |
  | :unprocessable      | ✗            | :fail_fast         | 1            |
  | :internal           | ✗            | :fail_fast         | 1            |
  | :configuration      | ✗            | :fail_fast         | 1            |
  | :unknown            | ✗            | :fail_fast         | 1            |
  """

  alias Events.Recoverable.Backoff

  # Transient error types that can be recovered
  @transient_types [:timeout, :rate_limit, :service_unavailable, :network, :external]

  # Types that should trip the circuit breaker
  @circuit_breaking_types [:service_unavailable, :external, :timeout]

  # Types that indicate degraded service
  @degraded_types [:rate_limit, :timeout]

  # Types that are critical
  @critical_types [:service_unavailable, :external, :internal]

  @doc """
  Determines if this error type is recoverable.

  Transient errors (timeout, rate_limit, service_unavailable, network, external)
  are considered recoverable. All other types are permanent failures.
  """
  @impl true
  def recoverable?(%{type: type}) when type in @transient_types, do: true
  def recoverable?(_), do: false

  @doc """
  Returns the recovery strategy based on error type.

  - `:timeout` - Simple retry with fixed delay
  - `:rate_limit` - Wait until (respects Retry-After if present)
  - `:service_unavailable` - Circuit break to prevent cascade
  - `:network` - Retry with exponential backoff
  - `:external` - Retry with backoff for external service errors
  """
  @impl true
  def strategy(%{type: :timeout}), do: :retry
  def strategy(%{type: :rate_limit}), do: :wait_until
  def strategy(%{type: :service_unavailable}), do: :circuit_break
  def strategy(%{type: :network}), do: :retry_with_backoff
  def strategy(%{type: :external}), do: :retry_with_backoff
  def strategy(_), do: :fail_fast

  @doc """
  Calculates retry delay based on error type and attempt.

  For rate limit errors, respects the `retry_after` metadata if present.
  For other types, uses appropriate backoff strategies.
  """
  @impl true
  def retry_delay(%{type: :rate_limit, metadata: metadata}, _attempt) do
    case extract_retry_after(metadata) do
      nil -> Backoff.exponential(1, base: 5_000, max: 60_000)
      delay_ms -> delay_ms
    end
  end

  def retry_delay(%{type: :timeout}, _attempt) do
    # Fixed 1 second delay for timeouts
    Backoff.fixed(1, delay: 1_000)
  end

  def retry_delay(%{type: :service_unavailable}, attempt) do
    # Longer backoff for service unavailable
    Backoff.exponential(attempt, base: 2_000, max: 30_000)
  end

  def retry_delay(%{type: :network}, attempt) do
    # Standard exponential backoff
    Backoff.exponential(attempt, base: 1_000, max: 15_000)
  end

  def retry_delay(%{type: :external}, attempt) do
    # Decorrelated jitter for external services (reduces thundering herd)
    Backoff.decorrelated(attempt, base: 1_000, max: 20_000)
  end

  def retry_delay(_, _), do: 0

  @doc """
  Returns maximum retry attempts based on error type.
  """
  @impl true
  def max_attempts(%{type: :rate_limit}), do: 5
  def max_attempts(%{type: :timeout}), do: 3
  def max_attempts(%{type: :network}), do: 3
  def max_attempts(%{type: :external}), do: 3
  def max_attempts(%{type: :service_unavailable}), do: 2
  def max_attempts(_), do: 1

  @doc """
  Determines if this error should trip the circuit breaker.

  Circuit breaker is tripped for systemic issues that suggest the
  downstream service is unhealthy.
  """
  @impl true
  def trips_circuit?(%{type: type}) when type in @circuit_breaking_types, do: true
  def trips_circuit?(_), do: false

  @doc """
  Returns the severity level for logging and alerting.
  """
  @impl true
  def severity(%{type: type}) when type in @degraded_types, do: :degraded
  def severity(%{type: type}) when type in @critical_types, do: :critical
  def severity(%{type: type}) when type in @transient_types, do: :transient
  def severity(_), do: :permanent

  @doc """
  No fallback values for generic errors.
  """
  @impl true
  def fallback(_), do: nil

  # Private helpers

  defp extract_retry_after(%{retry_after: seconds}) when is_integer(seconds) do
    Backoff.parse_delay(seconds)
  end

  defp extract_retry_after(%{"retry_after" => seconds}) do
    Backoff.parse_delay(seconds)
  end

  defp extract_retry_after(%{headers: headers}) when is_list(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> Backoff.parse_delay(value)
      nil -> nil
    end
  end

  defp extract_retry_after(%{headers: headers}) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      nil -> nil
      value -> Backoff.parse_delay(value)
    end
  end

  defp extract_retry_after(_), do: nil
end
