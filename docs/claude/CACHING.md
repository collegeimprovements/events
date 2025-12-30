# Caching Reference

> **Quick reference for `@cacheable` decorator with presets, full API, and custom preset creation.**

## Getting Started

```elixir
defmodule MyApp.Users do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate cacheable(Presets.database(cache: MyApp.Cache, key: {User, id}))
  def get_user(id), do: Repo.get(User, id)
end
```

---

## Built-in Presets

Use presets for common caching patterns. Import with:

```elixir
alias FnDecorator.Caching.Presets
```

### Preset Quick Reference

| Preset | TTL | Stale | Refresh | Best For |
|--------|-----|-------|---------|----------|
| `high_availability` | 5m | 24h | stale_access + expiry | User-facing reads |
| `always_fresh` | 30s | - | expiry | Critical config, feature flags |
| `external_api` | 15m | 4h | cron */15 | Third-party APIs |
| `expensive` | 6h | 7d | cron */6h | Reports, aggregations |
| `session` | 30m | - | - | User sessions, carts |
| `database` | 5m | 1h | stale_access | Standard DB queries |
| `minimal` | user | - | - | Simple caching |

### Preset Examples

```elixir
# High availability - prioritizes returning data over freshness
@decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
def get_user(id), do: Repo.get(User, id)

# Always fresh - critical data that must be current
@decorate cacheable(Presets.always_fresh(cache: MyApp.Cache, key: :feature_flags))
def get_flags, do: ConfigService.fetch()

# External API - resilient to outages
@decorate cacheable(Presets.external_api(cache: MyApp.Cache, key: {:weather, city}))
def get_weather(city), do: WeatherAPI.fetch(city)

# Expensive computation - long-lived cache
@decorate cacheable(Presets.expensive(cache: MyApp.Cache, key: {:report, date}))
def generate_report(date), do: Reports.compute(date)

# Session data - short-lived, no stale
@decorate cacheable(Presets.session(cache: MyApp.Cache, key: {:session, id}))
def get_session(id), do: Sessions.fetch(id)

# Database reads - standard caching
@decorate cacheable(Presets.database(cache: MyApp.Cache, key: {Product, id}))
def get_product(id), do: Repo.get(Product, id)

# Minimal - just TTL, you specify duration
@decorate cacheable(Presets.minimal(cache: MyApp.Cache, key: {Item, id}, ttl: :timer.minutes(10)))
def get_item(id), do: Repo.get(Item, id)
```

### Override Preset Defaults

```elixir
# Start with preset, override specific values
@decorate cacheable(Presets.high_availability(
  cache: MyApp.Cache,
  key: {User, id},
  ttl: :timer.minutes(10)  # Override default 5m TTL
))
def get_user(id), do: Repo.get(User, id)
```

---

## Creating Custom Presets

Presets are just keyword lists. Create your own in your codebase:

```elixir
# lib/my_app/cache_presets.ex
defmodule MyApp.CachePresets do
  @moduledoc "Application-specific cache presets"

  alias FnDecorator.Caching.Presets

  @doc "For internal microservice calls"
  def microservice(opts \\ []) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      refresh: [on: :stale_access, retries: 3],
      serve_stale: [ttl: :timer.minutes(5)],
      prevent_thunder_herd: [max_wait: :timer.seconds(5)]
    ], opts)
  end

  @doc "For paginated list endpoints"
  def paginated_list(opts \\ []) do
    Presets.merge([
      store: [ttl: :timer.minutes(2), only_if: &match?({:ok, %{data: [_ | _]}}, &1)],
      serve_stale: [ttl: :timer.minutes(10)],
      prevent_thunder_herd: true
    ], opts)
  end

  @doc "Compose high_availability with custom options"
  def resilient_api(opts \\ []) do
    Presets.compose([
      Presets.high_availability(),
      [prevent_thunder_herd: [max_wait: :timer.seconds(20)]],
      opts
    ])
  end
end
```

Usage:

```elixir
alias MyApp.CachePresets

@decorate cacheable(CachePresets.microservice(cache: MyApp.Cache, key: {:orders, user_id}))
def get_user_orders(user_id), do: OrderService.fetch(user_id)

@decorate cacheable(CachePresets.paginated_list(cache: MyApp.Cache, key: {:products, page}))
def list_products(page), do: Products.paginate(page)
```

---

## Full API Reference

### Complete Structure

```elixir
@decorate cacheable(
  # STORE: Where, what key, how long, what to cache
  store: [
    cache: module(),                    # Required - cache module
    key: term() | (... -> term()),      # Required - cache key or function
    ttl: timeout(),                     # Required - how long data stays fresh
    only_if: (term() -> boolean())      # Optional - condition to cache result
  ],

  # REFRESH: When and how to refresh (optional)
  refresh: [
    on: trigger() | [trigger()],        # When to refresh
    retries: pos_integer()              # Retry attempts (default: 3)
  ],

  # SERVE STALE: Serve expired data while refreshing (optional)
  serve_stale: [
    ttl: timeout()                      # How long to keep stale data available
  ],

  # THUNDER HERD: Prevent stampede (default: ON)
  prevent_thunder_herd: boolean() | timeout() | [
    max_wait: timeout(),                # How long waiters wait (default: 5s)
    retries: pos_integer(),             # Cache re-checks (default: 3)
    lock_timeout: timeout(),            # Auto-release crashed lock (default: 30s)
    on_timeout: on_timeout()            # Fallback action (default: :serve_stale)
  ],

  # FALLBACK: Error handling (optional)
  fallback: [
    on_refresh_failure: fallback_action(),
    on_cache_unavailable: fallback_action()
  ]
)
```

### Types

```elixir
@type trigger ::
  | :stale_access                                    # Refresh when stale data accessed
  | :immediately_when_expired                        # Refresh right when TTL expires
  | {:every, timeout()}                              # Periodic refresh
  | {:every, timeout(), only_if_stale: boolean()}   # Periodic, skip if fresh
  | {:cron, String.t()}                              # Cron schedule
  | {:cron, String.t(), only_if_stale: boolean()}   # Cron, skip if fresh

@type on_timeout ::
  | :serve_stale                    # Return stale data if available, else error
  | :error                          # Return {:error, :timeout}
  | {:call, function()}             # Call fallback function
  | {:value, term()}                # Return static value

@type fallback_action ::
  | :serve_stale                    # Serve stale data
  | :error                          # Return error
  | {:call, function()}             # Call fallback function
  | {:value, term()}                # Return static value
```

### Trigger Aliases

```elixir
# All equivalent - normalized to :immediately_when_expired
:immediately_when_expired  # Canonical (preferred)
:when_expired              # Alias
:on_expiry                 # Alias
```

---

## Option Details

### store

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `cache` | module | Yes | Cache module (e.g., `MyApp.Cache`) |
| `key` | term \| function | Yes | Cache key or function returning key |
| `ttl` | timeout | Yes | Time data stays fresh |
| `only_if` | function | No | Only cache if function returns true |

```elixir
store: [
  cache: MyApp.Cache,
  key: {User, id},                           # Tuple key
  key: fn id -> {User, id} end,              # Dynamic key
  ttl: :timer.minutes(5),
  only_if: &match?({:ok, _}, &1)             # Only cache {:ok, _} results
]
```

### refresh

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `on` | trigger \| [trigger] | - | When to trigger refresh |
| `retries` | pos_integer | 3 | Retry attempts on failure |

```elixir
# Single trigger
refresh: [on: :stale_access]

# Multiple triggers (all active, any can fire)
refresh: [
  on: [
    :stale_access,                              # Refresh when stale data accessed
    :immediately_when_expired,                  # Refresh right when TTL expires
    {:cron, "0 * * * *", only_if_stale: true}   # Hourly safety net
  ],
  retries: 5
]
```

### serve_stale

| Option | Type | Description |
|--------|------|-------------|
| `ttl` | timeout | How long to keep stale data available after fresh TTL expires |

```elixir
store: [ttl: :timer.minutes(5)],      # Fresh for 5 minutes
serve_stale: [ttl: :timer.hours(1)]   # Then stale for 1 hour (total 65 minutes)
```

### prevent_thunder_herd

Prevents cache stampede when multiple requests hit expired cache simultaneously.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_wait` | timeout | 5s | How long waiters wait for fetcher |
| `retries` | integer | 3 | Cache re-checks before giving up |
| `lock_timeout` | timeout | 30s | Auto-release if fetcher crashes |
| `on_timeout` | on_timeout | `:serve_stale` | Fallback when wait times out |

```elixir
# Default ON with all defaults
prevent_thunder_herd: true

# Just customize wait time
prevent_thunder_herd: :timer.seconds(10)

# Full customization
prevent_thunder_herd: [
  max_wait: :timer.seconds(10),
  retries: 5,
  lock_timeout: :timer.seconds(60),
  on_timeout: {:call, &fallback_user/1}
]

# Disable (rare)
prevent_thunder_herd: false
```

### fallback

| Option | Type | Description |
|--------|------|-------------|
| `on_refresh_failure` | fallback_action | What to do when refresh fails |
| `on_cache_unavailable` | fallback_action | What to do when cache is down |

```elixir
fallback: [
  on_refresh_failure: :serve_stale,
  on_cache_unavailable: {:call, &direct_fetch/1}
]
```

---

## Compile-Time Validation

The decorator validates configuration at compile time:

### Errors (compilation fails)

| Check | Message |
|-------|---------|
| Missing `store.cache` | `store.cache is required` |
| Missing `store.key` | `store.key is required` |
| Missing `store.ttl` | `store.ttl is required` |
| `ttl <= 0` | `ttl must be positive` |
| Invalid cron | `invalid cron expression: "..."` |
| `:stale_access` without `serve_stale` | `:stale_access requires serve_stale` |
| `serve_stale.ttl <= store.ttl` | `serve_stale.ttl must be > store.ttl` |
| `{:every, interval} < store.ttl` without `only_if_stale` | Suggest `:immediately_when_expired` |

### Warnings

| Check | Message |
|-------|---------|
| `lock_timeout < max_wait` | `may cause duplicate fetches` |

---

## Behavior Summary

| Scenario | Behavior |
|----------|----------|
| Cache hit (fresh) | Return cached data |
| Cache hit (stale) + `serve_stale` | Return stale, trigger refresh |
| Cache miss + thunder herd ON | First request fetches, others wait |
| Wait timeout | Retry cache → fallback (stale/error/call) |
| Refresh failure | Retry up to N times → fallback |
| Cache unavailable | Use `fallback.on_cache_unavailable` |

---

## Real-World Examples

### User Profile with High Availability

```elixir
@decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
def get_user(id), do: Repo.get(User, id)
```

### Feature Flags (Always Fresh)

```elixir
@decorate cacheable(Presets.always_fresh(cache: MyApp.Cache, key: :feature_flags))
def get_feature_flags, do: ConfigService.fetch_flags()
```

### Weather API with Long Stale Window

```elixir
@decorate cacheable(
  Presets.external_api(
    cache: MyApp.Cache,
    key: {:weather, city},
    ttl: :timer.minutes(10)  # Override to 10 min
  )
)
def get_weather(city), do: WeatherAPI.fetch(city)
```

### Expensive Report with Cron Refresh

```elixir
@decorate cacheable(
  store: [cache: MyApp.Cache, key: {:daily_report, date}, ttl: :timer.hours(6)],
  refresh: [on: {:cron, "0 */6 * * *"}, retries: 3],
  serve_stale: [ttl: :timer.days(7)],
  prevent_thunder_herd: [max_wait: :timer.minutes(2), lock_timeout: :timer.minutes(10)]
)
def generate_daily_report(date), do: Reports.compute(date)
```

### Custom Fallback Function

```elixir
@decorate cacheable(
  store: [cache: MyApp.Cache, key: {User, id}, ttl: :timer.minutes(5)],
  serve_stale: [ttl: :timer.hours(1)],
  prevent_thunder_herd: [on_timeout: {:call, &guest_user/1}],
  fallback: [on_cache_unavailable: {:call, &direct_db_fetch/1}]
)
def get_user(id), do: Repo.get(User, id)

defp guest_user(_args), do: {:ok, %User{name: "Guest"}}
defp direct_db_fetch([id]), do: Repo.get(User, id)
```

---

## Preset Composition

```elixir
alias FnDecorator.Caching.Presets

# Method 1: Using compose
@decorate cacheable(
  Presets.compose([
    Presets.high_availability(),
    [store: [ttl: :timer.minutes(10)]],
    [store: [cache: MyApp.Cache, key: {User, id}]]
  ])
)

# Method 2: Pipeline style
@decorate cacheable(
  Presets.high_availability()
  |> Presets.merge([store: [ttl: :timer.minutes(10)]])
  |> Presets.merge([store: [cache: MyApp.Cache, key: {User, id}]])
)

# Method 3: Direct function call with overrides
@decorate cacheable(Presets.high_availability(
  cache: MyApp.Cache,
  key: {User, id},
  ttl: :timer.minutes(10)
))
```
