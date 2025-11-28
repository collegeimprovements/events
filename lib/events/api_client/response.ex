defmodule Events.APIClient.Response do
  @moduledoc """
  Unified response wrapper for API client requests.

  Provides a consistent interface for handling responses from external APIs,
  including success/error status, rate limit information, and request tracing.

  ## Structure

      %Response{
        status: 200,
        body: %{"id" => "cus_123", "email" => "user@example.com"},
        headers: %{"x-request-id" => "req_abc"},
        request_id: "local_xyz",
        api_request_id: "stripe_abc",
        rate_limit: %{limit: 100, remaining: 99, reset: ~U[2024-01-15 14:00:00Z]}
      }

  ## Status Helpers

      response |> Response.success?()     # true for 2xx
      response |> Response.client_error?() # true for 4xx
      response |> Response.server_error?() # true for 5xx
      response |> Response.retryable?()   # true for 429, 5xx

  ## Body Access

      response |> Response.get("data")
      response |> Response.get(["customer", "email"])
  """

  @type rate_limit_info :: %{
          limit: non_neg_integer() | nil,
          remaining: non_neg_integer() | nil,
          reset: DateTime.t() | non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          body: term(),
          headers: map(),
          request_id: String.t() | nil,
          api_request_id: String.t() | nil,
          rate_limit: rate_limit_info() | nil,
          timing_ms: non_neg_integer() | nil
        }

  defstruct [
    :status,
    :body,
    :request_id,
    :api_request_id,
    :rate_limit,
    :timing_ms,
    headers: %{}
  ]

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Creates a new Response from Req response data.

  ## Examples

      Response.new(200, body, headers)
      Response.new(200, body, headers, request_id: "req_123")
  """
  @spec new(non_neg_integer(), term(), map() | list(), keyword()) :: t()
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
  Creates a Response from a Req response struct.

  ## Examples

      Response.from_req(req_response)
      Response.from_req(req_response, request_id: "local_123")
  """
  @spec from_req(Req.Response.t(), keyword()) :: t()
  def from_req(%Req.Response{} = resp, opts \\ []) do
    new(resp.status, resp.body, resp.headers, opts)
  end

  # ============================================
  # Status Predicates
  # ============================================

  @doc "Returns true if the response status is 2xx."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}), do: status >= 200 and status < 300

  @doc "Returns true if the response status is 4xx."
  @spec client_error?(t()) :: boolean()
  def client_error?(%__MODULE__{status: status}), do: status >= 400 and status < 500

  @doc "Returns true if the response status is 5xx."
  @spec server_error?(t()) :: boolean()
  def server_error?(%__MODULE__{status: status}), do: status >= 500 and status < 600

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

  @doc "Returns true if the response is a rate limit (429)."
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{status: 429}), do: true
  def rate_limited?(%__MODULE__{}), do: false

  # ============================================
  # Body Access
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

  @doc """
  Gets a header value (case-insensitive).

  ## Examples

      Response.get_header(resp, "x-request-id")
      Response.get_header(resp, "Content-Type")
  """
  @spec get_header(t(), String.t(), term()) :: term()
  def get_header(%__MODULE__{headers: headers}, name, default \\ nil) do
    name_lower = String.downcase(name)
    Map.get(headers, name_lower, default)
  end

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

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, ""} -> seconds * 1000
      _ -> nil
    end
  end

  # ============================================
  # Result Helpers
  # ============================================

  @doc """
  Converts a Response to a result tuple.

  Returns `{:ok, body}` for success, `{:error, response}` for errors.

  ## Examples

      Response.to_result(success_response)
      #=> {:ok, %{"id" => "cus_123"}}

      Response.to_result(error_response)
      #=> {:error, %Response{status: 404, ...}}
  """
  @spec to_result(t()) :: {:ok, term()} | {:error, t()}
  def to_result(%__MODULE__{} = resp) do
    if success?(resp) do
      {:ok, resp.body}
    else
      {:error, resp}
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
  def to_full_result(%__MODULE__{} = resp) do
    if success?(resp) do
      {:ok, resp}
    else
      {:error, resp}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
  end

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
end
