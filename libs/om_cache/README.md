# OmCache

Nebulex cache wrapper with adapter selection, key generation, and graceful degradation.

## Installation

```elixir
def deps do
  [
    {:om_cache, "~> 0.1.0"},
    {:nebulex, "~> 2.5"},
    {:nebulex_redis_adapter, "~> 2.3"}  # Optional: for Redis
  ]
end
```

## Why OmCache?

```
Raw Nebulex approach:                   With OmCache:
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│ defmodule MyApp.Cache do         │   │ defmodule MyApp.Cache do         │
│   use Nebulex.Cache,             │   │   use OmCache,                   │
│     otp_app: :my_app,            │   │     otp_app: :my_app             │
│     adapter: NebulexRedisAdapter │   │ end                              │
│ end                              │   │                                  │
│                                  │   │ # config/runtime.exs             │
│ # Different adapters = rewrite   │   │ config :my_app, MyApp.Cache,     │
│ # No environment variable switch │   │   OmCache.Config.build()         │
│ # Manual Redis config            │   │                                  │
│ # No graceful degradation        │   │ # CACHE_ADAPTER=redis (default)  │
│                                  │   │ # CACHE_ADAPTER=local            │
│ # config/config.exs              │   │ # CACHE_ADAPTER=partitioned      │
│ config :my_app, MyApp.Cache,     │   │ # CACHE_ADAPTER=null (testing)   │
│   conn_opts: [                   │   │                                  │
│     host: System.get_env("X"),   │   │ # Automatic Redis config         │
│     port: ...                    │   │ # Key generation helpers         │
│   ]                              │   │ # Telemetry integration          │
│ # Repeated boilerplate           │   │ # Decorator integration          │
└──────────────────────────────────┘   └──────────────────────────────────┘
```

---

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
# config/runtime.exs
config :my_app, MyApp.Cache, OmCache.Config.build()
```

### 3. Add to Supervision Tree

```elixir
# application.ex
def start(_type, _args) do
  children = [
    MyApp.Cache,
    # ...other children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 4. Use the Cache

```elixir
# Basic operations
MyApp.Cache.put({User, 123}, user_struct)
MyApp.Cache.get({User, 123})
#=> %User{id: 123, ...}

MyApp.Cache.delete({User, 123})

# With TTL
MyApp.Cache.put({User, 123}, user, ttl: :timer.minutes(30))

# Get or compute
MyApp.Cache.get_or_put({User, 123}, fn -> Repo.get(User, 123) end)
```

---

## Adapter Selection

Switch adapters via environment variable:

```bash
# Redis cache (default) - Production
CACHE_ADAPTER=redis mix phx.server

# Local in-memory cache - Development/single node
CACHE_ADAPTER=local mix phx.server

# Distributed cache - Sharded across Erlang cluster
CACHE_ADAPTER=partitioned mix phx.server

# Distributed cache - Replicated to all nodes
CACHE_ADAPTER=replicated mix phx.server

# Disable caching (no-op) - Testing
CACHE_ADAPTER=null mix phx.server
```

### Adapter Comparison

| Adapter | Backend | Distribution | Use Case |
|---------|---------|--------------|----------|
| `redis` | Redis | Centralized | Production, shared state |
| `local` | ETS | Single node | Development, single instance |
| `partitioned` | ETS + Erlang | Sharded | Multi-node, large datasets |
| `replicated` | ETS + Erlang | Full copy | Multi-node, read-heavy |
| `null` | None | N/A | Testing, cache disabled |

### When to Use Each Adapter

```elixir
# Redis: Shared state, persistence, production
# - Cache survives restarts
# - Shared across all nodes
# - Requires Redis infrastructure
CACHE_ADAPTER=redis

# Local: Simple, fast, no dependencies
# - Development environment
# - Single-node deployments
# - Testing with real cache behavior
CACHE_ADAPTER=local

# Partitioned: Distributed without Redis
# - Large datasets
# - Write-heavy workloads
# - Each key lives on one node (consistent hashing)
# - Requires Erlang clustering (libcluster)
CACHE_ADAPTER=partitioned

# Replicated: All nodes have all data
# - Small datasets
# - Read-heavy workloads
# - Every node has full copy
# - Requires Erlang clustering
CACHE_ADAPTER=replicated

# Null: Disable caching entirely
# - Unit tests
# - Integration tests
# - Debugging cache issues
CACHE_ADAPTER=null
```

---

## Key Design

Use tuples for namespaced, structured keys:

### Basic Patterns

```elixir
# Entity by ID
{User, 123}
{Order, "ord_abc123"}
{Product, product_id}

# Entity by alternate key
{User, :email, "user@example.com"}
{User, :username, "johndoe"}
{Product, :sku, "SKU-12345"}

# Namespaced data
{:session, session_id}
{:token, refresh_token}
{:config, :feature_flags}
{:rate_limit, user_id, :api_calls}
```

### Hierarchical Keys

```elixir
# Multi-level hierarchy
{:tenant, tenant_id, User, user_id}
{:org, org_id, :settings}
{:user, user_id, :preferences, :notifications}

# Lists and collections
{:user, user_id, :orders}
{:product, product_id, :reviews}
```

### Computed Keys

```elixir
# Search results
{:search, :products, query_hash}
{:search, :users, %{role: "admin", status: "active"} |> :erlang.phash2()}

# Aggregations
{:stats, :daily, Date.utc_today()}
{:report, :monthly, year, month}

# API responses
{:api, :weather, city_id, Date.utc_today()}
{:api, :exchange_rate, "USD", "EUR"}
```

---

## TTL (Time To Live)

Set expiration on cache entries:

```elixir
# Fixed TTL
MyApp.Cache.put(key, value, ttl: :timer.minutes(5))
MyApp.Cache.put(key, value, ttl: :timer.hours(1))
MyApp.Cache.put(key, value, ttl: :timer.days(7))

# Dynamic TTL based on content
ttl = if user.premium?, do: :timer.hours(24), else: :timer.hours(1)
MyApp.Cache.put({User, user.id}, user, ttl: ttl)

# Get remaining TTL
MyApp.Cache.ttl({User, 123})
#=> 1_800_000  # 30 minutes remaining in ms

# Infinite TTL (no expiration)
MyApp.Cache.put(key, value)  # No ttl option = never expires
```

### TTL Strategies

```elixir
# Session data - moderate TTL
MyApp.Cache.put({:session, session_id}, session_data, ttl: :timer.hours(4))

# Feature flags - short TTL for quick updates
MyApp.Cache.put({:config, :feature_flags}, flags, ttl: :timer.minutes(5))

# Expensive computations - longer TTL
MyApp.Cache.put({:report, :daily, date}, report, ttl: :timer.hours(24))

# Static data - very long TTL
MyApp.Cache.put({:config, :countries}, countries, ttl: :timer.days(30))
```

---

## Cache Operations

Full Nebulex API available:

### Basic Operations

```elixir
# Put/Get/Delete
MyApp.Cache.put(key, value)
MyApp.Cache.get(key)
MyApp.Cache.delete(key)

# Get with default
MyApp.Cache.get(key, default: %{})

# Check existence
MyApp.Cache.has_key?(key)

# Get or compute (cache-aside pattern)
MyApp.Cache.get_or_put(key, fn -> compute_value() end)
MyApp.Cache.get_or_put(key, fn -> compute_value() end, ttl: :timer.minutes(30))

# Touch (reset TTL without changing value)
MyApp.Cache.touch(key)
```

### Bulk Operations

```elixir
# Put multiple
MyApp.Cache.put_all([{key1, val1}, {key2, val2}, {key3, val3}])

# Get multiple
MyApp.Cache.get_all([key1, key2, key3])
#=> %{key1 => val1, key2 => val2, key3 => nil}

# Delete multiple
MyApp.Cache.delete_all([key1, key2, key3])
```

### Atomic Operations

```elixir
# Increment/decrement counters
MyApp.Cache.incr(:page_views)
MyApp.Cache.incr({:user, user_id, :login_count}, 1)
MyApp.Cache.decr({:product, product_id, :stock}, 1)

# Update with function
MyApp.Cache.update(key, initial, fn existing ->
  %{existing | count: existing.count + 1}
end)
```

### Cache Management

```elixir
# Clear all entries
MyApp.Cache.delete_all()

# Get cache size
MyApp.Cache.count_all()

# Get stats (if enabled)
MyApp.Cache.stats()
#=> %{
#     hits: 1234,
#     misses: 56,
#     writes: 789,
#     evictions: 12
#   }
```

---

## Custom Key Generator

Implement the `OmCache.KeyGenerator` behaviour for custom key generation:

### Default Behavior

```elixir
# No arguments -> 0
OmCache.KeyGenerator.generate(Mod, :func, [])
#=> 0

# Single argument -> use as key
OmCache.KeyGenerator.generate(Mod, :func, [123])
#=> 123

# Multiple arguments -> hash
OmCache.KeyGenerator.generate(Mod, :func, [1, 2, 3])
#=> :erlang.phash2([1, 2, 3])
```

### Custom Implementation

```elixir
defmodule MyApp.CustomKeyGenerator do
  @behaviour OmCache.KeyGenerator

  @impl true
  def generate(mod, fun, args) do
    # Include module and function for namespacing
    {mod, fun, :erlang.phash2(args)}
  end
end

defmodule MyApp.Cache do
  use OmCache,
    otp_app: :my_app,
    key_generator: MyApp.CustomKeyGenerator
end
```

### Prefixed Key Generator

```elixir
defmodule MyApp.PrefixedKeyGenerator do
  @behaviour OmCache.KeyGenerator

  @impl true
  def generate(mod, fun, args) do
    # Add environment prefix for isolation
    env = Application.get_env(:my_app, :environment, :dev)
    {env, mod, fun, :erlang.phash2(args)}
  end
end
```

### Tenant-Aware Key Generator

```elixir
defmodule MyApp.TenantKeyGenerator do
  @behaviour OmCache.KeyGenerator

  @impl true
  def generate(mod, fun, args) do
    # Get tenant from process dictionary
    tenant_id = Process.get(:current_tenant_id)
    {:tenant, tenant_id, mod, fun, :erlang.phash2(args)}
  end
end
```

---

## Configuration

### Environment-Based Configuration

```elixir
# config/runtime.exs
config :my_app, MyApp.Cache, OmCache.Config.build()
```

### Custom Environment Variables

```elixir
OmCache.Config.build(
  adapter_env: "MY_CACHE_ADAPTER",      # Default: "CACHE_ADAPTER"
  redis_host_env: "MY_REDIS_HOST",      # Default: "REDIS_HOST"
  redis_port_env: "MY_REDIS_PORT",      # Default: "REDIS_PORT"
  default_adapter: :local               # Default: :redis
)
```

### Adapter-Specific Options

```elixir
# Local adapter options
OmCache.Config.build(
  default_adapter: :local,
  local_opts: [
    max_size: 500_000,
    gc_interval: :timer.hours(6),
    allocated_memory: 1_000_000_000
  ]
)

# Redis adapter options
OmCache.Config.build(
  default_adapter: :redis,
  redis_opts: [
    pool_size: 10,
    ssl: true,
    socket_opts: [:inet6]
  ]
)

# Partitioned adapter options
OmCache.Config.build(
  default_adapter: :partitioned,
  partitioned_opts: [
    primary_storage_adapter: Nebulex.Adapters.Local,
    keyslot: MyApp.CustomKeyslot
  ]
)

# Replicated adapter options
OmCache.Config.build(
  default_adapter: :replicated,
  replicated_opts: [
    primary_storage_adapter: Nebulex.Adapters.Local
  ]
)
```

### Direct Configuration

```elixir
# Full manual config
config :my_app, MyApp.Cache,
  adapter: NebulexRedisAdapter,
  conn_opts: [
    host: "redis.example.com",
    port: 6380,
    password: System.get_env("REDIS_PASSWORD"),
    ssl: true
  ],
  pool_size: 20
```

---

## Telemetry Integration

OmCache provides telemetry helpers:

### Attach Logger

```elixir
# In application.ex or startup
OmCache.Telemetry.attach_logger(:my_cache_logger)

# With options
OmCache.Telemetry.attach_logger(:my_cache_logger,
  level: :info,
  log_args: true  # Log cache keys (careful with sensitive data)
)
```

### Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:nebulex, :cache, :command, :start]` | `%{system_time: t}` | `%{cache, command, args}` |
| `[:nebulex, :cache, :command, :stop]` | `%{duration: ns}` | `%{cache, command, result}` |
| `[:nebulex, :cache, :command, :exception]` | `%{duration: ns}` | `%{cache, command, kind, reason}` |

### Custom Handlers

```elixir
defmodule MyApp.CacheMetrics do
  require Logger

  def handle_event([:nebulex, :cache, :command, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Track in your metrics system
    :telemetry.execute(
      [:my_app, :cache, metadata.command],
      %{duration: duration_ms},
      %{cache: metadata.cache}
    )

    # Log slow operations
    if duration_ms > 100 do
      Logger.warning("Slow cache operation: #{metadata.command} took #{duration_ms}ms")
    end
  end

  def handle_event([:nebulex, :cache, :command, :exception], _measurements, metadata, _config) do
    Logger.error("Cache error: #{metadata.command} failed with #{inspect(metadata.reason)}")

    # Report to error tracking
    Sentry.capture_message("Cache operation failed",
      extra: %{command: metadata.command, reason: metadata.reason}
    )
  end
end

# Attach handler
:telemetry.attach_many(
  "cache-metrics",
  [
    [:nebulex, :cache, :command, :stop],
    [:nebulex, :cache, :command, :exception]
  ],
  &MyApp.CacheMetrics.handle_event/4,
  nil
)
```

### Stats Collection

```elixir
defmodule MyApp.CacheStats do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :telemetry.attach_many(
      "cache-stats",
      [
        [:nebulex, :cache, :command, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, state}
  end

  def handle_event([:nebulex, :cache, :command, :stop], _measurements, metadata, _config) do
    command = metadata.command
    hit? = metadata.result != nil

    case command do
      :get -> if hit?, do: :ets.update_counter(:cache_stats, :hits, 1, {:hits, 0}),
                    else: :ets.update_counter(:cache_stats, :misses, 1, {:misses, 0})
      :put -> :ets.update_counter(:cache_stats, :writes, 1, {:writes, 0})
      _ -> :ok
    end
  end
end
```

---

## Decorator Integration

Use with `FnDecorator.Caching` for function-level caching:

### Basic Usage

```elixir
defmodule MyApp.Users do
  use FnDecorator

  @decorate cacheable(cache: MyApp.Cache, key: {User, id}, ttl: :timer.minutes(30))
  def get_user(id) do
    Repo.get(User, id)
  end

  @decorate cache_evict(cache: MyApp.Cache, key: {User, id})
  def update_user(id, attrs) do
    User
    |> Repo.get!(id)
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @decorate cache_evict(cache: MyApp.Cache, key: {User, id})
  def delete_user(id) do
    User
    |> Repo.get!(id)
    |> Repo.delete()
  end
end
```

### With Presets

```elixir
defmodule MyApp.Products do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  # High availability for product reads
  @decorate cacheable(Presets.high_availability(
    cache: MyApp.Cache,
    key: {Product, id}
  ))
  def get_product(id), do: Repo.get(Product, id)

  # External API with stale-while-revalidate
  @decorate cacheable(Presets.external_api(
    cache: MyApp.Cache,
    key: {:inventory, product_id}
  ))
  def get_inventory(product_id) do
    InventoryService.fetch(product_id)
  end

  # Expensive computation
  @decorate cacheable(Presets.expensive(
    cache: MyApp.Cache,
    key: {:report, :sales, date}
  ))
  def generate_sales_report(date) do
    Reports.generate_sales(date)
  end
end
```

### Cache-Aside Pattern

```elixir
defmodule MyApp.Sessions do
  use FnDecorator

  @decorate cacheable(
    cache: MyApp.Cache,
    key: {:session, session_id},
    ttl: :timer.hours(4),
    only_if: &match?({:ok, _}, &1)  # Only cache successful results
  )
  def get_session(session_id) do
    case Repo.get_by(Session, id: session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @decorate cache_put(cache: MyApp.Cache, key: {:session, session.id})
  def refresh_session(session) do
    {:ok, %{session | last_activity: DateTime.utc_now()}}
  end
end
```

---

## Real-World Examples

### 1. User Session Cache

```elixir
defmodule MyApp.SessionCache do
  alias MyApp.Cache

  @session_ttl :timer.hours(4)

  def get(session_id) do
    Cache.get({:session, session_id})
  end

  def put(session_id, session_data) do
    Cache.put({:session, session_id}, session_data, ttl: @session_ttl)
  end

  def refresh(session_id) do
    Cache.touch({:session, session_id})
  end

  def delete(session_id) do
    Cache.delete({:session, session_id})
  end

  def active_count do
    # Count sessions with pattern (if using Redis)
    Cache.count_all()
  end
end
```

### 2. Multi-Level Caching

```elixir
defmodule MyApp.Products do
  alias MyApp.{Cache, Repo}

  @short_ttl :timer.minutes(5)
  @long_ttl :timer.hours(1)

  def get(id) do
    # Try L1 cache first (local, fast)
    case Process.get({:product_cache, id}) do
      nil ->
        # Try L2 cache (distributed)
        case Cache.get({Product, id}) do
          nil ->
            # Cache miss - fetch from DB
            product = Repo.get(Product, id)

            if product do
              Cache.put({Product, id}, product, ttl: @long_ttl)
              Process.put({:product_cache, id}, {product, System.monotonic_time()})
            end

            product

          product ->
            # Update L1 cache
            Process.put({:product_cache, id}, {product, System.monotonic_time()})
            product
        end

      {product, cached_at} ->
        # Check L1 TTL
        if System.monotonic_time() - cached_at > :timer.minutes(1) do
          Process.delete({:product_cache, id})
          get(id)  # Refresh from L2
        else
          product
        end
    end
  end
end
```

### 3. Rate Limiting

```elixir
defmodule MyApp.RateLimiter do
  alias MyApp.Cache

  @window_seconds 60
  @max_requests 100

  def check(user_id, action) do
    key = {:rate_limit, user_id, action, current_window()}

    case Cache.incr(key) do
      1 ->
        # First request in window - set TTL
        Cache.touch(key)
        Cache.put(key, 1, ttl: :timer.seconds(@window_seconds))
        :ok

      count when count <= @max_requests ->
        :ok

      _count ->
        {:error, :rate_limited}
    end
  end

  defp current_window do
    div(System.system_time(:second), @window_seconds)
  end
end
```

### 4. Feature Flags

```elixir
defmodule MyApp.FeatureFlags do
  alias MyApp.{Cache, Repo}

  @ttl :timer.minutes(5)

  def enabled?(flag_name, context \\ %{}) do
    flags = get_all_flags()
    evaluate(flags[flag_name], context)
  end

  defp get_all_flags do
    Cache.get_or_put({:config, :feature_flags}, fn ->
      Repo.all(FeatureFlag)
      |> Map.new(&{&1.name, &1})
    end, ttl: @ttl)
  end

  defp evaluate(nil, _context), do: false
  defp evaluate(%{enabled: false}, _context), do: false
  defp evaluate(%{percentage: p}, _context) when p == 100, do: true
  defp evaluate(%{percentage: p}, %{user_id: uid}) do
    :erlang.phash2(uid, 100) < p
  end
  defp evaluate(%{enabled: true}, _context), do: true

  def invalidate do
    Cache.delete({:config, :feature_flags})
  end
end
```

### 5. API Response Caching

```elixir
defmodule MyApp.WeatherCache do
  alias MyApp.{Cache, WeatherAPI}

  @ttl :timer.minutes(15)
  @stale_ttl :timer.hours(4)

  def get_weather(city) do
    key = {:weather, city |> String.downcase() |> String.trim()}

    case Cache.get(key) do
      nil ->
        fetch_and_cache(key, city)

      %{fetched_at: fetched_at} = cached when is_stale?(fetched_at) ->
        # Serve stale data while refreshing in background
        Task.start(fn -> fetch_and_cache(key, city) end)
        {:ok, cached}

      cached ->
        {:ok, cached}
    end
  end

  defp fetch_and_cache(key, city) do
    case WeatherAPI.fetch(city) do
      {:ok, data} ->
        enriched = Map.put(data, :fetched_at, DateTime.utc_now())
        Cache.put(key, enriched, ttl: @stale_ttl)
        {:ok, enriched}

      {:error, _} = error ->
        error
    end
  end

  defp is_stale?(fetched_at) do
    DateTime.diff(DateTime.utc_now(), fetched_at, :millisecond) > @ttl
  end
end
```

### 6. Database Query Caching

```elixir
defmodule MyApp.Queries do
  use FnDecorator
  alias MyApp.{Cache, Repo}
  import Ecto.Query

  @decorate cacheable(
    cache: Cache,
    key: {:users, :active_count},
    ttl: :timer.minutes(5)
  )
  def count_active_users do
    User
    |> where([u], u.active == true)
    |> Repo.aggregate(:count)
  end

  @decorate cacheable(
    cache: Cache,
    key: {:top_products, category_id, limit},
    ttl: :timer.hours(1)
  )
  def top_products(category_id, limit \\ 10) do
    Product
    |> where([p], p.category_id == ^category_id)
    |> order_by([p], desc: p.sales_count)
    |> limit(^limit)
    |> Repo.all()
  end

  def invalidate_product_cache(category_id) do
    # Invalidate all limits for this category
    Enum.each([5, 10, 20, 50], fn limit ->
      Cache.delete({:top_products, category_id, limit})
    end)
  end
end
```

---

## Best Practices

### 1. Use Structured Keys

```elixir
# Good: Structured, readable, predictable
{User, 123}
{:session, session_id}
{Order, order_id, :items}

# Bad: String concatenation, hard to debug
"user_123"
"session:#{session_id}"
"order:#{order_id}:items"
```

### 2. Set Appropriate TTLs

```elixir
# Good: TTL based on data volatility
Cache.put({:config, :settings}, settings, ttl: :timer.hours(24))  # Rarely changes
Cache.put({User, id}, user, ttl: :timer.minutes(15))              # Changes occasionally
Cache.put({:api, :weather}, weather, ttl: :timer.minutes(5))      # Changes frequently

# Bad: No TTL or very long TTL for volatile data
Cache.put({User, id}, user)  # Never expires - stale data risk!
```

### 3. Handle Cache Misses Gracefully

```elixir
# Good: Fallback on cache miss
def get_user(id) do
  case Cache.get({User, id}) do
    nil -> fetch_and_cache(id)
    user -> {:ok, user}
  end
end

defp fetch_and_cache(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user ->
      Cache.put({User, id}, user, ttl: :timer.minutes(30))
      {:ok, user}
  end
end

# Bad: Assume cache always has data
def get_user(id) do
  Cache.get({User, id})  # Returns nil on miss!
end
```

### 4. Invalidate on Writes

```elixir
# Good: Explicit invalidation on mutations
def update_user(user, attrs) do
  with {:ok, updated} <- Repo.update(User.changeset(user, attrs)) do
    Cache.delete({User, user.id})
    Cache.delete({User, :email, user.email})
    {:ok, updated}
  end
end

# Bad: Update without cache invalidation (stale data)
def update_user(user, attrs) do
  Repo.update(User.changeset(user, attrs))
  # Cache still has old data!
end
```

### 5. Use Bulk Operations

```elixir
# Good: Single call for multiple keys
users = Cache.get_all([{User, 1}, {User, 2}, {User, 3}])

# Bad: N+1 cache calls
users = Enum.map([1, 2, 3], fn id -> Cache.get({User, id}) end)
```

### 6. Monitor Cache Performance

```elixir
# Good: Attach telemetry handlers
OmCache.Telemetry.attach_logger(:cache_logger, level: :info)

# Good: Track hit/miss ratio in metrics
:telemetry.attach("cache-metrics",
  [:nebulex, :cache, :command, :stop],
  &MyApp.Metrics.track_cache/4,
  nil
)
```

---

## Configuration Reference

### OmCache Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:otp_app` | atom | required | OTP application name |
| `:default_adapter` | atom | `:redis` | Default adapter |
| `:key_generator` | module | `OmCache.KeyGenerator` | Custom key generator |

### OmCache.Config.build/1 Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:adapter_env` | string | `"CACHE_ADAPTER"` | Env var for adapter |
| `:redis_host_env` | string | `"REDIS_HOST"` | Env var for Redis host |
| `:redis_port_env` | string | `"REDIS_PORT"` | Env var for Redis port |
| `:default_adapter` | atom | `:redis` | Default when env not set |
| `:local_opts` | keyword | see below | Local adapter options |
| `:redis_opts` | keyword | `[]` | Redis adapter options |
| `:partitioned_opts` | keyword | `[]` | Partitioned adapter options |
| `:replicated_opts` | keyword | `[]` | Replicated adapter options |

### Local Adapter Defaults

```elixir
[
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  allocated_memory: 2_000_000_000,
  gc_cleanup_min_timeout: :timer.seconds(10),
  gc_cleanup_max_timeout: :timer.minutes(10),
  stats: true
]
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CACHE_ADAPTER` | `"redis"` | Adapter type |
| `REDIS_HOST` | `"localhost"` | Redis server host |
| `REDIS_PORT` | `6379` | Redis server port |

---

## Troubleshooting

### Redis Connection Issues

```elixir
# Check if Redis is available
OmCache.Config.redis_available?()
#=> true or false

# Get Redis URL for debugging
OmCache.Config.redis_url()
#=> "redis://localhost:6379"

# Fallback to local adapter if Redis unavailable
config = if OmCache.Config.redis_available?() do
  OmCache.Config.build(default_adapter: :redis)
else
  OmCache.Config.build(default_adapter: :local)
end
```

### Cache Not Working in Tests

```elixir
# config/test.exs
config :my_app, MyApp.Cache,
  adapter: Nebulex.Adapters.Nil  # Disable caching in tests

# Or use environment variable
# CACHE_ADAPTER=null mix test
```

### Debugging Cache Keys

```elixir
# Log all cache operations
OmCache.Telemetry.attach_logger(:debug_logger, level: :debug, log_args: true)

# Check if key exists
MyApp.Cache.has_key?({User, 123})
#=> true or false

# Get all keys (local adapter only)
MyApp.Cache.all()
```

---

## License

MIT
