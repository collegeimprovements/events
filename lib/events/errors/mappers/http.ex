defmodule Events.Errors.Mappers.Http do
  @moduledoc """
  Error mapper for HTTP client errors.

  ## Deprecation Notice

  **This module is deprecated.** Use the `Events.Normalizable` protocol with
  `Events.HttpError` wrapper instead:

      # OLD (deprecated)
      Mappers.Http.normalize_status(404)

      # NEW (preferred)
      Events.HttpError.new(404) |> Events.Normalizable.normalize()

      # For Mint errors (protocol implementation exists)
      Events.Normalizable.normalize(%Mint.TransportError{reason: :timeout})

  Handles normalization of errors from HTTP clients like:
  - Req
  - Tesla
  - HTTPoison
  - Mint
  """

  @deprecated "Use Events.HttpError with Events.Normalizable protocol instead"

  alias Events.Errors.Error

  @doc """
  Normalizes HTTP response status codes into Error structs.

  ## Examples

      iex> Http.normalize_status(404)
      %Error{type: :not_found, code: :not_found}

      iex> Http.normalize_status(500)
      %Error{type: :external, code: :internal_server_error}
  """
  @spec normalize_status(integer(), map()) :: Error.t()
  def normalize_status(status_code, details \\ %{}) do
    {type, code, message} = map_status_code(status_code)

    Error.new(type, code,
      message: message,
      details: Map.put(details, :status_code, status_code),
      source: :http
    )
  end

  @doc """
  Normalizes Req errors.
  """
  @spec normalize_req({:error, Exception.t()}) :: Error.t()
  def normalize_req({:error, %{__exception__: true, reason: reason} = error}) do
    # Handle Req.TransportError
    if Map.has_key?(error, :reason) do
      normalize_transport_error(reason)
    else
      # Use Normalizable protocol instead of old mapper
      Events.Normalizable.normalize(error)
    end
  end

  def normalize_req({:error, exception}) do
    # Use Normalizable protocol instead of old mapper
    Events.Normalizable.normalize(exception)
  end

  @doc """
  Normalizes transport/connection errors.
  """
  @spec normalize_transport_error(term()) :: Error.t()
  def normalize_transport_error(:timeout) do
    Error.new(:timeout, :connection_timeout,
      message: "Connection timeout",
      source: :http
    )
  end

  def normalize_transport_error(:econnrefused) do
    Error.new(:network, :connection_refused,
      message: "Connection refused",
      source: :http
    )
  end

  def normalize_transport_error(:ehostunreach) do
    Error.new(:network, :host_unreachable,
      message: "Host unreachable",
      source: :http
    )
  end

  def normalize_transport_error(:nxdomain) do
    Error.new(:network, :dns_error,
      message: "DNS resolution failed",
      source: :http
    )
  end

  def normalize_transport_error(:closed) do
    Error.new(:network, :connection_closed,
      message: "Connection closed",
      source: :http
    )
  end

  def normalize_transport_error(reason) do
    Error.new(:network, :transport_error,
      message: "Network transport error",
      details: %{reason: reason},
      source: :http
    )
  end

  ## HTTP Status Code Mappings

  # 4xx Client Errors
  defp map_status_code(400), do: {:bad_request, :bad_request, "Bad Request"}
  defp map_status_code(401), do: {:unauthorized, :unauthorized, "Unauthorized"}
  defp map_status_code(402), do: {:forbidden, :payment_required, "Payment Required"}
  defp map_status_code(403), do: {:forbidden, :forbidden, "Forbidden"}
  defp map_status_code(404), do: {:not_found, :not_found, "Not Found"}
  defp map_status_code(405), do: {:bad_request, :method_not_allowed, "Method Not Allowed"}
  defp map_status_code(406), do: {:bad_request, :not_acceptable, "Not Acceptable"}

  defp map_status_code(407),
    do: {:unauthorized, :proxy_auth_required, "Proxy Authentication Required"}

  defp map_status_code(408), do: {:timeout, :request_timeout, "Request Timeout"}
  defp map_status_code(409), do: {:conflict, :conflict, "Conflict"}
  defp map_status_code(410), do: {:not_found, :gone, "Gone"}
  defp map_status_code(411), do: {:bad_request, :length_required, "Length Required"}
  defp map_status_code(412), do: {:unprocessable, :precondition_failed, "Precondition Failed"}
  defp map_status_code(413), do: {:bad_request, :payload_too_large, "Payload Too Large"}
  defp map_status_code(414), do: {:bad_request, :uri_too_long, "URI Too Long"}

  defp map_status_code(415),
    do: {:bad_request, :unsupported_media_type, "Unsupported Media Type"}

  defp map_status_code(416), do: {:bad_request, :range_not_satisfiable, "Range Not Satisfiable"}
  defp map_status_code(417), do: {:unprocessable, :expectation_failed, "Expectation Failed"}
  defp map_status_code(418), do: {:bad_request, :im_a_teapot, "I'm a teapot"}
  defp map_status_code(421), do: {:bad_request, :misdirected_request, "Misdirected Request"}
  defp map_status_code(422), do: {:unprocessable, :unprocessable_entity, "Unprocessable Entity"}
  defp map_status_code(423), do: {:conflict, :locked, "Locked"}
  defp map_status_code(424), do: {:unprocessable, :failed_dependency, "Failed Dependency"}
  defp map_status_code(425), do: {:bad_request, :too_early, "Too Early"}
  defp map_status_code(426), do: {:bad_request, :upgrade_required, "Upgrade Required"}
  defp map_status_code(428), do: {:unprocessable, :precondition_required, "Precondition Required"}
  defp map_status_code(429), do: {:rate_limit, :too_many_requests, "Too Many Requests"}

  defp map_status_code(431),
    do: {:bad_request, :headers_too_large, "Request Header Fields Too Large"}

  defp map_status_code(451), do: {:forbidden, :unavailable_legal, "Unavailable For Legal Reasons"}

  # 5xx Server Errors
  defp map_status_code(500), do: {:external, :internal_server_error, "Internal Server Error"}
  defp map_status_code(501), do: {:external, :not_implemented, "Not Implemented"}
  defp map_status_code(502), do: {:external, :bad_gateway, "Bad Gateway"}
  defp map_status_code(503), do: {:service_unavailable, :service_unavailable, "Service Unavailable"}
  defp map_status_code(504), do: {:timeout, :gateway_timeout, "Gateway Timeout"}

  defp map_status_code(505),
    do: {:external, :http_version_not_supported, "HTTP Version Not Supported"}

  defp map_status_code(506), do: {:external, :variant_also_negotiates, "Variant Also Negotiates"}

  defp map_status_code(507),
    do: {:service_unavailable, :insufficient_storage, "Insufficient Storage"}

  defp map_status_code(508), do: {:external, :loop_detected, "Loop Detected"}
  defp map_status_code(510), do: {:external, :not_extended, "Not Extended"}

  defp map_status_code(511),
    do: {:unauthorized, :network_auth_required, "Network Authentication Required"}

  # Fallback for other codes
  defp map_status_code(code) when code >= 400 and code < 500,
    do: {:bad_request, :client_error, "Client Error"}

  defp map_status_code(code) when code >= 500,
    do: {:external, :server_error, "Server Error"}

  defp map_status_code(code), do: {:unknown, :unknown_status, "Unknown HTTP status: #{code}"}
end
