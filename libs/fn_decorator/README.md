# FnDecorator

A comprehensive decorator library for Elixir with caching, telemetry, debugging, type enforcement, security, and more.

## Installation

```elixir
def deps do
  [{:fn_decorator, "~> 0.1.0"}]
end
```

## Why Decorators?

Decorators let you add cross-cutting concerns to functions without cluttering business logic:

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
- **Separation of concerns** - Business logic stays clean
- **Reusability** - Apply same behavior to many functions
- **Composability** - Stack multiple decorators
- **Testability** - Test concerns in isolation
- **Zero runtime overhead** - Applied at compile time

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

## Decorator Categories

### Caching

Three core caching patterns inspired by Spring Cache:

#### `@cacheable` - Read-Through Caching

```elixir
# Using presets (recommended)
alias FnDecorator.Caching.Presets

@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
def get_user(id), do: Repo.get(User, id)

@decorate cacheable(Presets.high_availability(store: [cache: MyCache, key: {:weather, city}]))
def get_weather(city), do: WeatherAPI.fetch(city)

@decorate cacheable(Presets.external_api(store: [cache: MyCache, key: {:stripe, customer_id}]))
def get_stripe_customer(customer_id), do: Stripe.get_customer(customer_id)

# Full configuration for custom scenarios
@decorate cacheable(
  store: [
    cache: MyCache,
    key: {User, id},
    ttl: :timer.minutes(5),
    only_if: &match?({:ok, _}, &1),
    tags: [:users]
  ],
  serve_stale: [ttl: :timer.hours(1)],
  refresh: [on: :stale_access],
  prevent_thunder_herd: [
    max_wait: :timer.seconds(5),
    lock_ttl: :timer.seconds(30),
    on_timeout: :serve_stale
  ],
  fallback: [on_error: :serve_stale]
)
def get_user(id), do: Repo.get(User, id)
```

**Cache Entry States:**

```
┌─────────┐
│  Fresh  │ ← Within TTL, returned immediately
└────┬────┘
     │ TTL expires
     ▼
┌─────────┐
│  Stale  │ ← TTL expired but within stale_ttl
└────┬────┘   Returned while refreshing in background
     │ stale_ttl expires
     ▼
┌─────────┐
│ Expired │ ← Treated as cache miss
└─────────┘
```

#### `@cache_put` - Write-Through Caching

```elixir
# Always execute, update cache with result
@decorate cache_put(cache: MyCache, keys: [{User, user.id}])
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

# Conditional caching
@decorate cache_put(
  cache: MyCache,
  keys: [{User, user.id}],
  match: fn
    {:ok, user} -> {true, user}
    {:error, _} -> false
  end
)
def update_user(user, attrs), do: ...
```

#### `@cache_evict` - Cache Invalidation

```elixir
# Delete specific key
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
def delete_user(id), do: Repo.delete(User, id)

# Delete by pattern
@decorate cache_evict(cache: MyCache, match: {User, :_})
def clear_user_cache(), do: :ok

# Delete before execution (e.g., logout)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
def logout(token), do: revoke_session(token)

# Conditional eviction
@decorate cache_evict(
  cache: MyCache,
  keys: [{User, id}],
  only_if: &match?({:ok, _}, &1)
)
def update_user(id, attrs), do: ...

# Tag-based eviction
@decorate cache_evict(cache: MyCache, tags: [:users])
def purge_all_users(), do: :ok

# Clear all entries
@decorate cache_evict(cache: MyCache, all_entries: true)
def clear_cache(), do: :ok
```

#### Caching Presets

| Preset | Fresh | Stale | max_wait | Use Case |
|--------|-------|-------|----------|----------|
| `minimal/1` | - | - | default | Full control |
| `database/1` | 30s | 5m | 2s | CRUD reads |
| `session/1` | 1m | - | 1s | Auth/session |
| `high_availability/1` | 1m | 1h | 5s | User-facing |
| `always_fresh/1` | 10s | - | 5s | Feature flags |
| `external_api/1` | 5m | 1h | 30s | Third-party APIs |
| `expensive/1` | 1h | 24h | 60s | Reports |
| `reference_data/1` | 1h | 24h | default | Static data |

```elixir
alias FnDecorator.Caching.Presets

# Each preset can be customized
@decorate cacheable(Presets.database(
  store: [cache: MyCache, key: {User, id}],
  store: [ttl: :timer.minutes(1)]  # Override default TTL
))
def get_user(id), do: ...

# Compose presets
@decorate cacheable(Presets.compose([
  Presets.database([]),
  [store: [cache: MyCache, key: {User, id}]],
  [store: [ttl: :timer.minutes(10)]]
]))
def get_user(id), do: ...
```

---

### Telemetry & Logging

#### `@telemetry_span` - Erlang Telemetry

```elixir
# Basic span
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs), do: ...

# With metadata
@decorate telemetry_span([:my_app, :process], include: [:user_id], metadata: %{source: :api})
def process_data(user_id, data), do: ...
```

**Events Emitted:**
- `[:my_app, :users, :create, :start]` - When function starts
- `[:my_app, :users, :create, :stop]` - When function completes
- `[:my_app, :users, :create, :exception]` - When function raises

#### `@otel_span` - OpenTelemetry

```elixir
@decorate otel_span("user.create")
def create_user(attrs), do: ...

@decorate otel_span("payment.process", include: [:amount, :currency])
def process_payment(amount, currency, card), do: ...
```

#### `@log_call` - Function Call Logging

```elixir
@decorate log_call(level: :info)
def important_operation, do: ...

@decorate log_call(level: :debug, message: "Starting background task")
def background_task(data), do: ...
```

#### `@log_context` - Logger Metadata

```elixir
@decorate log_context([:user_id, :request_id])
def handle_request(user_id, request_id, params) do
  Logger.info("Processing")  # Includes user_id and request_id in metadata
  ...
end
```

#### `@log_if_slow` - Slow Operation Warnings

```elixir
@decorate log_if_slow(threshold: 1000)
def potentially_slow_query(params), do: ...

@decorate log_if_slow(threshold: 500, level: :error, message: "Critical path too slow")
def critical_operation, do: ...
```

#### `@log_query` - Database Query Logging

```elixir
@decorate log_query(slow_threshold: 500)
def get_user_with_posts(user_id), do: ...

@decorate log_query(level: :info, include_query: true)
def complex_aggregation, do: ...
```

#### `@capture_errors` - Error Tracking

```elixir
@decorate capture_errors(reporter: Sentry)
def risky_operation(data), do: ...

@decorate capture_errors(reporter: Sentry, threshold: 3)
def operation_with_retries(data), do: ...
```

#### `@track_memory` - Memory Monitoring

```elixir
@decorate track_memory(threshold: 10_000_000)  # 10MB
def memory_intensive_operation(data), do: ...
```

---

### Type Enforcement

#### `@returns_result` - Result Type

```elixir
@decorate returns_result(ok: User.t(), error: :atom)
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end

# With validation
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t(), validate: true)
def update_user(user, attrs), do: ...

# Strict mode
@decorate returns_result(ok: String.t(), error: :atom, strict: true)
def format_name(user), do: ...
```

#### `@returns_maybe` - Optional/Nullable Type

```elixir
@decorate returns_maybe(type: User.t())
def find_user_by_email(email), do: Repo.get_by(User, email: email)

@decorate returns_maybe(type: String.t(), default: "Unknown")
def get_username(user_id), do: ...
```

#### `@returns_bang` - Bang Variant

```elixir
@decorate returns_bang(type: User.t())
def get_user!(id), do: Repo.get!(User, id)

# Auto-unwrap result tuples
@decorate returns_bang(type: User.t(), on_error: :unwrap)
def create_user!(attrs), do: User.create(attrs)
```

#### `@normalize_result` - Normalize Any Return

```elixir
# Wrap raw values in {:ok, value}
@decorate normalize_result()
def get_user(id), do: Repo.get(User, id)
# Returns: {:ok, %User{}} or {:ok, nil}

# Treat nil as error
@decorate normalize_result(nil_is_error: true)
def get_user(id), do: Repo.get(User, id)
# Returns: {:ok, %User{}} or {:error, :nil_value}

# Wrap exceptions
@decorate normalize_result(wrap_exceptions: true)
def risky_operation, do: raise "Something went wrong"
# Returns: {:error, %RuntimeError{}}

# Transform errors
@decorate normalize_result(error_mapper: fn e -> "Failed: #{inspect(e)}" end)
def fetch_data, do: {:error, :timeout}
# Returns: {:error, "Failed: :timeout"}

# Full configuration
@decorate normalize_result(
  nil_is_error: true,
  false_is_error: true,
  wrap_exceptions: true,
  error_patterns: [:invalid, :not_found, :timeout]
)
def complex_operation, do: ...
```

#### `@returns_struct`, `@returns_list`, `@returns_union`

```elixir
@decorate returns_struct(type: User)
def build_user(attrs), do: struct(User, attrs)

@decorate returns_struct(type: User, nullable: true)
def find_user(id), do: Repo.get(User, id)

@decorate returns_list(of: User.t(), min_length: 1, max_length: 100)
def get_active_users, do: Repo.all(from u in User, where: u.active)

@decorate returns_union(types: [User.t(), Organization.t(), nil])
def find_entity(id), do: find_user(id) || find_org(id)
```

---

### Performance

#### `@benchmark` - Performance Benchmarking

```elixir
@decorate benchmark(iterations: 1000)
def fast_operation(x, y), do: x + y
# Output:
# [BENCHMARK] MyModule.fast_operation/2
# Iterations: 1000
# Average: 0.001ms
# Min: 0.000ms
# Max: 0.015ms

@decorate benchmark(iterations: 100, warmup: 10, format: :statistical, memory: true)
def complex_operation(data), do: ...
# Output includes standard deviation, percentiles, memory usage
```

#### `@measure` - Simple Timing

```elixir
@decorate measure()
def calculate(x, y), do: x * y
# Output: [MEASURE] MyModule.calculate/2 took 15ms

@decorate measure(unit: :microsecond, label: "DB Query")
def query_database, do: Repo.all(User)
# Output: [MEASURE] DB Query took 1234μs

@decorate measure(include_result: true)
def get_users, do: Repo.all(User)
# Output: [MEASURE] MyModule.get_users/0 took 45ms (result: list of 150 items)
```

---

### Debugging

All debugging decorators are automatically disabled in production.

#### `@debug` - Use dbg/2

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

#### `@inspect` - Examine Arguments/Results

```elixir
@decorate inspect(what: :args)
def process_user(user, attrs), do: ...

@decorate inspect(what: :result, label: "Query Result")
def get_users, do: Repo.all(User)

@decorate inspect(what: :both, opts: [pretty: true, width: 100])
def transform_data(input), do: ...
```

#### `@pry` - Interactive Breakpoints

```elixir
@decorate pry()
def buggy_function(data), do: ...

# Conditional pry - only on errors
@decorate pry(condition: fn result -> match?({:error, _}, result) end)
def process_payment(payment), do: ...

@decorate pry(before: true, after: false)
def initialize_system(config), do: ...
```

---

### Purity

#### `@pure` - Pure Function Verification

```elixir
# Documentation only
@decorate pure()
def add(x, y), do: x + y

# Runtime verification
@decorate pure(verify: true, samples: 10)
def calculate(a, b, c), do: a * b + c

# Strict mode (compile warnings)
@decorate pure(strict: true)
def process(data), do: transform(data)

# Allow logging
@decorate pure(strict: true, allow_io: true)
def process_with_logging(data) do
  Logger.debug("Processing")
  transform(data)
end
```

#### `@deterministic` - Same Input = Same Output

```elixir
@decorate deterministic(samples: 10)
def calculate_discount(price, percentage), do: price * (percentage / 100)

@decorate deterministic(samples: 5, on_failure: :raise)
def hash_password(password), do: ...
```

#### `@idempotent` - Multiple Calls = Same Effect

```elixir
@decorate idempotent(calls: 3)
def set_user_status(user_id, status), do: User.update_status(user_id, status)

@decorate idempotent(calls: 5, compare: :deep_equality)
def cache_update(key, value), do: ...
```

#### `@memoizable` - Safe to Cache

```elixir
@decorate memoizable()
def fibonacci(n) when n < 2, do: n
def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)

@decorate memoizable(verify: true)
def expensive_calculation(x, y), do: ...
```

---

### Security

#### `@role_required` - Role-Based Access Control

```elixir
@decorate role_required(roles: [:admin])
def delete_user(current_user, user_id), do: Repo.delete(User, user_id)

@decorate role_required(roles: [:admin, :moderator], on_error: :return_error)
def ban_user(context, user_id), do: User.ban(user_id)

# Custom role check
@decorate role_required(
  roles: [:owner],
  check_fn: fn user, roles ->
    user.role in roles or user.is_superadmin
  end
)
def sensitive_operation(user, data), do: ...
```

#### `@rate_limit` - Rate Limiting

```elixir
@decorate rate_limit(max: 100, window: :minute)
def public_api_endpoint(params), do: ...

@decorate rate_limit(max: 10, window: :hour, by: :user_id, on_error: :return_error)
def expensive_operation(user_id, data), do: ...

# Custom key function
@decorate rate_limit(
  max: 50,
  window: :minute,
  by: :custom,
  key_fn: fn [conn | _] -> conn.remote_ip end
)
def api_endpoint(conn, params), do: ...
```

#### `@audit_log` - Audit Trail

```elixir
@decorate audit_log(level: :critical)
def delete_account(admin_user, account_id), do: Account.delete(account_id)

@decorate audit_log(level: :info, fields: [:user_id, :amount], include_result: true)
def transfer_funds(user_id, from_account, to_account, amount), do: ...

@decorate audit_log(
  store: ComplianceAuditLog,
  metadata: %{regulation: "SOX", system: "financial"}
)
def modify_financial_records(user, changes), do: ...
```

---

### Testing

#### `@with_fixtures` - Fixture Loading

```elixir
@decorate with_fixtures(fixtures: [:user, :organization])
def test_permissions(user, organization) do
  assert authorized?(user, organization)
end

@decorate with_fixtures(fixtures: [:db_connection], cleanup: false)
def test_query(db_connection), do: ...
```

#### `@sample_data` - Data Generation

```elixir
@decorate sample_data(generator: &Faker.Internet.email/0)
def test_email_validation(email) do
  assert valid_email?(email)
end

@decorate sample_data(generator: UserFactory, count: 5)
def test_bulk_operation(users) do
  assert length(users) == 5
end
```

#### `@timeout_test` - Test Timeouts

```elixir
@decorate timeout_test(timeout: 1000)
def test_fast_operation, do: perform_operation()

@decorate timeout_test(timeout: 5000, on_timeout: :return_error)
def test_slow_operation, do: slow_operation()
```

---

## Telemetry Helpers

For consistent instrumentation patterns:

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

**Available Macros/Functions:**

| Macro/Function | Purpose |
|----------------|---------|
| `span/3` | Wrap code with start/stop events |
| `emit/3` | Emit single event |
| `timed/2` | Measure execution time |
| `start_span/2` | Manual span start |
| `stop_span/2` | Manual span completion |
| `attach_logger/2` | Debug event logging |

---

## Decorator Order

Decorators are applied **bottom to top**. The order matters:

```elixir
# This:
@decorate telemetry_span(...)   # Applied 3rd (outermost)
@decorate cacheable(...)        # Applied 2nd
@decorate returns_result(...)   # Applied 1st (closest to function)
def get_user(id), do: ...

# Produces (conceptually):
def get_user(id) do
  telemetry_span do          # Outer wrapper
    cacheable do             # Middle wrapper
      returns_result do      # Inner wrapper
        Repo.get(User, id)   # Original function
      end
    end
  end
end
```

**Recommended Order:**

1. **Outermost** - Telemetry/logging (capture full execution)
2. **Middle** - Caching (before expensive operations)
3. **Inner** - Type enforcement (validate final result)

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
  def create(conn, %{"user" => user_params}) do
    case Users.create(user_params) do
      {:ok, user} ->
        conn |> put_status(:created) |> render("show.json", user: user)
      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render("error.json", changeset: changeset)
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

### Background Worker with Resilient Caching

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
    report_id
    |> fetch_data()
    |> transform_data()
    |> generate_pdf()
  end
end
```

### External API Client with Fallbacks

```elixir
defmodule MyApp.ExternalServices.WeatherAPI do
  use FnDecorator
  alias FnDecorator.Caching.Presets

  @decorate telemetry_span([:myapp, :external, :weather])
  @decorate cacheable(Presets.external_api(
    store: [
      cache: MyCache,
      key: {:weather, city},
      only_if: &match?({:ok, _}, &1)
    ]
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

### Service with Purity Guarantees

```elixir
defmodule MyApp.Calculator do
  use FnDecorator

  @decorate pure(strict: true)
  @decorate memoizable()
  def fibonacci(0), do: 0
  def fibonacci(1), do: 1
  def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)

  @decorate deterministic(samples: 5)
  def discount_price(price, percentage) do
    price * (1 - percentage / 100)
  end

  @decorate idempotent(calls: 3)
  def apply_coupon(order, coupon_code) do
    # Multiple applications should have same effect
    Order.apply_coupon(order, coupon_code)
  end
end
```

### Admin Operations with Security

```elixir
defmodule MyApp.Admin do
  use FnDecorator

  @decorate role_required(roles: [:admin, :superadmin])
  @decorate audit_log(level: :critical, fields: [:user_id, :reason], include_result: true)
  @decorate telemetry_span([:myapp, :admin, :suspend_user])
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
```

---

## Telemetry Events Reference

### Caching Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:fn_decorator, :cache, :hit]` | `%{duration: ns}` | `%{key: ..., status: :fresh/:stale}` |
| `[:fn_decorator, :cache, :miss]` | `%{duration: ns}` | `%{key: ...}` |
| `[:fn_decorator, :cache, :fetch]` | `%{duration: ns}` | `%{key: ..., success: bool}` |
| `[:fn_decorator, :cache, :refresh]` | `%{duration: ns}` | `%{key: ..., success: bool}` |
| `[:fn_decorator, :cache, :lock]` | `%{duration: ns}` | `%{key: ..., result: :acquired/:timeout}` |

### Custom Events

Events from `@telemetry_span`:
- `event ++ [:start]` - Measurements: `%{system_time: ...}`
- `event ++ [:stop]` - Measurements: `%{duration: ..., duration_ms: ...}`
- `event ++ [:exception]` - Measurements + `%{kind: ..., reason: ..., stacktrace: ...}`

---

## Best Practices

### 1. Use Presets for Caching

```elixir
# Good - clear intent
@decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))

# Less clear - manual configuration
@decorate cacheable(store: [cache: MyCache, key: {User, id}, ttl: 30_000], serve_stale: [...])
```

### 2. Order Decorators Intentionally

```elixir
# Good - telemetry captures full execution including cache
@decorate telemetry_span(...)
@decorate cacheable(...)
def get_user(id), do: ...

# Less useful - telemetry only sees cache lookup
@decorate cacheable(...)
@decorate telemetry_span(...)
def get_user(id), do: ...
```

### 3. Be Specific with Types

```elixir
# Good - clear contract
@decorate returns_result(ok: User.t(), error: :not_found | :forbidden)

# Less clear
@decorate returns_result()
```

### 4. Audit Critical Operations

```elixir
# Good - compliance-ready
@decorate audit_log(level: :critical, fields: [:account_id, :amount], include_result: true)
def transfer_funds(...), do: ...
```

### 5. Combine Security Decorators

```elixir
# Defense in depth
@decorate role_required(roles: [:admin])
@decorate rate_limit(max: 10, window: :minute)
@decorate audit_log(level: :warning)
def admin_action(...), do: ...
```

---

## Creating Custom Presets

```elixir
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts \\ []) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      serve_stale: [ttl: :timer.minutes(5)],
      refresh: [on: :stale_access],
      prevent_thunder_herd: [max_wait: :timer.seconds(5)]
    ], opts)
  end

  def critical_config(opts \\ []) do
    Presets.merge(Presets.always_fresh([]), opts)
  end
end

# Usage
@decorate cacheable(MyApp.CachePresets.microservice(store: [cache: MyCache, key: key]))
def get_data(key), do: ...
```

---

## License

MIT
