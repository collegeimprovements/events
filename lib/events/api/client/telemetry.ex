defmodule Events.Api.Client.Telemetry do
  @moduledoc """
  Telemetry integration for API clients.

  Emits telemetry events for all API requests, enabling observability
  through metrics, logging, and tracing.

  ## Events

  ### Request Lifecycle

  - `[:events, :api_client, :request, :start]` - Request started
  - `[:events, :api_client, :request, :stop]` - Request completed successfully
  - `[:events, :api_client, :request, :exception]` - Request raised an exception

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
        Events.Api.Client.Telemetry.attach_default_handlers()
        # ...
      end

  ## Custom Handlers

  Attach your own handlers:

      :telemetry.attach(
        "my-api-metrics",
        [:events, :api_client, :request, :stop],
        &MyApp.Metrics.handle_api_request/4,
        nil
      )

  ## Using with OpenTelemetry

  The events are compatible with OpenTelemetry. Use the span helpers:

      Events.Api.Client.Telemetry.span(:stripe, fn ->
        Stripe.create_customer(params, config)
      end, %{operation: :create_customer})

  ## Logging

  Enable request logging:

      Events.Api.Client.Telemetry.attach_logger()

  This will log all requests at the `:info` level with timing information.
  """

  require Logger

  @prefix Application.compile_env(:events, [__MODULE__, :telemetry_prefix], [:events, :api_client])

  # ============================================
  # Event Names
  # ============================================

  @doc """
  Returns the telemetry event prefix.
  """
  @spec prefix() :: [atom()]
  def prefix, do: @prefix

  @doc """
  Returns all event names emitted by API clients.
  """
  @spec events() :: [[atom()]]
  def events do
    [
      @prefix ++ [:request, :start],
      @prefix ++ [:request, :stop],
      @prefix ++ [:request, :exception],
      @prefix ++ [:retry],
      @prefix ++ [:circuit_breaker, :state_change],
      @prefix ++ [:rate_limiter, :wait],
      @prefix ++ [:rate_limiter, :acquire]
    ]
  end

  # ============================================
  # Emit Events
  # ============================================

  @doc """
  Emits a request start event.

  Called automatically by the API client framework.
  """
  @spec emit_start(atom(), map()) :: integer()
  def emit_start(client, metadata) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [:request, :start],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{client: client, start_time: start_time})
    )

    start_time
  end

  @doc """
  Emits a request stop event.

  Called automatically by the API client framework.
  """
  @spec emit_stop(integer(), atom(), map()) :: :ok
  def emit_stop(start_time, client, metadata) do
    duration = System.monotonic_time() - start_time

    measurements = %{
      duration: duration,
      status: Map.get(metadata, :status)
    }

    :telemetry.execute(
      @prefix ++ [:request, :stop],
      measurements,
      Map.merge(metadata, %{client: client})
    )
  end

  @doc """
  Emits a request exception event.

  Called automatically by the API client framework.
  """
  @spec emit_exception(integer(), atom(), atom(), term(), list(), map()) :: :ok
  def emit_exception(start_time, client, kind, reason, stacktrace, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:request, :exception],
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
  @spec emit_retry(atom(), integer(), integer(), map()) :: :ok
  def emit_retry(client, attempt, delay_ms, metadata) do
    :telemetry.execute(
      @prefix ++ [:retry],
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
  @spec span(atom(), (-> result), map()) :: result when result: term()
  def span(client, fun, metadata \\ %{}) when is_function(fun, 0) do
    request_id = generate_request_id()
    metadata = Map.put(metadata, :request_id, request_id)
    start_time = emit_start(client, metadata)

    try do
      result = fun.()

      stop_metadata =
        case result do
          {:ok, %{status: status}} -> Map.put(metadata, :status, status)
          {:ok, _} -> metadata
          {:error, %{status: status}} -> Map.put(metadata, :status, status)
          {:error, _} -> metadata
          _ -> metadata
        end

      emit_stop(start_time, client, stop_metadata)
      result
    rescue
      e ->
        emit_exception(start_time, client, :error, e, __STACKTRACE__, metadata)
        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        emit_exception(start_time, client, kind, reason, __STACKTRACE__, metadata)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  # ============================================
  # Default Handlers
  # ============================================

  @doc """
  Attaches default telemetry handlers for logging and metrics.

  ## Options

  - `:log_level` - Log level for request logs (default: `:info`)
  - `:log_slow_threshold_ms` - Log slow requests at `:warn` level (default: 5000)
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
  """
  @spec attach_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(opts \\ []) do
    config = %{
      level: Keyword.get(opts, :level, :info),
      slow_threshold_ms: Keyword.get(opts, :slow_threshold_ms, 5000)
    }

    :telemetry.attach_many(
      "events-api-client-logger",
      [
        @prefix ++ [:request, :stop],
        @prefix ++ [:request, :exception]
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
    :telemetry.detach("events-api-client-logger")
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
        "[#{metadata.client}] #{metadata[:method] || "REQUEST"} #{metadata[:path] || "/"} " <>
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
        "[#{metadata.client}] #{metadata[:method] || "REQUEST"} #{metadata[:path] || "/"} " <>
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
