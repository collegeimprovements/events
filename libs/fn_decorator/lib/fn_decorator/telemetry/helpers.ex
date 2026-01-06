defmodule FnDecorator.Telemetry.Helpers do
  @moduledoc """
  Telemetry helpers for consistent instrumentation.

  Provides macros and functions for:
  - Span tracking (start/stop events with duration)
  - Consistent measurement and metadata formatting
  - Error tracking with automatic span completion

  ## Quick Reference

  | Macro/Function | Use Case |
  |----------------|----------|
  | `span/3` | Wrap code block with start/stop events |
  | `emit/3` | Emit a single telemetry event |
  | `timed/2` | Measure execution time |

  ## Usage

      use FnDecorator.Telemetry.Helpers

      # Automatic span tracking
      span [:myapp, :crud, :create], %{schema: User} do
        Repo.insert(changeset)
      end

      # Manual emission
      emit [:myapp, :cache, :hit], %{key: key}, %{size: byte_size(value)}

  ## Event Naming Convention

  All events follow the pattern: `[:app, :domain, :operation, :phase]`

  - `:start` - Operation began
  - `:stop` - Operation completed (success or failure)
  - `:exception` - Operation raised an exception

  ## Measurements

  Standard measurements included automatically:
  - `:duration` - Native time units
  - `:duration_ms` - Milliseconds (convenience)
  - `:system_time` - Absolute timestamp (start events)

  ## Metadata

  Metadata should include:
  - Context identifiers (schema, id, etc.)
  - Operation details (action, options)
  - Error information (on exception)
  """

  @doc """
  Imports telemetry macros for use in a module.

  ## Example

      defmodule MyApp.Service do
        use FnDecorator.Telemetry.Helpers

        def fetch(id) do
          span [:myapp, :service, :fetch], %{id: id} do
            do_fetch(id)
          end
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import FnDecorator.Telemetry.Helpers, only: [span: 3, span: 4, emit: 3, emit: 4, timed: 2]
      require FnDecorator.Telemetry.Helpers
    end
  end

  @doc """
  Wraps a code block with telemetry span events.

  Automatically emits `:start` and `:stop` (or `:exception`) events with
  duration measurements.

  ## Parameters

  - `event` - Base event name (list of atoms)
  - `metadata` - Metadata map for the events
  - `block` - Code to execute

  ## Options

  - `:include_result` - Include result in stop metadata (default: false)
  - `:error_level` - Telemetry error level (default: :exception)

  ## Examples

      # Basic span
      span [:myapp, :crud, :create], %{schema: User} do
        Repo.insert(changeset)
      end

      # With options
      span [:myapp, :api, :call], %{endpoint: url}, include_result: true do
        http_client.get(url)
      end

  ## Emitted Events

  - `event ++ [:start]` - When block begins
    - Measurements: `%{system_time: ...}`
    - Metadata: provided metadata

  - `event ++ [:stop]` - When block completes successfully
    - Measurements: `%{duration: ..., duration_ms: ...}`
    - Metadata: provided metadata + optional result

  - `event ++ [:exception]` - When block raises
    - Measurements: `%{duration: ..., duration_ms: ...}`
    - Metadata: provided metadata + `%{kind: ..., reason: ..., stacktrace: ...}`
  """
  defmacro span(event, metadata, opts_or_block)

  defmacro span(event, metadata, do: block) do
    do_span(event, metadata, [], block)
  end

  defmacro span(_event, _metadata, opts) when is_list(opts) do
    quote do
      unquote(opts)
    end
  end

  @doc """
  Wraps a code block with telemetry span events and options.

  Same as `span/3` but with explicit options.

  ## Examples

      span [:myapp, :api, :call], %{url: url}, [include_result: true] do
        make_request(url)
      end
  """
  defmacro span(event, metadata, opts, do: block) do
    do_span(event, metadata, opts, block)
  end

  defp do_span(event, metadata, opts, block) do
    quote do
      start_time = System.monotonic_time()
      start_meta = unquote(metadata)

      :telemetry.execute(
        unquote(event) ++ [:start],
        %{system_time: System.system_time()},
        start_meta
      )

      try do
        result = unquote(block)

        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        # Classify result and enrich metadata
        result_classification = FnDecorator.Telemetry.Helpers.classify_result(result)

        stop_meta =
          start_meta
          |> Map.merge(result_classification)
          |> then(fn meta ->
            if Keyword.get(unquote(opts), :include_result, false) do
              Map.put(meta, :result, result)
            else
              meta
            end
          end)

        :telemetry.execute(
          unquote(event) ++ [:stop],
          %{duration: duration, duration_ms: duration_ms},
          stop_meta
        )

        result
      rescue
        e ->
          duration = System.monotonic_time() - start_time
          duration_ms = System.convert_time_unit(duration, :native, :millisecond)

          exception_meta =
            start_meta
            |> Map.put(:kind, :error)
            |> Map.put(:reason, e)
            |> Map.put(:stacktrace, __STACKTRACE__)

          :telemetry.execute(
            unquote(event) ++ [:exception],
            %{duration: duration, duration_ms: duration_ms},
            exception_meta
          )

          reraise e, __STACKTRACE__
      catch
        kind, reason ->
          duration = System.monotonic_time() - start_time
          duration_ms = System.convert_time_unit(duration, :native, :millisecond)

          exception_meta =
            start_meta
            |> Map.put(:kind, kind)
            |> Map.put(:reason, reason)
            |> Map.put(:stacktrace, __STACKTRACE__)

          :telemetry.execute(
            unquote(event) ++ [:exception],
            %{duration: duration, duration_ms: duration_ms},
            exception_meta
          )

          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  @doc """
  Emits a single telemetry event.

  ## Parameters

  - `event` - Event name (list of atoms)
  - `measurements` - Measurements map
  - `metadata` - Metadata map

  ## Examples

      emit [:myapp, :cache, :hit], %{}, %{key: key}
      emit [:myapp, :queue, :enqueue], %{queue_size: 42}, %{job: job_name}
  """
  defmacro emit(event, measurements, metadata) do
    quote do
      :telemetry.execute(unquote(event), unquote(measurements), unquote(metadata))
    end
  end

  @doc """
  Emits a telemetry event with timestamp.

  Automatically adds `:system_time` to measurements.

  ## Examples

      emit_with_time [:myapp, :user, :login], %{}, %{user_id: id}
  """
  defmacro emit(event, measurements, metadata, _opts) do
    quote do
      measurements_with_time = Map.put(unquote(measurements), :system_time, System.system_time())
      :telemetry.execute(unquote(event), measurements_with_time, unquote(metadata))
    end
  end

  @doc """
  Measures execution time of a function.

  Returns `{duration_ms, result}`.

  ## Examples

      {time_ms, result} = timed(fn -> expensive_operation() end)
      Logger.info("Operation took \#{time_ms}ms")

      # With options
      {time_us, result} = timed(fn -> query() end, unit: :microsecond)
  """
  @spec timed((-> term()), keyword()) :: {non_neg_integer(), term()}
  def timed(fun, opts \\ []) when is_function(fun, 0) do
    unit = Keyword.get(opts, :unit, :millisecond)
    start_time = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start_time
    duration_converted = System.convert_time_unit(duration, :native, unit)
    {duration_converted, result}
  end

  @doc """
  Creates a span context for manual span management.

  Useful when you need more control over span lifecycle.

  ## Examples

      ctx = start_span([:myapp, :batch, :process], %{batch_id: id})
      # ... do work ...
      stop_span(ctx)
  """
  @spec start_span([atom()], map()) :: map()
  def start_span(event, metadata) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      event ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    %{
      event: event,
      metadata: metadata,
      start_time: start_time
    }
  end

  @doc """
  Completes a span started with `start_span/2`.

  ## Examples

      ctx = start_span([:myapp, :batch, :process], %{batch_id: id})
      result = process_batch(batch)
      stop_span(ctx, result: result)
  """
  @spec stop_span(map(), keyword()) :: :ok
  def stop_span(ctx, opts \\ []) do
    duration = System.monotonic_time() - ctx.start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    stop_meta =
      case Keyword.get(opts, :result) do
        nil -> ctx.metadata
        result -> Map.put(ctx.metadata, :result, result)
      end

    :telemetry.execute(
      ctx.event ++ [:stop],
      %{duration: duration, duration_ms: duration_ms},
      stop_meta
    )

    :ok
  end

  @doc """
  Completes a span with an exception.

  ## Examples

      ctx = start_span([:myapp, :batch, :process], %{batch_id: id})
      try do
        process_batch(batch)
        stop_span(ctx)
      rescue
        e ->
          exception_span(ctx, :error, e, __STACKTRACE__)
          reraise e, __STACKTRACE__
      end
  """
  @spec exception_span(map(), atom(), term(), list()) :: :ok
  def exception_span(ctx, kind, reason, stacktrace) do
    duration = System.monotonic_time() - ctx.start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    exception_meta =
      ctx.metadata
      |> Map.put(:kind, kind)
      |> Map.put(:reason, reason)
      |> Map.put(:stacktrace, stacktrace)

    :telemetry.execute(
      ctx.event ++ [:exception],
      %{duration: duration, duration_ms: duration_ms},
      exception_meta
    )

    :ok
  end

  @doc """
  Attaches a telemetry handler that logs events.

  Useful for debugging telemetry events.

  ## Examples

      # Log all events under a prefix
      FnDecorator.Telemetry.Helpers.attach_logger([:myapp, :crud])

      # With custom log level
      FnDecorator.Telemetry.Helpers.attach_logger([:myapp, :api], level: :debug)
  """
  @spec attach_logger([atom()], keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(prefix, opts \\ []) do
    level = Keyword.get(opts, :level, :info)
    handler_id = "telemetry_logger_#{Enum.join(prefix, "_")}"

    :telemetry.attach_many(
      handler_id,
      [
        prefix ++ [:start],
        prefix ++ [:stop],
        prefix ++ [:exception]
      ],
      &log_handler/4,
      %{level: level}
    )
  end

  defp log_handler(event, measurements, metadata, %{level: level}) do
    require Logger

    event_name = Enum.join(event, ".")

    message =
      case List.last(event) do
        :start ->
          "#{event_name} started"

        :stop ->
          duration_ms = Map.get(measurements, :duration_ms, 0)
          "#{event_name} completed in #{duration_ms}ms"

        :exception ->
          duration_ms = Map.get(measurements, :duration_ms, 0)
          reason = Map.get(metadata, :reason, :unknown)
          "#{event_name} failed in #{duration_ms}ms: #{inspect(reason)}"

        _ ->
          "#{event_name}: #{inspect(measurements)}"
      end

    Logger.log(level, message, metadata)
  end

  @doc """
  Classifies function results into metadata for telemetry.

  Detects Result tuples, Maybe types, and other patterns to enrich
  telemetry metadata with result information.

  ## Examples

      iex> classify_result({:ok, %User{}})
      %{result: :ok}

      iex> classify_result({:error, :not_found})
      %{result: :error, error_type: :not_found}

      iex> classify_result({:error, %Ecto.Changeset{}})
      %{result: :error, error_type: Ecto.Changeset}

      iex> classify_result(:ok)
      %{result: :ok}

      iex> classify_result(nil)
      %{}
  """
  @spec classify_result(term()) :: map()
  def classify_result({:ok, _}), do: %{result: :ok}

  def classify_result({:error, reason}) when is_atom(reason) do
    %{result: :error, error_type: reason}
  end

  def classify_result({:error, %{__struct__: struct}}) do
    %{result: :error, error_type: struct}
  end

  def classify_result({:error, _reason}) do
    %{result: :error, error_type: :unknown}
  end

  def classify_result(:ok), do: %{result: :ok}
  def classify_result(:error), do: %{result: :error}

  def classify_result(_), do: %{}
end
