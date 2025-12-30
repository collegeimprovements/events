defmodule OmPubSub.Telemetry do
  @moduledoc """
  Telemetry integration for OmPubSub.

  Provides helpers for emitting and handling telemetry events for PubSub operations,
  including Redis connection monitoring.

  ## PubSub Events

  - `[:om_pubsub, :subscribe, :start | :stop]` - Subscribe operations
  - `[:om_pubsub, :broadcast, :start | :stop]` - Broadcast operations

  ## Redis Connection Events

  When using Redis adapter, monitors connection status:

  - `[:om_pubsub, :redis, :connected]` - Redis connection established
  - `[:om_pubsub, :redis, :disconnected]` - Redis connection lost

  ## Quick Start

      # Monitor Redis connection status (logs + optional callback)
      OmPubSub.Telemetry.attach_redis_monitor(:my_monitor,
        on_disconnect: fn meta -> MyApp.Alerts.pagerduty("Redis down!") end,
        on_connect: fn meta -> MyApp.Alerts.resolve("Redis back up") end
      )

      # Or just log everything
      OmPubSub.Telemetry.attach_logger(:my_logger)
      OmPubSub.Telemetry.attach_redis_monitor(:my_redis_monitor)

  ## Measurements

  - `:system_time` - System time at event
  - `:duration` - Operation duration in native units (for :stop events)

  ## Metadata

  - `:pubsub` - PubSub name
  - `:topic` - Topic name
  - `:event` - Event name (for broadcast)
  - `:adapter` - Current adapter (:redis or :local)
  - `:address` - Redis address (for connection events)
  - `:reason` - Disconnect reason (for disconnection events)
  """

  require Logger

  @doc """
  Attaches a simple logging handler for PubSub operations.

  ## Options

  - `:level` - Log level (default: :debug)

  ## Examples

      OmPubSub.Telemetry.attach_logger(:my_pubsub_logger)
      OmPubSub.Telemetry.attach_logger(:my_pubsub_logger, level: :info)
  """
  @spec attach_logger(atom(), keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(handler_id, opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    config = %{level: level}

    :telemetry.attach_many(
      handler_id,
      [
        [:om_pubsub, :subscribe, :start],
        [:om_pubsub, :subscribe, :stop],
        [:om_pubsub, :broadcast, :start],
        [:om_pubsub, :broadcast, :stop]
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

  @doc """
  Emits a subscribe start event.
  """
  @spec emit_subscribe_start(atom(), String.t(), atom()) :: :ok
  def emit_subscribe_start(pubsub, topic, adapter) do
    :telemetry.execute(
      [:om_pubsub, :subscribe, :start],
      %{system_time: System.system_time()},
      %{pubsub: pubsub, topic: topic, adapter: adapter}
    )
  end

  @doc """
  Emits a subscribe stop event.
  """
  @spec emit_subscribe_stop(atom(), String.t(), atom(), integer()) :: :ok
  def emit_subscribe_stop(pubsub, topic, adapter, duration) do
    :telemetry.execute(
      [:om_pubsub, :subscribe, :stop],
      %{system_time: System.system_time(), duration: duration},
      %{pubsub: pubsub, topic: topic, adapter: adapter}
    )
  end

  @doc """
  Emits a broadcast start event.
  """
  @spec emit_broadcast_start(atom(), String.t(), atom(), atom()) :: :ok
  def emit_broadcast_start(pubsub, topic, event, adapter) do
    :telemetry.execute(
      [:om_pubsub, :broadcast, :start],
      %{system_time: System.system_time()},
      %{pubsub: pubsub, topic: topic, event: event, adapter: adapter}
    )
  end

  @doc """
  Emits a broadcast stop event.
  """
  @spec emit_broadcast_stop(atom(), String.t(), atom(), atom(), integer()) :: :ok
  def emit_broadcast_stop(pubsub, topic, event, adapter, duration) do
    :telemetry.execute(
      [:om_pubsub, :broadcast, :stop],
      %{system_time: System.system_time(), duration: duration},
      %{pubsub: pubsub, topic: topic, event: event, adapter: adapter}
    )
  end

  @doc false
  def handle_event([:om_pubsub, :subscribe, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "PubSub #{inspect(metadata.pubsub)} subscribe to #{metadata.topic} (#{metadata.adapter})"
    end)

    :ok
  end

  def handle_event([:om_pubsub, :subscribe, :stop], measurements, metadata, config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.log(config.level, fn ->
      "PubSub #{inspect(metadata.pubsub)} subscribed to #{metadata.topic} in #{duration_us}us"
    end)

    :ok
  end

  def handle_event([:om_pubsub, :broadcast, :start], _measurements, metadata, config) do
    Logger.log(config.level, fn ->
      "PubSub #{inspect(metadata.pubsub)} broadcast #{metadata.event} to #{metadata.topic}"
    end)

    :ok
  end

  def handle_event([:om_pubsub, :broadcast, :stop], measurements, metadata, config) do
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    Logger.log(config.level, fn ->
      "PubSub #{inspect(metadata.pubsub)} broadcast #{metadata.event} to #{metadata.topic} in #{duration_us}us"
    end)

    :ok
  end

  # ============================================================================
  # Redis Connection Monitoring
  # ============================================================================

  @doc """
  Attaches a Redis connection monitor.

  Monitors Redix connection events and emits `[:om_pubsub, :redis, :connected | :disconnected]`
  events. Optionally calls provided callbacks on connection state changes.

  ## Options

  - `:on_connect` - Function called when Redis connects. Receives metadata map.
  - `:on_disconnect` - Function called when Redis disconnects. Receives metadata map.
  - `:log_level` - Log level for connection events (default: `:warning` for disconnect, `:info` for connect)

  ## Examples

      # Just logging
      OmPubSub.Telemetry.attach_redis_monitor(:my_monitor)

      # With alerting callbacks
      OmPubSub.Telemetry.attach_redis_monitor(:my_monitor,
        on_disconnect: fn meta ->
          MyApp.Slack.alert("Redis disconnected: \#{inspect(meta.reason)}")
        end,
        on_connect: fn meta ->
          MyApp.Slack.notify("Redis reconnected: \#{meta.address}")
        end
      )

      # With PagerDuty integration
      OmPubSub.Telemetry.attach_redis_monitor(:pagerduty_monitor,
        on_disconnect: &MyApp.PagerDuty.trigger/1,
        on_connect: &MyApp.PagerDuty.resolve/1
      )
  """
  @spec attach_redis_monitor(atom(), keyword()) :: :ok | {:error, :already_exists}
  def attach_redis_monitor(handler_id, opts \\ []) do
    config = %{
      on_connect: Keyword.get(opts, :on_connect),
      on_disconnect: Keyword.get(opts, :on_disconnect),
      connect_level: Keyword.get(opts, :connect_level, :info),
      disconnect_level: Keyword.get(opts, :disconnect_level, :warning)
    }

    :telemetry.attach_many(
      handler_id,
      [
        [:redix, :connection],
        [:redix, :disconnection]
      ],
      &__MODULE__.handle_redis_event/4,
      config
    )
  end

  @doc """
  Detaches a Redis connection monitor.
  """
  @spec detach_redis_monitor(atom()) :: :ok | {:error, :not_found}
  def detach_redis_monitor(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Attaches handlers for om_pubsub Redis events (after they've been transformed from Redix events).

  Use this if you want to handle the normalized `[:om_pubsub, :redis, ...]` events
  rather than raw Redix events.

  ## Examples

      :telemetry.attach(
        "my-redis-handler",
        [:om_pubsub, :redis, :disconnected],
        fn _event, _measurements, metadata, _config ->
          IO.puts("Redis down! Reason: \#{inspect(metadata.reason)}")
        end,
        nil
      )
  """
  @spec attach_redis_events(atom(), keyword()) :: :ok | {:error, :already_exists}
  def attach_redis_events(handler_id, opts \\ []) do
    config = Keyword.get(opts, :config, nil)

    :telemetry.attach_many(
      handler_id,
      [
        [:om_pubsub, :redis, :connected],
        [:om_pubsub, :redis, :disconnected]
      ],
      Keyword.get(opts, :handler, &__MODULE__.default_redis_event_handler/4),
      config
    )
  end

  @doc false
  def handle_redis_event([:redix, :connection], _measurements, metadata, config) do
    address = format_address(metadata)

    # Log the connection
    Logger.log(config.connect_level, fn ->
      "Redis connected: #{address}"
    end)

    # Emit our own event
    :telemetry.execute(
      [:om_pubsub, :redis, :connected],
      %{system_time: System.system_time()},
      %{address: address, raw_metadata: metadata}
    )

    # Call user callback if provided
    if config.on_connect do
      safe_callback(config.on_connect, %{address: address, metadata: metadata})
    end

    :ok
  end

  def handle_redis_event([:redix, :disconnection], _measurements, metadata, config) do
    address = format_address(metadata)
    reason = Map.get(metadata, :reason, :unknown)

    # Log the disconnection
    Logger.log(config.disconnect_level, fn ->
      "Redis disconnected: #{address} - reason: #{inspect(reason)}"
    end)

    # Emit our own event
    :telemetry.execute(
      [:om_pubsub, :redis, :disconnected],
      %{system_time: System.system_time()},
      %{address: address, reason: reason, raw_metadata: metadata}
    )

    # Call user callback if provided
    if config.on_disconnect do
      safe_callback(config.on_disconnect, %{address: address, reason: reason, metadata: metadata})
    end

    :ok
  end

  @doc false
  def default_redis_event_handler([:om_pubsub, :redis, :connected], _measurements, metadata, _config) do
    Logger.info("OmPubSub Redis connected: #{metadata.address}")
    :ok
  end

  def default_redis_event_handler([:om_pubsub, :redis, :disconnected], _measurements, metadata, _config) do
    Logger.warning("OmPubSub Redis disconnected: #{metadata.address} - #{inspect(metadata.reason)}")
    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp format_address(metadata) do
    host = Map.get(metadata, :host, Map.get(metadata, :address, "unknown"))
    port = Map.get(metadata, :port, "?")
    "#{host}:#{port}"
  end

  defp safe_callback(callback, metadata) do
    try do
      callback.(metadata)
    rescue
      e ->
        Logger.error("OmPubSub telemetry callback failed: #{inspect(e)}")
    end
  end
end
