defmodule OmApiClient.Telemetry do
  @moduledoc """
  Telemetry integration for API clients.

  Emits telemetry events for all API requests, enabling observability
  through metrics, logging, and tracing.

  ## Events

  ### Request Lifecycle

  - `[:om_api_client, :request, :start]` - Request started
  - `[:om_api_client, :request, :stop]` - Request completed successfully
  - `[:om_api_client, :request, :exception]` - Request raised an exception

  ### Measurements

  | Event | Measurements |
  |-------|-------------|
  | `:start` | `%{system_time: integer}` |
  | `:stop` | `%{duration: integer, status: integer}` |
  | `:exception` | `%{duration: integer}` |

  ### Metadata

  All events include:

  - `:client` - Client module name
  - `:method` - HTTP method
  - `:path` - Request path
  - `:request_id` - Unique request identifier

  Additional metadata on `:stop`:

  - `:status` - HTTP status code
  - `:retries` - Number of retries attempted

  Additional metadata on `:exception`:

  - `:kind` - Exception kind (`:error`, `:exit`, `:throw`)
  - `:reason` - Exception reason
  - `:stacktrace` - Exception stacktrace

  ## Setup

  Attach handlers in your application startup:

      # In application.ex
      def start(_type, _args) do
        OmApiClient.Telemetry.attach_default_handlers()
        # ...
      end

  ## Custom Handlers

  Attach your own handlers:

      :telemetry.attach(
        "my-api-metrics",
        [:om_api_client, :request, :stop],
        &MyApp.Metrics.handle_api_request/4,
        nil
      )

  ## Custom Prefix

  You can use a custom telemetry prefix per client:

      use OmApiClient,
        base_url: "https://api.example.com",
        telemetry_prefix: [:my_app, :api]

  ## Logging

  Enable request logging:

      OmApiClient.Telemetry.attach_logger()

  This will log all requests at the `:info` level with timing information.
  """

  require Logger

  @default_prefix [:om_api_client]

  # ============================================
  # Event Names
  # ============================================

  @doc """
  Returns the default telemetry event prefix.
  """
  @spec default_prefix() :: [atom()]
  def default_prefix, do: @default_prefix

  @doc """
  Returns all event names emitted by API clients with the given prefix.
  """
  @spec events(prefix :: [atom()]) :: [[atom()]]
  def events(prefix \\ @default_prefix) do
    [
      prefix ++ [:request, :start],
      prefix ++ [:request, :stop],
      prefix ++ [:request, :exception],
      prefix ++ [:retry],
      prefix ++ [:circuit_breaker, :state_change],
      prefix ++ [:rate_limiter, :wait],
      prefix ++ [:rate_limiter, :acquire]
    ]
  end

  # ============================================
  # Emit Events
  # ============================================

  @doc """
  Emits a request start event.

  Called automatically by the API client framework.
  """
  @spec emit_start(atom(), map(), [atom()]) :: integer()
  def emit_start(client, metadata, prefix \\ @default_prefix) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      prefix ++ [:request, :start],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{client: client, start_time: start_time})
    )

    start_time
  end

  @doc """
  Emits a request stop event.

  Called automatically by the API client framework.
  """
  @spec emit_stop(integer(), atom(), map(), [atom()]) :: :ok
  def emit_stop(start_time, client, metadata, prefix \\ @default_prefix) do
    duration = System.monotonic_time() - start_time

    measurements = %{
      duration: duration,
      status: Map.get(metadata, :status)
    }

    :telemetry.execute(
      prefix ++ [:request, :stop],
      measurements,
      Map.merge(metadata, %{client: client})
    )
  end

  @doc """
  Emits a request exception event.

  Called automatically by the API client framework.
  """
  @spec emit_exception(integer(), atom(), atom(), term(), list(), map(), [atom()]) :: :ok
  def emit_exception(start_time, client, kind, reason, stacktrace, metadata, prefix \\ @default_prefix) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      prefix ++ [:request, :exception],
      %{duration: duration},
      Map.merge(metadata, %{
        client: client,
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      })
    )
  end

  @doc """
  Emits a retry event.
  """
  @spec emit_retry(atom(), integer(), integer(), map(), [atom()]) :: :ok
  def emit_retry(client, attempt, delay_ms, metadata, prefix \\ @default_prefix) do
    :telemetry.execute(
      prefix ++ [:retry],
      %{attempt: attempt, delay_ms: delay_ms},
      Map.merge(metadata, %{client: client})
    )
  end

  # ============================================
  # Span Helper
  # ============================================

  @doc """
  Executes a function within a telemetry span.

  Emits start, stop, and exception events automatically.

  ## Examples

      Telemetry.span(:stripe, fn ->
        Stripe.create_customer(params, config)
      end, %{operation: :create_customer})
  """
  @spec span(atom(), (-> result), map(), [atom()]) :: result when result: term()
  def span(client, fun, metadata \\ %{}, prefix \\ @default_prefix) when is_function(fun, 0) do
    request_id = generate_request_id()
    base_metadata = Map.merge(metadata, %{request_id: request_id, client: client})

    :telemetry.span(prefix ++ [:request], base_metadata, fn ->
      result = fun.()

      enriched_metadata =
        case result do
          {:ok, %{status: status}} -> Map.put(base_metadata, :status, status)
          {:ok, _} -> base_metadata
          {:error, %{status: status}} -> Map.put(base_metadata, :status, status)
          {:error, _} -> base_metadata
          _ -> base_metadata
        end

      {result, enriched_metadata}
    end)
  end

  # ============================================
  # Default Handlers
  # ============================================

  @doc """
  Attaches default telemetry handlers for logging and metrics.

  ## Options

  - `:log_level` - Log level for request logs (default: `:info`)
  - `:log_slow_threshold_ms` - Log slow requests at `:warn` level (default: 5000)
  - `:prefix` - Telemetry prefix (default: [:om_api_client])
  """
  @spec attach_default_handlers(keyword()) :: :ok
  def attach_default_handlers(opts \\ []) do
    attach_logger(opts)
    :ok
  end

  @doc """
  Attaches a logging handler for API requests.

  ## Options

  - `:level` - Log level (default: `:info`)
  - `:slow_threshold_ms` - Threshold for slow request warnings (default: 5000)
  - `:prefix` - Telemetry prefix (default: [:om_api_client])
  """
  @spec attach_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    config = %{
      level: Keyword.get(opts, :level, :info),
      slow_threshold_ms: Keyword.get(opts, :slow_threshold_ms, 5000)
    }

    :telemetry.attach_many(
      "om-api-client-logger",
      [
        prefix ++ [:request, :stop],
        prefix ++ [:request, :exception]
      ],
      &__MODULE__.handle_log_event/4,
      config
    )
  end

  @doc """
  Detaches the logging handler.
  """
  @spec detach_logger() :: :ok | {:error, :not_found}
  def detach_logger do
    :telemetry.detach("om-api-client-logger")
  end

  @doc false
  def handle_log_event(
        event,
        measurements,
        metadata,
        config
      ) do
    case List.last(event) do
      :stop -> log_request_complete(measurements, metadata, config)
      :exception -> log_request_exception(measurements, metadata, config)
    end
  end

  defp log_request_complete(measurements, metadata, config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    status = measurements[:status] || "unknown"

    level =
      cond do
        duration_ms > config.slow_threshold_ms -> :warning
        status >= 500 -> :error
        status >= 400 -> :warning
        true -> config.level
      end

    Logger.log(
      level,
      fn ->
        "[#{inspect(metadata.client)}] #{metadata[:method] || "REQUEST"} #{metadata[:path] || "/"} " <>
          "-> #{status} (#{duration_ms}ms)"
      end,
      request_id: metadata[:request_id],
      client: metadata.client,
      status: status,
      duration_ms: duration_ms
    )
  end

  defp log_request_exception(measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      fn ->
        "[#{inspect(metadata.client)}] #{metadata[:method] || "REQUEST"} #{metadata[:path] || "/"} " <>
          "EXCEPTION: #{inspect(metadata.kind)} - #{inspect(metadata.reason)} (#{duration_ms}ms)"
      end,
      request_id: metadata[:request_id],
      client: metadata.client,
      duration_ms: duration_ms,
      kind: metadata.kind,
      reason: metadata.reason
    )
  end

  # ============================================
  # Helpers
  # ============================================

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
