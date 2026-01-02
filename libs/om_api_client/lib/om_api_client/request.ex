defmodule OmApiClient.Request do
  @moduledoc """
  Request builder for API clients.

  Provides a chainable API for constructing HTTP requests with
  support for various body formats, authentication, and metadata.

  ## Usage

      Request.new(config)
      |> Request.method(:post)
      |> Request.path("/v1/customers")
      |> Request.json(%{email: "user@example.com"})
      |> Request.header("idempotency-key", key)

  ## Body Formats

  The request builder supports multiple body formats:

  - JSON: `Request.json(req, data)` - Encodes as JSON, sets Content-Type
  - Form: `Request.form(req, data)` - URL-encoded form data
  - Multipart: `Request.multipart(req, parts)` - Multipart form data
  - Raw: `Request.body(req, binary)` - Raw binary body

  ## Query Parameters

      Request.new(config)
      |> Request.query(limit: 100, offset: 0)
      |> Request.query(:filter, "active")  # Add single param

  ## Headers

      Request.new(config)
      |> Request.header("x-custom-header", "value")
      |> Request.headers([{"x-another", "value"}])

  ## Metadata

  Attach metadata for logging/telemetry:

      Request.new(config)
      |> Request.metadata(:operation, :create_customer)
      |> Request.metadata(:customer_id, customer_id)
  """

  @type method :: :get | :post | :put | :patch | :delete | :head | :options
  @type body_type :: :json | :form | :multipart | :raw | nil
  @type header :: {String.t(), String.t()}

  @type t :: %__MODULE__{
          config: map(),
          method: method() | nil,
          path: String.t() | nil,
          query: keyword(),
          headers: [header()],
          body: term(),
          body_type: body_type(),
          timeout: pos_integer() | nil,
          receive_timeout: pos_integer() | nil,
          metadata: map(),
          idempotency_key: String.t() | nil,
          circuit_breaker: atom() | nil,
          rate_limit_key: atom() | nil
        }

  @enforce_keys [:config]
  defstruct [
    :config,
    :method,
    :path,
    :body,
    :body_type,
    :timeout,
    :receive_timeout,
    :idempotency_key,
    :circuit_breaker,
    :rate_limit_key,
    query: [],
    headers: [],
    metadata: %{}
  ]

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Creates a new request with the given configuration.

  The config map typically contains authentication credentials
  and other client-specific settings.

  ## Examples

      Request.new(%{api_key: "sk_test_xxx"})
      Request.new(%{username: "user", password: "pass"})
  """
  @spec new(map()) :: t()
  def new(config) when is_map(config) do
    %__MODULE__{config: config}
  end

  # ============================================
  # Request Building
  # ============================================

  @doc """
  Sets the HTTP method.

  ## Examples

      Request.method(req, :post)
      Request.method(req, :get)
  """
  @spec method(t(), method()) :: t()
  def method(%__MODULE__{} = req, method) when method in [:get, :post, :put, :patch, :delete, :head, :options] do
    %{req | method: method}
  end

  @doc """
  Sets the request path.

  ## Examples

      Request.path(req, "/v1/customers")
      Request.path(req, "/v1/customers/\#{customer_id}")
  """
  @spec path(t(), String.t()) :: t()
  def path(%__MODULE__{} = req, path) when is_binary(path) do
    %{req | path: path}
  end

  @doc """
  Appends a segment to the current path.

  ## Examples

      req
      |> Request.path("/v1/customers")
      |> Request.append_path(customer_id)
      |> Request.append_path("charges")
      # => "/v1/customers/cus_123/charges"
  """
  @spec append_path(t(), String.t()) :: t()
  def append_path(%__MODULE__{path: current} = req, segment) when is_binary(segment) do
    current_path = current || ""
    new_path = String.trim_trailing(current_path, "/") <> "/" <> String.trim_leading(segment, "/")
    %{req | path: new_path}
  end

  @doc """
  Adds query parameters.

  Can be called multiple times; parameters are merged.

  ## Examples

      Request.query(req, limit: 100)
      Request.query(req, limit: 100, offset: 0)
  """
  @spec query(t(), keyword()) :: t()
  def query(%__MODULE__{} = req, params) when is_list(params) do
    %{req | query: Keyword.merge(req.query, params)}
  end

  @doc """
  Adds a single query parameter.

  ## Examples

      Request.query(req, :filter, "active")
  """
  @spec query(t(), atom(), term()) :: t()
  def query(%__MODULE__{} = req, key, value) when is_atom(key) do
    %{req | query: Keyword.put(req.query, key, value)}
  end

  @doc """
  Adds a header to the request.

  ## Examples

      Request.header(req, "x-custom-header", "value")
      Request.header(req, "authorization", "Bearer token")
  """
  @spec header(t(), String.t(), String.t()) :: t()
  def header(%__MODULE__{} = req, name, value) when is_binary(name) and is_binary(value) do
    %{req | headers: [{name, value} | req.headers]}
  end

  @doc """
  Adds multiple headers to the request.

  ## Examples

      Request.headers(req, [{"x-custom", "value"}, {"x-another", "value2"}])
  """
  @spec headers(t(), [header()]) :: t()
  def headers(%__MODULE__{} = req, headers) when is_list(headers) do
    %{req | headers: headers ++ req.headers}
  end

  # ============================================
  # Body Helpers
  # ============================================

  @doc """
  Sets a JSON body.

  Automatically sets Content-Type to application/json.

  ## Examples

      Request.json(req, %{email: "user@example.com"})
      Request.json(req, %{items: [%{id: 1}, %{id: 2}]})
  """
  @spec json(t(), term()) :: t()
  def json(%__MODULE__{} = req, data) do
    req
    |> header("content-type", "application/json")
    |> body(data, :json)
  end

  @doc """
  Sets a form-encoded body.

  Automatically sets Content-Type to application/x-www-form-urlencoded.

  ## Examples

      Request.form(req, email: "user@example.com", name: "John")
  """
  @spec form(t(), keyword() | map()) :: t()
  def form(%__MODULE__{} = req, data) do
    req
    |> header("content-type", "application/x-www-form-urlencoded")
    |> body(data, :form)
  end

  @doc """
  Sets a multipart body for file uploads.

  ## Examples

      Request.multipart(req, [
        {:file, path, filename: "document.pdf"},
        {"field", "value"}
      ])
  """
  @spec multipart(t(), list()) :: t()
  def multipart(%__MODULE__{} = req, parts) when is_list(parts) do
    body(req, parts, :multipart)
  end

  @doc """
  Sets the raw request body.

  ## Examples

      Request.body(req, ~s({"custom": "json"}))
      Request.body(req, <<binary_data::binary>>)
  """
  @spec body(t(), term()) :: t()
  @spec body(t(), term(), body_type()) :: t()
  def body(%__MODULE__{} = req, data, type \\ :raw) do
    %{req | body: data, body_type: type}
  end

  # ============================================
  # Timeout Configuration
  # ============================================

  @doc """
  Sets the connection timeout in milliseconds.

  ## Examples

      Request.timeout(req, 5000)
  """
  @spec timeout(t(), pos_integer()) :: t()
  def timeout(%__MODULE__{} = req, ms) when is_integer(ms) and ms > 0 do
    %{req | timeout: ms}
  end

  @doc """
  Sets the receive timeout in milliseconds.

  ## Examples

      Request.receive_timeout(req, 30_000)
  """
  @spec receive_timeout(t(), pos_integer()) :: t()
  def receive_timeout(%__MODULE__{} = req, ms) when is_integer(ms) and ms > 0 do
    %{req | receive_timeout: ms}
  end

  # ============================================
  # Metadata & Middleware
  # ============================================

  @doc """
  Adds metadata to the request for logging/telemetry.

  ## Examples

      Request.metadata(req, :operation, :create_customer)
      Request.metadata(req, :user_id, user_id)
  """
  @spec metadata(t(), atom(), term()) :: t()
  def metadata(%__MODULE__{} = req, key, value) when is_atom(key) do
    %{req | metadata: Map.put(req.metadata, key, value)}
  end

  @doc """
  Sets the idempotency key for the request.

  ## Examples

      Request.idempotency_key(req, "unique-request-id")
      Request.idempotency_key(req, UUID.uuid4())
  """
  @spec idempotency_key(t(), String.t()) :: t()
  def idempotency_key(%__MODULE__{} = req, key) when is_binary(key) do
    req
    |> header("idempotency-key", key)
    |> Map.put(:idempotency_key, key)
  end

  @doc """
  Associates a circuit breaker with this request.

  ## Examples

      Request.circuit_breaker(req, :stripe_api)
  """
  @spec circuit_breaker(t(), atom()) :: t()
  def circuit_breaker(%__MODULE__{} = req, name) when is_atom(name) do
    %{req | circuit_breaker: name}
  end

  @doc """
  Associates a rate limiter with this request.

  ## Examples

      Request.rate_limit_key(req, :stripe_api)
  """
  @spec rate_limit_key(t(), atom()) :: t()
  def rate_limit_key(%__MODULE__{} = req, name) when is_atom(name) do
    %{req | rate_limit_key: name}
  end

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts the request to Req options.

  This is used internally to execute the request via Req.

  ## Examples

      Request.to_req_options(req)
      #=> [method: :post, url: "/v1/customers", json: %{...}]
  """
  @spec to_req_options(t()) :: keyword()
  def to_req_options(%__MODULE__{} = req) do
    opts = [
      method: req.method || :get,
      url: req.path || "/",
      headers: Enum.reverse(req.headers)
    ]

    opts = if req.query != [], do: Keyword.put(opts, :params, req.query), else: opts
    opts = if req.timeout, do: Keyword.put(opts, :connect_timeout, req.timeout), else: opts
    opts = if req.receive_timeout, do: Keyword.put(opts, :receive_timeout, req.receive_timeout), else: opts

    add_body_to_opts(opts, req.body, req.body_type)
  end

  defp add_body_to_opts(opts, nil, _type), do: opts

  defp add_body_to_opts(opts, body, :json) do
    Keyword.put(opts, :json, body)
  end

  defp add_body_to_opts(opts, body, :form) do
    form_data = if is_map(body), do: Map.to_list(body), else: body
    Keyword.put(opts, :form, form_data)
  end

  defp add_body_to_opts(opts, parts, :multipart) do
    Keyword.put(opts, :form_multipart, parts)
  end

  defp add_body_to_opts(opts, body, :raw) do
    Keyword.put(opts, :body, body)
  end

  defp add_body_to_opts(opts, _body, nil), do: opts
end
