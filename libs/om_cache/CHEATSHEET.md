# OmCache Cheatsheet

## Setup

```elixir
# Define cache
defmodule MyApp.Cache do
  use OmCache, otp_app: :my_app                          # defaults to :redis
  use OmCache, otp_app: :my_app, default_adapter: :local # force local
end

# Configure (runtime.exs)
config :my_app, MyApp.Cache, OmCache.Config.build()
config :my_app, MyApp.Cache, OmCache.Config.build(default_adapter: :local)

# Supervise
children = [MyApp.Cache]
```

## Config (`OmCache.Config`)

```elixir
OmCache.Config.build()                                    # Redis from env vars
OmCache.Config.build(default_adapter: :local)              # Force local
OmCache.Config.build(default_adapter: :null)               # No-op (testing)
OmCache.Config.build(local_opts: [max_size: 500_000])      # Custom local opts
OmCache.Config.build(redis_opts: [pool_size: 10])          # Custom redis opts
```

## Raw Cache Operations (Nebulex API)

```elixir
Cache.put(key, value)                                      # Store
Cache.put(key, value, ttl: :timer.minutes(5))              # Store with TTL
Cache.get(key)                                             # Fetch (nil on miss)
Cache.delete(key)                                          # Delete
Cache.has_key?(key)                                        # Exists?
Cache.get_or_put(key, fn -> compute() end)                 # Cache-aside
Cache.put_all([{k1, v1}, {k2, v2}])                        # Bulk put
Cache.get_all([k1, k2, k3])                                # Bulk get
Cache.incr(key)                                            # Atomic increment
Cache.decr(key)                                            # Atomic decrement
Cache.count_all()                                          # Size
Cache.delete_all()                                         # Clear
```

## Helpers (`OmCache.Helpers`)

```elixir
alias OmCache.Helpers

Helpers.fetch(cache, key)                                  # {:ok, val} | {:error, %Error{}}
Helpers.fetch(cache, key, default: %{})                    # {:ok, %{}} on miss
Helpers.fetch!(cache, key)                                 # val | raises OmCache.Error
Helpers.put_safe(cache, key, val)                          # {:ok, :ok} | {:error, %Error{}}
Helpers.put_safe(cache, key, val, ttl: 60_000)             # With TTL
Helpers.delete_safe(cache, key)                            # {:ok, :ok} | {:error, %Error{}}
Helpers.exists?(cache, key)                                # {:ok, bool} | {:error, %Error{}}
Helpers.ttl(cache, key)                                    # {:ok, ms} | {:error, %Error{}}

# Cache-aside
Helpers.get_or_fetch(cache, key, fn ->
  {:ok, Repo.get(User, id)}
end, ttl: :timer.minutes(30))

# Batch
Helpers.fetch_batch(cache, [k1, k2])                       # %{k1 => {:ok, v}, k2 => {:error, e}}
Helpers.put_batch(cache, [{k1, v1}, {k2, v2}])             # {:ok, :ok}
Helpers.put_batch(cache, %{k1: v1, k2: v2})                # Also accepts maps
```

## Batch (`OmCache.Batch`)

```elixir
alias OmCache.Batch

# Fetch with auto-loading
Batch.fetch_batch(cache, [1, 2, 3], &load/1)
Batch.fetch_batch(cache, ids, &load/1,
  key_fn: &{:user, &1},
  ttl: :timer.minutes(30),
  concurrency: 20
)

# Parallel fetch (no auto-load)
Batch.fetch_parallel(cache, [k1, k2, k3])                 # {:ok, %{hits: %{}, misses: []}}

# Batch write/delete
Batch.put_batch(cache, %{k1: v1, k2: v2}, ttl: :timer.hours(1))
Batch.delete_batch(cache, [k1, k2, k3])

# Warm cache from DB in batches
Batch.warm_cache(cache, ids, fn batch ->
  rows = Repo.all(from u in User, where: u.id in ^batch)
  {:ok, Map.new(rows, &{{User, &1.id}, &1})}
end, batch_size: 100, concurrency: 5, ttl: :timer.hours(1))

# Pipeline
Batch.pipeline(cache, [
  {:get, key1},
  {:put, key2, value2},
  {:delete, key3}
])
```

## Multi-Level (`OmCache.MultiLevel`)

```elixir
alias OmCache.MultiLevel

MultiLevel.get(l1, l2, key)                                # L1 → L2 → nil (promotes to L1)
MultiLevel.get(l1, l2, key, skip_l1: true)                 # L2 only
MultiLevel.get(l1, l2, key, skip_promotion: true)           # Don't write L1 on L2 hit
MultiLevel.put(l1, l2, key, val)                            # Both levels
MultiLevel.put(l1, l2, key, val, l1_ttl: 300_000, l2_ttl: 3_600_000)
MultiLevel.put(l1, l2, key, val, l1_only: true)             # L1 only
MultiLevel.put(l1, l2, key, val, l2_only: true)             # L2 only
MultiLevel.delete(l1, l2, key)                              # Both
MultiLevel.invalidate(l1, l2, key)                          # Alias for delete
MultiLevel.clear_all(l1, l2)                                # Nuke both

MultiLevel.get_or_fetch(l1, l2, key, fn ->
  {:ok, Repo.get(User, id)}
end)
```

## Circuit Breaker (`OmCache.CircuitBreaker`)

```elixir
alias OmCache.CircuitBreaker

# Start
CircuitBreaker.start_link(cache)
CircuitBreaker.start_link(cache,
  error_threshold: 5,
  open_timeout: 30_000,
  latency_threshold: 1_000,
  latency_sample_size: 10
)

# Use
CircuitBreaker.call(cache, fn c -> c.get(key) end,
  fallback: fn -> Repo.get(User, id) end,
  timeout: 5_000
)

# Inspect
CircuitBreaker.get_state(cache)                             # :closed | :open | :half_open
CircuitBreaker.open?(cache)                                 # bool
CircuitBreaker.stats(cache)                                 # %{state, error_count, avg_latency_ms, ...}
CircuitBreaker.reset(cache)                                 # Force close
```

## Invalidation (`OmCache.Invalidation`)

```elixir
alias OmCache.Invalidation

# Group (all adapters)
Invalidation.invalidate_group(cache, [k1, k2, k3])         # {:ok, count}
Invalidation.invalidate_all(cache)                          # {:ok, :ok}

# Pattern (ETS adapters only — local, partitioned)
Invalidation.invalidate_pattern(cache, {User, :_})          # All User keys
Invalidation.invalidate_pattern(cache, {:session, :_})      # All sessions
Invalidation.invalidate_pattern(cache, {:_, user_id, :_})   # By position

# Tags (ETS adapters only)
Invalidation.put_tagged(cache, {Product, 1}, prod,
  tags: [:products, :electronics], ttl: :timer.hours(1))
Invalidation.invalidate_tagged(cache, :electronics)         # {:ok, count}
```

## Warming (`OmCache.Warming`)

```elixir
alias OmCache.Warming

# Warm individual keys in parallel
Warming.warm(cache, [1, 2, 3], fn id ->
  {:ok, Repo.get(User, id)}
end, key_fn: &{:user, &1}, ttl: :timer.hours(1), concurrency: 20)

# Warm with pre-loaded data
Warming.warm_batch(cache, users, fn u -> {User, u.id} end,
  ttl: :timer.hours(1))
```

## Stats (`OmCache.Stats`)

```elixir
alias OmCache.Stats

Stats.attach(cache)                                         # Start collecting
Stats.attach(cache, track_keys: true, latency_samples: 5000)
Stats.get_stats(cache)                                      # Full stats map
Stats.hit_ratio(cache)                                      # 0.0..1.0
Stats.reset(cache)                                          # Zero counters
Stats.detach(cache)                                         # Stop + cleanup
```

## Telemetry (`OmCache.Telemetry`)

```elixir
alias OmCache.Telemetry

Telemetry.attach_logger(:my_logger)                         # Attach logger
Telemetry.attach_logger(:my_logger, level: :info, log_args: true)
Telemetry.detach_logger(:my_logger)

# Custom events
Telemetry.emit_cache_hit(cache, key, duration_ms)
Telemetry.emit_cache_miss(cache, key, duration_ms)
Telemetry.emit_cache_write(cache, key, duration_ms)
Telemetry.emit_cache_error(cache, %OmCache.Error{})
Telemetry.emit_eviction(cache, key, :expired)
Telemetry.emit_batch_operation(cache, :fetch, count, duration_ms)
Telemetry.emit_warming(cache, count, duration_ms)
Telemetry.emit_circuit_breaker_state(cache, :closed, :open)
```

## Error (`OmCache.Error`)

```elixir
alias OmCache.Error

# Constructors
Error.connection_failed(cache, "Redis down")
Error.timeout(key, :get, "Timed out")
Error.not_found(key, :get)
Error.serialization_error(key, :put, "Bad data")
Error.adapter_unavailable(cache, "Not started")
Error.invalid_ttl(-100, "Must be positive")
Error.cache_full(key, "At capacity")
Error.invalid_key(nil, "Cannot be nil")
Error.operation_failed(:delete, "Unknown error")
Error.unknown("Something broke")
Error.from_exception(%RuntimeError{message: "boom"}, :get, key)

# Protocols
FnTypes.Protocols.Recoverable.recoverable?(error)           # true for connection/timeout
FnTypes.Protocols.Recoverable.strategy(error)                # :retry_with_backoff
FnTypes.Protocols.Normalizable.normalize(error, [])          # => %FnTypes.Error{}
raise error                                                  # OmCache.Error is an exception
```

## Test Helpers (`OmCache.TestHelpers`)

```elixir
import OmCache.TestHelpers

setup_test_cache(cache)                                     # %{cache: cache} + cleanup
clear_test_cache(cache)                                     # :ok
seed_cache(cache, [{k1, v1}, {k2, v2}], ttl: 60_000)       # Bulk seed

# Assertions
assert_cached(cache, key, expected_value)
refute_cached(cache, key)
assert_key_exists(cache, key)
assert_cache_size(cache, 5)
cache_size(cache)                                           # integer

# Utilities
simulate_miss(cache, key, fn -> test_code() end)
wait_for_expiry(110)                                        # ms
```

## Key Generator (`OmCache.KeyGenerator`)

```elixir
# Default behaviour
OmCache.KeyGenerator.generate(Mod, :func, [])              # => 0
OmCache.KeyGenerator.generate(Mod, :func, [123])           # => 123
OmCache.KeyGenerator.generate(Mod, :func, [1, 2, 3])      # => :erlang.phash2([1, 2, 3])

# Custom
defmodule MyApp.KeyGen do
  @behaviour OmCache.KeyGenerator
  @impl true
  def generate(mod, fun, args), do: {mod, fun, :erlang.phash2(args)}
end

defmodule MyApp.Cache do
  use OmCache, otp_app: :my_app, key_generator: MyApp.KeyGen
end
```
