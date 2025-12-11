defmodule Events.Api.Client do
  @moduledoc """
  Unified framework for building external API clients.

  Provides a composable, pipeline-based approach to making HTTP requests
  with built-in support for authentication, retries, circuit breaking,
  rate limiting, and telemetry.

  ## Quick Start

      defmodule MyApp.Clients.Stripe do
        use Events.Api.Client,
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
  - `:telemetry` - Enable telemetry events (default: true)
  - `:idempotency` - Idempotency settings (scope, enabled for mutating requests)

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
      use Events.Api.Client, auth: :bearer

      # Basic Auth
      use Events.Api.Client, auth: :basic

      # Custom auth via protocol
      use Events.Api.Client, auth: :custom

  ## Resilience

  Built-in middleware for production-ready API clients:

      use Events.Api.Client,
        retry: [max_attempts: 3, base_delay: 1000],
        circuit_breaker: :stripe_api,
        rate_limiter: :stripe_api

  ## Telemetry

  All requests emit telemetry events:

  - `[:events, :api_client, :request, :start]` - Request started
  - `[:events, :api_client, :request, :stop]` - Request completed
  - `[:events, :api_client, :request, :exception]` - Request failed

  See `Events.Api.Client.Telemetry` for details.
  """

  alias Events.Api.Client.{Request, Response, Telemetry}

  defmacro __using__(opts) do
    base_url = Keyword.fetch!(opts, :base_url)
    auth_type = Keyword.get(opts, :auth, :bearer)
    content_type = Keyword.get(opts, :content_type, :json)
    retry_opts = Keyword.get(opts, :retry, true)
    circuit_breaker = Keyword.get(opts, :circuit_breaker)
    rate_limiter = Keyword.get(opts, :rate_limiter)
    telemetry_enabled = Keyword.get(opts, :telemetry, true)
    idempotency_opts = Keyword.get(opts, :idempotency)

    quote do
      @behaviour Events.Api.Client.Behaviour

      alias Events.Api.Client.{Request, Response, Auth, Telemetry}

      @base_url unquote(base_url)
      @auth_type unquote(auth_type)
      @content_type unquote(content_type)
      @retry_opts unquote(retry_opts)
      @circuit_breaker unquote(circuit_breaker)
      @rate_limiter unquote(rate_limiter)
      @telemetry_enabled unquote(telemetry_enabled)
      @idempotency_opts unquote(idempotency_opts)
      @client_name __MODULE__

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
             {:ok, response} <- maybe_with_idempotency(request) do
          {:ok, response}
        end
      end

      defp maybe_with_idempotency(%Request{idempotency_key: nil} = request) do
        do_request(request)
      end

      defp maybe_with_idempotency(%Request{idempotency_key: key} = request) do
        case @idempotency_opts do
          nil ->
            # No idempotency configured, just add header and execute
            do_request(request)

          opts when is_list(opts) ->
            # Use idempotency middleware
            scope = Keyword.get(opts, :scope, derive_idempotency_scope())
            Events.Infra.Idempotency.Middleware.wrap(request, &do_request/1, scope: scope)

          true ->
            # Default idempotency with derived scope
            Events.Infra.Idempotency.Middleware.wrap(request, &do_request/1,
              scope: derive_idempotency_scope()
            )
        end
      end

      defp derive_idempotency_scope do
        # Extract host from base_url as default scope
        @base_url
        |> URI.parse()
        |> Map.get(:host)
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
        config
        |> get_auth()
        |> apply_auth(request)
      end

      defp apply_auth(nil, request), do: {:ok, request}

      defp apply_auth(auth, request) do
        case Auth.valid?(auth) do
          true ->
            {:ok, Auth.authenticate(auth, request)}

          false ->
            auth
            |> Auth.refresh()
            |> apply_refreshed_auth(request)
        end
      end

      defp apply_refreshed_auth({:ok, new_auth}, request) do
        {:ok, Auth.authenticate(new_auth, request)}
      end

      defp apply_refreshed_auth({:error, _} = error, _request), do: error

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

        telemetry_meta = %{
          method: request.method,
          path: request.path,
          request_id: request_id,
          metadata: request.metadata
        }

        # Emit telemetry start event
        start_time = maybe_emit_telemetry_start(telemetry_meta)

        try do
          case Req.request(opts) do
            {:ok, resp} ->
              timing =
                System.monotonic_time(:millisecond) -
                  (start_time || System.monotonic_time(:millisecond))

              response =
                Response.from_req(resp,
                  request_id: request_id,
                  timing_ms: timing
                )

              # Emit telemetry stop event
              maybe_emit_telemetry_stop(
                start_time,
                Map.put(telemetry_meta, :status, response.status)
              )

              {:ok, response}

            {:error, exception} ->
              maybe_emit_telemetry_stop(start_time, telemetry_meta)
              {:error, exception}
          end
        rescue
          e ->
            maybe_emit_telemetry_exception(start_time, :error, e, __STACKTRACE__, telemetry_meta)
            reraise e, __STACKTRACE__
        catch
          kind, reason ->
            maybe_emit_telemetry_exception(start_time, kind, reason, __STACKTRACE__, telemetry_meta)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
      end

      # Telemetry emission - pattern matched on @telemetry_enabled compile-time constant
      if @telemetry_enabled do
        defp maybe_emit_telemetry_start(metadata) do
          Telemetry.emit_start(@client_name, metadata)
        end

        defp maybe_emit_telemetry_stop(nil, _metadata), do: :ok

        defp maybe_emit_telemetry_stop(start_time, metadata) do
          Telemetry.emit_stop(start_time, @client_name, metadata)
        end

        defp maybe_emit_telemetry_exception(nil, _kind, _reason, _stacktrace, _metadata), do: :ok

        defp maybe_emit_telemetry_exception(start_time, kind, reason, stacktrace, metadata) do
          Telemetry.emit_exception(start_time, @client_name, kind, reason, stacktrace, metadata)
        end
      else
        defp maybe_emit_telemetry_start(_metadata), do: nil
        defp maybe_emit_telemetry_stop(_start_time, _metadata), do: :ok
        defp maybe_emit_telemetry_exception(_start_time, _kind, _reason, _stacktrace, _metadata), do: :ok
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
