defmodule Events.Decorators.Telemetry do
  @moduledoc """
  Telemetry and logging decorators for the Events application.

  Provides comprehensive observability through telemetry events,
  structured logging, and performance monitoring.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate telemetry_span([:my_app, :operation])
        def complex_operation(params) do
          # Emits telemetry events for start, stop, exception
        end

        @decorate log_call(:info, label: "Processing")
        def process_data(data) do
          # Logs function calls with arguments and results
        end

        @decorate log_if_slow(threshold: 1000)
        def slow_operation do
          # Logs warning if execution exceeds 1 second
        end
      end
  """

  @doc """
  Emits telemetry events for function execution.

  Emits:
  - `[:event | :start]` - On function start
  - `[:event | :stop]` - On successful completion
  - `[:event | :exception]` - On exception

  ## Options

  - `:event_name` - Event name prefix (required)
  - `:metadata` - Additional metadata to include
  """
  defmacro telemetry_span(event_name, opts \\ []) do
    quote do
      use Decorator.Define, telemetry_span: 2
      unquote(event_name)
      unquote(opts)
    end
  end

  @doc """
  Creates OpenTelemetry spans.

  ## Options

  - `:span_name` - Span name (default: function name)
  - `:attributes` - Span attributes
  - `:kind` - Span kind (:internal, :server, :client)
  """
  defmacro otel_span(span_name \\ nil, opts \\ []) do
    quote do
      use Decorator.Define, otel_span: 2
      unquote(span_name)
      unquote(opts)
    end
  end

  @doc """
  Logs function calls.

  ## Options

  - `:level` - Log level (:debug, :info, :warning, :error)
  - `:label` - Custom label for the log
  - `:include_args` - Include function arguments
  - `:include_result` - Include function result
  """
  defmacro log_call(level \\ :info, opts \\ []) do
    quote do
      use Decorator.Define, log_call: 2
      unquote(level)
      unquote(opts)
    end
  end

  @doc """
  Sets Logger metadata context.

  ## Options

  - `:fields` - List of argument names to add to Logger metadata
  - `:prefix` - Prefix for metadata keys
  """
  defmacro log_context(fields, opts \\ []) do
    quote do
      use Decorator.Define, log_context: 2
      unquote(fields)
      unquote(opts)
    end
  end

  @doc """
  Logs slow operations.

  ## Options

  - `:threshold` - Time threshold in milliseconds (required)
  - `:level` - Log level for slow operations (default: :warning)
  """
  defmacro log_if_slow(opts) do
    quote do
      use Decorator.Define, log_if_slow: 1
      unquote(opts)
    end
  end

  @doc """
  Logs database queries.

  ## Options

  - `:repo` - Ecto repo module
  - `:level` - Log level (default: :debug)
  - `:include_results` - Include query results
  """
  defmacro log_query(opts \\ []) do
    quote do
      use Decorator.Define, log_query: 1
      unquote(opts)
    end
  end

  @doc """
  Sends logs to remote service.

  ## Options

  - `:service` - Remote logging service module
  - `:async` - Send logs asynchronously
  - `:batch` - Batch multiple logs
  """
  defmacro log_remote(opts \\ []) do
    quote do
      use Decorator.Define, log_remote: 1
      unquote(opts)
    end
  end

  @doc """
  Tracks memory usage.

  ## Options

  - `:threshold` - Memory threshold for warnings
  - `:metric_name` - Name for memory metrics
  """
  defmacro track_memory(opts \\ []) do
    quote do
      use Decorator.Define, track_memory: 1
      unquote(opts)
    end
  end

  @doc """
  Captures and reports errors.

  ## Options

  - `:reporter` - Error reporting module
  - `:include_stacktrace` - Include full stacktrace
  - `:reraise` - Reraise after capturing
  """
  defmacro capture_errors(opts \\ []) do
    quote do
      use Decorator.Define, capture_errors: 1
      unquote(opts)
    end
  end
end
