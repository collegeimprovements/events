defmodule Events.APIClient.Request do
  @moduledoc """
  Base request token for API client pipelines.

  Provides a chainable, composable API for building HTTP requests
  that can be executed against external APIs.

  ## Quick Start

      Request.new(config)
      |> Request.method(:post)
      |> Request.path("/v1/customers")
      |> Request.json(%{email: "user@example.com"})
      |> Request.execute()

  ## Chainable Options

      Request.new(config)
      |> Request.method(:post)
      |> Request.path("/v1/customers")
      |> Request.header("X-Custom", "value")
      |> Request.query(expand: ["charges"])
      |> Request.json(%{email: "user@example.com"})
      |> Request.timeout({30, :seconds})
      |> Request.retries(3)
      |> Request.idempotency_key(key)

  ## Metadata

  Attach arbitrary metadata for logging, telemetry, or debugging:

      Request.new(config)
      |> Request.metadata(:operation, :create_customer)
      |> Request.metadata(:user_id, "usr_123")
  """

  alias Events.APIClient.Response

  @type method :: :get | :post | :put | :patch | :delete | :head | :options
  @type body :: term()
  @type headers :: [{String.t(), String.t()}]

  @type t :: %__MODULE__{
          config: struct(),
          method: method(),
          path: String.t(),
          query: keyword() | map(),
          headers: headers(),
          body: body(),
          idempotency_key: String.t() | nil,
          retries: non_neg_integer(),
          timeout: pos_integer(),
          metadata: map(),
          circuit_breaker: atom() | nil,
          rate_limit_key: atom() | nil
        }

  defstruct [
    :config,
    :idempotency_key,
    :circuit_breaker,
    :rate_limit_key,
    method: :get,
    path: "/",
    query: [],
    headers: [],
    body: nil,
    retries: 3,
    timeout: 30_000,
    metadata: %{}
  ]

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Creates a new request with the given client config.

  ## Examples

      Request.new(stripe_config)
      Request.new(%Stripe.Config{api_key: "sk_test_..."})
  """
  @spec new(struct()) :: t()
  def new(config) do
    %__MODULE__{config: config}
  end

  # ============================================
  # HTTP Method & Path
  # ============================================

  @doc """
  Sets the HTTP method.

  ## Examples

      req |> Request.method(:post)
      req |> Request.method(:delete)
  """
  @spec method(t(), method()) :: t()
  def method(%__MODULE__{} = req, method)
      when method in [:get, :post, :put, :patch, :delete, :head, :options] do
    %{req | method: method}
  end

  @doc """
  Sets the request path.

  ## Examples

      req |> Request.path("/v1/customers")
      req |> Request.path("/v1/customers/cus_123")
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
    new_path = String.trim_trailing(current, "/") <> "/" <> String.trim_leading(segment, "/")
    %{req | path: new_path}
  end

  # ============================================
  # Query Parameters
  # ============================================

  @doc """
  Sets query parameters, replacing any existing ones.

  ## Examples

      req |> Request.query(limit: 10, offset: 20)
      req |> Request.query(%{expand: ["charges", "invoices"]})
  """
  @spec query(t(), keyword() | map()) :: t()
  def query(%__MODULE__{} = req, params) when is_list(params) or is_map(params) do
    %{req | query: params}
  end

  @doc """
  Adds a single query parameter.

  ## Examples

      req |> Request.put_query(:limit, 10)
  """
  @spec put_query(t(), atom(), term()) :: t()
  def put_query(%__MODULE__{query: query} = req, key, value) when is_atom(key) do
    new_query =
      case query do
        q when is_list(q) -> Keyword.put(q, key, value)
        q when is_map(q) -> Map.put(q, key, value)
      end

    %{req | query: new_query}
  end

  # ============================================
  # Headers
  # ============================================

  @doc """
  Sets headers, replacing any existing ones.

  ## Examples

      req |> Request.headers([{"content-type", "application/json"}])
  """
  @spec headers(t(), headers()) :: t()
  def headers(%__MODULE__{} = req, headers) when is_list(headers) do
    %{req | headers: headers}
  end

  @doc """
  Adds a single header.

  ## Examples

      req |> Request.header("x-custom-header", "value")
      req |> Request.header("idempotency-key", key)
  """
  @spec header(t(), String.t(), String.t()) :: t()
  def header(%__MODULE__{headers: headers} = req, name, value)
      when is_binary(name) and is_binary(value) do
    %{req | headers: [{name, value} | headers]}
  end

  # ============================================
  # Body
  # ============================================

  @doc """
  Sets the request body.

  ## Examples

      req |> Request.body("raw string body")
      req |> Request.body(<<binary_data>>)
  """
  @spec body(t(), term()) :: t()
  def body(%__MODULE__{} = req, body) do
    %{req | body: body}
  end

  @doc """
  Sets a JSON body (will be encoded when executed).

  Also sets the content-type header to application/json.

  ## Examples

      req |> Request.json(%{email: "user@example.com"})
  """
  @spec json(t(), term()) :: t()
  def json(%__MODULE__{} = req, data) do
    req
    |> body({:json, data})
    |> header("content-type", "application/json")
  end

  @doc """
  Sets a form-urlencoded body.

  ## Examples

      req |> Request.form(email: "user@example.com", name: "Jane")
  """
  @spec form(t(), keyword() | map()) :: t()
  def form(%__MODULE__{} = req, data) do
    req
    |> body({:form, data})
    |> header("content-type", "application/x-www-form-urlencoded")
  end

  # ============================================
  # Resilience Options
  # ============================================

  @doc """
  Sets an idempotency key for safe retries.

  ## Examples

      req |> Request.idempotency_key("order_12345_create")
      req |> Request.idempotency_key(UUID.uuid4())
  """
  @spec idempotency_key(t(), String.t()) :: t()
  def idempotency_key(%__MODULE__{} = req, key) when is_binary(key) do
    %{req | idempotency_key: key}
  end

  @doc """
  Sets the number of retry attempts for transient failures.

  ## Examples

      req |> Request.retries(5)
      req |> Request.retries(0)  # Disable retries
  """
  @spec retries(t(), non_neg_integer()) :: t()
  def retries(%__MODULE__{} = req, count) when is_integer(count) and count >= 0 do
    %{req | retries: count}
  end

  @doc """
  Sets the request timeout.

  Accepts milliseconds or duration tuples.

  ## Examples

      req |> Request.timeout(30_000)
      req |> Request.timeout({30, :seconds})
      req |> Request.timeout({2, :minutes})
  """
  @spec timeout(t(), pos_integer() | {pos_integer(), atom()}) :: t()
  def timeout(%__MODULE__{} = req, duration) do
    %{req | timeout: normalize_duration(duration)}
  end

  @doc """
  Sets the circuit breaker to use for this request.

  ## Examples

      req |> Request.circuit_breaker(:stripe_api)
  """
  @spec circuit_breaker(t(), atom()) :: t()
  def circuit_breaker(%__MODULE__{} = req, name) when is_atom(name) do
    %{req | circuit_breaker: name}
  end

  @doc """
  Sets the rate limit key for this request.

  ## Examples

      req |> Request.rate_limit_key(:stripe_api)
  """
  @spec rate_limit_key(t(), atom()) :: t()
  def rate_limit_key(%__MODULE__{} = req, key) when is_atom(key) do
    %{req | rate_limit_key: key}
  end

  # ============================================
  # Metadata
  # ============================================

  @doc """
  Adds metadata to the request.

  Useful for logging, telemetry, or passing context through the request pipeline.

  ## Examples

      req |> Request.metadata(:operation, :create_customer)
      req |> Request.metadata(%{user_id: "123", trace_id: "abc"})
  """
  @spec metadata(t(), atom(), term()) :: t()
  def metadata(%__MODULE__{metadata: meta} = req, key, value) when is_atom(key) do
    %{req | metadata: Map.put(meta, key, value)}
  end

  @spec metadata(t(), map()) :: t()
  def metadata(%__MODULE__{metadata: meta} = req, new_meta) when is_map(new_meta) do
    %{req | metadata: Map.merge(meta, new_meta)}
  end

  @doc """
  Gets a metadata value.

  ## Examples

      Request.get_metadata(req, :operation)
      #=> :create_customer
  """
  @spec get_metadata(t(), atom(), term()) :: term()
  def get_metadata(%__MODULE__{metadata: meta}, key, default \\ nil) when is_atom(key) do
    Map.get(meta, key, default)
  end

  # ============================================
  # Execution
  # ============================================

  @doc """
  Executes the request and returns a Response.

  This is typically called by the client module, not directly.
  The client module should implement the actual HTTP call using Req.

  ## Examples

      Request.new(config)
      |> Request.method(:get)
      |> Request.path("/v1/customers")
      |> Request.execute()
      #=> {:ok, %Response{status: 200, body: %{...}}}
  """
  @spec execute(t(), (t() -> {:ok, Response.t()} | {:error, term()})) ::
          {:ok, Response.t()} | {:error, term()}
  def execute(%__MODULE__{} = req, executor) when is_function(executor, 1) do
    executor.(req)
  end

  # ============================================
  # Helpers
  # ============================================

  @doc """
  Converts the request to Req options.

  Used internally by client implementations.

  ## Examples

      opts = Request.to_req_options(request)
      Req.request(opts)
  """
  @spec to_req_options(t(), keyword()) :: keyword()
  def to_req_options(%__MODULE__{} = req, base_opts \\ []) do
    opts =
      base_opts
      |> Keyword.put(:method, req.method)
      |> Keyword.put(:url, req.path)
      |> maybe_put(:params, normalize_query(req.query))
      |> maybe_put(:headers, req.headers)
      |> Keyword.put(:receive_timeout, req.timeout)

    add_body_option(opts, req.body)
  end

  defp add_body_option(opts, nil), do: opts
  defp add_body_option(opts, {:json, data}), do: Keyword.put(opts, :json, data)
  defp add_body_option(opts, {:form, data}), do: Keyword.put(opts, :form, data)
  defp add_body_option(opts, body), do: Keyword.put(opts, :body, body)

  defp normalize_query([]), do: nil
  defp normalize_query(query) when is_list(query), do: query
  defp normalize_query(query) when is_map(query) and map_size(query) == 0, do: nil
  defp normalize_query(query) when is_map(query), do: Enum.to_list(query)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_duration({n, :second}), do: n * 1000
  defp normalize_duration({n, :seconds}), do: n * 1000
  defp normalize_duration({n, :minute}), do: n * 60_000
  defp normalize_duration({n, :minutes}), do: n * 60_000
  defp normalize_duration({n, :hour}), do: n * 3_600_000
  defp normalize_duration({n, :hours}), do: n * 3_600_000
  defp normalize_duration(ms) when is_integer(ms), do: ms
end
