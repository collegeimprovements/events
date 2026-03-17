defmodule OmS3.Telemetry do
  @moduledoc """
  Telemetry events for S3 operations.

  Emits telemetry events for all S3 operations, enabling observability,
  metrics collection, and debugging.

  ## Events

  All events are prefixed with `[:om_s3]`:

  ### Request Events

  - `[:om_s3, :request, :start]` - Request started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{operation: atom(), bucket: string(), key: string()}`

  - `[:om_s3, :request, :stop]` - Request completed successfully
    - Measurements: `%{duration: integer()}` (native time units)
    - Metadata: `%{operation: atom(), bucket: string(), key: string(), status: integer()}`

  - `[:om_s3, :request, :exception]` - Request failed with exception
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{operation: atom(), bucket: string(), key: string(), kind: atom(), reason: term()}`

  ### Batch Events

  - `[:om_s3, :batch, :start]` - Batch operation started
    - Measurements: `%{system_time: integer(), count: integer()}`
    - Metadata: `%{operation: atom()}`

  - `[:om_s3, :batch, :stop]` - Batch operation completed
    - Measurements: `%{duration: integer(), succeeded: integer(), failed: integer()}`
    - Metadata: `%{operation: atom()}`

  ### Streaming Events

  - `[:om_s3, :stream, :start]` - Stream started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{direction: :download | :upload, bucket: string(), key: string()}`

  - `[:om_s3, :stream, :chunk]` - Chunk processed
    - Measurements: `%{bytes: integer(), chunk_number: integer()}`
    - Metadata: `%{direction: :download | :upload, bucket: string(), key: string()}`

  - `[:om_s3, :stream, :stop]` - Stream completed
    - Measurements: `%{duration: integer(), total_bytes: integer()}`
    - Metadata: `%{direction: :download | :upload, bucket: string(), key: string()}`

  ## Usage

  ### Basic Handler

      :telemetry.attach_many(
        "my-s3-handler",
        [
          [:om_s3, :request, :stop],
          [:om_s3, :request, :exception],
          [:om_s3, :batch, :stop]
        ],
        &MyApp.Telemetry.handle_s3_event/4,
        nil
      )

  ### Metrics with Telemetry.Metrics

      defmodule MyApp.Telemetry do
        import Telemetry.Metrics

        def metrics do
          [
            counter("om_s3.request.stop.count", tags: [:operation, :bucket]),
            distribution("om_s3.request.stop.duration",
              unit: {:native, :millisecond},
              tags: [:operation]
            ),
            counter("om_s3.request.exception.count", tags: [:operation, :kind]),
            summary("om_s3.batch.stop.succeeded"),
            summary("om_s3.batch.stop.failed")
          ]
        end
      end

  ### With Logger

      OmS3.Telemetry.attach_default_logger()

  ## Instrumenting Operations

  The telemetry module provides helper functions that wrap operations
  with automatic telemetry emission:

      # Instrument a single operation
      OmS3.Telemetry.span(:get, bucket, key, fn ->
        OmS3.Client.get_object(config, bucket, key)
      end)

      # Instrument a batch operation
      OmS3.Telemetry.batch_span(:put_all, 10, fn ->
        OmS3.put_all(files, config, to: uri)
      end)
  """

  require Logger

  @prefix [:om_s3]

  # ============================================
  # Event Emission
  # ============================================

  @doc """
  Emits a request start event.
  """
  @spec emit_start(atom(), String.t(), String.t(), map()) :: integer()
  def emit_start(operation, bucket, key, extra_metadata \\ %{}) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [:request, :start],
      %{system_time: System.system_time()},
      Map.merge(
        %{operation: operation, bucket: bucket, key: key},
        extra_metadata
      )
    )

    start_time
  end

  @doc """
  Emits a request stop event.
  """
  @spec emit_stop(integer(), atom(), String.t(), String.t(), map()) :: :ok
  def emit_stop(start_time, operation, bucket, key, extra_metadata \\ %{}) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:request, :stop],
      %{duration: duration},
      Map.merge(
        %{operation: operation, bucket: bucket, key: key},
        extra_metadata
      )
    )
  end

  @doc """
  Emits a request exception event.
  """
  @spec emit_exception(integer(), atom(), String.t(), String.t(), atom(), term()) :: :ok
  def emit_exception(start_time, operation, bucket, key, kind, reason) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:request, :exception],
      %{duration: duration},
      %{operation: operation, bucket: bucket, key: key, kind: kind, reason: reason}
    )
  end

  @doc """
  Emits batch start event.
  """
  @spec emit_batch_start(atom(), non_neg_integer()) :: integer()
  def emit_batch_start(operation, count) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [:batch, :start],
      %{system_time: System.system_time(), count: count},
      %{operation: operation}
    )

    start_time
  end

  @doc """
  Emits batch stop event.
  """
  @spec emit_batch_stop(integer(), atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def emit_batch_stop(start_time, operation, succeeded, failed) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:batch, :stop],
      %{duration: duration, succeeded: succeeded, failed: failed},
      %{operation: operation}
    )
  end

  @doc """
  Emits stream events.
  """
  @spec emit_stream_start(:download | :upload, String.t(), String.t()) :: integer()
  def emit_stream_start(direction, bucket, key) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      @prefix ++ [:stream, :start],
      %{system_time: System.system_time()},
      %{direction: direction, bucket: bucket, key: key}
    )

    start_time
  end

  @spec emit_stream_chunk(:download | :upload, String.t(), String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def emit_stream_chunk(direction, bucket, key, bytes, chunk_number) do
    :telemetry.execute(
      @prefix ++ [:stream, :chunk],
      %{bytes: bytes, chunk_number: chunk_number},
      %{direction: direction, bucket: bucket, key: key}
    )
  end

  @spec emit_stream_stop(integer(), :download | :upload, String.t(), String.t(), non_neg_integer()) :: :ok
  def emit_stream_stop(start_time, direction, bucket, key, total_bytes) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @prefix ++ [:stream, :stop],
      %{duration: duration, total_bytes: total_bytes},
      %{direction: direction, bucket: bucket, key: key}
    )
  end

  # ============================================
  # Instrumentation Helpers
  # ============================================

  @doc """
  Wraps a single S3 operation with telemetry.

  ## Examples

      OmS3.Telemetry.span(:get, "my-bucket", "path/to/file.txt", fn ->
        OmS3.Client.get_object(config, bucket, key)
      end)
  """
  @spec span(atom(), String.t(), String.t(), (-> result)) :: result when result: term()
  def span(operation, bucket, key, fun) when is_function(fun, 0) do
    start_time = emit_start(operation, bucket, key)

    try do
      result = fun.()
      status = extract_status(result)
      emit_stop(start_time, operation, bucket, key, %{status: status})
      result
    rescue
      e ->
        emit_exception(start_time, operation, bucket, key, :error, e)
        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        emit_exception(start_time, operation, bucket, key, kind, reason)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Wraps a batch S3 operation with telemetry.

  ## Examples

      OmS3.Telemetry.batch_span(:put_all, length(files), fn ->
        OmS3.put_all(files, config, to: uri)
      end)
  """
  @spec batch_span(atom(), non_neg_integer(), (-> [result])) :: [result] when result: term()
  def batch_span(operation, count, fun) when is_function(fun, 0) do
    start_time = emit_batch_start(operation, count)

    try do
      results = fun.()
      {succeeded, failed} = count_results(results)
      emit_batch_stop(start_time, operation, succeeded, failed)
      results
    rescue
      e ->
        emit_batch_stop(start_time, operation, 0, count)
        reraise e, __STACKTRACE__
    end
  end

  # ============================================
  # Default Logger
  # ============================================

  @doc """
  Attaches a default logger handler for S3 telemetry events.

  Logs all S3 operations at the debug level.

  ## Options

  - `:level` - Log level (default: :debug)
  - `:log_success` - Whether to log successful operations (default: true)
  - `:log_exceptions` - Whether to log exceptions (default: true)
  - `:log_slow_threshold` - Log warning for operations slower than this (ms, default: 5000)

  ## Examples

      OmS3.Telemetry.attach_default_logger()
      OmS3.Telemetry.attach_default_logger(level: :info, log_slow_threshold: 10_000)
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    handler_id = "om_s3_default_logger"

    events = [
      [:om_s3, :request, :stop],
      [:om_s3, :request, :exception],
      [:om_s3, :batch, :stop],
      [:om_s3, :stream, :stop]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_event/4,
      opts
    )
  end

  @doc """
  Detaches the default logger handler.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach("om_s3_default_logger")
  end

  @doc false
  def handle_event(event, measurements, metadata, opts) do
    level = Keyword.get(opts, :level, :debug)
    log_success = Keyword.get(opts, :log_success, true)
    log_exceptions = Keyword.get(opts, :log_exceptions, true)
    slow_threshold = Keyword.get(opts, :log_slow_threshold, 5000)

    case event do
      [:om_s3, :request, :stop] when log_success ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        if duration_ms > slow_threshold do
          Logger.warning(
            "[OmS3] Slow operation: #{metadata.operation} #{metadata.bucket}/#{metadata.key} took #{duration_ms}ms"
          )
        else
          Logger.log(
            level,
            "[OmS3] #{metadata.operation} #{metadata.bucket}/#{metadata.key} completed in #{duration_ms}ms"
          )
        end

      [:om_s3, :request, :exception] when log_exceptions ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        Logger.error(
          "[OmS3] #{metadata.operation} #{metadata.bucket}/#{metadata.key} failed: #{inspect(metadata.reason)} (#{duration_ms}ms)"
        )

      [:om_s3, :batch, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        total = measurements.succeeded + measurements.failed

        if measurements.failed > 0 do
          Logger.warning(
            "[OmS3] Batch #{metadata.operation}: #{measurements.succeeded}/#{total} succeeded, #{measurements.failed} failed (#{duration_ms}ms)"
          )
        else
          Logger.log(
            level,
            "[OmS3] Batch #{metadata.operation}: #{measurements.succeeded}/#{total} succeeded (#{duration_ms}ms)"
          )
        end

      [:om_s3, :stream, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        mb = Float.round(measurements.total_bytes / 1_048_576, 2)

        Logger.log(
          level,
          "[OmS3] Stream #{metadata.direction} #{metadata.bucket}/#{metadata.key}: #{mb}MB in #{duration_ms}ms"
        )

      _ ->
        :ok
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp extract_status(:ok), do: 200
  defp extract_status({:ok, _}), do: 200
  defp extract_status({:ok, _, _}), do: 200
  defp extract_status({:error, :not_found}), do: 404
  defp extract_status({:error, {:s3_error, status, _}}), do: status
  defp extract_status({:error, _}), do: 500
  defp extract_status(_), do: 200

  defp count_results(results) when is_list(results) do
    Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {s, f} -> {s + 1, f}
      {:ok, _, _}, {s, f} -> {s + 1, f}
      {:error, _, _}, {s, f} -> {s, f + 1}
      _, {s, f} -> {s, f}
    end)
  end
end
