defimpl Events.Protocols.Normalizable, for: Mint.TransportError do
  @moduledoc """
  Normalizable implementation for Mint.TransportError.

  Handles low-level transport/network errors from the Mint HTTP client:
  - Connection timeouts
  - Connection refused
  - DNS resolution failures
  - TLS/SSL errors
  - Socket errors
  """

  alias Events.Types.Error

  def normalize(%Mint.TransportError{reason: reason}, opts) do
    {type, code, message, recoverable} = map_reason(reason)

    Error.new(type, code,
      message: message,
      source: Mint,
      recoverable: recoverable,
      details: %{reason: format_reason(reason)},
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Timeout errors
  defp map_reason(:timeout),
    do: {:timeout, :connection_timeout, "Connection timed out", true}

  # Connection refused
  defp map_reason(:econnrefused),
    do: {:network, :connection_refused, "Connection refused", true}

  defp map_reason(:econnreset),
    do: {:network, :connection_reset, "Connection reset by peer", true}

  defp map_reason(:econnaborted),
    do: {:network, :connection_aborted, "Connection aborted", true}

  # Host/network unreachable
  defp map_reason(:ehostunreach),
    do: {:network, :host_unreachable, "Host unreachable", true}

  defp map_reason(:enetunreach),
    do: {:network, :network_unreachable, "Network unreachable", true}

  defp map_reason(:ehostdown),
    do: {:network, :host_down, "Host is down", true}

  # DNS errors
  defp map_reason(:nxdomain),
    do: {:network, :dns_error, "DNS resolution failed - domain does not exist", false}

  defp map_reason(:enoent),
    do: {:network, :dns_error, "DNS resolution failed", true}

  # Socket errors
  defp map_reason(:closed),
    do: {:network, :connection_closed, "Connection closed unexpectedly", true}

  defp map_reason(:enotconn),
    do: {:network, :not_connected, "Socket is not connected", true}

  defp map_reason(:epipe),
    do: {:network, :broken_pipe, "Broken pipe", true}

  defp map_reason(:emfile),
    do: {:external, :too_many_files, "Too many open files", true}

  defp map_reason(:enfile),
    do: {:external, :file_table_overflow, "File table overflow", true}

  # TLS/SSL errors
  defp map_reason({:tls_alert, {:certificate_expired, _}}),
    do: {:network, :certificate_expired, "TLS certificate expired", false}

  defp map_reason({:tls_alert, {:certificate_revoked, _}}),
    do: {:network, :certificate_revoked, "TLS certificate revoked", false}

  defp map_reason({:tls_alert, {:unknown_ca, _}}),
    do: {:network, :unknown_ca, "Unknown certificate authority", false}

  defp map_reason({:tls_alert, {:handshake_failure, _}}),
    do: {:network, :tls_handshake_failure, "TLS handshake failed", true}

  defp map_reason({:tls_alert, {alert, _}}),
    do: {:network, :tls_error, "TLS error: #{alert}", false}

  defp map_reason({:tls_alert, alert}) when is_atom(alert),
    do: {:network, :tls_error, "TLS error: #{alert}", false}

  # Proxy errors
  defp map_reason({:proxy, reason}),
    do: {:network, :proxy_error, "Proxy error: #{inspect(reason)}", true}

  # Generic fallback
  defp map_reason(reason),
    do: {:network, :transport_error, "Transport error: #{format_reason(reason)}", true}

  defp format_reason(reason) when is_atom(reason), do: reason
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason({type, details}), do: "#{type}: #{inspect(details)}"
  defp format_reason(reason), do: inspect(reason)
end

defimpl Events.Protocols.Normalizable, for: Mint.HTTPError do
  @moduledoc """
  Normalizable implementation for Mint.HTTPError.

  Handles HTTP protocol-level errors (malformed responses, invalid headers, etc.).
  """

  alias Events.Types.Error

  def normalize(%Mint.HTTPError{reason: reason, module: module}, opts) do
    {code, message} = map_http_error(reason)

    Error.new(:external, code,
      message: message,
      source: module || Mint,
      recoverable: recoverable?(reason),
      details: %{reason: format_reason(reason)},
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp map_http_error(:too_many_concurrent_requests),
    do: {:too_many_requests, "Too many concurrent requests"}

  defp map_http_error(:request_body_too_large),
    do: {:payload_too_large, "Request body too large"}

  defp map_http_error(:invalid_response),
    do: {:invalid_response, "Invalid HTTP response"}

  defp map_http_error(:invalid_request),
    do: {:invalid_request, "Invalid HTTP request"}

  defp map_http_error({:invalid_header_name, _}),
    do: {:invalid_header, "Invalid header name"}

  defp map_http_error({:invalid_header_value, _}),
    do: {:invalid_header, "Invalid header value"}

  defp map_http_error(reason),
    do: {:http_protocol_error, "HTTP protocol error: #{format_reason(reason)}"}

  defp recoverable?(:too_many_concurrent_requests), do: true
  defp recoverable?(_), do: false

  defp format_reason(reason) when is_atom(reason), do: reason
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason({type, details}), do: "#{type}: #{inspect(details)}"
  defp format_reason(reason), do: inspect(reason)
end
