# FnDecorator

Composable decorators for Elixir functions — caching, telemetry, type enforcement, security, debugging, and more. Zero runtime overhead from the decorator mechanism (applied at compile time).

## Installation

```elixir
def deps do
  [{:fn_decorator, "~> 0.1.0"}]
end
```

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:fn_decorator, "~> 0.1.0"}
```

**2. Configure** (`config/config.exs` — optional):

```elixir
# Telemetry settings
config :fn_decorator, FnDecorator.Telemetry,
  repo: MyApp.Repo,
  telemetry_prefix: [:my_app]

# Distributed lock adapter (only for multi-node caching)
config :fn_decorator,
  lock_adapter: MyApp.RedisLock
```

No supervision, no environment variables. Works with zero config — the above is optional for telemetry and distributed caching.

## Why Decorators?

Decorators separate cross-cutting concerns from business logic:

```
Without Decorators                    With Decorators
─────────────────────                 ───────────────────
def get_user(id) do                   @decorate cacheable(...)
  start = System.monotonic_time()     @decorate telemetry_span(...)
  Logger.info("Getting user #{id}")   @decorate log_if_slow(...)
                                      def get_user(id) do
  result = case Cache.get(id) do        Repo.get(User, id)
    nil ->                            end
      user = Repo.get(User, id)
      Cache.put(id, user)             # Clean, focused business logic
      user                            # Cross-cutting concerns are
    cached -> cached                  # declared, not implemented
  end

  duration = System.monotonic_time() - start
  :telemetry.execute(...)

  if duration > 1000 do
    Logger.warn("Slow operation")
  end

  result
end
```

**Key Benefits:**
- **Separation of concerns** — Business logic stays clean
- **Reusability** — Apply same behavior to many functions
- **Composability** — Stack multiple decorators
- **Testability** — Test concerns in isolation
- **Zero runtime overhead** — Applied at compile time

---

## Quick Start

```elixir
defmodule MyApp.Users do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  # Combine multiple decorators
  @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
  @decorate telemetry_span([:my_app, :users, :get])
  @decorate log_if_slow(threshold: 1000)
  @decorate returns_result(ok: User.t(), error: :atom)
  def get_user(id) do
    Repo.get(User, id)
  end

  @decorate cache_evict(cache: MyCache, keys: [{User, id}])
  @decorate audit_log(level: :warning, fields: [:id])
  def delete_user(id) do
    Repo.delete(User, id)
  end

  @decorate normalize_result(nil_is_error: true)
  @decorate role_required(roles: [:admin])
  def admin_action(current_user, data) do
    perform_admin_action(data)
  end
end
```

---

## All Decorators at a Glance

| Category | Decorators |
|----------|-----------|
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `returns_pipeline`, `normalize_result` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `log_remote`, `capture_errors`, `track_memory`, `benchmark`, `measure` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Debugging** | `debug`, `inspect`, `pry`, `trace_vars` |
| **Tracing** | `trace_calls`, `trace_modules`, `trace_dependencies` |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable` |
| **Testing** | `with_fixtures`, `sample_data`, `timeout_test`, `mock` |
| **Composition** | `pipe_through`, `around`, `compose` |
| **OpenTelemetry** | `otel_span_advanced`, `propagate_context`, `with_baggage` |

---

## Which Module to Use?

```
Do you need application-specific decorators (workflow steps, scheduled jobs)?
│
├─ No  → use FnDecorator
│        Standard decorators: @cacheable, @telemetry_span, etc.
│
└─ Yes → use YourApp.Extensions.Decorator
         Application decorators (@step, @scheduled) + all FnDecorator decorators
```

```elixir
# Standard decorators only
defmodule MyApp.Users do
  use FnDecorator
  @decorate cacheable(...)
  def get_user(id), do: ...
end

# Application decorators (includes all standard decorators via re-export)
defmodule MyApp.OrderWorkflow do
  use Events.Extensions.Decorator
  @decorate step()                    # Application-specific
  @decorate telemetry_span(...)       # Standard (re-exported)
  def validate_order(ctx), do: ...
end
```

### Creating Application Decorators

```elixir
defmodule MyApp.Extensions.Decorator do
  defmacro __using__(_opts) do
    quote do
      use FnDecorator
      import MyApp.Extensions.Decorator
    end
  end

  defdecorator scheduled(opts \\ []) do
    # Implementation
  end

  defdecorator step(opts \\ []) do
    # Implementation
  end
end
```

---

## Caching

Three core patterns inspired by Spring Cache:

### `cacheable` — Read-Through Caching

On cache miss, execute the function and store the result. On cache hit, return the cached value without executing.

#### Using Presets (Recommended)

```elixir
alias FnDecorator.Caching.Presets

# Database queries — short TTL, quick refresh
@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
def get_user(id), do: Repo.get(User, id)

# User-facing reads — tolerates staleness, survives outages
@decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {User, id}]))
def get_user(id), do: Repo.get(User, id)

# Feature flags — always current, error on stale
@decorate cacheable(Presets.always_fresh(store: [cache: MyCache, key: :feature_flags]))
def get_flags, do: ConfigService.fetch()

# Third-party APIs — long cache, stale on API outage
@decorate cacheable(Presets.external_api(store: [cache: MyCache, key: {:weather, city}]))
def get_weather(city), do: WeatherAPI.fetch(city)

# Reports / ML — very long cache, patient lock wait
@decorate cacheable(Presets.expensive(store: [cache: MyCache, key: {:report, date}]))
def generate_report(date), do: Reports.compute(date)

# Auth sessions — no stale serving, error on timeout
@decorate cacheable(Presets.session(store: [cache: MyCache, key: {:session, sid}]))
def get_session(sid), do: Sessions.fetch(sid)

# Countries, currencies — slow-changing data
@decorate cacheable(Presets.reference_data(store: [cache: MyCache, key: :countries]))
def list_countries, do: Repo.all(Country)
```

#### Preset Reference

| Preset | Fresh TTL | Stale TTL | Max Wait | On Timeout | Best For |
|--------|-----------|-----------|----------|-----------|----------|
| `minimal` | — | — | default | — | Full manual control |
| `database` | 30s | 5m | 2s | serve stale | CRUD reads |
| `session` | 1m | — | 1s | error | Auth, sessions |
| `high_availability` | 1m | 1h | 5s | serve stale | User-facing reads |
| `always_fresh` | 10s | — | 5s | error | Feature flags, config |
| `external_api` | 5m | 1h | 30s | serve stale | Third-party APIs |
| `expensive` | 1h | 24h | 60s | serve stale | Reports, aggregations |
| `reference_data` | 1h | 24h | default | — | Lookup tables |

All presets include thunder herd prevention and can be customized:

```elixir
# Override any preset default
@decorate cacheable(Presets.database(
  store: [cache: MyCache, key: {User, id}, ttl: :timer.minutes(2)],  # Override 30s TTL
  serve_stale: [ttl: :timer.minutes(15)]                             # Override 5m stale
))
def get_user(id), do: Repo.get(User, id)

# Compose multiple presets (later wins)
@decorate cacheable(Presets.compose([
  Presets.database([]),
  [store: [cache: MyCache, key: {User, id}, ttl: :timer.minutes(1)]]
]))
def get_user(id), do: Repo.get(User, id)
```

#### Full `cacheable` API

For when presets don't fit your use case:

```elixir
@decorate cacheable(
  # Required: where and how to cache
  store: [
    cache: MyCache,                          # Cache module (required)
    key: {User, id},                         # Cache key (required)
    ttl: :timer.minutes(5),                  # Fresh duration (required)
    only_if: &match?({:ok, _}, &1),          # Only cache successful results
    tags: [:users]                           # Tags for grouped invalidation
  ],

  # Stale-while-revalidate: serve expired data while refreshing
  serve_stale: [
    ttl: :timer.hours(1)                     # How long stale data is servable
  ],

  # Background refresh on stale access
  refresh: [
    on: :stale_access                        # Trigger async refresh
  ],

  # Thunder herd / cache stampede prevention
  prevent_thunder_herd: [
    max_wait: :timer.seconds(5),             # How long waiters wait (default: 5s)
    lock_ttl: :timer.seconds(30),            # Lock expiry (default: 30s)
    on_timeout: :serve_stale                 # :serve_stale | :error | :proceed | {:call, fn} | {:value, term}
  ],

  # Fallback on fetch failure
  fallback: [
    on_error: :serve_stale                   # :raise | :serve_stale | {:call, fn} | {:value, term}
  ]
)
def get_user(id), do: Repo.get(User, id)
```

#### Cache Entry Lifecycle

```
┌─────────┐
│  Fresh  │ ← Within TTL, returned immediately
└────┬────┘
     │ TTL expires
     ▼
┌─────────┐
│  Stale  │ ← TTL expired but within stale_ttl
└────┬────┘   Returned immediately; async refresh triggered in background
     │ stale_ttl expires
     ▼
┌─────────┐
│ Expired │ ← Treated as cache miss, fetched synchronously
└─────────┘
```

#### Thunder Herd Prevention

When a cache entry expires and 100 requests hit simultaneously, only one process fetches from the source. The rest wait for the cached result:

```
Process A: acquire lock → fetch from DB → store in cache → release lock
Process B: lock busy → wait... → get cached result (from A)
Process C: lock busy → wait... → get cached result (from A)
```

Features:
- Dead holder detection — if the lock holder crashes, waiters detect it immediately and retry (no 30s wait)
- Race-safe takeover — expired/dead locks are taken over atomically
- Configurable timeout behavior — serve stale, error, proceed, or call custom function

### `cache_put` — Write-Through Caching

Always execute the function, then update the cache with the result:

```elixir
# Update cache after write
@decorate cache_put(cache: MyCache, keys: [{User, user.id}])
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

# Conditional — only cache successful results
@decorate cache_put(
  cache: MyCache,
  keys: [{User, user.id}],
  match: fn
    {:ok, user} -> {true, user}     # Cache the unwrapped user
    {:error, _} -> false            # Don't cache errors
  end
)
def update_user(user, attrs), do: ...
```

### `cache_evict` — Cache Invalidation

Remove entries from the cache:

```elixir
# Delete specific key
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
def delete_user(id), do: Repo.delete(User, id)

# Delete by tag (all entries tagged :users)
@decorate cache_evict(cache: MyCache, tags: [:users])
def purge_user_cache, do: :ok

# Delete all entries
@decorate cache_evict(cache: MyCache, all_entries: true)
def clear_cache, do: :ok

# Evict BEFORE execution (e.g., logout)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
def logout(token), do: revoke_session(token)

# Conditional eviction
@decorate cache_evict(cache: MyCache, keys: [{User, id}], only_if: &match?({:ok, _}, &1))
def update_user(id, attrs), do: ...
```

### Custom Cache Presets

```elixir
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      serve_stale: [ttl: :timer.minutes(5)],
      refresh: [on: :stale_access],
      prevent_thunder_herd: [max_wait: 5_000]
    ], opts)
  end

  def resilient_api(opts) do
    Presets.compose([Presets.high_availability([]), opts])
  end
end

# Usage
@decorate cacheable(MyApp.CachePresets.microservice(store: [cache: MyCache, key: {:order, id}]))
def get_order(id), do: ...
```

---

## Type Enforcement

### `returns_result` — Result Type Contracts

Validates that a function returns `{:ok, value} | {:error, reason}`:

```elixir
# Basic — documents the return type
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end

# With validation — raises on wrong type at runtime
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
def update_user(user, attrs), do: ...

# Strict mode — compile-time warnings for suspicious patterns
@decorate returns_result(ok: String.t(), error: :atom, strict: true)
def format_name(user), do: ...
```

### `returns_maybe` — Optional Values

Validates `value | nil` returns:

```elixir
@decorate returns_maybe(type: User.t())
def find_user_by_email(email), do: Repo.get_by(User, email: email)

# With default value for nil
@decorate returns_maybe(type: String.t(), default: "Unknown")
def get_username(user_id), do: ...
```

### `returns_bang` — Bang Variants

Unwraps `{:ok, value}` or raises on `{:error, _}`:

```elixir
@decorate returns_bang(type: User.t())
def get_user!(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
# Returns user directly or raises
```

### `returns_struct` — Struct Type Validation

```elixir
@decorate returns_struct(type: User)
def build_user(attrs), do: struct(User, attrs)

@decorate returns_struct(type: User, nullable: true)
def find_user(id), do: Repo.get(User, id)
```

### `returns_list` — List Validation

```elixir
@decorate returns_list(of: User.t())
def list_users, do: Repo.all(User)

@decorate returns_list(of: User.t(), min_length: 1, max_length: 100)
def get_active_users, do: Repo.all(from u in User, where: u.active)
```

### `returns_union` — Union Types

```elixir
@decorate returns_union(types: [User.t(), Organization.t(), nil])
def find_entity(id), do: find_user(id) || find_org(id)
```

### `returns_pipeline` — Pipeline-Compatible Results

```elixir
@decorate returns_pipeline(ok: User.t(), error: :atom, chain: true)
def get_user(id), do: Repo.get(User, id)
```

### `normalize_result` — Normalize Any Return to Result Tuples

Converts various return shapes into consistent `{:ok, value} | {:error, reason}`:

```elixir
# Wrap raw values
@decorate normalize_result()
def get_user(id), do: Repo.get(User, id)
# nil → {:ok, nil}, %User{} → {:ok, %User{}}

# Treat nil as error
@decorate normalize_result(nil_is_error: true)
def get_user(id), do: Repo.get(User, id)
# nil → {:error, :nil_value}, %User{} → {:ok, %User{}}

# Wrap exceptions as error tuples
@decorate normalize_result(wrap_exceptions: true)
def risky_op, do: raise "boom"
# → {:error, %RuntimeError{message: "boom"}}

# Transform errors
@decorate normalize_result(error_mapper: fn e -> "Failed: #{inspect(e)}" end)
def fetch_data, do: {:error, :timeout}
# → {:error, "Failed: :timeout"}

# Full configuration
@decorate normalize_result(
  nil_is_error: true,
  false_is_error: true,
  wrap_exceptions: true,
  error_patterns: [:invalid, :not_found, :timeout],
  error_mapper: &format_error/1,
  success_mapper: &normalize_user/1
)
def complex_operation(params), do: ...
```

---

## Telemetry & Logging

### `telemetry_span` — Erlang Telemetry Events

```elixir
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs), do: ...

# With metadata from function arguments
@decorate telemetry_span([:my_app, :process], include: [:user_id], metadata: %{source: :api})
def process_data(user_id, data), do: ...
```

**Events emitted:**
- `[:my_app, :users, :create, :start]` — `%{system_time: ...}`
- `[:my_app, :users, :create, :stop]` — `%{duration: ..., duration_ms: ...}`
- `[:my_app, :users, :create, :exception]` — `%{duration: ..., kind: ..., reason: ..., stacktrace: ...}`

### `otel_span` — OpenTelemetry Spans

```elixir
@decorate otel_span("users.create")
def create_user(attrs), do: ...

@decorate otel_span("payment.process", include: [:amount, :currency], attributes: %{provider: "stripe"})
def process_payment(amount, currency, card), do: ...
```

### `log_call` — Function Call Logging

```elixir
@decorate log_call(level: :info)
def process_order(order), do: ...

@decorate log_call(level: :debug, message: "Starting background task")
def background_task(data), do: ...
```

### `log_context` — Logger Metadata

Sets Logger metadata for the function body and any functions called within:

```elixir
@decorate log_context([:user_id, :request_id])
def handle_request(user_id, request_id, params) do
  Logger.info("Processing")  # Includes user_id and request_id in metadata
  process(params)
end
```

### `log_if_slow` — Slow Operation Detection

```elixir
@decorate log_if_slow(threshold: 1000)
def potentially_slow_query(params), do: ...

@decorate log_if_slow(threshold: 500, level: :error, message: "Critical path too slow")
def critical_operation, do: ...
```

### `log_query` — Database Query Logging

```elixir
@decorate log_query(slow_threshold: 500)
def get_user_with_posts(user_id), do: ...

@decorate log_query(level: :info, slow_level: :warning, include_query: true)
def complex_aggregation, do: ...
```

### `log_remote` — Remote Service Logging

```elixir
@decorate log_remote(service: WeatherAPI, async: true)
def get_weather(city), do: WeatherAPI.fetch(city)

@decorate log_remote(service: Stripe, metadata: %{action: :charge})
def charge_card(customer_id, amount), do: ...
```

### `capture_errors` — Error Tracking

```elixir
@decorate capture_errors(reporter: Sentry)
def risky_operation(data), do: ...

@decorate capture_errors(reporter: Sentry, threshold: 3)
def operation_with_retries(data), do: ...
```

### `track_memory` — Memory Monitoring

```elixir
@decorate track_memory(threshold: 10_000_000)  # Warn if >10MB
def memory_intensive_operation(data), do: ...
```

### `benchmark` — Performance Benchmarking

```elixir
@decorate benchmark(iterations: 1000)
def fast_operation(x, y), do: x + y
# Output:
# [BENCHMARK] MyModule.fast_operation/2
# Iterations: 1000
# Average: 0.001ms | Min: 0.000ms | Max: 0.015ms

@decorate benchmark(iterations: 100, warmup: 10, format: :statistical, memory: true)
def complex_operation(data), do: ...
# Includes standard deviation, percentiles, memory usage
```

### `measure` — Simple Timing

```elixir
@decorate measure()
def calculate(x, y), do: x * y
# Output: [MEASURE] MyModule.calculate/2 took 15ms

@decorate measure(unit: :microsecond, label: "DB Query", include_result: true)
def query_database, do: Repo.all(User)
# Output: [MEASURE] DB Query took 1234μs (result: list of 150 items)
```

---

## Security

### `role_required` — Role-Based Access Control

```elixir
# First argument must be the user/context with role info
@decorate role_required(roles: [:admin])
def delete_user(current_user, user_id), do: Repo.delete(User, user_id)

# Multiple roles (any match)
@decorate role_required(roles: [:admin, :moderator], on_error: :return_error)
def ban_user(context, user_id), do: User.ban(user_id)
# Returns {:error, :unauthorized} instead of raising

# Return nil on unauthorized
@decorate role_required(roles: [:admin], on_error: :return_nil)
def get_secrets(user), do: ...

# Custom role check function
@decorate role_required(
  roles: [:owner],
  check_fn: fn user, roles ->
    user.role in roles or user.is_superadmin
  end
)
def sensitive_operation(user, data), do: ...
```

### `rate_limit` — Rate Limiting

```elixir
# Global rate limit
@decorate rate_limit(max: 100, window: :minute)
def public_api_endpoint(params), do: ...

# Per-user rate limit
@decorate rate_limit(max: 10, window: :hour, by: :user_id, on_error: :return_error)
def expensive_operation(user_id, data), do: ...
# Returns {:error, :rate_limited} when exceeded

# Sleep instead of error
@decorate rate_limit(max: 5, window: :second, on_error: :sleep)
def metered_operation(data), do: ...

# Custom key function
@decorate rate_limit(
  max: 50,
  window: :minute,
  by: :custom,
  key_fn: fn [conn | _] -> conn.remote_ip end
)
def api_endpoint(conn, params), do: ...

# Custom backend
@decorate rate_limit(max: 100, window: :minute, backend: MyApp.RedisRateLimiter)
def distributed_endpoint(params), do: ...
```

### `audit_log` — Audit Trail

```elixir
# Basic audit
@decorate audit_log(level: :info)
def update_user(user, attrs), do: ...

# With specific fields and result
@decorate audit_log(level: :critical, fields: [:user_id, :amount], include_result: true)
def transfer_funds(user_id, from_account, to_account, amount), do: ...

# Custom audit store
@decorate audit_log(
  store: ComplianceAuditLog,
  metadata: %{regulation: "SOX", system: "financial"},
  async: true
)
def modify_financial_records(user, changes), do: ...
```

---

## Validation

### `validate_schema` — Input Validation

```elixir
@decorate validate_schema(schema: UserSchema)
def create_user(params), do: ...

@decorate validate_schema(schema: UserSchema, on_error: :raise, strict: true, coerce: true)
def strict_create(params), do: ...
```

### `coerce_types` — Type Coercion

```elixir
@decorate coerce_types(args: [id: :integer, active: :boolean])
def get_user(id, active), do: ...
# "123" → 123, "true" → true

@decorate coerce_types(args: [amount: :float], on_error: :return_error)
def process_payment(amount), do: ...
```

### `serialize` — Result Serialization

```elixir
@decorate serialize(format: :json, only: [:id, :name, :email])
def get_user_json(id), do: Repo.get(User, id)

@decorate serialize(format: :map, except: [:password_hash, :__meta__], rename: [inserted_at: :created_at])
def get_user_map(id), do: ...
```

### `contract` — Design by Contract

```elixir
@decorate contract(
  pre: fn args -> length(args) > 0 end,
  post: fn result -> match?({:ok, _}, result) end,
  invariant: fn -> System.monotonic_time() > 0 end,
  on_error: :raise
)
def process(items), do: ...

# Multiple preconditions
@decorate contract(
  pre: [
    fn [amount | _] -> amount > 0 end,
    fn [_, currency | _] -> currency in [:usd, :eur, :gbp] end
  ]
)
def charge(amount, currency), do: ...
```

---

## Debugging

All debugging decorators are **automatically disabled in production** (`Mix.env() == :prod`).

### `debug` — Use `dbg/2`

```elixir
@decorate debug()
def calculate(x, y) do
  x
  |> add(y)
  |> multiply(2)
end

@decorate debug(label: "User Creation")
def create_user(attrs), do: ...
```

### `inspect` — Examine Arguments and Results

```elixir
@decorate inspect(what: :args)
def process_user(user, attrs), do: ...

@decorate inspect(what: :result, label: "Query Result")
def get_users, do: Repo.all(User)

@decorate inspect(what: :both, opts: [pretty: true, width: 100])
def transform_data(input), do: ...
```

### `pry` — Interactive Breakpoints

```elixir
@decorate pry()
def buggy_function(data), do: ...

# Only pry on errors
@decorate pry(condition: fn result -> match?({:error, _}, result) end)
def process_payment(payment), do: ...

# Pry before function, not after
@decorate pry(before: true, after: false)
def initialize_system(config), do: ...
```

### `trace_vars` — Variable Tracing

```elixir
@decorate trace_vars(vars: [:user, :order, :total])
def process_order(user, order) do
  total = calculate_total(order)
  # Prints values of user, order, total
  ...
end
```

---

## Tracing

Tracing decorators are **automatically disabled in production**.

### `trace_calls` — Function Call Tracing

```elixir
@decorate trace_calls(depth: 3, format: :tree)
def process_order(order), do: ...
# Output:
# ├─ process_order/1
# │  ├─ validate_order/1
# │  ├─ calculate_total/1
# │  │  └─ apply_discount/2
# │  └─ charge_payment/2

@decorate trace_calls(filter: ~r/MyApp\.Orders/, exclude: [:log])
def order_workflow(params), do: ...
```

### `trace_modules` — Module Dependency Tracing

```elixir
@decorate trace_modules(filter: ~r/MyApp/, unique: true, exclude_stdlib: true)
def complex_operation(data), do: ...
# Shows which modules are touched during execution
```

### `trace_dependencies` — Dependency Graph

```elixir
@decorate trace_dependencies(type: :external, format: :graph)
def full_workflow(params), do: ...
# Shows external service dependencies
```

---

## Purity

### `pure` — Pure Function Verification

```elixir
# Documentation only
@decorate pure()
def add(x, y), do: x + y

# Runtime verification — calls function multiple times, checks same result
@decorate pure(verify: true, samples: 10)
def calculate(a, b, c), do: a * b + c

# Strict mode — compile-time analysis for IO, state, etc.
@decorate pure(strict: true)
def transform(data), do: Enum.map(data, &process/1)

# Allow logging in otherwise pure function
@decorate pure(strict: true, allow_io: true)
def process_with_logging(data) do
  Logger.debug("Processing #{length(data)} items")
  Enum.map(data, &transform/1)
end
```

### `deterministic` — Same Input = Same Output

```elixir
@decorate deterministic(samples: 5)
def calculate_discount(price, percentage), do: price * (percentage / 100)

@decorate deterministic(samples: 10, on_failure: :raise)
def hash_data(input), do: :crypto.hash(:sha256, input)
```

### `idempotent` — Multiple Calls = Same Effect

```elixir
@decorate idempotent(calls: 3)
def set_user_status(user_id, status), do: User.update_status(user_id, status)

@decorate idempotent(calls: 5, compare: :deep_equality)
def update_config(key, value), do: Config.set(key, value)

# Custom comparator
@decorate idempotent(
  calls: 3,
  compare: :custom,
  comparator: fn a, b -> a.id == b.id end
)
def upsert_record(attrs), do: ...
```

### `memoizable` — Safe to Cache

Marks a function as safe for memoization:

```elixir
@decorate memoizable()
def fibonacci(0), do: 0
def fibonacci(1), do: 1
def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)

# Verify memoizability at runtime
@decorate memoizable(verify: true, warn_impure: true)
def expensive_calculation(x, y), do: ...
```

---

## Testing

### `with_fixtures` — Fixture Loading

```elixir
@decorate with_fixtures(fixtures: [:user, :organization])
def test_permissions(user, organization) do
  assert authorized?(user, organization)
end

@decorate with_fixtures(fixtures: [:db_connection], cleanup: false)
def test_query(db_connection), do: ...
```

### `sample_data` — Test Data Generation

```elixir
@decorate sample_data(generator: &Faker.Internet.email/0)
def test_email_validation(email), do: assert valid_email?(email)

@decorate sample_data(generator: UserFactory, count: 5)
def test_bulk_operation(users), do: assert length(users) == 5
```

### `timeout_test` — Test Timeouts

```elixir
@decorate timeout_test(timeout: 1000)
def test_fast_operation, do: perform_operation()

@decorate timeout_test(timeout: 5000, on_timeout: :return_error)
def test_slow_operation, do: slow_operation()
```

### `mock` — Simplified Mocking

```elixir
@decorate mock(module: HTTPClient, functions: [get: fn _ -> {:ok, %{status: 200}} end])
def test_api_call, do: ...
```

---

## Composition

### `pipe_through` — Function Pipeline

```elixir
@decorate pipe_through([&validate/1, &transform/1, &persist/1])
def process(data), do: data
```

### `around` — Around Advice (AOP)

```elixir
@decorate around(fn body, args ->
  Logger.info("Before")
  result = body.(args)
  Logger.info("After")
  result
end)
def operation(data), do: ...
```

### `compose` — Decorator Composition

```elixir
@decorate compose([
  {:telemetry_span, [[:my_app, :operation]]},
  {:log_if_slow, [threshold: 1000]},
  {:capture_errors, [reporter: Sentry]}
])
def monitored_operation(data), do: ...
```

#### Reusable Presets with `defpreset`

```elixir
defmodule MyApp.DecoratorPresets do
  use FnDecorator.Compose

  defpreset :monitored do
    [
      {:telemetry_span, [[:my_app, :operation]]},
      {:log_if_slow, [threshold: 1000]},
      {:capture_errors, [reporter: Sentry]}
    ]
  end

  defpreset :cached, opts do
    cache = Keyword.fetch!(opts, :cache)
    [{:cacheable, [cache: cache]}, {:telemetry_span, [[:my_app, :cache]]}]
  end
end

# Usage
@decorate compose(monitored())
def operation(data), do: ...
```

---

## Telemetry Helpers

For non-decorator telemetry instrumentation:

```elixir
defmodule MyApp.Service do
  use FnDecorator.Telemetry.Helpers

  def fetch(id) do
    span [:myapp, :service, :fetch], %{id: id} do
      do_fetch(id)
    end
  end

  def process(data) do
    emit [:myapp, :service, :process], %{}, %{size: byte_size(data)}
    do_process(data)
  end

  def expensive_operation do
    {time_ms, result} = timed(fn -> do_work() end)
    Logger.info("Operation took #{time_ms}ms")
    result
  end
end
```

| Macro/Function | Purpose |
|----------------|---------|
| `span/3`, `span/4` | Wrap code block with start/stop/exception events |
| `emit/3`, `emit/4` | Emit a single telemetry event |
| `timed/2` | Measure execution time in milliseconds |
| `start_span/2` | Manual span start |
| `stop_span/2` | Manual span completion |
| `attach_logger/2` | Attach debug logger to events |

---

## Decorator Order

Decorators are applied **bottom to top** (innermost first):

```elixir
@decorate telemetry_span(...)   # Applied 3rd — outermost wrapper
@decorate cacheable(...)        # Applied 2nd
@decorate returns_result(...)   # Applied 1st — closest to function
def get_user(id), do: ...

# Equivalent to:
def get_user(id) do
  telemetry_span do
    cacheable do
      returns_result do
        Repo.get(User, id)
      end
    end
  end
end
```

**Recommended stacking order:**

```
Outermost (top)  → Observability    telemetry_span, log_call, capture_errors
                 → Security         role_required, rate_limit
                 → Caching          cacheable (skip expensive work)
                 → Audit            audit_log
Inner (bottom)   → Type contracts   returns_result, normalize_result, validate_schema
```

---

## Real-World Examples

### API Controller with Full Instrumentation

```elixir
defmodule MyAppWeb.UserController do
  use Phoenix.Controller
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate telemetry_span([:myapp, :api, :users, :show])
  @decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {:user, id}]))
  @decorate returns_result(ok: User.t(), error: :atom)
  def show(conn, %{"id" => id}) do
    case Users.get(id) do
      {:ok, user} -> render(conn, "show.json", user: user)
      {:error, :not_found} -> send_resp(conn, 404, "Not found")
    end
  end

  @decorate telemetry_span([:myapp, :api, :users, :create])
  @decorate audit_log(level: :info, fields: [:email])
  @decorate rate_limit(max: 10, window: :minute, by: :ip)
  def create(conn, %{"user" => params}) do
    case Users.create(params) do
      {:ok, user} -> conn |> put_status(:created) |> render("show.json", user: user)
      {:error, cs} -> conn |> put_status(422) |> render("error.json", changeset: cs)
    end
  end

  @decorate telemetry_span([:myapp, :api, :users, :delete])
  @decorate cache_evict(cache: MyCache, keys: [{:user, id}])
  @decorate role_required(roles: [:admin])
  @decorate audit_log(level: :critical, fields: [:id])
  def delete(conn, %{"id" => id}, current_user) do
    Users.delete(id)
    send_resp(conn, 204, "")
  end
end
```

### Service Layer with Resilient Caching

```elixir
defmodule MyApp.Accounts do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate telemetry_span([:myapp, :accounts, :get])
  @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
  @decorate returns_result(ok: User.t(), error: :atom)
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @decorate telemetry_span([:myapp, :accounts, :create])
  @decorate cache_evict(cache: MyCache, tags: [:users])
  @decorate audit_log(level: :info, fields: [:email])
  @decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
  def create_user(attrs) do
    %User{} |> User.changeset(attrs) |> Repo.insert()
  end

  @decorate telemetry_span([:myapp, :accounts, :update])
  @decorate cache_put(cache: MyCache, keys: [{User, user.id}])
  @decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
  def update_user(user, attrs) do
    user |> User.changeset(attrs) |> Repo.update()
  end

  @decorate cacheable(Presets.always_fresh(store: [cache: MyCache, key: {:permissions, user_id}]))
  def get_permissions(user_id) do
    Repo.all(from p in Permission, where: p.user_id == ^user_id)
  end
end
```

### External API Client with Fallbacks

```elixir
defmodule MyApp.WeatherService do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate telemetry_span([:myapp, :external, :weather])
  @decorate cacheable(Presets.external_api(
    store: [cache: MyCache, key: {:weather, city}, only_if: &match?({:ok, _}, &1)]
  ))
  @decorate rate_limit(max: 100, window: :minute)
  @decorate capture_errors(reporter: Sentry)
  @decorate returns_result(ok: map(), error: :atom)
  def get_weather(city) do
    case HTTPClient.get("https://api.weather.com/#{city}") do
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.decode!(body)}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: _}} -> {:error, :api_error}
      {:error, _} -> {:error, :network_error}
    end
  end
end
```

### Background Worker

```elixir
defmodule MyApp.Workers.ReportGenerator do
  use Oban.Worker
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @impl Oban.Worker
  @decorate telemetry_span([:myapp, :workers, :report])
  @decorate log_if_slow(threshold: 30_000)
  def perform(%Oban.Job{args: %{"report_id" => report_id}}) do
    generate_report(report_id)
  end

  @decorate cacheable(Presets.expensive(store: [cache: MyCache, key: {:report, report_id}]))
  @decorate normalize_result(wrap_exceptions: true)
  defp generate_report(report_id) do
    report_id |> fetch_data() |> transform_data() |> generate_pdf()
  end
end
```

### Admin Operations with Defense in Depth

```elixir
defmodule MyApp.Admin do
  use FnDecorator

  @decorate telemetry_span([:myapp, :admin, :suspend_user])
  @decorate role_required(roles: [:admin, :superadmin])
  @decorate rate_limit(max: 20, window: :minute, by: :user_id)
  @decorate audit_log(level: :critical, fields: [:user_id, :reason], include_result: true)
  def suspend_user(current_admin, user_id, reason) do
    with {:ok, user} <- Users.get(user_id),
         {:ok, _} <- Users.suspend(user, reason) do
      {:ok, user}
    end
  end

  @decorate role_required(roles: [:superadmin])
  @decorate audit_log(level: :critical, metadata: %{action: "data_export"})
  @decorate rate_limit(max: 5, window: :hour, by: :user_id)
  def export_all_data(current_admin) do
    DataExport.generate_full_export()
  end
end
```

### Pure Calculations with Verification

```elixir
defmodule MyApp.Pricing do
  use FnDecorator

  @decorate pure(strict: true)
  @decorate memoizable()
  @decorate returns_result(ok: Decimal.t(), error: :atom)
  def calculate_total(items) do
    total = items |> Enum.map(& &1.price) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    {:ok, total}
  end

  @decorate deterministic(samples: 5)
  def discount_price(price, percentage) do
    Decimal.mult(price, Decimal.sub(1, Decimal.div(percentage, 100)))
  end

  @decorate idempotent(calls: 3)
  @decorate audit_log(level: :info, fields: [:order_id, :coupon])
  def apply_coupon(order_id, coupon_code) do
    Order.apply_coupon(order_id, coupon_code)
  end
end
```

---

## Telemetry Events Reference

### Cache Events

All prefixed with `[:fn_decorator, :cache]`:

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `:hit` | `%{duration: ns, time: wall}` | `%{key: term, status: :fresh \| :stale}` |
| `:miss` | `%{duration: ns, time: wall}` | `%{key: term}` |
| `:fetch` | `%{duration: ns, time: wall}` | `%{key: term, success: bool}` |
| `:refresh` | `%{duration: ns, time: wall}` | `%{key: term, success: bool, failures: int}` |
| `:lock` | `%{duration: ns, time: wall}` | `%{key: term, result: :acquired \| :timeout \| :lock_freed}` |

### Span Events

Events from `@telemetry_span(event)`:

| Event | Measurements | Notes |
|-------|--------------|-------|
| `event ++ [:start]` | `%{system_time: ns}` | Function entry |
| `event ++ [:stop]` | `%{duration: ns, duration_ms: ms}` | Successful completion |
| `event ++ [:exception]` | `%{duration: ns, kind: atom, reason: term, stacktrace: list}` | Exception raised |

---

## Configuration

```elixir
# config/config.exs
config :fn_decorator,
  telemetry_enabled: true,
  log_level: :info

config :fn_decorator, FnDecorator.Telemetry,
  telemetry_prefix: [:my_app],
  repo: MyApp.Repo

# Optional: distributed lock adapter for multi-node caching
config :fn_decorator, :lock_adapter, MyApp.RedisLock
```

### Lock Adapter Behaviour

For multi-node deployments, implement `FnDecorator.Caching.Lock`:

```elixir
defmodule MyApp.RedisLock do
  @behaviour FnDecorator.Caching.Lock

  @impl true
  def acquire(key, lock_ttl), do: ...

  @impl true
  def release(key, token), do: ...

  @impl true
  def locked?(key), do: ...
end
```

---

## Best Practices

### 1. Use Presets for Caching

```elixir
# Good — clear intent, sensible defaults
@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))

# Avoid — manual config is verbose and error-prone
@decorate cacheable(store: [cache: MyCache, key: {User, id}, ttl: 30_000], serve_stale: [...])
```

### 2. Order Decorators Intentionally

```elixir
# Good — telemetry captures full execution including cache lookup time
@decorate telemetry_span(...)
@decorate cacheable(...)
def get_user(id), do: ...

# Worse — telemetry only measures the post-cache path
@decorate cacheable(...)
@decorate telemetry_span(...)
def get_user(id), do: ...
```

### 3. Be Specific with Types

```elixir
# Good — clear contract
@decorate returns_result(ok: User.t(), error: :not_found | :forbidden)

# Less useful
@decorate returns_result()
```

### 4. Layer Security

```elixir
# Defense in depth
@decorate role_required(roles: [:admin])       # Who can access?
@decorate rate_limit(max: 10, window: :minute) # How often?
@decorate audit_log(level: :warning)           # What happened?
def admin_action(...), do: ...
```

### 5. Cache Only Successes

```elixir
# Don't cache errors
@decorate cacheable(Presets.database(
  store: [cache: MyCache, key: {User, id}, only_if: &match?({:ok, _}, &1)]
))
def get_user(id), do: ...
```

### 6. Use `normalize_result` at Boundaries

```elixir
# At external API boundaries — normalize messy returns
@decorate normalize_result(nil_is_error: true, wrap_exceptions: true)
def fetch_from_legacy_api(id), do: LegacyAPI.get(id)
```

---

## License

MIT
