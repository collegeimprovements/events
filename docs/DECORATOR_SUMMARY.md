# Events Decorator System - Complete Guide

A comprehensive, production-ready decorator system for Elixir with 30+ decorators covering all major use cases.

## Table of Contents

- [Quick Start](#quick-start)
- [All Decorators Overview](#all-decorators-overview)
- [Decorator Categories](#decorator-categories)
  - [1. Caching](#1-caching)
  - [2. Telemetry & Logging](#2-telemetry--logging)
  - [3. Performance](#3-performance)
  - [4. Debugging](#4-debugging-devtest-only)
  - [5. Tracing](#5-tracing-devtest-only)
  - [6. Purity](#6-purity)
  - [7. Testing](#7-testing)
  - [8. Advanced](#8-advanced)
- [Common Patterns](#common-patterns)
- [Best Practices](#best-practices)
- [Architecture](#architecture)

## Quick Start

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate cacheable(cache: MyCache, key: {User, id})
  @decorate telemetry_span([:users, :get])
  @decorate log_if_slow(threshold: 1000)
  def get_user(id) do
    Repo.get(User, id)
  end
end
```

## All Decorators Overview

### Caching (3)
- `cacheable` - Read-through caching
- `cache_put` - Write-through caching
- `cache_evict` - Cache invalidation

### Telemetry & Logging (9)
- `telemetry_span` - Erlang telemetry events
- `otel_span` - OpenTelemetry spans
- `log_call` - Function call logging
- `log_context` - Logger metadata
- `log_if_slow` - Slow operation logging
- `log_query` - Database query logging
- `log_remote` - Remote service logging
- `track_memory` - Memory usage tracking
- `capture_errors` - Error tracking/reporting

### Performance (2)
- `benchmark` - Comprehensive benchmarking
- `measure` - Simple time measurement

### Debugging - Dev/Test Only (4)
- `debug` - Elixir dbg/2 integration
- `inspect` - Inspect args/results
- `pry` - Interactive breakpoints
- `trace_vars` - Variable tracing

### Tracing - Dev/Test Only (3)
- `trace_calls` - Function call tracing
- `trace_modules` - Module usage tracking
- `trace_dependencies` - Dependency tracking

### Purity (4)
- `pure` - Purity verification
- `deterministic` - Determinism checking
- `idempotent` - Idempotence verification
- `memoizable` - Memoization safety marker

### Testing (5)
- `property_test` - Property testing helpers
- `with_fixtures` - Fixture loading
- `sample_data` - Test data generation
- `timeout_test` - Test timeouts
- `mock` - Mocking support

### Advanced (3)
- `pipe_through` - Function pipelines
- `around` - Around advice/AOP
- `compose` - Decorator composition

**Total: 33 decorators**

---

## Decorator Categories

## 1. Caching

### `@cacheable` - Read-Through Caching

**Use Case**: Cache expensive function results

```elixir
@decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
def get_user(id) do
  Repo.get(User, id)
end
```

**Options**:
- `cache:` - Cache module (required)
- `key:` - Explicit cache key
- `ttl:` - Time-to-live in milliseconds
- `match:` - Conditional caching function

**Advanced Example**:
```elixir
# Only cache non-nil results
@decorate cacheable(
  cache: MyCache,
  key: {User, id},
  ttl: :timer.hours(1),
  match: fn
    %User{} = user -> {true, user}
    nil -> false
  end
)
def get_user(id), do: Repo.get(User, id)
```

### `@cache_put` - Write-Through Caching

**Use Case**: Update cache on writes

```elixir
@decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

defp match_ok({:ok, user}), do: {true, user}
defp match_ok(_), do: false
```

### `@cache_evict` - Cache Invalidation

**Use Case**: Clear cache on deletes/updates

```elixir
@decorate cache_evict(cache: MyCache, keys: [{User, id}, {:users, :all}])
def delete_user(id) do
  Repo.delete(User, id)
end
```

---

## 2. Telemetry & Logging

### `@telemetry_span` - Erlang Telemetry

**Use Case**: Instrument with Erlang telemetry

```elixir
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs) do
  Repo.insert(User.changeset(%User{}, attrs))
end
```

**Events Emitted**:
- `[:my_app, :users, :create, :start]`
- `[:my_app, :users, :create, :stop]`
- `[:my_app, :users, :create, :exception]`

### `@log_if_slow` - Slow Operation Logging

**Use Case**: Detect performance regressions

```elixir
@decorate log_if_slow(threshold: 1000, level: :warn)
def complex_query(params) do
  Repo.all(build_complex_query(params))
end
```

### `@log_query` - Database Query Logging

**Use Case**: Log SQL queries with timing

```elixir
@decorate log_query(slow_threshold: 500)
def get_user_with_posts(user_id) do
  User
  |> where(id: ^user_id)
  |> preload(:posts)
  |> Repo.one()
end
```

**Output**:
```
[DEBUG] Query executed in 45ms
[WARN] SLOW QUERY (1234ms): SELECT * FROM users...
```

### `@log_remote` - Remote Logging

**Use Case**: Send logs to Datadog, Logstash, etc.

```elixir
@decorate log_remote(service: DatadogLogger, async: true)
def critical_operation(data) do
  process(data)
end
```

### `@track_memory` - Memory Tracking

**Use Case**: Monitor memory-intensive operations

```elixir
@decorate track_memory(threshold: 10_000_000) # 10MB
def process_large_dataset(data) do
  # Memory-intensive processing
end
```

---

## 3. Performance

### `@benchmark` - Comprehensive Benchmarking

**Use Case**: Performance testing and optimization

```elixir
@decorate benchmark(iterations: 1000, warmup: 10, format: :statistical, memory: true)
def optimized_function(x, y) do
  x * y + calculate_something(x, y)
end
```

**Output**:
```
[BENCHMARK] MyModule.optimized_function/2
  Iterations: 1000
  Average: 0.123ms
  Median: 0.120ms
  Std Dev: 0.015ms
  Min: 0.100ms
  Max: 0.250ms
  95th percentile: 0.145ms
  99th percentile: 0.180ms
  Avg Memory: 2.45KB
```

### `@measure` - Simple Measurement

**Use Case**: Quick timing measurement

```elixir
@decorate measure(unit: :microsecond, label: "DB Query", include_result: true)
def query_database do
  Repo.all(User)
end
```

**Output**: `[MEASURE] DB Query took 1234μs (result: list of 150 items)`

---

## 4. Debugging (Dev/Test Only)

### `@debug` - Elixir dbg/2 Integration

**Use Case**: Detailed pipeline debugging

```elixir
@decorate debug(label: "User Pipeline")
def process_user(user) do
  user
  |> validate()
  |> enrich_data()
  |> save()
end
```

**Output**: Shows each pipeline step with values

### `@inspect` - Argument/Result Inspection

**Use Case**: See what's going in and out

```elixir
@decorate inspect(what: :both, opts: [pretty: true])
def transform_data(input) do
  complex_transformation(input)
end
```

**Options for `what`**:
- `:args` - Inspect arguments only
- `:result` - Inspect result only
- `:both` - Inspect both
- `:all` - Full pipeline inspection

### `@pry` - Interactive Breakpoints

**Use Case**: Debug complex logic interactively

```elixir
@decorate pry(condition: fn result -> result.status == :error end)
def process_payment(payment) do
  PaymentGateway.charge(payment)
end
# Only breaks if payment fails
```

---

## 5. Tracing (Dev/Test Only)

### `@trace_calls` - Function Call Tracing

**Use Case**: Understand execution flow

```elixir
@decorate trace_calls(depth: 2, filter: ~r/MyApp\./, format: :tree)
def complex_workflow(data) do
  step_1(data)
  |> step_2()
  |> step_3()
end
```

**Output**:
```
[TRACE CALLS] MyApp.Workflow.complex_workflow/1
  ↳ MyApp.Workflow.step_1/1
  ↳ MyApp.Workflow.step_2/1
    ↳ MyApp.Helper.validate/1
  ↳ MyApp.Workflow.step_3/1
```

### `@trace_modules` - Module Usage Tracking

**Use Case**: Find hidden dependencies

```elixir
@decorate trace_modules(filter: ~r/^MyApp\.Services/)
def api_call(endpoint) do
  # Shows all MyApp.Services.* modules called
  process(endpoint)
end
```

---

## 6. Purity

### `@pure` - Purity Verification

**Use Case**: Ensure functional purity

```elixir
@decorate pure(verify: true, strict: true, samples: 10)
def calculate_discount(price, percentage) do
  price * (percentage / 100)
end
```

**Detects**:
- IO operations
- Process state changes
- Non-deterministic results
- Side effects

### `@deterministic` - Determinism Checking

**Use Case**: Verify consistent results

```elixir
@decorate deterministic(samples: 5, on_failure: :raise)
def hash_value(input) do
  :crypto.hash(:sha256, input)
end
```

### `@idempotent` - Idempotence Verification

**Use Case**: Test safe repeated calls

```elixir
@decorate idempotent(calls: 3, compare: :equality)
def update_user_status(user_id, status) do
  User.update_status(user_id, status)
end
```

---

## 7. Testing

### `@property_test` - Property Testing

**Use Case**: Property-based testing

```elixir
@decorate property_test(runs: 100)
def test_addition_commutative(a, b) when is_integer(a) and is_integer(b) do
  assert add(a, b) == add(b, a)
end
```

### `@with_fixtures` - Fixture Management

**Use Case**: Automatic fixture loading

```elixir
@decorate with_fixtures(fixtures: [:user, :organization])
def test_permissions(user, organization) do
  assert can_access?(user, organization)
end
```

### `@timeout_test` - Test Timeouts

**Use Case**: Prevent hanging tests

```elixir
@decorate timeout_test(timeout: 5000, on_timeout: :raise)
def test_async_operation do
  perform_async_task()
end
```

---

## 8. Advanced

### `@pipe_through` - Function Pipelines

**Use Case**: Transform results through pipeline

```elixir
@decorate pipe_through([
  &String.trim/1,
  &String.upcase/1,
  &validate/1
])
def get_name(user) do
  user.name
end
```

### `@around` - Around Advice (AOP)

**Use Case**: Wrap with custom behavior

```elixir
@decorate around(&RetryHelper.with_retry/2)
def call_external_api(endpoint) do
  HTTPClient.get(endpoint)
end

defmodule RetryHelper do
  def with_retry(decorated_fn, endpoint, max \\ 3) do
    Enum.reduce_while(1..max, nil, fn attempt, _ ->
      case decorated_fn.(endpoint) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _} when attempt < max -> {:cont, nil}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
```

### `@compose` - Decorator Composition

**Use Case**: Reusable decorator combinations

```elixir
@decorate compose([
  {:cacheable, [cache: MyCache, key: id]},
  {:telemetry_span, [[:app, :get]]},
  {:log_if_slow, [threshold: 1000]},
  {:track_memory, [threshold: 5_000_000]}
])
def get_data(id) do
  expensive_operation(id)
end

# Or define reusable compositions
defmodule MyDecorators do
  def monitored_cache(key) do
    [
      {:cacheable, [cache: MyCache, key: key]},
      {:telemetry_span, [[:app, :cache]]},
      {:log_if_slow, [threshold: 500]}
    ]
  end
end

@decorate compose(MyDecorators.monitored_cache({User, id}))
def get_user(id), do: Repo.get(User, id)
```

---

## Common Patterns

### Pattern 1: Monitored Cache Read

```elixir
@decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
@decorate telemetry_span([:app, :users, :get])
@decorate log_if_slow(threshold: 1000)
@decorate track_memory(threshold: 5_000_000)
def get_user(id) do
  Repo.get(User, id)
end
```

### Pattern 2: Safe Cache Write

```elixir
@decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
@decorate telemetry_span([:app, :users, :update])
@decorate log_call(:info)
def update_user(user, attrs) do
  user
  |> User.changeset(attrs)
  |> Repo.update()
end

defp match_ok({:ok, user}), do: {true, user}
defp match_ok(_), do: false
```

### Pattern 3: Resilient API Call

```elixir
@decorate around(&RetryHelper.with_retry/2)
@decorate telemetry_span([:app, :external_api, :call])
@decorate log_if_slow(threshold: 5000)
@decorate capture_errors(reporter: Sentry)
def call_external_api(endpoint) do
  HTTPClient.get(endpoint)
end
```

### Pattern 4: Development Debugging

```elixir
if Mix.env() == :dev do
  @decorate debug()
  @decorate inspect(what: :both)
  @decorate trace_calls(depth: 2)
end

@decorate pure(verify: true)
def complex_calculation(x, y, z) do
  # Complex logic here
end
```

### Pattern 5: Performance Testing

```elixir
@decorate benchmark(
  iterations: 1000,
  warmup: 100,
  format: :statistical,
  memory: true
)
@decorate pure(verify: true)
def optimized_algorithm(data) do
  # Your optimized code
end
```

---

## Best Practices

### 1. Decorator Order Matters

Decorators are applied **bottom to top**:

```elixir
@decorate log_call()       # Applied LAST (outermost)
@decorate cacheable(...)   # Applied SECOND
@decorate telemetry_span() # Applied FIRST (innermost)
def my_function, do: ...
```

**Execution flow**:
1. `log_call` logs entry
2. `cacheable` checks cache
3. If cache miss, `telemetry_span` wraps execution
4. Function body runs

### 2. Environment-Specific Decorators

Use conditional compilation for debug decorators:

```elixir
if Mix.env() in [:dev, :test] do
  @decorate debug()
  @decorate pry()
  @decorate trace_calls()
end

@decorate cacheable(cache: MyCache, key: id)
def get_data(id), do: ...
```

### 3. Composition for Reusability

Define common patterns once:

```elixir
defmodule MyDecorators do
  def standard_query(key) do
    [
      {:cacheable, [cache: MyCache, key: key, ttl: 3600]},
      {:telemetry_span, [[:app, :query]]},
      {:log_if_slow, [threshold: 1000]},
      {:log_query, [slow_threshold: 500]}
    ]
  end
end

@decorate compose(MyDecorators.standard_query({User, id}))
def get_user(id), do: Repo.get(User, id)
```

### 4. Match Functions for Conditional Caching

```elixir
# Cache only successful results
defp match_ok({:ok, result}), do: {true, result}
defp match_ok({:error, _}), do: false

# Cache with transformation
defp match_and_slim({:ok, user}) do
  slim_user = Map.take(user, [:id, :email, :name])
  {true, slim_user}
end
defp match_and_slim(_), do: false

@decorate cacheable(cache: MyCache, key: id, match: &match_and_slim/1)
def get_user_full(id), do: Repo.get(User, id) |> Repo.preload(:all_associations)
```

### 5. Purity for Critical Functions

```elixir
@decorate pure(verify: true, strict: true)
@decorate deterministic(samples: 10)
@decorate memoizable()
def calculate_price(base, tax_rate, discount) do
  base * (1 + tax_rate) * (1 - discount)
end
```

### 6. Comprehensive Monitoring

```elixir
@decorate compose([
  {:cacheable, [cache: MyCache, key: id]},
  {:telemetry_span, [[:app, :critical, :operation]]},
  {:otel_span, ["critical.operation"]},
  {:log_if_slow, [threshold: 500]},
  {:log_remote, [service: DatadogLogger]},
  {:track_memory, [threshold: 10_000_000]},
  {:capture_errors, [reporter: Sentry]}
])
def critical_business_operation(id) do
  # Critical code
end
```

---

## Architecture

### Module Structure

```
lib/events/
├── decorator/
│   ├── decorator.ex              # Main entry point
│   ├── define.ex                 # Decorator registry
│   ├── ast.ex                    # AST utilities
│   ├── context.ex                # Context struct
│   │
│   ├── caching/
│   │   ├── decorators.ex         # Caching decorators
│   │   └── helpers.ex            # Caching utilities
│   │
│   ├── telemetry/
│   │   ├── decorators.ex         # Telemetry decorators
│   │   └── helpers.ex            # Telemetry utilities
│   │
│   ├── debugging/
│   │   ├── decorators.ex         # Debugging decorators
│   │   └── helpers.ex            # Debugging utilities
│   │
│   ├── tracing/
│   │   ├── decorators.ex         # Tracing decorators
│   │   └── helpers.ex            # Tracing utilities
│   │
│   ├── purity/
│   │   ├── decorators.ex         # Purity decorators
│   │   └── helpers.ex            # Purity utilities
│   │
│   ├── testing/
│   │   ├── decorators.ex         # Testing decorators
│   │   └── helpers.ex            # Testing utilities
│   │
│   └── pipeline/
│       ├── decorators.ex         # Pipeline decorators
│       └── helpers.ex            # Pipeline utilities
│
└── cache.ex                      # Nebulex cache module
```

### Design Principles

1. **Pattern Matching Everywhere** - All AST operations use pattern matching
2. **Composability** - Decorators can be stacked and composed
3. **Type Safety** - NimbleOptions validates all options at compile time
4. **Clean Code** - Clear module boundaries, helper utilities
5. **Context-Driven** - Rich context passed to all decorators
6. **Zero Runtime Overhead** - Compile-time transformations only
7. **Environment-Aware** - Debug decorators auto-disabled in production

### How It Works

1. **Definition**: `use Events.Decorator.Define` registers decorators
2. **Application**: `@decorate decorator_name(opts)` applies to function
3. **Transformation**: Decorator receives `(opts, body, context)`
4. **AST Modification**: Decorator returns transformed AST
5. **Compilation**: Modified code is compiled

---

## Performance Considerations

- **Compile-time**: All decorators applied at compile time
- **Runtime overhead**: Only from actual operations (cache lookups, logging, etc.)
- **Debug decorators**: Automatically disabled in production
- **Caching**: Near-zero overhead on cache hits
- **Telemetry**: Minimal overhead (~microseconds per event)
- **Benchmarking**: Use only in dev/test environments

---

## Migration Guide

### From Raw Caching to Decorators

**Before**:
```elixir
def get_user(id) do
  case MyCache.get({User, id}) do
    nil ->
      result = Repo.get(User, id)
      MyCache.put({User, id}, result)
      result
    cached -> cached
  end
end
```

**After**:
```elixir
@decorate cacheable(cache: MyCache, key: {User, id})
def get_user(id) do
  Repo.get(User, id)
end
```

### From Manual Telemetry to Decorators

**Before**:
```elixir
def create_user(attrs) do
  start = System.monotonic_time()

  result = Repo.insert(User.changeset(%User{}, attrs))

  duration = System.monotonic_time() - start
  :telemetry.execute([:app, :user, :create], %{duration: duration}, %{})

  result
end
```

**After**:
```elixir
@decorate telemetry_span([:app, :user, :create])
def create_user(attrs) do
  Repo.insert(User.changeset(%User{}, attrs))
end
```

---

## Troubleshooting

### Decorator Not Working

1. Check you have `use Events.Decorator` in your module
2. Verify decorator name is correct (check `Events.Decorator.Define`)
3. Ensure options are valid (NimbleOptions will raise compile errors)
4. Check decorator order (they apply bottom-to-top)

### Cache Not Working

1. Verify cache module is started in your supervision tree
2. Check key generation is consistent
3. Use `match` function to debug what's being cached
4. Ensure TTL is reasonable

### Performance Issues

1. Remove debug decorators in production
2. Check cache hit rate
3. Use `benchmark` decorator to identify bottlenecks
4. Consider async operations for remote logging

---

## Future Enhancements

Potential additions:
- Rate limiting decorator
- Circuit breaker decorator
- Async/await decorator
- Validation decorator
- Authorization decorator
- Database transaction decorator
- Saga pattern decorator

---

## Contributing

When adding new decorators:

1. Create decorator in appropriate module (`Caching`, `Telemetry`, etc.)
2. Add NimbleOptions schema for validation
3. Implement decorator function
4. Add to `Events.Decorator.Define`
5. Add comprehensive documentation with examples
6. Update this guide

---

## License

Internal to Events application.

## Questions?

- Check inline documentation: `h Events.Decorator.Caching.cacheable`
- Review examples in `lib/events/accounts.ex`
- See detailed docs in each decorator module
