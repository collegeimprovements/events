# OmCache

Nebulex cache wrapper with adapter selection, key generation, and graceful degradation.

## Features

- **Adapter auto-selection**: Redis, local, or null based on environment
- **Key generation**: Customizable key generation strategies
- **Configuration helpers**: Build config from environment variables
- **Telemetry integration**: Built-in telemetry events for monitoring

## Installation

```elixir
def deps do
  [
    {:om_cache, path: "../om_cache"}
  ]
end
```

## Quick Start

### 1. Define Your Cache Module

```elixir
defmodule MyApp.Cache do
  use OmCache,
    otp_app: :my_app,
    default_adapter: :redis
end
```

### 2. Configure in runtime.exs

```elixir
config :my_app, MyApp.Cache, OmCache.Config.build()
```

### 3. Add to Supervision Tree

```elixir
children = [
  MyApp.Cache,
  # ...
]
```

### 4. Use the Cache

```elixir
MyApp.Cache.put({User, 123}, user_struct)
MyApp.Cache.get({User, 123})
MyApp.Cache.delete({User, 123})

# With TTL
MyApp.Cache.put({User, 123}, user, ttl: :timer.minutes(30))
```

## Adapter Selection

Set the `CACHE_ADAPTER` environment variable:

```bash
# Redis cache (default)
CACHE_ADAPTER=redis mix phx.server

# Local in-memory cache (single node)
CACHE_ADAPTER=local mix phx.server

# Distributed cache across Erlang cluster (sharded)
CACHE_ADAPTER=partitioned mix phx.server

# Distributed cache across Erlang cluster (replicated)
CACHE_ADAPTER=replicated mix phx.server

# Disable caching (no-op)
CACHE_ADAPTER=null mix phx.server
```

### Distributed Caching (without Redis)

When Redis is unavailable but you need distributed caching across an Erlang cluster:

| Adapter | Description | Best For |
|---------|-------------|----------|
| `partitioned` | Shards data across nodes using consistent hashing | Large datasets, write-heavy |
| `replicated` | Copies all data to every node | Small datasets, read-heavy |

**Note**: Both require Erlang clustering to be configured (e.g., via `libcluster`).

## Configuration Options

```elixir
# Custom environment variables
OmCache.Config.build(
  adapter_env: "MY_CACHE_ADAPTER",
  redis_host_env: "MY_REDIS_HOST",
  redis_port_env: "MY_REDIS_PORT",
  default_adapter: :local
)

# Custom local adapter options
OmCache.Config.build(
  default_adapter: :local,
  local_opts: [max_size: 500_000, gc_interval: :timer.hours(6)]
)

# Custom partitioned adapter options
OmCache.Config.build(
  default_adapter: :partitioned,
  partitioned_opts: [primary_storage_adapter: Nebulex.Adapters.Local]
)

# Custom replicated adapter options
OmCache.Config.build(
  default_adapter: :replicated,
  replicated_opts: [primary_storage_adapter: Nebulex.Adapters.Local]
)
```

## Custom Key Generator

```elixir
defmodule MyApp.CustomKeyGenerator do
  @behaviour OmCache.KeyGenerator

  @impl true
  def generate(mod, fun, args) do
    {mod, fun, :erlang.phash2(args)}
  end
end

defmodule MyApp.Cache do
  use OmCache,
    otp_app: :my_app,
    key_generator: MyApp.CustomKeyGenerator
end
```

## Telemetry

Attach a logger for cache operations:

```elixir
OmCache.Telemetry.attach_logger(:my_cache_logger, level: :info)
```

Or attach custom handlers:

```elixir
:telemetry.attach(
  "cache-metrics",
  [:nebulex, :cache, :command, :stop],
  &MyApp.Metrics.handle_cache_event/4,
  nil
)
```

## With Decorators

Use with `FnDecorator.Caching`:

```elixir
defmodule MyApp.Users do
  use FnDecorator

  @decorate cacheable(cache: MyApp.Cache, key: {User, id})
  def get_user(id), do: Repo.get(User, id)

  @decorate cache_evict(cache: MyApp.Cache, key: {User, id})
  def delete_user(id), do: Repo.delete(id)
end
```

## License

MIT
