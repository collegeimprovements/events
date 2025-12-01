# Implementation for DBConnection errors
# These are connection pool and database connection errors

if Code.ensure_loaded?(DBConnection.ConnectionError) do
  defimpl Events.Protocols.Recoverable, for: DBConnection.ConnectionError do
    @moduledoc """
    Recoverable implementation for DBConnection errors.

    These errors come from the database connection pool and include:
    - Connection timeouts
    - Pool checkout timeouts
    - Deadlocks
    - Connection resets

    Deadlocks are a special case - they can be retried immediately
    as the database has already resolved the deadlock.
    """

    alias Events.Protocols.Recoverable.Backoff

    @impl true
    def recoverable?(%{message: message}) do
      cond do
        contains?(message, "deadlock") -> true
        contains?(message, "timeout") -> true
        contains?(message, "connection") -> true
        contains?(message, "pool") -> true
        contains?(message, "closed") -> true
        true -> false
      end
    end

    @impl true
    def strategy(%{message: message}) do
      cond do
        # Deadlocks can be retried immediately
        contains?(message, "deadlock") -> :retry
        # Connection issues may indicate pool exhaustion
        contains?(message, "pool") -> :retry_with_backoff
        contains?(message, "timeout") -> :retry_with_backoff
        # Connection drops should trip circuit
        contains?(message, "connection") and contains?(message, "closed") -> :circuit_break
        true -> :retry_with_backoff
      end
    end

    @impl true
    def retry_delay(%{message: message}, attempt) do
      cond do
        # Deadlock - quick retry with small jitter
        contains?(message, "deadlock") ->
          50 + :rand.uniform(50) * attempt

        # Pool timeout - back off to let pool recover
        contains?(message, "pool") or contains?(message, "timeout") ->
          Backoff.exponential(attempt, base: 500, max: 5_000)

        # Connection issues - longer backoff
        true ->
          Backoff.exponential(attempt, base: 1_000, max: 10_000)
      end
    end

    @impl true
    def max_attempts(%{message: message}) do
      cond do
        contains?(message, "deadlock") -> 3
        contains?(message, "pool") -> 2
        contains?(message, "timeout") -> 2
        true -> 2
      end
    end

    @impl true
    def trips_circuit?(%{message: message}) do
      # Trip circuit for connection drops, not for deadlocks/timeouts
      contains?(message, "connection") and
        (contains?(message, "closed") or contains?(message, "refused"))
    end

    @impl true
    def severity(%{message: message}) do
      cond do
        contains?(message, "deadlock") -> :transient
        contains?(message, "timeout") -> :degraded
        contains?(message, "pool") -> :degraded
        contains?(message, "closed") or contains?(message, "refused") -> :critical
        true -> :transient
      end
    end

    @impl true
    def fallback(_), do: nil

    # Helper for case-insensitive substring check
    defp contains?(message, substring) when is_binary(message) do
      String.contains?(String.downcase(message), substring)
    end

    defp contains?(_, _), do: false
  end
end
