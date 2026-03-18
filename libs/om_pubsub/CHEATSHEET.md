# OmPubSub Cheatsheet

> Phoenix.PubSub wrapper with multiple adapters and auto fallback. For full docs, see `README.md`.

## Setup

```elixir
# Supervision tree
children = [{OmPubSub, name: MyApp.PubSub}]
```

---

## Core API

```elixir
# Subscribe
OmPubSub.subscribe(MyApp.PubSub, "room:123")

# Broadcast
OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hello!"})

# Broadcast from (excludes sender)
OmPubSub.broadcast_from(MyApp.PubSub, self(), "room:123", :typing, %{user: "Alice"})

# Unsubscribe
OmPubSub.unsubscribe(MyApp.PubSub, "room:123")
```

---

## Receiving Messages

```elixir
# In GenServer / LiveView
def handle_info({:new_message, payload}, state) do
  IO.inspect(payload)
  {:noreply, state}
end
```

---

## Adapters

| Adapter | Use Case | Multi-Node |
|---------|----------|------------|
| `:local` (default) | Development, single node | No |
| `:redis` | Production, multi-node | Yes |
| `:postgres` | When Redis unavailable | Yes |

```elixir
# Redis adapter
{OmPubSub, name: MyApp.PubSub, adapter: :redis, redis_url: "redis://localhost:6379"}

# PostgreSQL adapter
{OmPubSub, name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo}

# Auto fallback (try Redis, fall back to local)
{OmPubSub, name: MyApp.PubSub, adapter: :auto}
```

---

## Introspection

```elixir
OmPubSub.adapter(MyApp.PubSub)                    #=> :redis
```
