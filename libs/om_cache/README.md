# OmCache

Nebulex cache wrapper with adapter selection, graceful degradation, and production-ready utilities.

## What You Get

- **One-line adapter switching** via `CACHE_ADAPTER` env var (redis/local/partitioned/replicated/null)
- **Result-tuple helpers** — `{:ok, value} | {:error, %OmCache.Error{}}` everywhere
- **Circuit breaker** — automatic fallback when cache is down
- **Multi-level caching** — L1 (local) + L2 (distributed) with auto-promotion
- **Batch operations** — parallel fetch with auto-loading for misses
- **Cache warming** — parallel preloading with concurrency control
- **Pattern & tag invalidation** — invalidate by pattern, tag, or key group
- **Performance stats** — hit ratio, latency percentiles, error breakdown
- **Telemetry** — built-in events + logger attachment
- **Test helpers** — assertions, seeding, cleanup macros

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:om_cache, "~> 0.1.0"}
```

**2. Define cache module**:

```elixir
defmodule MyApp.Cache do
  use OmCache, otp_app: :my_app
end
```

**3. Configure** (`config/runtime.exs`):

```elixir
config :my_app, MyApp.Cache, OmCache.Config.build()
```

**4. Add to supervision tree** (`application.ex`):

```elixir
children = [MyApp.Cache]
```

**5. Set environment variables** (optional):

```bash
CACHE_ADAPTER=redis         # redis | local | partitioned | replicated | null
REDIS_HOST=localhost         # Redis host (default: localhost)
REDIS_PORT=6379              # Redis port (default: 6379)
```

Custom env var names and adapter defaults can be set via `OmCache.Config.build/1` options:

```elixir
OmCache.Config.build(
  adapter_env: "MY_CACHE_ADAPTER",
  redis_host_env: "MY_REDIS_HOST",
  default_adapter: :local,
  local_opts: [max_size: 500_000],
  redis_opts: [pool_size: 10]
)
```

---

## Quick Start

### 1. Define Cache

```elixir
defmodule MyApp.Cache do
  use OmCache, otp_app: :my_app
end
```

### 2. Configure

```elixir
# config/runtime.exs
config :my_app, MyApp.Cache, OmCache.Config.build()
```

### 3. Supervise

```elixir
# application.ex
children = [MyApp.Cache]
```

### 4. Use

```elixir
MyApp.Cache.put({User, 123}, user, ttl: :timer.minutes(30))
MyApp.Cache.get({User, 123})
MyApp.Cache.delete({User, 123})
```

---

## Adapter Selection

```bash
CACHE_ADAPTER=redis       # Production — Redis (default)
CACHE_ADAPTER=local       # Dev — ETS, single node
CACHE_ADAPTER=partitioned # Cluster — sharded across Erlang nodes
CACHE_ADAPTER=replicated  # Cluster — full copy on every node
CACHE_ADAPTER=null        # Test — no-op
```

| Adapter | Backend | Distribution | Best For |
|---------|---------|-------------|----------|
| `redis` | Redis | Centralized | Production, shared state |
| `local` | ETS | Single node | Development, single instance |
| `partitioned` | ETS + Erlang | Sharded | Multi-node, large datasets |
| `replicated` | ETS + Erlang | Full copy | Multi-node, read-heavy |
| `null` | None | N/A | Testing |

### Custom Config

```elixir
OmCache.Config.build(
  adapter_env: "MY_CACHE_ADAPTER",
  redis_host_env: "MY_REDIS_HOST",
  redis_port_env: "MY_REDIS_PORT",
  default_adapter: :local,
  local_opts: [max_size: 500_000],
  redis_opts: [pool_size: 10, ssl: true]
)
```

---

## Key Design

Use tuples for structured, namespaced keys:

```elixir
{User, 123}                          # Entity by ID
{User, :email, "a@b.com"}           # Entity by alternate key
{:session, session_id}               # Namespaced data
{:tenant, tid, User, uid}           # Hierarchical
{:search, :products, query_hash}    # Computed
```

---

## Result-Tuple Helpers (`OmCache.Helpers`)

Wraps raw Nebulex calls with `{:ok, value} | {:error, %OmCache.Error{}}`:

```elixir
alias OmCache.Helpers

# Fetch with result tuple
Helpers.fetch(MyApp.Cache, {User, 123})
#=> {:ok, %User{}} or {:error, %OmCache.Error{type: :key_not_found}}

# Fetch or raise
Helpers.fetch!(MyApp.Cache, {User, 123})
#=> %User{} or raises OmCache.Error

# Safe put with key/TTL validation
Helpers.put_safe(MyApp.Cache, {User, 123}, user, ttl: :timer.minutes(30))
#=> {:ok, :ok} or {:error, %OmCache.Error{type: :invalid_ttl}}

# Cache-aside pattern
Helpers.get_or_fetch(MyApp.Cache, {User, 123}, fn ->
  {:ok, Repo.get(User, 123)}
end, ttl: :timer.minutes(30))

# Batch fetch
Helpers.fetch_batch(MyApp.Cache, [{User, 1}, {User, 2}])
#=> %{{User, 1} => {:ok, user1}, {User, 2} => {:error, %Error{type: :key_not_found}}}

# Check existence
Helpers.exists?(MyApp.Cache, {User, 123})
#=> {:ok, true}
```

---

## Batch Operations (`OmCache.Batch`)

Parallel fetching with auto-loading for misses:

```elixir
alias OmCache.Batch

# Fetch batch — loads misses via loader, caches results
Batch.fetch_batch(MyApp.Cache, [1, 2, 3], fn id ->
  {:ok, Repo.get(User, id)}
end, key_fn: &{:user, &1}, ttl: :timer.minutes(30))
#=> {:ok, %{1 => user1, 2 => user2, 3 => user3}}

# Parallel fetch — returns hits and misses separately
Batch.fetch_parallel(MyApp.Cache, [{User, 1}, {User, 2}, {User, 999}])
#=> {:ok, %{hits: %{{User, 1} => user1}, misses: [{User, 999}]}}

# Batch put
Batch.put_batch(MyApp.Cache, %{a: 1, b: 2, c: 3})

# Batch delete
Batch.delete_batch(MyApp.Cache, [{User, 1}, {User, 2}])

# Warm cache in batches from database
Batch.warm_cache(MyApp.Cache, user_ids, fn batch ->
  users = Repo.all(from u in User, where: u.id in ^batch)
  {:ok, Map.new(users, fn u -> {{User, u.id}, u} end)}
end, batch_size: 100, ttl: :timer.hours(1))
#=> {:ok, 1500}

# Sequential pipeline
Batch.pipeline(MyApp.Cache, [
  {:get, {User, 1}},
  {:put, {User, 2}, user2},
  {:delete, {User, 3}}
])
#=> {:ok, [user1, :ok, :ok]}
```

---

## Multi-Level Caching (`OmCache.MultiLevel`)

Two-tier cache: fast L1 (local) + shared L2 (distributed):

```elixir
defmodule MyApp.L1Cache do
  use OmCache, otp_app: :my_app, default_adapter: :local
end

defmodule MyApp.L2Cache do
  use OmCache, otp_app: :my_app, default_adapter: :redis
end
```

```elixir
alias OmCache.MultiLevel

# Get — checks L1, then L2, promotes to L1 on L2 hit
MultiLevel.get(MyApp.L1Cache, MyApp.L2Cache, {User, 123})

# Put — writes to both levels, rolls back L1 if L2 fails
MultiLevel.put(MyApp.L1Cache, MyApp.L2Cache, {User, 123}, user,
  l1_ttl: :timer.minutes(5),
  l2_ttl: :timer.hours(1)
)

# Get or fetch — loads on double miss, stores in both
MultiLevel.get_or_fetch(MyApp.L1Cache, MyApp.L2Cache, {User, 123}, fn ->
  {:ok, Repo.get(User, 123)}
end)

# Delete from both
MultiLevel.delete(MyApp.L1Cache, MyApp.L2Cache, {User, 123})

# Options
MultiLevel.get(l1, l2, key, skip_l1: true)           # Bypass L1
MultiLevel.get(l1, l2, key, skip_promotion: true)     # Don't promote to L1
MultiLevel.put(l1, l2, key, val, l1_only: true)       # L1 only
MultiLevel.put(l1, l2, key, val, l2_only: true)       # L2 only
```

---

## Circuit Breaker (`OmCache.CircuitBreaker`)

Automatic fallback when cache is down:

```elixir
alias OmCache.CircuitBreaker

# Start (add to supervision tree)
CircuitBreaker.start_link(MyApp.Cache,
  error_threshold: 5,        # Open after 5 consecutive errors
  open_timeout: 30_000,      # Try half-open after 30s
  latency_threshold: 1_000   # Open if avg latency > 1s
)

# Use — returns cache result or fallback
CircuitBreaker.call(MyApp.Cache, fn cache ->
  cache.get({User, 123})
end, fallback: fn ->
  Repo.get(User, 123)
end)

# State inspection
CircuitBreaker.get_state(MyApp.Cache)  #=> :closed | :open | :half_open
CircuitBreaker.open?(MyApp.Cache)      #=> false
CircuitBreaker.stats(MyApp.Cache)
#=> %{state: :closed, error_count: 0, avg_latency_ms: 2.5, uptime_seconds: 3600}

# Manual reset
CircuitBreaker.reset(MyApp.Cache)
```

State machine: `closed → open → half_open → closed`

---

## Cache Invalidation (`OmCache.Invalidation`)

### Group Invalidation (all adapters)

```elixir
alias OmCache.Invalidation

keys = [{User, 1}, {User, 2}, {:session, "abc"}]
Invalidation.invalidate_group(MyApp.Cache, keys)
#=> {:ok, 3}

# Clear everything
Invalidation.invalidate_all(MyApp.Cache)
```

### Pattern Invalidation (ETS adapters only)

```elixir
# Invalidate all User keys
Invalidation.invalidate_pattern(MyApp.Cache, {User, :_})

# Invalidate all sessions
Invalidation.invalidate_pattern(MyApp.Cache, {:session, :_})
```

### Tag-Based Invalidation (ETS adapters only)

```elixir
# Store with tags
Invalidation.put_tagged(MyApp.Cache, {Product, 123}, product,
  tags: [:products, :electronics], ttl: :timer.hours(1))

# Invalidate by tag
Invalidation.invalidate_tagged(MyApp.Cache, :electronics)
#=> {:ok, 12}
```

> **Limitations**: Pattern matching scans all keys (O(n)). Tag metadata is not atomic under concurrent writes. Both only work with ETS-backed adapters. For Redis, use group invalidation with explicit key lists.

---

## Cache Warming (`OmCache.Warming`)

```elixir
alias OmCache.Warming

# Warm specific keys in parallel
Warming.warm(MyApp.Cache, user_ids, fn id ->
  {:ok, Repo.get(User, id)}
end, key_fn: &{:user, &1}, ttl: :timer.hours(1), concurrency: 20)
#=> {:ok, 150}

# Warm with pre-loaded data
users = Repo.all(from u in User, where: u.active)
Warming.warm_batch(MyApp.Cache, users, fn user ->
  {User, user.id}
end, ttl: :timer.hours(1))
#=> {:ok, 150}
```

For periodic warming, use `OmScheduler` to call these functions on a cron schedule.

---

## Performance Stats (`OmCache.Stats`)

```elixir
alias OmCache.Stats

# Attach (in application.ex)
Stats.attach(MyApp.Cache, track_keys: true)

# Query
Stats.get_stats(MyApp.Cache)
#=> %{
#     hits: 1234, misses: 56, hit_ratio: 0.956,
#     writes: 450, deletes: 23, errors: 2,
#     avg_latency_ms: 2.5, p50_latency_ms: 1.2,
#     p95_latency_ms: 8.5, p99_latency_ms: 15.3,
#     error_breakdown: %{connection_error: 1, timeout: 1},
#     top_keys: [{{User, 123}, 45}, {{Product, 456}, 32}]
#   }

Stats.hit_ratio(MyApp.Cache)  #=> 0.956
Stats.reset(MyApp.Cache)
Stats.detach(MyApp.Cache)
```

---

## Telemetry (`OmCache.Telemetry`)

### Logger

```elixir
OmCache.Telemetry.attach_logger(:my_cache_logger, level: :info)
```

### Custom Events

```elixir
OmCache.Telemetry.emit_cache_hit(MyApp.Cache, {User, 123}, 2.5)
OmCache.Telemetry.emit_cache_miss(MyApp.Cache, {User, 999}, 1.2)
OmCache.Telemetry.emit_cache_error(MyApp.Cache, error)
OmCache.Telemetry.emit_cache_write(MyApp.Cache, {User, 123}, 3.1)
OmCache.Telemetry.emit_eviction(MyApp.Cache, {User, 123}, :expired)
OmCache.Telemetry.emit_batch_operation(MyApp.Cache, :fetch, 25, 150.5)
OmCache.Telemetry.emit_warming(MyApp.Cache, 150, 2500.0)
OmCache.Telemetry.emit_circuit_breaker_state(MyApp.Cache, :closed, :open)
```

### Nebulex Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:nebulex, :cache, :command, :start]` | `system_time` | `cache, command, args` |
| `[:nebulex, :cache, :command, :stop]` | `duration` | `cache, command, result` |
| `[:nebulex, :cache, :command, :exception]` | `duration` | `cache, command, kind, reason` |

---

## Error Handling (`OmCache.Error`)

Structured error type with protocol implementations:

```elixir
alias OmCache.Error

# Smart constructors
Error.connection_failed(MyApp.Cache, "Redis down")
Error.timeout({User, 1}, :get, "Operation took 5s")
Error.not_found({User, 999}, :get)

# Pattern match on type
case Helpers.fetch(MyApp.Cache, key) do
  {:ok, value} -> value
  {:error, %Error{type: :key_not_found}} -> handle_miss()
  {:error, %Error{type: :connection_failed}} -> handle_outage()
end

# Recoverable protocol
FnTypes.Protocols.Recoverable.recoverable?(error)   #=> true for connection/timeout
FnTypes.Protocols.Recoverable.strategy(error)        #=> :retry_with_backoff
FnTypes.Protocols.Recoverable.max_attempts(error)    #=> 3

# Normalizable protocol
FnTypes.Protocols.Normalizable.normalize(error, [])  #=> %FnTypes.Error{}

# Raisable
raise Error.not_found({User, 1})
```

Error types: `:connection_failed`, `:timeout`, `:key_not_found`, `:serialization_error`, `:adapter_unavailable`, `:invalid_ttl`, `:cache_full`, `:operation_failed`, `:invalid_key`, `:unknown`

---

## Decorator Integration

```elixir
defmodule MyApp.Users do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
  def get_user(id), do: Repo.get(User, id)

  @decorate cache_evict(cache: MyApp.Cache, key: {User, id})
  def update_user(id, attrs) do
    User |> Repo.get!(id) |> User.changeset(attrs) |> Repo.update()
  end
end
```

---

## Testing (`OmCache.TestHelpers`)

```elixir
defmodule MyApp.UsersTest do
  use ExUnit.Case
  import OmCache.TestHelpers

  setup do
    setup_test_cache(MyApp.Cache)
  end

  test "caches user", %{cache: cache} do
    cache.put({User, 1}, %User{id: 1})

    assert_cached(cache, {User, 1}, %User{id: 1})
    assert_cache_size(cache, 1)
    refute_cached(cache, {User, 999})
    assert_key_exists(cache, {User, 1})
  end

  test "cache miss triggers load" do
    simulate_miss(MyApp.Cache, {User, 1}, fn ->
      result = MyApp.Users.get_user(1)
      assert result != nil
    end)
  end
end
```

### Test Config

```elixir
# config/test.exs — disable caching
config :my_app, MyApp.Cache, adapter: Nebulex.Adapters.Nil

# Or use local for real cache behavior in tests
config :my_app, MyApp.Cache, OmCache.Config.build(default_adapter: :local)
```

---

## Module Reference

| Module | Purpose |
|--------|---------|
| `OmCache` | Cache module definition (`use OmCache`) |
| `OmCache.Config` | Adapter selection + config builder |
| `OmCache.KeyGenerator` | Cache key generation behaviour |
| `OmCache.Error` | Structured errors with protocols |
| `OmCache.Helpers` | Result-tuple wrappers |
| `OmCache.Batch` | Parallel batch operations |
| `OmCache.MultiLevel` | Two-tier L1/L2 caching |
| `OmCache.CircuitBreaker` | Graceful degradation |
| `OmCache.Invalidation` | Pattern, tag, group invalidation |
| `OmCache.Warming` | Cache preloading |
| `OmCache.Stats` | Performance metrics |
| `OmCache.Telemetry` | Telemetry events + logger |
| `OmCache.TestHelpers` | Test utilities |

---

## License

MIT
