defmodule Events.APIClient do
  @moduledoc """
  Unified framework for building external API clients.

  Provides a composable, pipeline-based approach to making HTTP requests
  with built-in support for authentication, retries, circuit breaking,
  and rate limiting.

  ## Quick Start

      defmodule MyApp.Clients.Stripe do
        use Events.APIClient,
          base_url: "https://api.stripe.com",
          auth: :bearer,
          content_type: :form

        def create_customer(params, config) do
          new(config)
          |> post("/v1/customers", params)
        end
      end

  ## Options

  - `:base_url` - Base URL for all requests (required)
  - `:auth` - Default auth type (`:bearer`, `:basic`, `:api_key`, `:none`)
  - `:content_type` - Default content type (`:json`, `:form`)
  - `:retry` - Enable retries (default: true)
  - `:circuit_breaker` - Circuit breaker name (atom)
  - `:rate_limiter` - Rate limiter name (atom)

  ## Dual API Pattern

  Clients can expose both direct and pipeline APIs:

      # Direct API (simple, config last)
      Stripe.create_customer(%{email: "user@example.com"}, config)

      # Pipeline API (composable, config first)
      Stripe.new(config)
      |> Stripe.customers()
      |> Stripe.create(%{email: "user@example.com"})

  ## Authentication

  The framework supports multiple authentication strategies:

      # API Key (Bearer token)
      use Events.APIClient, auth: :bearer

      # Basic Auth
      use Events.APIClient, auth: :basic

      # Custom auth via protocol
      use Events.APIClient, auth: :custom

  ## Resilience

  Built-in middleware for production-ready API clients:

      use Events.APIClient,
        retry: [max_attempts: 3, base_delay: 1000],
        circuit_breaker: :stripe_api,
        rate_limiter: :stripe_api
  """

  alias Events.APIClient.{Request, Response}

  defmacro __using__(opts) do
    base_url = Keyword.fetch!(opts, :base_url)
    auth_type = Keyword.get(opts, :auth, :bearer)
    content_type = Keyword.get(opts, :content_type, :json)
    retry_opts = Keyword.get(opts, :retry, true)
    circuit_breaker = Keyword.get(opts, :circuit_breaker)
    rate_limiter = Keyword.get(opts, :rate_limiter)

    quote do
      @behaviour Events.APIClient.Behaviour

      alias Events.APIClient.{Request, Response, Auth}

      @base_url unquote(base_url)
      @auth_type unquote(auth_type)
      @content_type unquote(content_type)
      @retry_opts unquote(retry_opts)
      @circuit_breaker unquote(circuit_breaker)
      @rate_limiter unquote(rate_limiter)

      # ============================================
      # Behaviour Implementation
      # ============================================

      @impl true
      def base_url(_config), do: @base_url

      @impl true
      def default_headers(_config), do: []

      @impl true
      def new(config) do
        req = Request.new(config)

        req =
          case @circuit_breaker do
            nil -> req
            name -> Request.circuit_breaker(req, name)
          end

        case @rate_limiter do
          nil -> req
          name -> Request.rate_limit_key(req, name)
        end
      end

      @impl true
      def execute(%Request{} = request) do
        with {:ok, request} <- authenticate_request(request),
             {:ok, response} <- do_request(request) do
          {:ok, response}
        end
      end

      # ============================================
      # HTTP Methods
      # ============================================

      @doc "Performs a GET request."
      @spec get(Request.t(), String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
      def get(%Request{} = req, path, opts \\ []) do
        req
        |> Request.method(:get)
        |> Request.path(path)
        |> maybe_add_query(opts[:query])
        |> execute()
      end

      @doc "Performs a POST request."
      @spec post(Request.t(), String.t(), term(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def post(%Request{} = req, path, body, opts \\ []) do
        req
        |> Request.method(:post)
        |> Request.path(path)
        |> add_body(body)
        |> maybe_add_query(opts[:query])
        |> execute()
      end

      @doc "Performs a PUT request."
      @spec put(Request.t(), String.t(), term(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def put(%Request{} = req, path, body, opts \\ []) do
        req
        |> Request.method(:put)
        |> Request.path(path)
        |> add_body(body)
        |> maybe_add_query(opts[:query])
        |> execute()
      end

      @doc "Performs a PATCH request."
      @spec patch(Request.t(), String.t(), term(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def patch(%Request{} = req, path, body, opts \\ []) do
        req
        |> Request.method(:patch)
        |> Request.path(path)
        |> add_body(body)
        |> maybe_add_query(opts[:query])
        |> execute()
      end

      @doc "Performs a DELETE request."
      @spec delete(Request.t(), String.t(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}
      def delete(%Request{} = req, path, opts \\ []) do
        req
        |> Request.method(:delete)
        |> Request.path(path)
        |> maybe_add_query(opts[:query])
        |> execute()
      end

      # ============================================
      # Private Helpers
      # ============================================

      defp authenticate_request(%Request{config: config} = request) do
        case get_auth(config) do
          nil ->
            {:ok, request}

          auth ->
            if Auth.valid?(auth) do
              {:ok, Auth.authenticate(auth, request)}
            else
              case Auth.refresh(auth) do
                {:ok, new_auth} ->
                  {:ok, Auth.authenticate(new_auth, request)}

                {:error, _} = error ->
                  error
              end
            end
        end
      end

      defp get_auth(config) do
        case @auth_type do
          :none -> nil
          :bearer -> get_bearer_auth(config)
          :basic -> get_basic_auth(config)
          :api_key -> get_api_key_auth(config)
          :custom -> config.auth
        end
      end

      defp get_bearer_auth(config) do
        case Map.get(config, :api_key) || Map.get(config, :access_token) do
          nil -> nil
          key -> Auth.APIKey.bearer(key)
        end
      end

      defp get_basic_auth(config) do
        username = Map.get(config, :username) || Map.get(config, :account_sid)
        password = Map.get(config, :password) || Map.get(config, :auth_token)

        case {username, password} do
          {nil, _} -> nil
          {_, nil} -> nil
          {u, p} -> Auth.Basic.new(u, p)
        end
      end

      defp get_api_key_auth(config) do
        case Map.get(config, :api_key) do
          nil -> nil
          key -> Auth.APIKey.new(key)
        end
      end

      defp add_body(req, body) do
        case @content_type do
          :json -> Request.json(req, body)
          :form -> Request.form(req, body)
          _ -> Request.body(req, body)
        end
      end

      defp maybe_add_query(req, nil), do: req
      defp maybe_add_query(req, []), do: req
      defp maybe_add_query(req, query), do: Request.query(req, query)

      defp do_request(%Request{} = request) do
        config = request.config
        base = base_url(config)
        headers = default_headers(config) ++ request.headers

        opts =
          request
          |> Request.to_req_options()
          |> Keyword.put(:base_url, base)
          |> Keyword.update(:headers, headers, &(&1 ++ headers))

        # Apply retry middleware if enabled
        opts = apply_retry_options(opts)

        request_id = generate_request_id()
        start_time = System.monotonic_time(:millisecond)

        case Req.request(opts) do
          {:ok, resp} ->
            timing = System.monotonic_time(:millisecond) - start_time

            response =
              Response.from_req(resp,
                request_id: request_id,
                timing_ms: timing
              )

            {:ok, response}

          {:error, exception} ->
            {:error, exception}
        end
      end

      defp apply_retry_options(opts) do
        case @retry_opts do
          false ->
            Keyword.put(opts, :retry, false)

          true ->
            Keyword.put(opts, :retry, :transient)

          retry_opts when is_list(retry_opts) ->
            Keyword.put(opts, :retry, :transient)
            |> Keyword.put(:retry_delay, retry_delay_fn(retry_opts))
        end
      end

      defp retry_delay_fn(opts) do
        base_delay = Keyword.get(opts, :base_delay, 1000)
        max_delay = Keyword.get(opts, :max_delay, 30_000)

        fn attempt ->
          delay = base_delay * Integer.pow(2, attempt - 1)
          jitter = :rand.uniform(div(delay, 4))
          min(delay + jitter, max_delay)
        end
      end

      defp generate_request_id do
        "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      end

      # Allow overriding
      defoverridable base_url: 1, default_headers: 1, execute: 1
    end
  end
end
