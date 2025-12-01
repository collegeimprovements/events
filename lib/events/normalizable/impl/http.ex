defmodule Events.HttpError do
  @moduledoc """
  Wrapper struct for HTTP error responses.

  Since HTTP status codes are integers and cannot have protocol implementations,
  this struct wraps HTTP error information for normalization.

  ## Usage

      # Wrap an HTTP error response
      error = Events.HttpError.new(404)
      error = Events.HttpError.new(500, body: %{"error" => "Internal error"})

      # Normalize it
      Events.Normalizable.normalize(error)
  """

  @type t :: %__MODULE__{
          status: pos_integer(),
          body: term(),
          headers: [{String.t(), String.t()}],
          url: String.t() | nil,
          method: atom() | nil
        }

  defstruct [:status, :body, :headers, :url, :method]

  @doc """
  Creates a new HTTP error wrapper.

  ## Options

  - `:body` - Response body (parsed or raw)
  - `:headers` - Response headers
  - `:url` - Request URL
  - `:method` - HTTP method (:get, :post, etc.)

  ## Examples

      HttpError.new(404)
      HttpError.new(500, body: %{"error" => "oops"}, url: "https://api.example.com")
  """
  @spec new(pos_integer(), keyword()) :: t()
  def new(status, opts \\ []) when is_integer(status) and status >= 400 do
    %__MODULE__{
      status: status,
      body: Keyword.get(opts, :body),
      headers: Keyword.get(opts, :headers, []),
      url: Keyword.get(opts, :url),
      method: Keyword.get(opts, :method)
    }
  end

  @doc """
  Creates an HTTP error from a Req/Tesla/HTTPoison response.
  """
  @spec from_response(map()) :: t()
  def from_response(%{status: status} = response) when status >= 400 do
    %__MODULE__{
      status: status,
      body: Map.get(response, :body),
      headers: Map.get(response, :headers, []),
      url: get_url(response),
      method: nil
    }
  end

  defp get_url(%{request: %{url: url}}), do: to_string(url)
  defp get_url(%{request_url: url}), do: url
  defp get_url(_), do: nil
end

defimpl Events.Normalizable, for: Events.HttpError do
  @moduledoc """
  Normalizable implementation for HTTP error responses.

  Maps HTTP status codes to appropriate error types and codes.
  """

  alias Events.Error

  def normalize(%Events.HttpError{status: status} = http_error, opts) do
    {type, code, message, recoverable} = map_status(status)

    Error.new(type, code,
      message: Keyword.get(opts, :message, message),
      source: :http,
      recoverable: recoverable,
      details: build_details(http_error),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp build_details(%Events.HttpError{} = error) do
    %{
      status_code: error.status,
      url: error.url,
      method: error.method
    }
    |> maybe_add_body(error.body)
    |> maybe_add_headers(error.headers)
  end

  defp maybe_add_body(details, nil), do: details
  defp maybe_add_body(details, body), do: Map.put(details, :body, body)

  defp maybe_add_headers(details, []), do: details
  defp maybe_add_headers(details, headers), do: Map.put(details, :headers, headers)

  # 4xx Client Errors
  defp map_status(400), do: {:bad_request, :bad_request, "Bad request", false}
  defp map_status(401), do: {:unauthorized, :unauthorized, "Unauthorized", false}
  defp map_status(402), do: {:forbidden, :payment_required, "Payment required", false}
  defp map_status(403), do: {:forbidden, :forbidden, "Forbidden", false}
  defp map_status(404), do: {:not_found, :not_found, "Not found", false}
  defp map_status(405), do: {:bad_request, :method_not_allowed, "Method not allowed", false}
  defp map_status(406), do: {:bad_request, :not_acceptable, "Not acceptable", false}

  defp map_status(407),
    do: {:unauthorized, :proxy_auth_required, "Proxy authentication required", false}

  defp map_status(408), do: {:timeout, :request_timeout, "Request timeout", true}
  defp map_status(409), do: {:conflict, :conflict, "Conflict", false}
  defp map_status(410), do: {:not_found, :gone, "Resource gone", false}
  defp map_status(411), do: {:bad_request, :length_required, "Content-Length required", false}
  defp map_status(412), do: {:validation, :precondition_failed, "Precondition failed", false}
  defp map_status(413), do: {:bad_request, :payload_too_large, "Payload too large", false}
  defp map_status(414), do: {:bad_request, :uri_too_long, "URI too long", false}
  defp map_status(415), do: {:bad_request, :unsupported_media_type, "Unsupported media type", false}
  defp map_status(416), do: {:bad_request, :range_not_satisfiable, "Range not satisfiable", false}
  defp map_status(417), do: {:validation, :expectation_failed, "Expectation failed", false}
  defp map_status(418), do: {:bad_request, :im_a_teapot, "I'm a teapot", false}
  defp map_status(421), do: {:bad_request, :misdirected_request, "Misdirected request", false}
  defp map_status(422), do: {:validation, :unprocessable_entity, "Unprocessable entity", false}
  defp map_status(423), do: {:conflict, :locked, "Resource locked", false}
  defp map_status(424), do: {:validation, :failed_dependency, "Failed dependency", false}
  defp map_status(425), do: {:bad_request, :too_early, "Too early", false}
  defp map_status(426), do: {:bad_request, :upgrade_required, "Upgrade required", false}
  defp map_status(428), do: {:validation, :precondition_required, "Precondition required", false}
  defp map_status(429), do: {:rate_limited, :too_many_requests, "Too many requests", true}

  defp map_status(431),
    do: {:bad_request, :headers_too_large, "Request header fields too large", false}

  defp map_status(451), do: {:forbidden, :unavailable_legal, "Unavailable for legal reasons", false}

  # 5xx Server Errors (generally recoverable)
  defp map_status(500), do: {:external, :internal_server_error, "Internal server error", true}
  defp map_status(501), do: {:external, :not_implemented, "Not implemented", false}
  defp map_status(502), do: {:external, :bad_gateway, "Bad gateway", true}
  defp map_status(503), do: {:external, :service_unavailable, "Service unavailable", true}
  defp map_status(504), do: {:timeout, :gateway_timeout, "Gateway timeout", true}

  defp map_status(505),
    do: {:external, :http_version_not_supported, "HTTP version not supported", false}

  defp map_status(506), do: {:external, :variant_also_negotiates, "Variant also negotiates", false}
  defp map_status(507), do: {:external, :insufficient_storage, "Insufficient storage", false}
  defp map_status(508), do: {:external, :loop_detected, "Loop detected", false}
  defp map_status(510), do: {:external, :not_extended, "Not extended", false}

  defp map_status(511),
    do: {:unauthorized, :network_auth_required, "Network authentication required", false}

  # Fallbacks
  defp map_status(code) when code >= 400 and code < 500,
    do: {:bad_request, :client_error, "Client error (#{code})", false}

  defp map_status(code) when code >= 500,
    do: {:external, :server_error, "Server error (#{code})", true}

  defp map_status(code),
    do: {:unknown, :unknown_status, "Unknown HTTP status (#{code})", false}
end
