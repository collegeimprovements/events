# Implementation for Mint.TransportError
# These are low-level HTTP transport errors

if Code.ensure_loaded?(Mint.TransportError) do
  defimpl Events.Protocols.Recoverable, for: Mint.TransportError do
    @moduledoc """
    Recoverable implementation for Mint transport errors.

    These are low-level network errors from the Mint HTTP client:
    - Connection refused
    - Connection reset
    - Timeouts
    - TLS errors
    - DNS failures

    Most transport errors are transient and recoverable, except for
    certificate/TLS errors which indicate configuration issues.
    """

    alias Events.Protocols.Recoverable.Backoff

    # Errors that are definitely transient
    @transient_reasons [
      :timeout,
      :closed,
      :econnrefused,
      :econnreset,
      :enotconn,
      :epipe,
      :etimedout,
      :ehostunreach,
      :enetunreach,
      :eaddrnotavail
    ]

    # Errors that indicate network issues but may be intermittent
    @network_reasons [:nxdomain, :enoent, :einval]

    # TLS/certificate errors - usually permanent configuration issues
    @tls_reasons [
      :bad_cert,
      :certificate_expired,
      :certificate_revoked,
      :certificate_unknown,
      :unknown_ca,
      :handshake_failure
    ]

    @impl true
    def recoverable?(%{reason: reason}) when reason in @transient_reasons, do: true
    def recoverable?(%{reason: reason}) when reason in @network_reasons, do: true
    def recoverable?(%{reason: reason}) when reason in @tls_reasons, do: false
    def recoverable?(%{reason: {:tls_alert, _}}), do: false
    def recoverable?(_), do: true

    @impl true
    def strategy(%{reason: :timeout}), do: :retry
    def strategy(%{reason: :etimedout}), do: :retry

    def strategy(%{reason: reason}) when reason in [:econnrefused, :ehostunreach, :enetunreach] do
      :circuit_break
    end

    def strategy(%{reason: reason}) when reason in @tls_reasons, do: :fail_fast
    def strategy(%{reason: {:tls_alert, _}}), do: :fail_fast
    def strategy(_), do: :retry_with_backoff

    @impl true
    def retry_delay(%{reason: reason}, _attempt) when reason in [:timeout, :etimedout] do
      # Quick retry for timeouts
      Backoff.fixed(1, delay: 1_000)
    end

    def retry_delay(%{reason: reason}, attempt) when reason in [:econnrefused, :ehostunreach] do
      # Longer backoff for connection issues
      Backoff.exponential(attempt, base: 2_000, max: 30_000)
    end

    def retry_delay(_, attempt) do
      Backoff.exponential(attempt, base: 1_000, max: 15_000)
    end

    @impl true
    def max_attempts(%{reason: reason}) when reason in [:timeout, :etimedout], do: 3
    def max_attempts(%{reason: reason}) when reason in [:econnrefused, :ehostunreach], do: 2
    def max_attempts(%{reason: reason}) when reason in @tls_reasons, do: 1
    def max_attempts(_), do: 3

    @impl true
    def trips_circuit?(%{reason: reason})
        when reason in [:econnrefused, :ehostunreach, :enetunreach] do
      true
    end

    def trips_circuit?(%{reason: :econnreset}), do: true
    def trips_circuit?(_), do: false

    @impl true
    def severity(%{reason: reason}) when reason in [:timeout, :etimedout, :closed], do: :transient
    def severity(%{reason: reason}) when reason in [:econnrefused, :ehostunreach], do: :degraded
    def severity(%{reason: reason}) when reason in @tls_reasons, do: :permanent
    def severity(%{reason: {:tls_alert, _}}), do: :permanent
    def severity(_), do: :transient

    @impl true
    def fallback(_), do: nil
  end
end

# Implementation for Mint.HTTPError
if Code.ensure_loaded?(Mint.HTTPError) do
  defimpl Events.Protocols.Recoverable, for: Mint.HTTPError do
    @moduledoc """
    Recoverable implementation for Mint HTTP protocol errors.

    These are HTTP-level errors (not transport), typically indicating
    protocol violations or malformed responses.
    """

    alias Events.Protocols.Recoverable.Backoff

    @impl true
    def recoverable?(%{reason: :timeout}), do: true
    def recoverable?(%{reason: {:server_closed_connection, _}}), do: true
    def recoverable?(_), do: false

    @impl true
    def strategy(%{reason: :timeout}), do: :retry
    def strategy(%{reason: {:server_closed_connection, _}}), do: :retry_with_backoff
    def strategy(_), do: :fail_fast

    @impl true
    def retry_delay(%{reason: :timeout}, _), do: Backoff.fixed(1, delay: 1_000)
    def retry_delay(_, attempt), do: Backoff.exponential(attempt, base: 500, max: 5_000)

    @impl true
    def max_attempts(%{reason: :timeout}), do: 3
    def max_attempts(_), do: 2

    @impl true
    def trips_circuit?(%{reason: {:server_closed_connection, _}}), do: true
    def trips_circuit?(_), do: false

    @impl true
    def severity(%{reason: :timeout}), do: :transient
    def severity(%{reason: {:server_closed_connection, _}}), do: :degraded
    def severity(_), do: :permanent

    @impl true
    def fallback(_), do: nil
  end
end
