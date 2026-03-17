defmodule OmCache.Telemetry do
  @moduledoc """
  Telemetry integration for OmCache.

  Provides helpers for attaching telemetry handlers to cache operations.

  ## Events

  OmCache emits the following telemetry events (via Nebulex):

  - `[:nebulex, :cache, :command, :start]` - Before command execution
  - `[:nebulex, :cache, :command, :stop]` - After successful command
  - `[:nebulex, :cache, :command, :exception]` - On command exception

  ## Measurements

  - `:system_time` - System time at event
  - `:duration` - Command duration in native units (for :stop/:exception)

  ## Metadata

  - `:cache` - Cache module
  - `:command` - Command name (e.g., :get, :put, :delete)
  - `:args` - Command arguments
  - `:result` - Command result (for :stop)
  - `:kind` - Exception kind (for :exception)
  - `:reason` - Exception reason (for :exception)
  - `:stacktrace` - Exception stacktrace (for :exception)

  ## Usage

      # Attach a simple logger
      OmCache.Telemetry.attach_logger(:my_cache_logger)

      # Attach custom handler
      :telemetry.attach(
        "cache-stats",
        [:nebulex, :cache, :command, :stop],
        &MyApp.Telemetry.handle_cache_event/4,
        nil
      )
  """

  require Logger

  @doc """
  Attaches a simple logging handler for cache operations.

  ## Options

  - `:level` - Log level (default: :debug)
  - `:log_args` - Whether to log args (default: false, can be large)

  ## Examples

      OmCache.Telemetry.attach_logger(:my_cache_logger)
      OmCache.Telemetry.attach_logger(:my_cache_logger, level: :info)
  """
  @spec attach_logger(atom(), keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(handler_id, opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    log_args = Keyword.get(opts, :log_args, false)

    config = %{level: level, log_args: log_args}

    :telemetry.attach_many(
      handler_id,
      [
        [:nebulex, :cache, :command, :start],
        [:nebulex, :cache, :command, :stop],
        [:nebulex, :cache, :command, :exception]
      ],
      &__MODULE__.handle_event/4,
      config
    )
  end

  @doc """
  Detaches a previously attached handler.
  """
  @spec detach_logger(atom()) :: :ok | {:error, :not_found}
  def detach_logger(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event([:nebulex, :cache, :command, :start], _measurements, metadata, config) do
    Logger.log(config.level, start_message(metadata, config.log_args))
  end

  def handle_event([:nebulex, :cache, :command, :stop], measurements, metadata, config) do
    duration_ms = duration_in_ms(measurements.duration)
    Logger.log(config.level, fn -> "Cache #{metadata.cache} #{metadata.command} completed in #{duration_ms}ms" end)
  end

  def handle_event([:nebulex, :cache, :command, :exception], measurements, metadata, _config) do
    duration_ms = duration_in_ms(measurements.duration)
    Logger.error(fn -> "Cache #{metadata.cache} #{metadata.command} failed after #{duration_ms}ms: #{inspect(metadata.reason)}" end)
  end

  # Pattern matching replaces if/else for log_args toggle
  defp start_message(metadata, true = _log_args) do
    fn -> "Cache #{metadata.cache} #{metadata.command} started with args: #{inspect(metadata.args)}" end
  end

  defp start_message(metadata, false = _log_args) do
    fn -> "Cache #{metadata.cache} #{metadata.command} started" end
  end

  defp duration_in_ms(duration), do: System.convert_time_unit(duration, :native, :millisecond)

  # ============================================
  # Custom Event Emitters
  # ============================================

  @doc """
  Emits a cache hit event.

  ## Examples

      OmCache.Telemetry.emit_cache_hit(MyApp.Cache, {User, 123}, 2.5)
  """
  @spec emit_cache_hit(module(), term(), float()) :: :ok
  def emit_cache_hit(cache, key, duration_ms) do
    :telemetry.execute(
      [:om_cache, :hit],
      %{duration: duration_ms},
      %{cache: cache, key: key}
    )
  end

  @doc """
  Emits a cache miss event.

  ## Examples

      OmCache.Telemetry.emit_cache_miss(MyApp.Cache, {User, 999}, 1.2)
  """
  @spec emit_cache_miss(module(), term(), float()) :: :ok
  def emit_cache_miss(cache, key, duration_ms) do
    :telemetry.execute(
      [:om_cache, :miss],
      %{duration: duration_ms},
      %{cache: cache, key: key}
    )
  end

  @doc """
  Emits a cache write event.

  ## Examples

      OmCache.Telemetry.emit_cache_write(MyApp.Cache, {User, 123}, 3.1)
  """
  @spec emit_cache_write(module(), term(), float()) :: :ok
  def emit_cache_write(cache, key, duration_ms) do
    :telemetry.execute(
      [:om_cache, :write],
      %{duration: duration_ms},
      %{cache: cache, key: key}
    )
  end

  @doc """
  Emits a cache error event.

  ## Examples

      error = OmCache.Error.connection_failed(MyApp.Cache, "Redis down")
      OmCache.Telemetry.emit_cache_error(MyApp.Cache, error)
  """
  @spec emit_cache_error(module(), OmCache.Error.t()) :: :ok
  def emit_cache_error(cache, %OmCache.Error{} = error) do
    :telemetry.execute(
      [:om_cache, :error],
      %{},
      %{cache: cache, error_type: error.type, error: error}
    )
  end

  @doc """
  Emits a cache eviction event.

  ## Examples

      OmCache.Telemetry.emit_eviction(MyApp.Cache, {User, 123}, :expired)
  """
  @spec emit_eviction(module(), term(), atom()) :: :ok
  def emit_eviction(cache, key, reason) do
    :telemetry.execute(
      [:om_cache, :eviction],
      %{},
      %{cache: cache, key: key, reason: reason}
    )
  end

  @doc """
  Emits a batch operation event.

  ## Examples

      OmCache.Telemetry.emit_batch_operation(MyApp.Cache, :fetch, 25, 150.5)
  """
  @spec emit_batch_operation(module(), atom(), non_neg_integer(), float()) :: :ok
  def emit_batch_operation(cache, operation, count, duration_ms) do
    :telemetry.execute(
      [:om_cache, :batch],
      %{count: count, duration: duration_ms},
      %{cache: cache, operation: operation}
    )
  end

  @doc """
  Emits a warming event.

  ## Examples

      OmCache.Telemetry.emit_warming(MyApp.Cache, 150, 2500.0)
  """
  @spec emit_warming(module(), non_neg_integer(), float()) :: :ok
  def emit_warming(cache, count, duration_ms) do
    :telemetry.execute(
      [:om_cache, :warming],
      %{count: count, duration: duration_ms},
      %{cache: cache}
    )
  end

  @doc """
  Emits a circuit breaker state change event.

  ## Examples

      OmCache.Telemetry.emit_circuit_breaker_state(MyApp.Cache, :open, :closed)
  """
  @spec emit_circuit_breaker_state(module(), atom(), atom()) :: :ok
  def emit_circuit_breaker_state(cache, from_state, to_state) do
    :telemetry.execute(
      [:om_cache, :circuit_breaker, :state_change],
      %{},
      %{cache: cache, from: from_state, to: to_state}
    )
  end
end

