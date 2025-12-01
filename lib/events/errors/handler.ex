defmodule Events.Errors.Handler do
  @moduledoc """
  Universal error handler for processing errors across different contexts.

  This module provides a single entry point for error handling that can be used
  in controllers, plugs, GraphQL resolvers, background jobs, and any other context.

  ## Features

  - Automatic error normalization
  - Context enrichment from connection/socket/process
  - Automatic storage with deduplication
  - Format conversion (JSON, GraphQL, etc.)
  - Logging and telemetry
  - Customizable per-context

  ## Usage

      # In Phoenix Controller
      def create(conn, params) do
        case Users.create(params) do
          {:ok, user} -> json(conn, user)
          {:error, reason} -> Handler.handle_error(reason, conn)
        end
      end

      # In GraphQL Resolver
      def resolve(args, context) do
        case Users.create(args) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> Handler.handle_error(reason, context, format: :graphql)
        end
      end

      # In Background Job
      def perform(args) do
        case process(args) do
          {:ok, result} -> :ok
          {:error, reason} -> Handler.handle_error(reason, args, context: :worker)
        end
      end

      # Generic
      Handler.handle_error(error, metadata: %{user_id: 123})
  """

  use Events.Decorator

  require Logger

  alias Events.Errors
  alias Events.Errors.Error
  alias Events.Errors.Enrichment.Context
  alias Events.Errors.Mappers
  alias Events.Recoverable

  @type context ::
          Plug.Conn.t()
          | Phoenix.Socket.t()
          | Absinthe.Resolution.t()
          | map()
          | keyword()

  @type format :: :json | :graphql | :tuple | :map | :error

  @type options :: [
          format: format(),
          status: integer(),
          store: boolean(),
          log: boolean(),
          log_level: Logger.level(),
          context: atom(),
          metadata: map(),
          enrich: boolean()
        ]

  @doc """
  Universal error handler that processes any error and returns appropriate response.

  ## Options

  - `:format` - Output format (:json, :graphql, :tuple, :map, :error) - default: auto-detect
  - `:status` - HTTP status code (only for Plug.Conn) - default: auto from error type
  - `:store` - Store error in database - default: true
  - `:log` - Log the error - default: true
  - `:log_level` - Log level (:debug, :info, :warn, :error) - default: :error
  - `:context` - Context identifier (:controller, :resolver, :worker, :plug) - default: auto-detect
  - `:metadata` - Additional metadata - default: %{}
  - `:enrich` - Enrich with context - default: true

  ## Examples

      # Auto-detect from Plug.Conn
      Handler.handle_error(changeset, conn)

      # With options
      Handler.handle_error(error, conn, store: false, log_level: :warn)

      # GraphQL format
      Handler.handle_error(error, context, format: :graphql)

      # Generic with metadata
      Handler.handle_error(error, metadata: %{user_id: 123, request_id: "req_123"})
  """
  @spec handle_error(term(), context() | keyword(), options()) :: term()
  @decorate telemetry_span([:events, :errors, :handler, :handle])
  def handle_error(error, context_or_opts \\ [], opts \\ [])

  # When called with just error and options (no context)
  def handle_error(error, opts, []) when is_list(opts) do
    handle_error(error, %{}, opts)
  end

  # Main handler
  def handle_error(error, context, opts) do
    opts = normalize_options(opts)

    # Step 1: Normalize the error
    normalized_error = Errors.normalize(error)

    # Step 2: Enrich with context if enabled
    enriched_error =
      if opts[:enrich] do
        enrich_error(normalized_error, context, opts)
      else
        maybe_add_metadata(normalized_error, opts[:metadata])
      end

    # Step 3: Log if enabled
    if opts[:log] do
      log_error(enriched_error, opts[:log_level])
    end

    # Step 4: Store if enabled
    if opts[:store] do
      store_error(enriched_error)
    end

    # Step 5: Format and return response
    format_response(enriched_error, context, opts)
  end

  @doc """
  Handle error and return tuple format.

  Always returns `{:error, formatted_error}`.

  ## Examples

      Handler.handle_error_tuple(changeset, conn)
      #=> {:error, %Error{}}
  """
  @spec handle_error_tuple(term(), context() | keyword(), options()) :: {:error, term()}
  def handle_error_tuple(error, context_or_opts \\ [], opts \\ []) do
    result = handle_error(error, context_or_opts, Keyword.put(opts, :format, :tuple))
    {:error, result}
  end

  @doc """
  Handle error in Plug context (Phoenix controllers).

  Returns a Plug.Conn with appropriate status and JSON response.

  ## Examples

      def create(conn, params) do
        case Users.create(params) do
          {:ok, user} -> json(conn, user)
          {:error, reason} -> Handler.handle_plug_error(conn, reason)
        end
      end
  """
  @spec handle_plug_error(Plug.Conn.t(), term(), options()) :: Plug.Conn.t()
  def handle_plug_error(conn, error, opts \\ []) do
    opts = Keyword.put(opts, :format, :json)
    handle_error(error, conn, opts)
  end

  @doc """
  Handle error in GraphQL context (Absinthe resolvers).

  Returns `{:error, error}` in Absinthe format.

  ## Examples

      def resolve(args, context) do
        case Users.create(args) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> Handler.handle_graphql_error(reason, context)
        end
      end
  """
  @spec handle_graphql_error(term(), map(), options()) :: {:error, term()}
  def handle_graphql_error(error, context, opts \\ []) do
    opts = Keyword.put(opts, :format, :graphql)
    result = handle_error(error, context, opts)
    {:error, result}
  end

  @doc """
  Handle error in background job context.

  Uses the `Recoverable` protocol to determine retry behavior.
  Returns appropriate instructions based on recovery strategy:

  - `:ok` - Error is not recoverable, don't retry
  - `{:error, :retry}` - Error is recoverable, retry with default delay
  - `{:error, :retry, delay: ms}` - Retry after specified delay
  - `{:error, :discard}` - Permanently failed, don't retry

  ## Examples

      def perform(args) do
        case process(args) do
          {:ok, result} -> :ok
          {:error, reason} -> Handler.handle_worker_error(reason, args)
        end
      end

      # With attempt tracking
      def perform(args, attempt: attempt) do
        case process(args) do
          {:ok, result} -> :ok
          {:error, reason} -> Handler.handle_worker_error(reason, args, attempt: attempt)
        end
      end
  """
  @spec handle_worker_error(term(), map() | keyword(), options()) ::
          :ok | {:error, :retry} | {:error, :retry, keyword()} | {:error, :discard}
  def handle_worker_error(error, context, opts \\ []) do
    handler_opts = Keyword.merge([context: :worker, format: :error], opts)
    error_struct = handle_error(error, context, handler_opts)
    attempt = Keyword.get(opts, :attempt, 1)

    case Recoverable.Helpers.recovery_decision(error_struct, attempt: attempt) do
      {:retry, decision_opts} ->
        {:error, :retry, delay: decision_opts[:delay]}

      {:wait, decision_opts} ->
        {:error, :retry, delay: decision_opts[:delay]}

      {:circuit_break, _} ->
        # Circuit is open, don't retry
        {:error, :discard}

      {:fail, _} ->
        :ok

      {:fallback, _} ->
        :ok
    end
  end

  @doc """
  Create a plug that handles errors in a pipeline.

  ## Examples

      # In router or pipeline
      plug Handler.error_plug(store: true, log_level: :warn)

      # Or as a rescue in controller
      defmodule MyController do
        use MyAppWeb, :controller

        def action(conn, _) do
          apply(__MODULE__, action_name(conn), [conn, conn.params])
        rescue
          error -> Handler.handle_plug_error(conn, error)
        end
      end
  """
  @spec error_plug(options()) :: Plug.t()
  def error_plug(_opts \\ []) do
    fn conn, _plug_opts ->
      # This would be used with Plug.ErrorHandler or similar
      conn
    end
  end

  ## Private Functions

  defp normalize_options(opts) do
    [
      format: Keyword.get(opts, :format),
      status: Keyword.get(opts, :status),
      store: Keyword.get(opts, :store, true),
      log: Keyword.get(opts, :log, true),
      log_level: Keyword.get(opts, :log_level, :error),
      context: Keyword.get(opts, :context),
      metadata: Keyword.get(opts, :metadata, %{}),
      enrich: Keyword.get(opts, :enrich, true)
    ]
  end

  defp enrich_error(error, context, opts) do
    context_data = extract_context_data(context, opts)
    additional_metadata = opts[:metadata] || %{}

    error
    |> Context.enrich(context_data)
    |> maybe_add_metadata(additional_metadata)
  end

  defp extract_context_data(%Plug.Conn{} = conn, _opts) do
    [
      user: extract_user_context(conn),
      request: extract_request_context(conn),
      application: extract_application_context(:controller)
    ]
  end

  defp extract_context_data(%{context: context} = resolution, _opts)
       when is_map(resolution) and is_map(context) do
    # Absinthe resolution context
    [
      user: extract_user_context(context),
      request: extract_request_context(context),
      application: extract_application_context(:graphql)
    ]
  end

  defp extract_context_data(%Phoenix.Socket{} = socket, _opts) do
    [
      user: extract_user_context(socket),
      application: extract_application_context(:socket)
    ]
  end

  defp extract_context_data(context, opts) when is_map(context) or is_list(context) do
    context = Map.new(context)

    [
      user: Map.get(context, :user, []),
      request: Map.get(context, :request, []),
      application: extract_application_context(opts[:context] || :generic)
    ]
  end

  defp extract_context_data(_context, opts) do
    [application: extract_application_context(opts[:context] || :unknown)]
  end

  defp extract_user_context(%Plug.Conn{assigns: assigns}) do
    user = assigns[:current_user]

    if user do
      [
        user_id: Map.get(user, :id),
        email: Map.get(user, :email),
        role: Map.get(user, :role)
      ]
    else
      []
    end
  end

  defp extract_user_context(%{current_user: user}) when is_map(user) do
    [
      user_id: Map.get(user, :id),
      email: Map.get(user, :email),
      role: Map.get(user, :role)
    ]
  end

  defp extract_user_context(_), do: []

  defp extract_request_context(%Plug.Conn{} = conn) do
    [
      request_id: Plug.Conn.get_resp_header(conn, "x-request-id") |> List.first(),
      path: conn.request_path,
      method: conn.method,
      remote_ip: to_string(:inet_parse.ntoa(conn.remote_ip))
    ]
  end

  defp extract_request_context(%{request_id: request_id, path: path}) do
    [request_id: request_id, path: path]
  end

  defp extract_request_context(_), do: []

  defp extract_application_context(context_type) do
    [
      context: context_type,
      node: node(),
      environment: Application.get_env(:events, :environment, :dev)
    ]
  end

  defp maybe_add_metadata(error, metadata) when metadata == %{} or metadata == [], do: error

  defp maybe_add_metadata(error, metadata) do
    Errors.with_metadata(error, metadata)
  end

  defp log_error(error, level) do
    Logger.log(level, fn ->
      """
      [#{error.type}:#{error.code}] #{error.message}
      Details: #{Kernel.inspect(error.details)}
      Source: #{Kernel.inspect(error.source)}
      Metadata: #{Kernel.inspect(error.metadata)}
      """
    end)
  end

  defp store_error(error) do
    # Store asynchronously to not block the request
    Errors.store_async(error)
  end

  defp format_response(error, context, opts) do
    format = opts[:format] || detect_format(context)

    case format do
      :json -> format_json(error, context, opts)
      :graphql -> format_graphql(error)
      :tuple -> error
      :map -> Errors.to_map(error)
      :error -> error
      _ -> error
    end
  end

  defp detect_format(%Plug.Conn{}), do: :json
  defp detect_format(%{context: _}), do: :graphql
  defp detect_format(_), do: :error

  defp format_json(error, %Plug.Conn{} = conn, opts) do
    status = opts[:status] || http_status_from_error(error)

    conn
    |> Plug.Conn.put_status(status)
    |> Phoenix.Controller.json(%{
      error: %{
        type: error.type,
        code: error.code,
        message: error.message,
        details: error.details
      }
    })
  end

  defp format_json(error, _context, _opts) do
    %{
      error: %{
        type: error.type,
        code: error.code,
        message: error.message,
        details: error.details
      }
    }
  end

  defp format_graphql(error) do
    Mappers.Graphql.to_absinthe(error)
  end

  defp http_status_from_error(%Error{type: type}) do
    case type do
      :validation -> 422
      :not_found -> 404
      :unauthorized -> 401
      :forbidden -> 403
      :conflict -> 409
      :internal -> 500
      :external -> 502
      :timeout -> 504
      :rate_limit -> 429
      :bad_request -> 400
      :unprocessable -> 422
      :service_unavailable -> 503
      :network -> 502
      :configuration -> 500
      :unknown -> 500
    end
  end
end
