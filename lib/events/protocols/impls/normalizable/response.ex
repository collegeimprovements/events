defimpl FnTypes.Protocols.Normalizable, for: Events.Api.Client.Response do
  @moduledoc """
  Normalizable implementation for API Response structs.

  Converts HTTP responses with error status codes to standardized FnTypes.Error
  structs. Uses the same status code mapping as HttpError for consistency.
  """

  alias FnTypes.Error
  alias Events.Api.Client.Response

  def normalize(%Response{status: status} = response, opts) when status >= 400 do
    {type, code, message, recoverable} = map_status(status)

    Error.new(type, code,
      message: extract_message(response, opts, message),
      source: :http,
      recoverable: recoverable,
      details: build_details(response),
      context: build_context(response, opts),
      step: Keyword.get(opts, :step)
    )
  end

  def normalize(%Response{status: status, body: body}, _opts) when status in 200..299 do
    # For success responses, return an error indicating misuse
    Error.new(:internal, :not_an_error,
      message: "Cannot normalize successful response (status #{status})",
      source: :http,
      recoverable: false,
      details: %{status: status, body: body}
    )
  end

  def normalize(%Response{status: status} = response, opts) do
    # For other status codes (1xx, 3xx), treat as unexpected
    Error.new(:unexpected, :unexpected_status,
      message: "Unexpected HTTP status: #{status}",
      source: :http,
      recoverable: false,
      details: build_details(response),
      context: build_context(response, opts)
    )
  end

  defp extract_message(response, opts, default) do
    Keyword.get(opts, :message) ||
      extract_error_message(response.body) ||
      default
  end

  defp extract_error_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error_message(%{"error" => msg}) when is_binary(msg), do: msg
  defp extract_error_message(%{"message" => msg}), do: msg
  defp extract_error_message(%{"errors" => [%{"message" => msg} | _]}), do: msg
  defp extract_error_message(body) when is_binary(body) and byte_size(body) < 500, do: body
  defp extract_error_message(_), do: nil

  defp build_details(%Response{} = response) do
    %{
      status_code: response.status,
      api_request_id: response.api_request_id,
      timing_ms: response.timing_ms
    }
    |> maybe_add_body(response.body)
    |> maybe_add_rate_limit(response.rate_limit)
  end

  defp maybe_add_body(details, nil), do: details
  defp maybe_add_body(details, body) when is_map(body), do: Map.put(details, :body, body)

  defp maybe_add_body(details, body) when is_binary(body) and byte_size(body) < 1000 do
    Map.put(details, :body, body)
  end

  defp maybe_add_body(details, _), do: details

  defp maybe_add_rate_limit(details, nil), do: details
  defp maybe_add_rate_limit(details, rate_limit), do: Map.put(details, :rate_limit, rate_limit)

  defp build_context(response, opts) do
    base_context = Keyword.get(opts, :context, %{})

    Map.merge(base_context, %{
      request_id: response.request_id,
      api_request_id: response.api_request_id
    })
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # 4xx Client Errors
  defp map_status(400), do: {:bad_request, :bad_request, "Bad request", false}
  defp map_status(401), do: {:unauthorized, :unauthorized, "Unauthorized", false}
  defp map_status(402), do: {:forbidden, :payment_required, "Payment required", false}
  defp map_status(403), do: {:forbidden, :forbidden, "Forbidden", false}
  defp map_status(404), do: {:not_found, :not_found, "Not found", false}
  defp map_status(405), do: {:bad_request, :method_not_allowed, "Method not allowed", false}
  defp map_status(408), do: {:timeout, :request_timeout, "Request timeout", true}
  defp map_status(409), do: {:conflict, :conflict, "Conflict", false}
  defp map_status(410), do: {:not_found, :gone, "Resource gone", false}
  defp map_status(422), do: {:validation, :unprocessable_entity, "Unprocessable entity", false}
  defp map_status(429), do: {:rate_limited, :too_many_requests, "Too many requests", true}

  # 5xx Server Errors (generally recoverable)
  defp map_status(500), do: {:external, :internal_server_error, "Internal server error", true}
  defp map_status(502), do: {:external, :bad_gateway, "Bad gateway", true}
  defp map_status(503), do: {:external, :service_unavailable, "Service unavailable", true}
  defp map_status(504), do: {:timeout, :gateway_timeout, "Gateway timeout", true}

  # Fallbacks
  defp map_status(code) when code >= 400 and code < 500 do
    {:bad_request, :client_error, "Client error (#{code})", false}
  end

  defp map_status(code) when code >= 500 do
    {:external, :server_error, "Server error (#{code})", true}
  end

  defp map_status(code) do
    {:unknown, :unknown_status, "Unknown HTTP status (#{code})", false}
  end
end
