defmodule OmApiClient.Response do
  @moduledoc """
  Response wrapper for API clients.

  Wraps HTTP responses with helper functions for common patterns
  like checking status codes, extracting data, and error handling.

  Implements `OmIdempotency.Response` for use with idempotency middleware.

  ## Structure

      %Response{
        status: 200,
        body: %{"id" => "cus_123", "email" => "user@example.com"},
        headers: %{"x-request-id" => "req_abc"},
        request_id: "local_xyz",
        api_request_id: "stripe_abc",
        rate_limit: %{limit: 100, remaining: 99, reset: ~U[2024-01-15 14:00:00Z]},
        timing_ms: 150
      }

  ## Pattern Matching

  The response struct supports direct pattern matching:

      {:ok, %Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Response{status: status}} when status >= 500 ->
        {:error, :server_error}

  ## Status Helpers

      response |> Response.success?()     # true for 2xx
      response |> Response.client_error?() # true for 4xx
      response |> Response.server_error?() # true for 5xx
      response |> Response.retryable?()   # true for 429, 5xx

  ## Accessing Data

      Response.get_in(resp, ["data", "user", "email"])
      Response.get_header(resp, "x-request-id")
      Response.get_header(resp, "x-ratelimit-remaining")
  """

  @behaviour OmIdempotency.Response

  @type rate_limit_info :: %{
          limit: non_neg_integer() | nil,
          remaining: non_neg_integer() | nil,
          reset: DateTime.t() | non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          status: pos_integer(),
          headers: map(),
          body: term(),
          request_id: String.t() | nil,
          api_request_id: String.t() | nil,
          rate_limit: rate_limit_info() | nil,
          timing_ms: pos_integer() | nil,
          raw: map() | nil
        }

  defstruct [
    :status,
    :body,
    :request_id,
    :api_request_id,
    :rate_limit,
    :timing_ms,
    :raw,
    headers: %{}
  ]

  # ============================================
  # Constructors
  # ============================================

  @doc """
  Creates a new Response from status, body, and headers.

  ## Options

  - `:request_id` - Local request ID for tracing
  - `:api_request_id` - API provider's request ID
  - `:timing_ms` - Request timing in milliseconds

  ## Examples

      Response.new(200, body, headers)
      Response.new(200, body, headers, request_id: "req_123")
  """
  @spec new(pos_integer(), term(), map() | list(), keyword()) :: t()
  def new(status, body, headers, opts \\ []) do
    headers_map = normalize_headers(headers)

    %__MODULE__{
      status: status,
      body: body,
      headers: headers_map,
      request_id: Keyword.get(opts, :request_id),
      api_request_id: extract_api_request_id(headers_map, opts),
      rate_limit: extract_rate_limit(headers_map),
      timing_ms: Keyword.get(opts, :timing_ms)
    }
  end

  @doc """
  Creates a Response from a Req response.

  ## Options

  - `:request_id` - Attach a request ID for tracing
  - `:timing_ms` - Request timing in milliseconds

  ## Examples

      Response.from_req(req_response)
      Response.from_req(req_response, request_id: "req_abc123")
  """
  @spec from_req(Req.Response.t(), keyword()) :: t()
  def from_req(%Req.Response{} = resp, opts \\ []) do
    headers_map = normalize_headers(resp.headers)

    %__MODULE__{
      status: resp.status,
      headers: headers_map,
      body: resp.body,
      request_id: Keyword.get(opts, :request_id),
      api_request_id: extract_api_request_id(headers_map, opts),
      rate_limit: extract_rate_limit(headers_map),
      timing_ms: Keyword.get(opts, :timing_ms),
      raw: resp
    }
  end

  # ============================================
  # Status Helpers
  # ============================================

  @doc """
  Returns true if the response indicates success (2xx status).

  ## Examples

      Response.success?(resp)  #=> true for 200, 201, 204
  """
  @impl OmIdempotency.Response
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}), do: status >= 200 and status < 300

  @doc """
  Returns true if the response indicates a client error (4xx status).

  ## Examples

      Response.client_error?(resp)  #=> true for 400, 404, 422
  """
  @spec client_error?(t()) :: boolean()
  def client_error?(%__MODULE__{status: status}), do: status >= 400 and status < 500

  @doc """
  Returns true if the response indicates a server error (5xx status).

  ## Examples

      Response.server_error?(resp)  #=> true for 500, 502, 503
  """
  @spec server_error?(t()) :: boolean()
  def server_error?(%__MODULE__{status: status}), do: status >= 500

  @doc """
  Returns true if the response indicates any error (4xx or 5xx).

  ## Examples

      Response.error?(resp)  #=> true for 400, 404, 500, etc.
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{} = resp), do: client_error?(resp) or server_error?(resp)

  @doc "Returns true if the response status is 1xx."
  @spec informational?(t()) :: boolean()
  def informational?(%__MODULE__{status: status}), do: status >= 100 and status < 200

  @doc "Returns true if the response status is 3xx."
  @spec redirect?(t()) :: boolean()
  def redirect?(%__MODULE__{status: status}), do: status >= 300 and status < 400

  @doc """
  Returns true if the request can be safely retried.

  Retryable conditions:
  - 429 Too Many Requests
  - 5xx Server errors
  - 408 Request Timeout
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{status: 429}), do: true
  def retryable?(%__MODULE__{status: 408}), do: true
  def retryable?(%__MODULE__{status: status}), do: status >= 500 and status < 600

  @doc """
  Returns true if the request was rate limited (429 status).

  ## Examples

      Response.rate_limited?(resp)
  """
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{status: 429}), do: true
  def rate_limited?(%__MODULE__{}), do: false

  @doc "Returns true if the response indicates an unauthorized request (401 status)."
  @spec unauthorized?(t()) :: boolean()
  def unauthorized?(%__MODULE__{status: 401}), do: true
  def unauthorized?(%__MODULE__{}), do: false

  @doc "Returns true if the response indicates a forbidden request (403 status)."
  @spec forbidden?(t()) :: boolean()
  def forbidden?(%__MODULE__{status: 403}), do: true
  def forbidden?(%__MODULE__{}), do: false

  @doc "Returns true if the resource was not found (404 status)."
  @spec not_found?(t()) :: boolean()
  def not_found?(%__MODULE__{status: 404}), do: true
  def not_found?(%__MODULE__{}), do: false

  # ============================================
  # Data Access
  # ============================================

  @doc """
  Gets a value from the response body.

  Supports nested access with a list of keys.

  ## Examples

      Response.get(resp, "id")
      #=> "cus_123"

      Response.get(resp, ["customer", "email"])
      #=> "user@example.com"

      Response.get(resp, "missing", "default")
      #=> "default"
  """
  @spec get(t(), String.t() | atom() | [String.t() | atom()], term()) :: term()
  def get(response, key, default \\ nil)

  def get(%__MODULE__{body: body}, key, default) when is_binary(key) or is_atom(key) do
    get_in_body(body, [key], default)
  end

  def get(%__MODULE__{body: body}, keys, default) when is_list(keys) do
    get_in_body(body, keys, default)
  end

  @doc """
  Gets a value from the response body using a path.

  ## Examples

      Response.get_in(resp, ["data", "user", "email"])
      Response.get_in(resp, ["errors", Access.at(0), "message"])
  """
  @spec get_in(t(), [term()]) :: term()
  def get_in(%__MODULE__{body: body}, path) when is_list(path) and is_map(body) do
    Kernel.get_in(body, path)
  end

  def get_in(%__MODULE__{}, _path), do: nil

  @doc """
  Gets a header value by name (case-insensitive).

  ## Examples

      Response.get_header(resp, "content-type")
      Response.get_header(resp, "x-request-id")
  """
  @spec get_header(t(), String.t(), term()) :: term()
  def get_header(%__MODULE__{headers: headers}, name, default \\ nil) when is_binary(name) do
    name_lower = String.downcase(name)
    Map.get(headers, name_lower, default)
  end

  @doc """
  Gets the Content-Type header.

  ## Examples

      Response.content_type(resp)
      #=> "application/json"
  """
  @spec content_type(t()) :: String.t() | nil
  def content_type(%__MODULE__{} = resp) do
    case get_header(resp, "content-type") do
      nil -> nil
      value -> value |> String.split(";") |> List.first() |> String.trim()
    end
  end

  # ============================================
  # Error Handling
  # ============================================

  @doc """
  Extracts an error message from the response body.

  Tries common error message locations:
  - `error.message`
  - `error`
  - `message`
  - `errors[0].message`

  ## Examples

      Response.error_message(resp)
      #=> "Invalid API key"
  """
  @spec error_message(t()) :: String.t() | nil
  def error_message(%__MODULE__{body: body}) when is_map(body) do
    cond do
      is_binary(body["error"]) ->
        body["error"]

      is_map(body["error"]) and is_binary(body["error"]["message"]) ->
        body["error"]["message"]

      is_binary(body["message"]) ->
        body["message"]

      is_list(body["errors"]) and length(body["errors"]) > 0 ->
        body["errors"] |> List.first() |> Map.get("message")

      is_binary(body["detail"]) ->
        body["detail"]

      true ->
        nil
    end
  end

  def error_message(%__MODULE__{body: body}) when is_binary(body), do: body
  def error_message(%__MODULE__{}), do: nil

  @doc """
  Extracts an error code from the response body.

  Tries common error code locations:
  - `error.code`
  - `code`
  - `error.type`

  ## Examples

      Response.error_code(resp)
      #=> "invalid_api_key"
  """
  @spec error_code(t()) :: String.t() | atom() | nil
  def error_code(%__MODULE__{body: body}) when is_map(body) do
    cond do
      is_map(body["error"]) and body["error"]["code"] ->
        body["error"]["code"]

      body["code"] ->
        body["code"]

      is_map(body["error"]) and body["error"]["type"] ->
        body["error"]["type"]

      body["type"] ->
        body["type"]

      true ->
        nil
    end
  end

  def error_code(%__MODULE__{}), do: nil

  # ============================================
  # Result Helpers
  # ============================================

  @doc """
  Converts the response to a result tuple.

  Returns `{:ok, body}` for success, `{:error, response}` for errors.

  ## Examples

      Response.to_result(success_response)
      #=> {:ok, %{"id" => "cus_123"}}

      Response.to_result(error_response)
      #=> {:error, %Response{status: 404, ...}}
  """
  @spec to_result(t()) :: {:ok, term()} | {:error, t()}
  def to_result(%__MODULE__{status: status, body: body}) when status in 200..299 do
    {:ok, body}
  end

  def to_result(%__MODULE__{} = resp), do: {:error, resp}

  @doc """
  Converts the response to a result tuple, extracting data from a path.

  ## Examples

      Response.to_result(resp, ["data", "customer"])
      #=> {:ok, %{"id" => "cus_123", ...}}
  """
  @spec to_result(t(), [term()]) :: {:ok, term()} | {:error, t()}
  def to_result(%__MODULE__{} = resp, path) do
    case to_result(resp) do
      {:ok, _body} -> {:ok, __MODULE__.get_in(resp, path)}
      error -> error
    end
  end

  @doc """
  Converts a Response to a result tuple with the full response.

  Returns `{:ok, response}` for success, `{:error, response}` for errors.

  ## Examples

      Response.to_full_result(success_response)
      #=> {:ok, %Response{status: 200, ...}}
  """
  @spec to_full_result(t()) :: {:ok, t()} | {:error, t()}
  def to_full_result(%__MODULE__{status: status} = resp) when status in 200..299 do
    {:ok, resp}
  end

  def to_full_result(%__MODULE__{} = resp), do: {:error, resp}

  @doc """
  Unwraps a successful response or returns an error.

  Similar to `to_result/1` but with better pattern matching support.

  ## Examples

      case Response.unwrap(response) do
        {:ok, %{"id" => id}} -> {:ok, id}
        {:error, %Response{status: 404}} -> {:error, :not_found}
        {:error, %Response{status: 422, body: body}} -> {:error, body["errors"]}
        {:error, resp} -> {:error, resp}
      end
  """
  @spec unwrap(t()) :: {:ok, term()} | {:error, t()}
  def unwrap(%__MODULE__{status: status, body: body}) when status in 200..299 do
    {:ok, body}
  end

  def unwrap(%__MODULE__{} = resp), do: {:error, resp}

  @doc """
  Transforms the response body if successful.

  ## Examples

      response
      |> Response.map(fn body -> body["data"] end)
      #=> {:ok, data} or {:error, response}
  """
  @spec map(t(), (term() -> term())) :: {:ok, term()} | {:error, t()}
  def map(%__MODULE__{status: status, body: body}, fun) when status in 200..299 do
    {:ok, fun.(body)}
  end

  def map(%__MODULE__{} = resp, _fun), do: {:error, resp}

  @doc """
  Transforms both success and error cases.

  ## Examples

      response
      |> Response.map_both(
        fn body -> body["user"] end,
        fn resp -> %{status: resp.status, message: resp.body["error"]} end
      )
  """
  @spec map_both(t(), (term() -> term()), (t() -> term())) :: {:ok, term()} | {:error, term()}
  def map_both(%__MODULE__{status: status, body: body}, success_fn, _error_fn)
      when status in 200..299 do
    {:ok, success_fn.(body)}
  end

  def map_both(%__MODULE__{} = resp, _success_fn, error_fn) do
    {:error, error_fn.(resp)}
  end

  # ============================================
  # Pattern Matching Helpers
  # ============================================

  @doc """
  Pattern matches on response status and returns appropriate result.

  Useful for handling different status codes with pattern matching.

  ## Examples

      case Response.categorize(response) do
        {:ok, body} -> process_success(body)
        {:not_found, _} -> handle_not_found()
        {:rate_limited, resp} -> wait_and_retry(resp)
        {:client_error, resp} -> handle_client_error(resp)
        {:server_error, resp} -> handle_server_error(resp)
      end
  """
  @spec categorize(t()) ::
          {:ok, term()}
          | {:created, term()}
          | {:accepted, term()}
          | {:no_content, nil}
          | {:not_found, t()}
          | {:unauthorized, t()}
          | {:forbidden, t()}
          | {:unprocessable, t()}
          | {:rate_limited, t()}
          | {:client_error, t()}
          | {:server_error, t()}
          | {:error, t()}
  def categorize(%__MODULE__{status: 200, body: body}), do: {:ok, body}
  def categorize(%__MODULE__{status: 201, body: body}), do: {:created, body}
  def categorize(%__MODULE__{status: 202, body: body}), do: {:accepted, body}
  def categorize(%__MODULE__{status: 204}), do: {:no_content, nil}
  def categorize(%__MODULE__{status: 401} = resp), do: {:unauthorized, resp}
  def categorize(%__MODULE__{status: 403} = resp), do: {:forbidden, resp}
  def categorize(%__MODULE__{status: 404} = resp), do: {:not_found, resp}
  def categorize(%__MODULE__{status: 422} = resp), do: {:unprocessable, resp}
  def categorize(%__MODULE__{status: 429} = resp), do: {:rate_limited, resp}

  def categorize(%__MODULE__{status: status} = resp) when status in 400..499,
    do: {:client_error, resp}

  def categorize(%__MODULE__{status: status} = resp) when status in 500..599,
    do: {:server_error, resp}

  def categorize(%__MODULE__{status: status, body: body}) when status in 200..299, do: {:ok, body}
  def categorize(%__MODULE__{} = resp), do: {:error, resp}

  # ============================================
  # Rate Limit Helpers
  # ============================================

  @doc """
  Returns the time in milliseconds until rate limit resets.

  Returns nil if no rate limit info is available.

  ## Examples

      Response.retry_after_ms(resp)
      #=> 5000
  """
  @spec retry_after_ms(t()) :: non_neg_integer() | nil
  def retry_after_ms(%__MODULE__{headers: headers, rate_limit: rate_limit}) do
    # First check for Retry-After header
    case Map.get(headers, "retry-after") do
      nil ->
        # Fall back to rate limit reset time
        case rate_limit do
          nil ->
            nil

          %{reset: nil} ->
            nil

          %{reset: reset} when is_integer(reset) ->
            now = System.system_time(:second)
            max(0, (reset - now) * 1000)

          %{reset: %DateTime{} = reset} ->
            now = DateTime.utc_now()
            diff = DateTime.diff(reset, now, :millisecond)
            max(0, diff)
        end

      seconds when is_binary(seconds) ->
        parse_retry_after(seconds)

      seconds when is_integer(seconds) ->
        seconds * 1000
    end
  end

  @doc """
  Extracts rate limit information from headers.

  ## Examples

      Response.rate_limit_info(resp)
      #=> %{limit: 100, remaining: 95, reset: 1705334400}
  """
  @spec rate_limit_info(t()) :: rate_limit_info() | nil
  def rate_limit_info(%__MODULE__{rate_limit: rate_limit}), do: rate_limit

  # ============================================
  # OmIdempotency.Response Implementation
  # ============================================

  @impl OmIdempotency.Response
  @spec status(t()) :: non_neg_integer()
  def status(%__MODULE__{status: status}), do: status

  @impl OmIdempotency.Response
  @spec body(t()) :: term()
  def body(%__MODULE__{body: body}), do: body

  @impl OmIdempotency.Response
  @spec headers(t()) :: map()
  def headers(%__MODULE__{headers: headers}), do: headers

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp get_in_body(body, keys, default) when is_map(body) do
    case get_nested(body, keys) do
      nil -> default
      value -> value
    end
  end

  defp get_in_body(_body, _keys, default), do: default

  defp get_nested(value, []), do: value

  defp get_nested(body, [key | rest]) when is_map(body) do
    value = Map.get(body, key) || Map.get(body, to_string(key))

    case value do
      nil -> nil
      v -> get_nested(v, rest)
    end
  end

  defp get_nested(_body, _keys), do: nil

  defp extract_api_request_id(headers, opts) do
    Keyword.get(opts, :api_request_id) ||
      Map.get(headers, "x-request-id") ||
      Map.get(headers, "x-stripe-request-id") ||
      Map.get(headers, "x-github-request-id") ||
      Map.get(headers, "request-id")
  end

  defp extract_rate_limit(headers) do
    limit =
      parse_int(Map.get(headers, "x-ratelimit-limit") || Map.get(headers, "x-rate-limit-limit"))

    remaining =
      parse_int(
        Map.get(headers, "x-ratelimit-remaining") || Map.get(headers, "x-rate-limit-remaining")
      )

    reset =
      parse_reset(Map.get(headers, "x-ratelimit-reset") || Map.get(headers, "x-rate-limit-reset"))

    case {limit, remaining, reset} do
      {nil, nil, nil} -> nil
      _ -> %{limit: limit, remaining: remaining, reset: reset}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_reset(nil), do: nil

  defp parse_reset(value) when is_binary(value) do
    case Integer.parse(value) do
      {timestamp, ""} -> timestamp
      _ -> nil
    end
  end

  defp parse_reset(value) when is_integer(value), do: value

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, ""} -> seconds * 1000
      _ -> nil
    end
  end
end

# ============================================
# Protocol Implementations
# ============================================

defimpl FnTypes.Protocols.Normalizable, for: OmApiClient.Response do
  @moduledoc """
  Normalizable implementation for API Response structs.

  Converts HTTP responses with error status codes to standardized FnTypes.Error
  structs. Uses the same status code mapping as HttpError for consistency.
  """

  alias FnTypes.Error
  alias OmApiClient.Response

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

defimpl FnTypes.Protocols.Recoverable, for: OmApiClient.Response do
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

  alias OmApiClient.Response
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
