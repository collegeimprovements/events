# Events Decorator System Reference

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Architecture](#architecture)
4. [Decorator Categories](#decorator-categories)
5. [Composition Patterns](#composition-patterns)
6. [Best Practices](#best-practices)
7. [API Reference](#api-reference)

## Overview

The Events decorator system provides a clean, composable way to add cross-cutting concerns to functions using the `@decorate` attribute. All decorators are applied at compile-time, resulting in zero runtime overhead for the decorator mechanism itself.

### Key Features

- **40+ decorators** across 11 categories
- **Compile-time code generation** - no runtime overhead
- **NimbleOptions validation** - type-safe configuration
- **Composable** - multiple decorators work together seamlessly
- **Environment-aware** - debug decorators auto-disable in production

## Quick Start

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  # Simple caching
  @decorate cacheable(cache: MyCache, key: id, ttl: 3600)
  def get_user(id), do: Repo.get(User, id)

  # Multiple decorators (applied bottom-to-top)
  @decorate log_if_slow(threshold: 1000)        # 3rd: outermost
  @decorate telemetry_span([:app, :users, :get]) # 2nd
  @decorate cacheable(cache: MyCache, key: id)   # 1st: innermost
  def get_user_with_telemetry(id), do: Repo.get(User, id)
end
```

## Architecture

```
┌─────────────────────────────────────────┐
│      User Code (@decorate attribute)    │
├─────────────────────────────────────────┤
│  Events.Infra.Decorator (Entry Point)         │
├─────────────────────────────────────────┤
│  Events.Infra.Decorator.Define (Registration) │
├─────────────────────────────────────────┤
│  Category Modules (Implementation)      │
│  - Caching, Telemetry, Debugging, etc.  │
├─────────────────────────────────────────┤
│  Events.Infra.Decorator.Shared (Utilities)    │
└─────────────────────────────────────────┘
```

### Execution Order

Decorators are applied **bottom-to-top** (closest to function = innermost):

```elixir
@decorate third()   # Applied last (outermost wrapper)
@decorate second()  # Applied second
@decorate first()   # Applied first (innermost wrapper)
def my_func, do: body
```

**Execution flow:** `third → second → first → body → first → second → third`

## Decorator Categories

### 1. Caching Decorators

#### `cacheable/1` - Read-through caching

```elixir
@decorate cacheable(
  cache: MyCache,           # Required: cache module
  key: {User, id},          # Cache key (can use variables)
  ttl: 3600,                # Time-to-live in seconds
  match: &match_success/1   # Only cache if match returns true
)
def get_user(id), do: Repo.get(User, id)

defp match_success(%User{}), do: true
defp match_success(nil), do: false
```

#### `cache_put/1` - Write-through caching

```elixir
@decorate cache_put(
  cache: MyCache,
  keys: [{User, user.id}, {User, user.email}],  # Multiple keys
  ttl: 3600,
  match: &match_ok/1
)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

defp match_ok({:ok, user}), do: {true, user}
defp match_ok(_), do: false
```

#### `cache_evict/1` - Cache invalidation

```elixir
@decorate cache_evict(
  cache: MyCache,
  keys: [{User, id}],
  before_invocation: true   # Evict before function runs (safer)
)
def delete_user(id), do: Repo.delete(User, id)
```

---

### 2. Telemetry & Observability Decorators

#### `telemetry_span/1,2` - Erlang telemetry events

```elixir
# Emits [:app, :users, :get, :start], [:app, :users, :get, :stop]
@decorate telemetry_span([:app, :users, :get])
def get_user(id), do: Repo.get(User, id)

# With variable capture
@decorate telemetry_span([:app, :process], include: [:user_id, :result])
def process(user_id, data), do: {:ok, transform(data)}
```

#### `otel_span/1,2` - OpenTelemetry distributed tracing

```elixir
@decorate otel_span("user.create")
def create_user(attrs), do: Repo.insert(User.changeset(%User{}, attrs))

@decorate otel_span("payment.process", include: [:amount, :currency])
def process_payment(amount, currency, card), do: charge(amount, currency, card)
```

#### `log_call/1` - Function call logging

```elixir
@decorate log_call(level: :info, message: "Creating user")
def create_user(attrs), do: Repo.insert(User.changeset(%User{}, attrs))
```

#### `log_context/1` - Set Logger metadata

```elixir
@decorate log_context([:user_id, :request_id])
def handle_request(user_id, request_id, params) do
  Logger.info("Processing")  # Includes user_id and request_id
  process(params)
end
```

#### `log_if_slow/1` - Slow operation monitoring

```elixir
@decorate log_if_slow(threshold: 1000, level: :warn)
def potentially_slow_query(params), do: Repo.all(complex_query(params))
```

#### `track_memory/1` - Memory usage monitoring

```elixir
@decorate track_memory(threshold: 10_000_000)  # 10MB
def memory_intensive_operation(data), do: process_large_dataset(data)
```

#### `capture_errors/1` - Error reporting (Sentry, etc.)

```elixir
@decorate capture_errors(reporter: Sentry, threshold: 1)
def risky_operation(data), do: external_api_call(data)
```

#### `benchmark/1` - Performance benchmarking

```elixir
@decorate benchmark(iterations: 1000, format: :statistical, memory: true)
def fast_operation(x, y), do: x + y

# Output:
# [BENCHMARK] MyModule.fast_operation/2
#   Iterations: 1000
#   Average: 0.001ms, Median: 0.001ms, Std Dev: 0.002ms
#   Min: 0.000ms, Max: 0.015ms
#   95th: 0.005ms, 99th: 0.010ms
```

#### `measure/1` - Simple timing measurement

```elixir
@decorate measure(unit: :millisecond, label: "DB Query")
def query_database, do: Repo.all(User)
# Output: [MEASURE] DB Query took 15ms
```

---

### 3. Debugging Decorators (Dev/Test Only)

These decorators automatically disable in production.

#### `debug/1` - Elixir dbg integration

```elixir
@decorate debug(label: "User Pipeline")
def process_user(user) do
  user
  |> validate()
  |> transform()
  |> persist()
end
```

#### `inspect/1` - Inspect arguments/results

```elixir
@decorate inspect(what: :both, opts: [pretty: true, width: 100])
def transform_data(input), do: complex_transformation(input)
```

#### `pry/1` - Interactive breakpoints

```elixir
# Conditional pry - only on errors
@decorate pry(condition: fn result -> match?({:error, _}, result) end)
def process_payment(payment), do: PaymentGateway.charge(payment)
```

---

### 4. Purity Decorators (Dev/Test Only)

#### `pure/1` - Mark and verify function purity

```elixir
@decorate pure(verify: true, samples: 10)
def calculate(a, b, c), do: a * b + c
```

#### `deterministic/1` - Verify deterministic behavior

```elixir
@decorate deterministic(samples: 5, on_failure: :raise)
def hash_value(input), do: :crypto.hash(:sha256, input)
```

#### `idempotent/1` - Verify idempotence

```elixir
@decorate idempotent(calls: 3)
def set_status(user_id, status), do: User.update_status(user_id, status)
```

---

### 5. Pipeline & Composition Decorators

#### `pipe_through/1` - Function pipeline

```elixir
@decorate pipe_through([
  &validate_input/1,
  &transform_data/1,
  &persist_to_db/1
])
def process_data(raw_data), do: raw_data
```

#### `around/1` - Around advice (AOP)

```elixir
@decorate around(&check_authorization/2)
def delete_user(user_id), do: Repo.delete(User, user_id)

defp check_authorization(decorated_fn, user_id) do
  if current_user_is_admin?() do
    decorated_fn.(user_id)
  else
    {:error, :unauthorized}
  end
end
```

#### `compose/1` - Dynamic decorator composition

```elixir
defmodule MyDecorators do
  def observable_cached(cache_key) do
    [
      {:log_if_slow, [threshold: 1000]},
      {:telemetry_span, [[:app, :cache, :access]]},
      {:cacheable, [cache: MyCache, key: cache_key]}
    ]
  end
end

@decorate compose(MyDecorators.observable_cached({User, user_id}))
def get_user(user_id), do: Repo.get(User, user_id)
```

---

### 6. Security Decorators

#### `role_required/1` - Role-based access control

```elixir
@decorate role_required(roles: [:admin, :moderator])
def admin_action(resource_id), do: delete_resource(resource_id)
```

#### `rate_limit/1` - Rate limiting

```elixir
@decorate rate_limit(max: 100, window: :minute, by: :user_id)
def api_endpoint(user_id, params), do: process(params)
```

#### `audit_log/1` - Audit logging for compliance

```elixir
@decorate audit_log(level: :critical, fields: [:user_id, :action])
def sensitive_operation(user_id, action, data), do: perform(action, data)
```

---

### 7. Validation Decorators

#### `validate_schema/1` - Schema validation

```elixir
@decorate validate_schema(
  schema: %{
    name: [type: :string, required: true],
    age: [type: :integer, min: 18]
  },
  on_error: :return_error
)
def process_adult(data), do: process(data)
```

---

### 8. Testing Decorators

#### `with_fixtures/1` - Automatic fixture loading

```elixir
@decorate with_fixtures(fixtures: [:user, :organization])
def test_permissions(user, organization) do
  assert can_access?(user, organization)
end
```

#### `timeout_test/1` - Test timeout enforcement

```elixir
@decorate timeout_test(timeout: 5000, on_timeout: :raise)
def test_slow_operation, do: potentially_slow_test()
```

---

## Composition Patterns

### Pattern 1: Layered Caching + Observability

```elixir
@decorate capture_errors(reporter: Sentry)       # 4th: error tracking
@decorate log_if_slow(threshold: 500)            # 3rd: performance monitoring
@decorate telemetry_span([:app, :users, :get])   # 2nd: telemetry
@decorate cacheable(cache: MyCache, key: id)     # 1st: caching
def get_user(id), do: Repo.get(User, id)
```

### Pattern 2: Reusable Decorator Compositions

```elixir
defmodule MyApp.Decorators do
  def monitored_query(event, cache_opts) do
    [
      {:capture_errors, [reporter: Sentry]},
      {:log_if_slow, [threshold: 1000]},
      {:telemetry_span, [event]},
      {:cacheable, cache_opts}
    ]
  end
end

defmodule MyApp.Users do
  use Events.Decorator

  @decorate compose(MyApp.Decorators.monitored_query(
    [:app, :users, :get],
    [cache: MyCache, key: {User, id}, ttl: 3600]
  ))
  def get_user(id), do: Repo.get(User, id)
end
```

### Pattern 3: Authorization Wrapper

```elixir
defmodule MyApp.AdminActions do
  use Events.Decorator

  @decorate around(&require_admin/2)
  @decorate audit_log(level: :critical, fields: [:admin_id, :user_id])
  def delete_user(admin_id, user_id), do: Repo.delete(User, user_id)

  defp require_admin(decorated_fn, admin_id, user_id) do
    if admin?(admin_id) do
      decorated_fn.(admin_id, user_id)
    else
      {:error, :forbidden}
    end
  end
end
```

### Pattern 4: Development-Only Debugging

```elixir
defmodule MyApp.DataProcessor do
  use Events.Decorator

  if Mix.env() in [:dev, :test] do
    @decorate debug()
    @decorate inspect(what: :both)
  end

  @decorate log_if_slow(threshold: 1000)
  def process(data), do: transform(data)
end
```

---

## Best Practices

### 1. Order Decorators by Concern

```elixir
# Recommended order (outermost to innermost):
@decorate capture_errors(...)     # Error handling (outermost)
@decorate log_if_slow(...)        # Performance monitoring
@decorate telemetry_span(...)     # Observability
@decorate cacheable(...)          # Caching (innermost, before business logic)
def my_function(args), do: body
```

### 2. Use Match Functions for Conditional Caching

```elixir
@decorate cacheable(cache: MyCache, key: id, match: &cache_if_found/1)
def get_user(id), do: Repo.get(User, id)

# Only cache successful results
defp cache_if_found(%User{} = user), do: {true, user}
defp cache_if_found(nil), do: false
```

### 3. Compose Reusable Patterns

```elixir
# Define once
defmodule MyApp.Decorators do
  def api_endpoint(event) do
    [
      {:rate_limit, [max: 100, window: :minute]},
      {:capture_errors, [reporter: Sentry]},
      {:telemetry_span, [event]}
    ]
  end
end

# Use everywhere
@decorate compose(MyApp.Decorators.api_endpoint([:api, :users, :list]))
def list_users(params), do: query_users(params)
```

### 4. Use Appropriate Cache Keys

```elixir
# Good: Specific, includes relevant identifiers
@decorate cacheable(cache: MyCache, key: {User, id})
@decorate cacheable(cache: MyCache, key: {Organization, org_id, :members})

# Avoid: Too generic
@decorate cacheable(cache: MyCache, key: :users)
```

### 5. Set Appropriate TTLs

```elixir
# Short TTL for frequently changing data
@decorate cacheable(cache: MyCache, key: {Stats, id}, ttl: 60)

# Longer TTL for stable data
@decorate cacheable(cache: MyCache, key: {Config, id}, ttl: 3600)
```

---

## API Reference

### Cache Module Interface

Your cache module must implement:

```elixir
@callback get(key :: term()) :: term() | nil
@callback put(key :: term(), value :: term(), opts :: keyword()) :: :ok
@callback delete(key :: term()) :: :ok
@callback delete_all() :: :ok  # Only needed for all_entries: true
```

### Error Handling Strategies

Most decorators support `on_error` option:

| Strategy | Behavior |
|----------|----------|
| `:raise` | Raise exception (default) |
| `:nothing` | Return nil, continue |
| `:return_error` | Return `{:error, reason}` |
| `:ignore` | Ignore error, return original result |
| `:log` | Log error, continue |

### Common Options

| Option | Type | Description |
|--------|------|-------------|
| `cache:` | module | Cache module to use |
| `key:` | term | Cache key (can include variables) |
| `ttl:` | integer | Time-to-live in seconds |
| `match:` | function | Conditional function |
| `on_error:` | atom | Error handling strategy |
| `include:` | list | Variables to capture in metadata |

---

## Troubleshooting

### Decorator Not Applied

Ensure you have `use Events.Infra.Decorator` at the top of your module:

```elixir
defmodule MyApp.Users do
  use Events.Infra.Decorator  # Required!

  @decorate cacheable(...)
  def get_user(id), do: ...
end
```

### Cache Key Not Working

Variables in cache keys must be function arguments:

```elixir
# Works - id is a function argument
@decorate cacheable(cache: MyCache, key: {User, id})
def get_user(id), do: ...

# Doesn't work - computed_key is not an argument
@decorate cacheable(cache: MyCache, key: computed_key)
def get_user(id) do
  computed_key = compute_key(id)
  ...
end
```

### Debugging Decorator Issues

Use `inspect` to see what's happening:

```elixir
@decorate inspect(what: :both)
@decorate cacheable(cache: MyCache, key: id)
def get_user(id), do: Repo.get(User, id)
```

---

## Performance Considerations

| Decorator | Overhead |
|-----------|----------|
| `cacheable` | Cache lookup + optional put |
| `telemetry_span` | `:telemetry.span/3` call |
| `log_*` | Logger call (async by default) |
| `measure` | 2x `System.monotonic_time/0` |
| `debug/inspect/pry` | Significant (dev only) |
| `benchmark` | Multiple iterations (dev only) |

**Tips:**
- Debug decorators auto-disable in production
- Cache decorators should be innermost (closest to function)
- Telemetry overhead is minimal (~microseconds)
