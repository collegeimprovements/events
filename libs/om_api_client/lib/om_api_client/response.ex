defmodule OmApiClient.Response do
  @moduledoc """
  Response wrapper for API clients.

  Wraps HTTP responses with helper functions for common patterns
  like checking status codes, extracting data, and error handling.

  ## Usage

      case Client.get(req, "/users/123") do
        {:ok, %Response{} = resp} ->
          if Response.success?(resp) do
            {:ok, resp.body}
          else
            {:error, Response.error_message(resp)}
          end

        {:error, reason} ->
          {:error, reason}
      end

  ## Pattern Matching

  The response struct supports direct pattern matching:

      {:ok, %Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Response{status: status}} when status >= 500 ->
        {:error, :server_error}

  ## Accessing Data

      Response.get_in(resp, ["data", "user", "email"])
      Response.get_header(resp, "x-request-id")
      Response.get_header(resp, "x-ratelimit-remaining")
  """

  @type header :: {String.t(), String.t()}

  @type t :: %__MODULE__{
          status: pos_integer(),
          headers: [header()] | map(),
          body: term(),
          request_id: String.t() | nil,
          timing_ms: pos_integer() | nil,
          raw: map() | nil
        }

  defstruct [
    :status,
    :body,
    :request_id,
    :timing_ms,
    :raw,
    headers: []
  ]

  # ============================================
  # Constructors
  # ============================================

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
    %__MODULE__{
      status: resp.status,
      headers: normalize_headers(resp.headers),
      body: resp.body,
      request_id: Keyword.get(opts, :request_id),
      timing_ms: Keyword.get(opts, :timing_ms),
      raw: resp
    }
  end

  @doc """
  Creates a Response from a raw HTTP response.

  ## Examples

      Response.new(200, [{"content-type", "application/json"}], %{})
  """
  @spec new(pos_integer(), [header()] | map(), term()) :: t()
  def new(status, headers, body) do
    %__MODULE__{
      status: status,
      headers: normalize_headers(headers),
      body: body
    }
  end

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  # ============================================
  # Status Helpers
  # ============================================

  @doc """
  Returns true if the response indicates success (2xx status).

  ## Examples

      Response.success?(resp)  #=> true for 200, 201, 204
  """
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

  @doc """
  Returns true if the request was rate limited (429 status).

  ## Examples

      Response.rate_limited?(resp)
  """
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{status: 429}), do: true
  def rate_limited?(%__MODULE__{}), do: false

  @doc """
  Returns true if the response indicates an unauthorized request (401 status).

  ## Examples

      Response.unauthorized?(resp)
  """
  @spec unauthorized?(t()) :: boolean()
  def unauthorized?(%__MODULE__{status: 401}), do: true
  def unauthorized?(%__MODULE__{}), do: false

  @doc """
  Returns true if the response indicates a forbidden request (403 status).

  ## Examples

      Response.forbidden?(resp)
  """
  @spec forbidden?(t()) :: boolean()
  def forbidden?(%__MODULE__{status: 403}), do: true
  def forbidden?(%__MODULE__{}), do: false

  @doc """
  Returns true if the resource was not found (404 status).

  ## Examples

      Response.not_found?(resp)
  """
  @spec not_found?(t()) :: boolean()
  def not_found?(%__MODULE__{status: 404}), do: true
  def not_found?(%__MODULE__{}), do: false

  # ============================================
  # Data Access
  # ============================================

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
  @spec get_header(t(), String.t()) :: String.t() | nil
  def get_header(%__MODULE__{headers: headers}, name) when is_binary(name) do
    name = String.downcase(name)

    case List.keyfind(headers, name, 0) do
      {_, value} -> value
      nil -> nil
    end
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

  @doc """
  Converts the response to a result tuple.

  Returns `{:ok, body}` for success, `{:error, error_info}` for errors.

  ## Examples

      case Response.to_result(resp) do
        {:ok, body} -> process(body)
        {:error, %{status: 404}} -> {:error, :not_found}
        {:error, error} -> {:error, error}
      end
  """
  @spec to_result(t()) :: {:ok, term()} | {:error, map()}
  def to_result(%__MODULE__{} = resp) do
    if success?(resp) do
      {:ok, resp.body}
    else
      {:error, %{
        status: resp.status,
        message: error_message(resp),
        code: error_code(resp),
        body: resp.body
      }}
    end
  end

  @doc """
  Converts the response to a result tuple, extracting data from a path.

  ## Examples

      Response.to_result(resp, ["data", "customer"])
      #=> {:ok, %{"id" => "cus_123", ...}}
  """
  @spec to_result(t(), [term()]) :: {:ok, term()} | {:error, map()}
  def to_result(%__MODULE__{} = resp, path) do
    case to_result(resp) do
      {:ok, _body} -> {:ok, __MODULE__.get_in(resp, path)}
      error -> error
    end
  end

  # ============================================
  # Rate Limiting
  # ============================================

  @doc """
  Extracts rate limit information from headers.

  ## Examples

      Response.rate_limit_info(resp)
      #=> %{limit: 100, remaining: 95, reset: 1705334400}
  """
  @spec rate_limit_info(t()) :: %{
          limit: pos_integer() | nil,
          remaining: non_neg_integer() | nil,
          reset: pos_integer() | nil
        }
  def rate_limit_info(%__MODULE__{} = resp) do
    %{
      limit: parse_int(get_header(resp, "x-ratelimit-limit") || get_header(resp, "x-rate-limit-limit")),
      remaining: parse_int(get_header(resp, "x-ratelimit-remaining") || get_header(resp, "x-rate-limit-remaining")),
      reset: parse_int(get_header(resp, "x-ratelimit-reset") || get_header(resp, "x-rate-limit-reset"))
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
