defmodule Events.Idempotency.Middleware do
  @moduledoc """
  Idempotency middleware for API client requests.

  Wraps API calls with idempotency protection, automatically:
  - Checking for cached responses before making requests
  - Storing successful responses for future deduplication
  - Handling concurrent duplicate requests

  ## Usage

  ### With Request Pipeline

      alias Events.Idempotency.Middleware, as: IdempotencyMiddleware

      Request.new(config)
      |> Request.idempotency_key(Idempotency.generate_key(:create_charge, order_id: 123))
      |> Request.method(:post)
      |> Request.path("/v1/charges")
      |> Request.json(%{amount: 1000})
      |> IdempotencyMiddleware.wrap(fn req -> Stripe.execute(req) end)

  ### Automatic Integration

  API clients can integrate idempotency automatically:

      defmodule MyApp.StripeClient do
        use Events.APIClient, base_url: "https://api.stripe.com"

        # This automatically wraps mutating requests with idempotency
        plug Events.Idempotency.Middleware, scope: "stripe"
      end

  ## Options

  - `:scope` - Scope for idempotency keys (default: derived from base_url)
  - `:ttl` - Time-to-live for cached responses (default: 24 hours)
  - `:enabled` - Whether to enable idempotency (default: true for POST/PUT/PATCH)
  - `:on_duplicate` - How to handle duplicates: `:return`, `:wait`, `:error`

  ## When Idempotency is Applied

  By default, idempotency is only applied to:
  - Requests with an idempotency_key set
  - POST, PUT, PATCH requests (mutating operations)

  GET, DELETE, HEAD, OPTIONS are idempotent by nature and don't need tracking.
  """

  require Logger

  alias Events.APIClient.Request
  alias Events.APIClient.Response
  alias Events.Idempotency

  @type opts :: [
          scope: String.t(),
          ttl: pos_integer(),
          enabled: boolean() | :auto,
          on_duplicate: :return | :wait | :error
        ]

  @mutating_methods [:post, :put, :patch]

  @doc """
  Wraps an API call with idempotency protection.

  ## Examples

      # With explicit key
      Request.new(config)
      |> Request.idempotency_key("order_123")
      |> Middleware.wrap(fn req -> Client.execute(req) end)

      # With options
      Request.new(config)
      |> Request.idempotency_key("order_123")
      |> Middleware.wrap(fn req -> Client.execute(req) end, scope: "stripe")
  """
  @spec wrap(Request.t(), (Request.t() -> {:ok, Response.t()} | {:error, term()}), opts()) ::
          {:ok, Response.t()} | {:error, term()}
  def wrap(%Request{} = req, executor, opts \\ []) when is_function(executor, 1) do
    if should_apply_idempotency?(req, opts) do
      execute_with_idempotency(req, executor, opts)
    else
      executor.(req)
    end
  end

  @doc """
  Creates a Req plugin for idempotency.

  ## Examples

      Req.new()
      |> Middleware.attach(scope: "stripe")
      |> Req.post("/v1/charges", json: %{amount: 1000})
  """
  @spec attach(Req.Request.t(), opts()) :: Req.Request.t()
  def attach(%Req.Request{} = req, opts \\ []) do
    Req.Request.register_options(req, [:idempotency_key])
    |> Req.Request.prepend_request_steps(idempotency: &request_step(&1, opts))
  end

  @doc """
  Generates an idempotency key for a request if not already set.

  Uses the request metadata to create a deterministic key.

  ## Examples

      req = Request.new(config) |> Request.method(:post) |> Request.path("/charges")
      Middleware.ensure_key(req)
      #=> %Request{idempotency_key: "post:/charges:abc123..."}
  """
  @spec ensure_key(Request.t(), opts()) :: Request.t()
  def ensure_key(req, opts \\ [])

  def ensure_key(%Request{idempotency_key: nil} = req, opts) do
    key = generate_request_key(req, opts)
    %{req | idempotency_key: key}
  end

  def ensure_key(%Request{} = req, _opts), do: req

  # ============================================
  # Private Implementation
  # ============================================

  defp should_apply_idempotency?(%Request{idempotency_key: nil}, _opts), do: false

  defp should_apply_idempotency?(%Request{idempotency_key: _key, method: method}, opts) do
    case Keyword.get(opts, :enabled, :auto) do
      true -> true
      false -> false
      :auto -> method in @mutating_methods
    end
  end

  defp execute_with_idempotency(%Request{idempotency_key: key} = req, executor, opts) do
    scope = Keyword.get(opts, :scope) || derive_scope(req)
    ttl = Keyword.get(opts, :ttl)
    on_duplicate = Keyword.get(opts, :on_duplicate, :return)

    execute_opts =
      [scope: scope, on_duplicate: on_duplicate, metadata: request_metadata(req)]
      |> maybe_add(:ttl, ttl)

    Idempotency.execute(key, fn -> execute_request(req, executor) end, execute_opts)
  end

  defp execute_request(%Request{} = req, executor) do
    case executor.(req) do
      {:ok, %Response{} = response} ->
        if Response.success?(response) do
          {:ok, response_to_cacheable(response)}
        else
          # Non-success HTTP response - treat as error for idempotency
          {:error, response_to_cacheable(response)}
        end

      {:error, _} = error ->
        error
    end
  end

  defp response_to_cacheable(%Response{} = response) do
    %{
      status: response.status,
      body: response.body,
      headers: response.headers
    }
  end

  defp derive_scope(%Request{config: config}) when is_struct(config) do
    case Map.get(config, :base_url) do
      nil -> nil
      url -> URI.parse(url).host
    end
  end

  defp derive_scope(_), do: nil

  defp request_metadata(%Request{} = req) do
    %{
      method: req.method,
      path: req.path,
      metadata: req.metadata
    }
  end

  defp generate_request_key(%Request{} = req, opts) do
    scope = Keyword.get(opts, :scope)
    body_hash = hash_body(req.body)

    parts =
      [
        Atom.to_string(req.method),
        req.path,
        body_hash
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    case scope do
      nil -> parts
      s -> "#{s}:#{parts}"
    end
  end

  defp hash_body(nil), do: nil
  defp hash_body({:json, data}), do: hash_term(data)
  defp hash_body({:form, data}), do: hash_term(data)
  defp hash_body(data) when is_binary(data), do: hash_term(data)
  defp hash_body(data), do: hash_term(data)

  defp hash_term(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  # Req plugin step
  defp request_step(request, opts) do
    case Req.Request.get_option(request, :idempotency_key) do
      nil ->
        request

      key ->
        # Store the key for use in response handling
        request
        |> Req.Request.put_private(:idempotency_key, key)
        |> Req.Request.put_private(:idempotency_opts, opts)
        |> Req.Request.put_header("idempotency-key", key)
    end
  end
end
