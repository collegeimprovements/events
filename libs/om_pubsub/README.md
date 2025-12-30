# OmPubSub

Phoenix.PubSub wrapper with multiple adapters and automatic fallback.

## Features

- **Multiple adapters**: Redis, PostgreSQL, or local
- **Automatic fallback**: Try adapters in order until one works
- **Graceful degradation**: Works even when external services are down
- **Convenience API**: Simple subscribe/broadcast functions
- **Telemetry integration**: Built-in telemetry and Redis monitoring

## Adapters

| Adapter | Use Case | Requirements |
|---------|----------|--------------|
| `:redis` | Multi-node, high throughput | Redis server |
| `:postgres` | Shared database, DB-triggered events | PostgreSQL (already have it) |
| `:local` | Single node, development | None |

## Installation

```elixir
def deps do
  [
    {:om_pubsub, path: "../om_pubsub"}
  ]
end
```

## Quick Start

### 1. Add to Supervision Tree

```elixir
children = [
  {OmPubSub, name: MyApp.PubSub},
  # ...
]
```

### 2. Subscribe and Broadcast

```elixir
# Subscribe to a topic
OmPubSub.subscribe(MyApp.PubSub, "room:123")

# Broadcast to a topic
OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hello"})

# In your process, receive the message
def handle_info({:new_message, payload}, state) do
  IO.inspect(payload)
  {:noreply, state}
end
```

## Configuration

Environment variables:
- `REDIS_HOST` - Redis host (default: "localhost")
- `REDIS_PORT` - Redis port (default: 6379)
- `PUBSUB_ADAPTER` - Force adapter: "redis", "postgres", or "local"

### Forcing an Adapter

```elixir
# Force local adapter (no external deps)
{OmPubSub, name: MyApp.PubSub, adapter: :local}

# Force Redis adapter
{OmPubSub, name: MyApp.PubSub, adapter: :redis}

# Force PostgreSQL adapter (requires repo)
{OmPubSub, name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo}

# Auto-detect (default: tries Redis -> Local)
{OmPubSub, name: MyApp.PubSub, adapter: :auto}
```

### Custom Fallback Chain

```elixir
# Try Redis -> Postgres -> Local
{OmPubSub, name: MyApp.PubSub,
  fallback_chain: [:redis, :postgres, :local],
  repo: MyApp.Repo}
```

### Custom Redis Config

```elixir
{OmPubSub,
  name: MyApp.PubSub,
  redis_host: "redis.local",
  redis_port: 6380}
```

### PostgreSQL Config

```elixir
# Using Ecto Repo (recommended)
{OmPubSub, name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo}

# Using direct connection opts
{OmPubSub, name: MyApp.PubSub, adapter: :postgres,
  conn_opts: [
    hostname: "localhost",
    database: "my_app",
    username: "postgres",
    password: "postgres"
  ]}
```

## API Reference

### Core Functions

```elixir
# Get the server name for direct Phoenix.PubSub calls
OmPubSub.server(MyApp.PubSub)
# => :"MyApp.PubSub.Server"

# Subscribe
OmPubSub.subscribe(MyApp.PubSub, "topic")

# Unsubscribe
OmPubSub.unsubscribe(MyApp.PubSub, "topic")

# Broadcast with event tuple
OmPubSub.broadcast(MyApp.PubSub, "topic", :event_name, payload)
# Receivers get: {:event_name, payload}

# Broadcast raw message
OmPubSub.broadcast_raw(MyApp.PubSub, "topic", any_message)
# Receivers get: any_message

# Broadcast from (excludes sender)
OmPubSub.broadcast_from(MyApp.PubSub, self(), "topic", :event, payload)

# Direct broadcast (local node only)
OmPubSub.direct_broadcast(MyApp.PubSub, node(), "topic", :event, payload)
```

### Adapter Inspection

```elixir
OmPubSub.adapter(MyApp.PubSub)  # => :redis or :local
OmPubSub.redis?(MyApp.PubSub)   # => true/false
OmPubSub.local?(MyApp.PubSub)   # => true/false
```

## Using with Phoenix

```elixir
# In application.ex
def start(_type, _args) do
  children = [
    {OmPubSub, name: MyApp.PubSub},
    MyAppWeb.Endpoint,
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# In endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    pubsub_server: :"MyApp.PubSub.Server"
end
```

## Telemetry

Attach a logger for PubSub operations:

```elixir
OmPubSub.Telemetry.attach_logger(:my_pubsub_logger, level: :info)
```

Or attach custom handlers:

```elixir
:telemetry.attach(
  "pubsub-metrics",
  [:om_pubsub, :broadcast, :stop],
  &MyApp.Metrics.handle_pubsub_event/4,
  nil
)
```

### PubSub Events

- `[:om_pubsub, :subscribe, :start | :stop]`
- `[:om_pubsub, :broadcast, :start | :stop]`

## Redis Connection Monitoring

Monitor Redis connection status with callbacks for alerting:

```elixir
# In your application startup
OmPubSub.Telemetry.attach_redis_monitor(:redis_monitor,
  on_disconnect: fn meta ->
    # Alert when Redis goes down
    MyApp.Slack.alert("Redis disconnected: #{inspect(meta.reason)}")
    MyApp.PagerDuty.trigger("redis-down", meta)
  end,
  on_connect: fn meta ->
    # Notify when Redis reconnects
    MyApp.Slack.notify("Redis reconnected: #{meta.address}")
    MyApp.PagerDuty.resolve("redis-down")
  end
)
```

### Simple Logging

```elixir
# Just log connection events (no callbacks)
OmPubSub.Telemetry.attach_redis_monitor(:redis_logger)

# Output:
# [info] Redis connected: localhost:6379
# [warning] Redis disconnected: localhost:6379 - reason: :tcp_closed
```

### Redis Events

- `[:om_pubsub, :redis, :connected]` - Redis connection established
- `[:om_pubsub, :redis, :disconnected]` - Redis connection lost

### Custom Event Handler

```elixir
:telemetry.attach(
  "redis-metrics",
  [:om_pubsub, :redis, :disconnected],
  fn _event, _measurements, metadata, _config ->
    MyApp.Metrics.increment("redis.disconnections")
    Logger.error("Redis down: #{metadata.address}")
  end,
  nil
)
```

## Resilience Notes

- **Redis auto-reconnects**: Redix handles reconnection automatically
- **No dynamic failover**: Adapter is set at startup, won't switch mid-run
- **Recommendation**: Use `attach_redis_monitor/2` for alerting, not failover

## License

MIT
