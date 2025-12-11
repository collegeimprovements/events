defmodule Events.Infra.Idempotency.Middleware do
  @moduledoc """
  Idempotency middleware for API client requests.

  Wraps API calls with idempotency protection, automatically:
  - Checking for cached responses before making requests
  - Storing successful responses for future deduplication
  - Handling concurrent duplicate requests

  ## Usage

  ### With Request Pipeline

      alias Events.Infra.Idempotency.Middleware, as: IdempotencyMiddleware

      Request.new(config)
      |> Request.idempotency_key(Idempotency.generate_key(:create_charge, order_id: 123))
      |> Request.method(:post)
      |> Request.path("/v1/charges")
      |> Request.json(%{amount: 1000})
      |> IdempotencyMiddleware.wrap(fn req -> Stripe.execute(req) end)

  ### Automatic Integration

  API clients can integrate idempotency automatically:

      defmodule MyApp.StripeClient do
        use Events.Api.Client, base_url: "https://api.stripe.com"

        # This automatically wraps mutating requests with idempotency
        plug Events.Infra.Idempotency.Middleware, scope: "stripe"
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

  alias Events.Infra.Idempotency
  alias Events.Infra.Idempotency.ResponseBehaviour

  @type opts :: [
          scope: String.t(),
          ttl: pos_integer(),
          enabled: boolean() | :auto,
          on_duplicate: :return | :wait | :error
        ]

  @mutating_methods [:post, :put, :patch]

  @doc """
  Wraps an API call with idempotency protection.

  Accepts any request struct that implements `Events.Infra.Idempotency.RequestBehaviour`
  or has the standard request fields (idempotency_key, method, path, body, config, metadata).

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
  @spec wrap(struct(), (struct() -> {:ok, struct()} | {:error, term()}), opts()) ::
          {:ok, struct()} | {:error, term()}
  def wrap(req, executor, opts \\ []) when is_struct(req) and is_function(executor, 1) do
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
  @spec ensure_key(struct(), opts()) :: struct()
  def ensure_key(req, opts \\ [])

  def ensure_key(req, opts) when is_struct(req) do
    case get_idempotency_key(req) do
      nil ->
        key = generate_request_key(req, opts)
        %{req | idempotency_key: key}

      _key ->
        req
    end
  end

  # ============================================
  # Private Implementation
  # ============================================

  # Helper to get idempotency key from any request struct
  defp get_idempotency_key(req) when is_struct(req) do
    Map.get(req, :idempotency_key)
  end

  # Helper to get method from any request struct
  defp get_method(req) when is_struct(req) do
    Map.get(req, :method)
  end

  defp should_apply_idempotency?(req, opts) when is_struct(req) do
    case get_idempotency_key(req) do
      nil -> false
      _key -> check_enabled(get_method(req), opts)
    end
  end

  defp check_enabled(method, opts) do
    case Keyword.get(opts, :enabled, :auto) do
      true -> true
      false -> false
      :auto -> method in @mutating_methods
    end
  end

  defp execute_with_idempotency(req, executor, opts) when is_struct(req) do
    key = get_idempotency_key(req)
    scope = Keyword.get(opts, :scope) || derive_scope(req)
    ttl = Keyword.get(opts, :ttl)
    on_duplicate = Keyword.get(opts, :on_duplicate, :return)

    execute_opts =
      [scope: scope, on_duplicate: on_duplicate, metadata: request_metadata(req)]
      |> maybe_add(:ttl, ttl)

    Idempotency.execute(key, fn -> execute_request(req, executor) end, execute_opts)
  end

  defp execute_request(req, executor) when is_struct(req) do
    case executor.(req) do
      {:ok, response} when is_struct(response) ->
        if response_success?(response) do
          {:ok, ResponseBehaviour.to_cacheable(response)}
        else
          # Non-success HTTP response - treat as error for idempotency
          {:error, ResponseBehaviour.to_cacheable(response)}
        end

      {:error, _} = error ->
        error
    end
  end

  # Check if response is successful using behaviour or default
  defp response_success?(response) when is_struct(response) do
    # Try to call success?/1 if the module implements it, otherwise use default
    module = response.__struct__

    if function_exported?(module, :success?, 1) do
      module.success?(response)
    else
      ResponseBehaviour.default_success?(response)
    end
  end

  defp derive_scope(req) when is_struct(req) do
    case Map.get(req, :config) do
      config when is_struct(config) ->
        case Map.get(config, :base_url) do
          nil -> nil
          url -> URI.parse(url).host
        end

      _ ->
        nil
    end
  end

  defp request_metadata(req) when is_struct(req) do
    %{
      method: Map.get(req, :method),
      path: Map.get(req, :path),
      metadata: Map.get(req, :metadata, %{})
    }
  end

  defp generate_request_key(req, opts) when is_struct(req) do
    scope = Keyword.get(opts, :scope)
    body = Map.get(req, :body)
    body_hash = hash_body(body)

    method = Map.get(req, :method)
    path = Map.get(req, :path)

    parts =
      [
        if(is_atom(method), do: Atom.to_string(method), else: to_string(method)),
        path,
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
