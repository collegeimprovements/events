# OmPubSub

Phoenix.PubSub wrapper with multiple adapters, automatic fallback, and graceful degradation.

## Installation

```elixir
def deps do
  [
    {:om_pubsub, path: "../om_pubsub"},
    {:phoenix_pubsub, "~> 2.1"},
    {:phoenix_pubsub_redis, "~> 3.0", optional: true},  # For Redis adapter
    {:redix, "~> 1.2", optional: true}                  # For Redis adapter
  ]
end
```

## Why OmPubSub?

```
Without OmPubSub:                          With OmPubSub:
┌─────────────────────────────────────┐    ┌─────────────────────────────────────┐
│                                     │    │                                     │
│  # Manual adapter configuration     │    │  # Automatic adapter with fallback  │
│  children = [                       │    │  children = [                       │
│    if redis_available?() do         │    │    {OmPubSub, name: MyApp.PubSub},  │
│      {Phoenix.PubSub,               │    │    # ...                            │
│       name: MyApp.PubSub,           │    │  ]                                  │
│       adapter: Phoenix.PubSub.Redis,│    │                                     │
│       redis_url: redis_url()}       │    │  # Subscribe                        │
│    else                             │    │  OmPubSub.subscribe(MyApp.PubSub,   │
│      {Phoenix.PubSub,               │    │    "user:123")                      │
│       name: MyApp.PubSub}           │    │                                     │
│    end                              │    │  # Broadcast                        │
│  ]                                  │    │  OmPubSub.broadcast(MyApp.PubSub,   │
│                                     │    │    "user:123", :notification, data) │
│  # Check which adapter is active    │    │                                     │
│  # ... no built-in way              │    │  # Check adapter at runtime         │
│                                     │    │  OmPubSub.adapter(MyApp.PubSub)     │
│  # Redis connection monitoring      │    │  #=> :redis                         │
│  # ... roll your own                │    │                                     │
│                                     │    │  # Built-in Redis monitoring        │
│  # PostgreSQL LISTEN/NOTIFY?        │    │  OmPubSub.Telemetry.attach_redis_   │
│  # ... write from scratch           │    │    monitor(:alerter, on_disconnect: │
│                                     │    │      &MyApp.Alert.redis_down/1)     │
└─────────────────────────────────────┘    └─────────────────────────────────────┘
```

**Key Benefits:**
- **Multiple adapters**: Redis, PostgreSQL LISTEN/NOTIFY, or local PG2
- **Automatic fallback**: Tries adapters in order until one works
- **Graceful degradation**: Works even when external services are down
- **Redis monitoring**: Built-in telemetry for connection status
- **PostgreSQL adapter**: Use your existing database for pub/sub
- **Convenience API**: Simple subscribe/broadcast functions

---

## Quick Start

### 1. Add to Supervision Tree

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    {OmPubSub, name: MyApp.PubSub},
    MyAppWeb.Endpoint,
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 2. Subscribe and Broadcast

```elixir
# In a GenServer or LiveView
def init(_) do
  OmPubSub.subscribe(MyApp.PubSub, "room:123")
  {:ok, %{}}
end

# Receive messages
def handle_info({:new_message, payload}, state) do
  # Handle the message
  IO.inspect(payload, label: "New message")
  {:noreply, state}
end

# Broadcast from anywhere
OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hello!"})
```

---

## Adapters

### Adapter Comparison

| Adapter | Use Case | Requirements | Pros | Cons |
|---------|----------|--------------|------|------|
| `:redis` | Multi-node, high throughput | Redis server | Fast, battle-tested | Extra infrastructure |
| `:postgres` | Shared database, DB triggers | PostgreSQL | No extra infra, DB events | 8KB payload limit |
| `:local` | Single node, development | None | Zero dependencies | Single node only |

### Redis Adapter (Recommended for Production)

```elixir
# Auto-detect (tries Redis, falls back to local)
{OmPubSub, name: MyApp.PubSub}

# Force Redis
{OmPubSub, name: MyApp.PubSub, adapter: :redis}

# Custom Redis configuration
{OmPubSub,
 name: MyApp.PubSub,
 adapter: :redis,
 redis_host: "redis.internal",
 redis_port: 6380}

# Using environment variables
# REDIS_HOST=redis.internal REDIS_PORT=6380
{OmPubSub, name: MyApp.PubSub, adapter: :redis}
```

### PostgreSQL Adapter

Uses PostgreSQL's built-in LISTEN/NOTIFY mechanism:

```elixir
# Using Ecto Repo (recommended)
{OmPubSub,
 name: MyApp.PubSub,
 adapter: :postgres,
 repo: MyApp.Repo}

# Using direct connection options
{OmPubSub,
 name: MyApp.PubSub,
 adapter: :postgres,
 conn_opts: [
   hostname: "localhost",
   database: "my_app_prod",
   username: "postgres",
   password: "secret"
 ]}

# Using DATABASE_URL
{OmPubSub,
 name: MyApp.PubSub,
 adapter: :postgres,
 conn_opts: [url: System.get_env("DATABASE_URL")]}
```

**PostgreSQL Limitations:**
- Payload size: 8KB max (PostgreSQL limitation)
- Same database: Only works across connections to the same DB
- Serialization: Payloads are JSON-encoded strings

### Local Adapter

```elixir
# Explicitly use local (single node)
{OmPubSub, name: MyApp.PubSub, adapter: :local}

# Environment variable
# PUBSUB_ADAPTER=local
{OmPubSub, name: MyApp.PubSub}
```

### Custom Fallback Chain

```elixir
# Try Redis -> Postgres -> Local
{OmPubSub,
 name: MyApp.PubSub,
 fallback_chain: [:redis, :postgres, :local],
 repo: MyApp.Repo}

# Try Postgres -> Local (no Redis)
{OmPubSub,
 name: MyApp.PubSub,
 fallback_chain: [:postgres, :local],
 repo: MyApp.Repo}
```

---

## Topic Patterns

### Topic Naming Conventions

```elixir
# Entity-scoped topics
"user:#{user_id}"           # User-specific events
"room:#{room_id}"           # Chat room messages
"order:#{order_id}"         # Order status updates

# Type-scoped topics
"notifications:#{user_id}"   # User notifications
"presence:#{room_id}"        # Presence updates
"typing:#{room_id}"          # Typing indicators

# Hierarchical topics
"org:#{org_id}:team:#{team_id}"  # Org > Team scoping
"project:#{project_id}:tasks"     # Project tasks

# Broadcast topics
"system:maintenance"         # System-wide announcements
"admin:alerts"               # Admin notifications
"global:feature_flags"       # Feature flag updates
```

### Multi-Topic Subscriptions

```elixir
# Subscribe to multiple topics
def init(%{user_id: user_id, room_id: room_id}) do
  pubsub = MyApp.PubSub

  OmPubSub.subscribe(pubsub, "user:#{user_id}")
  OmPubSub.subscribe(pubsub, "room:#{room_id}")
  OmPubSub.subscribe(pubsub, "system:announcements")

  {:ok, %{user_id: user_id, room_id: room_id}}
end

# Handle messages from different topics
def handle_info({:new_message, payload}, state) do
  # Room message
  {:noreply, update_messages(state, payload)}
end

def handle_info({:notification, payload}, state) do
  # User notification
  {:noreply, add_notification(state, payload)}
end

def handle_info({:announcement, payload}, state) do
  # System announcement
  {:noreply, show_banner(state, payload)}
end
```

---

## API Reference

### Core Functions

```elixir
# Get the underlying Phoenix.PubSub server name
OmPubSub.server(MyApp.PubSub)
#=> :"MyApp.PubSub.Server"

# Subscribe current process to a topic
OmPubSub.subscribe(pubsub, topic)
OmPubSub.subscribe(MyApp.PubSub, "room:123")

# Unsubscribe from a topic
OmPubSub.unsubscribe(pubsub, topic)
OmPubSub.unsubscribe(MyApp.PubSub, "room:123")

# Broadcast event + payload (receivers get {event, payload})
OmPubSub.broadcast(pubsub, topic, event, payload)
OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hi"})
# Receivers get: {:new_message, %{text: "Hi"}}

# Broadcast raw message (receivers get exact message)
OmPubSub.broadcast_raw(pubsub, topic, message)
OmPubSub.broadcast_raw(MyApp.PubSub, "room:123", {:custom, :format, data})
# Receivers get: {:custom, :format, data}

# Broadcast excluding sender
OmPubSub.broadcast_from(pubsub, from_pid, topic, event, payload)
OmPubSub.broadcast_from(MyApp.PubSub, self(), "room:123", :typing, %{user: "Alice"})

# Direct broadcast (local node only)
OmPubSub.direct_broadcast(pubsub, node, topic, event, payload)
OmPubSub.direct_broadcast(MyApp.PubSub, node(), "room:123", :ping, %{})
```

### Adapter Inspection

```elixir
# Get current adapter
OmPubSub.adapter(MyApp.PubSub)
#=> :redis | :postgres | :local

# Check specific adapter
OmPubSub.redis?(MyApp.PubSub)     #=> true/false
OmPubSub.postgres?(MyApp.PubSub)  #=> true/false
OmPubSub.local?(MyApp.PubSub)     #=> true/false
```

---

## Phoenix Integration

### With Phoenix LiveView

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(%{"room_id" => room_id}, _session, socket) do
    if connected?(socket) do
      OmPubSub.subscribe(MyApp.PubSub, "room:#{room_id}")
    end

    {:ok,
     socket
     |> assign(:room_id, room_id)
     |> assign(:messages, list_messages(room_id))}
  end

  @impl true
  def handle_event("send_message", %{"text" => text}, socket) do
    message = create_message(socket.assigns.room_id, text)

    OmPubSub.broadcast(
      MyApp.PubSub,
      "room:#{socket.assigns.room_id}",
      :new_message,
      message
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, update(socket, :messages, &[message | &1])}
  end

  @impl true
  def handle_info({:user_typing, %{user: user}}, socket) do
    {:noreply, assign(socket, :typing_user, user)}
  end
end
```

### With Phoenix Channels

```elixir
defmodule MyAppWeb.RoomChannel do
  use MyAppWeb, :channel

  @impl true
  def join("room:" <> room_id, _params, socket) do
    OmPubSub.subscribe(MyApp.PubSub, "room:#{room_id}:internal")
    {:ok, assign(socket, :room_id, room_id)}
  end

  @impl true
  def handle_in("message", %{"text" => text}, socket) do
    room_id = socket.assigns.room_id

    # Broadcast to internal subscribers (background workers, etc.)
    OmPubSub.broadcast(MyApp.PubSub, "room:#{room_id}:internal", :new_message, %{
      text: text,
      user_id: socket.assigns.user_id,
      room_id: room_id
    })

    # Also broadcast to channel clients
    broadcast!(socket, "message", %{text: text})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:moderation_action, %{action: action}}, socket) do
    push(socket, "moderation", %{action: action})
    {:noreply, socket}
  end
end
```

### Endpoint Configuration

```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  pubsub_server: :"MyApp.PubSub.Server"

# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    pubsub_server: :"MyApp.PubSub.Server"

  socket "/socket", MyAppWeb.UserSocket,
    websocket: true,
    longpoll: false
end
```

---

## Message Patterns

### Event Pattern (Recommended)

```elixir
# Structured event messages
OmPubSub.broadcast(MyApp.PubSub, "orders", :order_created, %{
  id: "ord_123",
  customer_id: "cus_456",
  total: 99.99
})

# Handle with pattern matching
def handle_info({:order_created, order}, state) do
  # Handle new order
  {:noreply, state}
end

def handle_info({:order_shipped, order}, state) do
  # Handle shipped order
  {:noreply, state}
end

def handle_info({:order_cancelled, order}, state) do
  # Handle cancellation
  {:noreply, state}
end
```

### Command Pattern

```elixir
# Send commands to workers
defmodule MyApp.CommandDispatcher do
  def dispatch_to_worker(worker_id, command, params) do
    OmPubSub.broadcast(
      MyApp.PubSub,
      "worker:#{worker_id}:commands",
      command,
      params
    )
  end
end

# Worker receives commands
defmodule MyApp.Worker do
  use GenServer

  def init(%{worker_id: worker_id}) do
    OmPubSub.subscribe(MyApp.PubSub, "worker:#{worker_id}:commands")
    {:ok, %{worker_id: worker_id}}
  end

  def handle_info({:process_item, params}, state) do
    result = process(params)
    broadcast_result(state.worker_id, result)
    {:noreply, state}
  end

  def handle_info({:pause, _}, state) do
    {:noreply, %{state | paused: true}}
  end

  def handle_info({:resume, _}, state) do
    {:noreply, %{state | paused: false}}
  end
end
```

### Notification Pattern

```elixir
# User notification service
defmodule MyApp.Notifications do
  def notify_user(user_id, type, data) do
    OmPubSub.broadcast(
      MyApp.PubSub,
      "notifications:#{user_id}",
      :notification,
      %{
        id: generate_id(),
        type: type,
        data: data,
        timestamp: DateTime.utc_now()
      }
    )
  end

  def notify_mention(user_id, mentioner, context) do
    notify_user(user_id, :mention, %{
      mentioner: mentioner,
      context: context
    })
  end

  def notify_comment(user_id, comment) do
    notify_user(user_id, :comment, %{
      comment_id: comment.id,
      content_preview: String.slice(comment.body, 0..100)
    })
  end
end
```

### Broadcast-From Pattern (Exclude Sender)

```elixir
# Typing indicator that doesn't echo back to sender
def handle_event("typing", _params, socket) do
  OmPubSub.broadcast_from(
    MyApp.PubSub,
    self(),
    "room:#{socket.assigns.room_id}",
    :user_typing,
    %{user: socket.assigns.current_user.name}
  )

  {:noreply, socket}
end

# All OTHER users in the room see the typing indicator
def handle_info({:user_typing, %{user: user}}, socket) do
  {:noreply, assign(socket, :typing_user, user)}
end
```

---

## Telemetry Integration

### Attach Logging Handler

```elixir
# Basic logging
OmPubSub.Telemetry.attach_logger(:my_pubsub_logger)

# With custom log level
OmPubSub.Telemetry.attach_logger(:my_pubsub_logger, level: :info)

# Detach when done
OmPubSub.Telemetry.detach_logger(:my_pubsub_logger)
```

### Custom Telemetry Handlers

```elixir
# Metrics collection
:telemetry.attach(
  "pubsub-metrics",
  [:om_pubsub, :broadcast, :stop],
  fn _event, measurements, metadata, _config ->
    duration_us = System.convert_time_unit(measurements.duration, :native, :microsecond)

    MyApp.Metrics.histogram("pubsub.broadcast.duration", duration_us, %{
      topic: metadata.topic,
      adapter: metadata.adapter
    })
  end,
  nil
)

# Broadcast counting
:telemetry.attach(
  "pubsub-counter",
  [:om_pubsub, :broadcast, :start],
  fn _event, _measurements, metadata, _config ->
    MyApp.Metrics.increment("pubsub.broadcasts", %{
      topic_prefix: topic_prefix(metadata.topic),
      event: metadata.event
    })
  end,
  nil
)

defp topic_prefix(topic) do
  topic |> String.split(":") |> List.first()
end
```

### Available Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:om_pubsub, :subscribe, :start]` | `system_time` | `pubsub`, `topic`, `adapter` |
| `[:om_pubsub, :subscribe, :stop]` | `system_time`, `duration` | `pubsub`, `topic`, `adapter` |
| `[:om_pubsub, :broadcast, :start]` | `system_time` | `pubsub`, `topic`, `event`, `adapter` |
| `[:om_pubsub, :broadcast, :stop]` | `system_time`, `duration` | `pubsub`, `topic`, `event`, `adapter` |
| `[:om_pubsub, :redis, :connected]` | `system_time` | `address`, `raw_metadata` |
| `[:om_pubsub, :redis, :disconnected]` | `system_time` | `address`, `reason`, `raw_metadata` |

---

## Redis Connection Monitoring

### Basic Monitoring

```elixir
# Just logging (logs connect/disconnect events)
OmPubSub.Telemetry.attach_redis_monitor(:redis_logger)

# Output:
# [info] Redis connected: localhost:6379
# [warning] Redis disconnected: localhost:6379 - reason: :tcp_closed
```

### With Alerting Callbacks

```elixir
# Slack + PagerDuty integration
OmPubSub.Telemetry.attach_redis_monitor(:redis_alerter,
  on_disconnect: fn meta ->
    MyApp.Slack.alert("#ops", "Redis disconnected: #{inspect(meta.reason)}")
    MyApp.PagerDuty.trigger("redis-down", %{
      address: meta.address,
      reason: meta.reason
    })
  end,
  on_connect: fn meta ->
    MyApp.Slack.notify("#ops", "Redis reconnected: #{meta.address}")
    MyApp.PagerDuty.resolve("redis-down")
  end
)
```

### Custom Log Levels

```elixir
OmPubSub.Telemetry.attach_redis_monitor(:redis_monitor,
  connect_level: :debug,      # Less noisy connects
  disconnect_level: :error    # Louder disconnects
)
```

### Metrics Collection

```elixir
# Track Redis connection stability
:telemetry.attach(
  "redis-disconnect-counter",
  [:om_pubsub, :redis, :disconnected],
  fn _event, _measurements, metadata, _config ->
    MyApp.Metrics.increment("redis.disconnections", %{
      address: metadata.address,
      reason: to_string(metadata.reason)
    })
  end,
  nil
)
```

---

## Custom Adapters

### Implementing a Custom Adapter

```elixir
defmodule MyApp.PubSub.CustomAdapter do
  @behaviour OmPubSub.Adapter

  use GenServer

  # Required callbacks

  @impl OmPubSub.Adapter
  def subscribe(server, topic, opts \\ []) do
    GenServer.call(server, {:subscribe, topic, self(), opts})
  end

  @impl OmPubSub.Adapter
  def unsubscribe(server, topic) do
    GenServer.call(server, {:unsubscribe, topic, self()})
  end

  @impl OmPubSub.Adapter
  def broadcast(server, topic, message) do
    GenServer.call(server, {:broadcast, topic, message})
  end

  @impl OmPubSub.Adapter
  def broadcast_from(server, from_pid, topic, message) do
    GenServer.call(server, {:broadcast_from, from_pid, topic, message})
  end

  # GenServer implementation

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    {:ok, %{subscribers: %{}, opts: opts}}
  end

  @impl GenServer
  def handle_call({:subscribe, topic, pid, _opts}, _from, state) do
    Process.monitor(pid)
    subscribers = Map.update(state.subscribers, topic, [pid], &[pid | &1])
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    subscribers = Map.update(state.subscribers, topic, [], &List.delete(&1, pid))
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:broadcast, topic, message}, _from, state) do
    dispatch(state.subscribers[topic] || [], message, nil)
    {:reply, :ok, state}
  end

  def handle_call({:broadcast_from, from_pid, topic, message}, _from, state) do
    dispatch(state.subscribers[topic] || [], message, from_pid)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = Map.new(state.subscribers, fn {topic, pids} ->
      {topic, List.delete(pids, pid)}
    end)
    {:noreply, %{state | subscribers: subscribers}}
  end

  defp dispatch(pids, message, exclude_pid) do
    Enum.each(pids, fn pid ->
      if pid != exclude_pid, do: send(pid, message)
    end)
  end
end
```

---

## Real-World Examples

### 1. Real-Time Chat

```elixir
defmodule MyApp.Chat do
  @pubsub MyApp.PubSub

  def join_room(room_id, user) do
    OmPubSub.subscribe(@pubsub, room_topic(room_id))
    broadcast_presence(room_id, :user_joined, user)
  end

  def leave_room(room_id, user) do
    broadcast_presence(room_id, :user_left, user)
    OmPubSub.unsubscribe(@pubsub, room_topic(room_id))
  end

  def send_message(room_id, user, text) do
    message = %{
      id: Ecto.UUID.generate(),
      room_id: room_id,
      user_id: user.id,
      user_name: user.name,
      text: text,
      sent_at: DateTime.utc_now()
    }

    # Persist message
    {:ok, _} = Repo.insert(Message.changeset(%Message{}, message))

    # Broadcast to room
    OmPubSub.broadcast(@pubsub, room_topic(room_id), :new_message, message)

    {:ok, message}
  end

  def send_typing(room_id, user) do
    OmPubSub.broadcast_from(
      @pubsub,
      self(),
      room_topic(room_id),
      :user_typing,
      %{user_id: user.id, user_name: user.name}
    )
  end

  defp room_topic(room_id), do: "chat:room:#{room_id}"

  defp broadcast_presence(room_id, event, user) do
    OmPubSub.broadcast(@pubsub, room_topic(room_id), event, %{
      user_id: user.id,
      user_name: user.name
    })
  end
end
```

### 2. Live Notifications

```elixir
defmodule MyApp.LiveNotifications do
  @pubsub MyApp.PubSub

  # Subscribe in LiveView mount
  def subscribe(user_id) do
    OmPubSub.subscribe(@pubsub, "notifications:#{user_id}")
  end

  # Send notification from anywhere
  def push(user_id, type, data) do
    notification = %{
      id: Ecto.UUID.generate(),
      type: type,
      data: data,
      read: false,
      created_at: DateTime.utc_now()
    }

    # Persist notification
    {:ok, saved} = Notifications.create(user_id, notification)

    # Push to connected user
    OmPubSub.broadcast(
      @pubsub,
      "notifications:#{user_id}",
      :notification,
      saved
    )

    {:ok, saved}
  end

  # Notification types
  def push_mention(user_id, mentioner, context) do
    push(user_id, :mention, %{
      mentioner_id: mentioner.id,
      mentioner_name: mentioner.name,
      context: context
    })
  end

  def push_comment(user_id, comment) do
    push(user_id, :comment, %{
      comment_id: comment.id,
      post_id: comment.post_id,
      author_name: comment.author.name
    })
  end

  def push_system(user_id, message) do
    push(user_id, :system, %{message: message})
  end
end

# In LiveView
defmodule MyAppWeb.NotificationBellLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, %{"user_id" => user_id}, socket) do
    if connected?(socket) do
      MyApp.LiveNotifications.subscribe(user_id)
    end

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:notifications, fetch_recent(user_id))
     |> assign(:unread_count, count_unread(user_id))}
  end

  @impl true
  def handle_info({:notification, notification}, socket) do
    {:noreply,
     socket
     |> update(:notifications, &[notification | Enum.take(&1, 9)])
     |> update(:unread_count, &(&1 + 1))}
  end
end
```

### 3. Order Status Updates

```elixir
defmodule MyApp.OrderUpdates do
  @pubsub MyApp.PubSub

  # Customer subscribes to their order
  def subscribe_to_order(order_id) do
    OmPubSub.subscribe(@pubsub, "order:#{order_id}")
  end

  # Merchant subscribes to all their orders
  def subscribe_to_store(store_id) do
    OmPubSub.subscribe(@pubsub, "store:#{store_id}:orders")
  end

  # Update order status (broadcasts to both customer and store)
  def update_status(order, new_status, details \\ %{}) do
    with {:ok, order} <- Orders.update_status(order, new_status) do
      event_data = %{
        order_id: order.id,
        status: new_status,
        previous_status: order.status,
        updated_at: DateTime.utc_now(),
        details: details
      }

      # Notify customer
      OmPubSub.broadcast(@pubsub, "order:#{order.id}", :status_updated, event_data)

      # Notify store
      OmPubSub.broadcast(
        @pubsub,
        "store:#{order.store_id}:orders",
        :order_status_updated,
        event_data
      )

      {:ok, order}
    end
  end

  # Status-specific helpers
  def mark_confirmed(order) do
    update_status(order, :confirmed, %{confirmed_at: DateTime.utc_now()})
  end

  def mark_preparing(order, estimated_ready) do
    update_status(order, :preparing, %{estimated_ready: estimated_ready})
  end

  def mark_ready(order) do
    update_status(order, :ready, %{ready_at: DateTime.utc_now()})
  end

  def mark_delivered(order) do
    update_status(order, :delivered, %{delivered_at: DateTime.utc_now()})
  end
end
```

### 4. Live Dashboard Updates

```elixir
defmodule MyApp.DashboardUpdates do
  @pubsub MyApp.PubSub

  # Broadcast metric updates
  def push_metric(metric_name, value, metadata \\ %{}) do
    OmPubSub.broadcast(@pubsub, "dashboard:metrics", :metric_updated, %{
      metric: metric_name,
      value: value,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    })
  end

  # Periodic stats pusher
  def start_stats_broadcaster do
    Task.start(fn -> stats_loop() end)
  end

  defp stats_loop do
    push_metric(:active_users, count_active_users())
    push_metric(:orders_today, count_todays_orders())
    push_metric(:revenue_today, calculate_todays_revenue())
    push_metric(:avg_response_time, calculate_avg_response_time())

    Process.sleep(:timer.seconds(5))
    stats_loop()
  end

  # Alert broadcasts
  def push_alert(level, title, message) do
    OmPubSub.broadcast(@pubsub, "dashboard:alerts", :new_alert, %{
      level: level,
      title: title,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end
end

# Dashboard LiveView
defmodule MyAppWeb.AdminDashboardLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      OmPubSub.subscribe(MyApp.PubSub, "dashboard:metrics")
      OmPubSub.subscribe(MyApp.PubSub, "dashboard:alerts")
    end

    {:ok,
     socket
     |> assign(:metrics, %{})
     |> assign(:alerts, [])}
  end

  @impl true
  def handle_info({:metric_updated, data}, socket) do
    {:noreply, update(socket, :metrics, &Map.put(&1, data.metric, data))}
  end

  @impl true
  def handle_info({:new_alert, alert}, socket) do
    {:noreply, update(socket, :alerts, &[alert | Enum.take(&1, 9)])}
  end
end
```

### 5. Multi-Player Game State

```elixir
defmodule MyApp.GameRoom do
  @pubsub MyApp.PubSub

  def join(game_id, player) do
    OmPubSub.subscribe(@pubsub, game_topic(game_id))
    broadcast_event(game_id, :player_joined, %{player: player})
  end

  def leave(game_id, player) do
    broadcast_event(game_id, :player_left, %{player: player})
    OmPubSub.unsubscribe(@pubsub, game_topic(game_id))
  end

  def move(game_id, player, move) do
    with {:ok, new_state} <- GameEngine.apply_move(game_id, player, move) do
      broadcast_event(game_id, :move_made, %{
        player: player,
        move: move,
        game_state: new_state
      })

      if new_state.finished do
        broadcast_event(game_id, :game_ended, %{
          winner: new_state.winner,
          final_state: new_state
        })
      end

      {:ok, new_state}
    end
  end

  def send_chat(game_id, player, message) do
    broadcast_event(game_id, :chat_message, %{
      player: player,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp game_topic(game_id), do: "game:#{game_id}"

  defp broadcast_event(game_id, event, data) do
    OmPubSub.broadcast(@pubsub, game_topic(game_id), event, data)
  end
end
```

### 6. Background Job Progress

```elixir
defmodule MyApp.JobProgress do
  @pubsub MyApp.PubSub

  # Subscribe to job progress (e.g., in LiveView)
  def subscribe(job_id) do
    OmPubSub.subscribe(@pubsub, "job:#{job_id}")
  end

  # Report progress from Oban worker
  def report_progress(job_id, current, total, message \\ nil) do
    OmPubSub.broadcast(@pubsub, "job:#{job_id}", :progress, %{
      current: current,
      total: total,
      percent: round(current / total * 100),
      message: message
    })
  end

  def report_started(job_id, total) do
    OmPubSub.broadcast(@pubsub, "job:#{job_id}", :started, %{
      total: total,
      started_at: DateTime.utc_now()
    })
  end

  def report_completed(job_id, result) do
    OmPubSub.broadcast(@pubsub, "job:#{job_id}", :completed, %{
      result: result,
      completed_at: DateTime.utc_now()
    })
  end

  def report_failed(job_id, error) do
    OmPubSub.broadcast(@pubsub, "job:#{job_id}", :failed, %{
      error: error,
      failed_at: DateTime.utc_now()
    })
  end
end

# Oban Worker
defmodule MyApp.Workers.ExportWorker do
  use Oban.Worker

  alias MyApp.JobProgress

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"user_id" => user_id}}) do
    records = fetch_records(user_id)
    total = length(records)

    JobProgress.report_started(job_id, total)

    result =
      records
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {record, index}, {:ok, acc} ->
        JobProgress.report_progress(job_id, index, total, "Processing #{record.name}")

        case process_record(record) do
          {:ok, processed} -> {:cont, {:ok, [processed | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, data} ->
        file_url = upload_export(data)
        JobProgress.report_completed(job_id, %{file_url: file_url})
        :ok

      {:error, reason} ->
        JobProgress.report_failed(job_id, reason)
        {:error, reason}
    end
  end
end
```

---

## Best Practices

### 1. Use Consistent Topic Naming

```elixir
# GOOD: Consistent, hierarchical naming
"user:#{user_id}"
"room:#{room_id}:messages"
"order:#{order_id}:status"

# BAD: Inconsistent naming
"users/#{user_id}"
"ROOM-#{room_id}"
"order_status_#{order_id}"
```

### 2. Use Event Tuples for Type Safety

```elixir
# GOOD: Structured event tuples
OmPubSub.broadcast(pubsub, topic, :order_created, order)
OmPubSub.broadcast(pubsub, topic, :order_shipped, shipment)

# Handler with pattern matching
def handle_info({:order_created, order}, state), do: ...
def handle_info({:order_shipped, shipment}, state), do: ...

# BAD: Magic strings or atoms
OmPubSub.broadcast_raw(pubsub, topic, %{type: "order_created", ...})
```

### 3. Subscribe After Connected Check

```elixir
# GOOD: Only subscribe when socket is connected
def mount(_params, _session, socket) do
  if connected?(socket) do
    OmPubSub.subscribe(MyApp.PubSub, "topic")
  end
  {:ok, socket}
end

# BAD: Subscribe before checking connection
def mount(_params, _session, socket) do
  OmPubSub.subscribe(MyApp.PubSub, "topic")  # May run on dead view
  {:ok, socket}
end
```

### 4. Unsubscribe on Cleanup

```elixir
# GOOD: Clean up subscriptions in GenServer
def terminate(_reason, state) do
  OmPubSub.unsubscribe(MyApp.PubSub, "user:#{state.user_id}")
  :ok
end

# In Phoenix Channels
def terminate(_reason, socket) do
  OmPubSub.unsubscribe(MyApp.PubSub, "room:#{socket.assigns.room_id}:internal")
  :ok
end
```

### 5. Handle Unknown Messages

```elixir
# GOOD: Catch-all clause for unexpected messages
def handle_info({event, _payload}, state) do
  Logger.debug("Unhandled PubSub event: #{inspect(event)}")
  {:noreply, state}
end

def handle_info(msg, state) do
  Logger.warning("Unexpected message: #{inspect(msg)}")
  {:noreply, state}
end
```

### 6. Monitor Redis in Production

```elixir
# GOOD: Set up monitoring on app start
def start(_type, _args) do
  # Attach Redis monitoring before starting PubSub
  OmPubSub.Telemetry.attach_redis_monitor(:redis_monitor,
    on_disconnect: &MyApp.Alerts.redis_down/1,
    on_connect: &MyApp.Alerts.redis_up/1
  )

  children = [
    {OmPubSub, name: MyApp.PubSub},
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 7. Use Fallback Chain for Resilience

```elixir
# GOOD: Configure fallback for graceful degradation
{OmPubSub,
 name: MyApp.PubSub,
 fallback_chain: [:redis, :postgres, :local],
 repo: MyApp.Repo}

# App continues working even if Redis is down
# (falls back to Postgres or local)
```

---

## Testing

### Test Helpers

```elixir
defmodule MyApp.PubSubCase do
  use ExUnit.CaseTemplate

  setup do
    # Use local adapter for tests
    start_supervised!({OmPubSub, name: MyApp.TestPubSub, adapter: :local})
    :ok
  end
end
```

### Testing Subscriptions

```elixir
defmodule MyApp.ChatTest do
  use MyApp.PubSubCase

  test "broadcasting messages to subscribers" do
    # Subscribe this test process
    OmPubSub.subscribe(MyApp.TestPubSub, "test:room")

    # Broadcast a message
    OmPubSub.broadcast(MyApp.TestPubSub, "test:room", :message, "Hello")

    # Assert we received it
    assert_receive {:message, "Hello"}
  end

  test "broadcast_from excludes sender" do
    OmPubSub.subscribe(MyApp.TestPubSub, "test:room")

    # Broadcast from self - should NOT receive
    OmPubSub.broadcast_from(MyApp.TestPubSub, self(), "test:room", :typing, %{})

    refute_receive {:typing, _}
  end

  test "multiple subscribers receive messages" do
    parent = self()

    # Spawn subscriber processes
    for i <- 1..3 do
      spawn(fn ->
        OmPubSub.subscribe(MyApp.TestPubSub, "test:room")
        receive do
          {:message, text} -> send(parent, {:received, i, text})
        end
      end)
    end

    # Give time to subscribe
    Process.sleep(50)

    # Broadcast
    OmPubSub.broadcast(MyApp.TestPubSub, "test:room", :message, "Hello all")

    # All should receive
    assert_receive {:received, 1, "Hello all"}
    assert_receive {:received, 2, "Hello all"}
    assert_receive {:received, 3, "Hello all"}
  end
end
```

### Testing with Mox

```elixir
# Define mock behaviour
Mox.defmock(MyApp.MockPubSub, for: OmPubSub.Adapter)

# In tests
test "service broadcasts on update" do
  expect(MyApp.MockPubSub, :broadcast, fn _server, topic, message ->
    assert topic == "order:123"
    assert message == {:status_updated, %{status: :shipped}}
    :ok
  end)

  Orders.update_status("123", :shipped)
end
```

---

## Configuration Reference

### Startup Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | atom | required | Name for this PubSub instance |
| `adapter` | atom | `:auto` | Adapter: `:redis`, `:postgres`, `:local`, `:auto` |
| `fallback_chain` | list | `[:redis, :local]` | Adapters to try in order |
| `repo` | module | nil | Ecto repo for Postgres adapter |
| `conn_opts` | keyword | `[]` | Direct Postgrex connection opts |
| `redis_host` | string | `"localhost"` | Redis host |
| `redis_port` | integer | `6379` | Redis port |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `PUBSUB_ADAPTER` | Force adapter: `"redis"`, `"postgres"`, `"local"` |
| `REDIS_HOST` | Redis host (default: `"localhost"`) |
| `REDIS_PORT` | Redis port (default: `6379`) |

### Full Configuration Example

```elixir
# config/prod.exs
config :my_app,
  pubsub_config: [
    name: MyApp.PubSub,
    adapter: :auto,
    fallback_chain: [:redis, :postgres, :local],
    repo: MyApp.Repo,
    redis_host: System.get_env("REDIS_HOST", "localhost"),
    redis_port: String.to_integer(System.get_env("REDIS_PORT", "6379"))
  ]

# application.ex
def start(_type, _args) do
  pubsub_config = Application.get_env(:my_app, :pubsub_config)

  children = [
    {OmPubSub, pubsub_config},
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

---

## Resilience Notes

- **Redis auto-reconnects**: Redix handles reconnection automatically
- **No dynamic failover**: Adapter is set at startup, won't switch mid-run
- **Postgres limitations**: 8KB payload max, same-database only
- **Local is single-node**: Use for development or single-instance deployments
- **Recommendation**: Use `attach_redis_monitor/2` for alerting, not automatic failover

---

## License

MIT
