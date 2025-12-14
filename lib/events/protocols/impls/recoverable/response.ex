defimpl FnTypes.Protocols.Recoverable, for: Events.Api.Client.Response do
  @moduledoc """
  Recoverable implementation for API Response structs.

  Maps HTTP status codes to recovery strategies:

  | Status | Recoverable? | Strategy           | Circuit Trip |
  |--------|--------------|--------------------| -------------|
  | 408    | Yes          | :retry             | No           |
  | 429    | Yes          | :wait_until        | No           |
  | 500    | Yes          | :retry_with_backoff| Yes          |
  | 502    | Yes          | :circuit_break     | Yes          |
  | 503    | Yes          | :circuit_break     | Yes          |
  | 504    | Yes          | :retry             | Yes          |
  | 4xx    | No           | :fail_fast         | No           |
  | 2xx    | No           | :fail_fast         | No           |
  """

  alias Events.Api.Client.Response
  alias FnTypes.Protocols.Recoverable.Backoff

  # Retryable status codes
  @retryable_statuses [408, 429, 500, 502, 503, 504]

  # Status codes that should trip circuit breaker
  @circuit_tripping_statuses [500, 502, 503, 504]

  @impl true
  def recoverable?(%Response{status: status}) when status in @retryable_statuses, do: true
  def recoverable?(%Response{}), do: false

  @impl true
  def strategy(%Response{status: 408}), do: :retry
  def strategy(%Response{status: 429}), do: :wait_until
  def strategy(%Response{status: 500}), do: :retry_with_backoff
  def strategy(%Response{status: 502}), do: :circuit_break
  def strategy(%Response{status: 503}), do: :circuit_break
  def strategy(%Response{status: 504}), do: :retry
  def strategy(%Response{}), do: :fail_fast

  @impl true
  def retry_delay(%Response{status: 429} = response, _attempt) do
    # Use Retry-After header if available
    case Response.retry_after_ms(response) do
      nil -> Backoff.exponential(1, base: 5_000, max: 60_000)
      delay_ms -> delay_ms
    end
  end

  def retry_delay(%Response{status: 408}, _attempt) do
    # Request timeout - fixed short delay
    Backoff.fixed(1, delay: 1_000)
  end

  def retry_delay(%Response{status: 504}, _attempt) do
    # Gateway timeout - fixed short delay
    Backoff.fixed(1, delay: 1_000)
  end

  def retry_delay(%Response{status: status}, attempt) when status in [500, 502, 503] do
    # Server errors - exponential backoff
    Backoff.exponential(attempt, base: 1_000, max: 30_000)
  end

  def retry_delay(%Response{}, _attempt), do: 0

  @impl true
  def max_attempts(%Response{status: 429}), do: 5
  def max_attempts(%Response{status: 408}), do: 3
  def max_attempts(%Response{status: 504}), do: 3
  def max_attempts(%Response{status: status}) when status in [500, 502, 503], do: 3
  def max_attempts(%Response{}), do: 1

  @impl true
  def trips_circuit?(%Response{status: status}) when status in @circuit_tripping_statuses, do: true
  def trips_circuit?(%Response{}), do: false

  @impl true
  def severity(%Response{status: 429}), do: :degraded
  def severity(%Response{status: 408}), do: :transient
  def severity(%Response{status: 504}), do: :transient
  def severity(%Response{status: status}) when status in [500, 502, 503], do: :critical
  def severity(%Response{status: status}) when status in 400..499, do: :permanent
  def severity(%Response{}), do: :permanent

  @impl true
  def fallback(%Response{}), do: nil
end
