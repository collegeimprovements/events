# Events Decorator System - Complete Reference Guide

## Quick Decision Table: What Decorator to Use When?

| **When You Want To...** | **Use This Decorator** | **Key Options** |
|-------------------------|------------------------|-----------------|
| **CACHING & PERFORMANCE** |
| Cache expensive operations | `@decorate cacheable(cache: MyCache, ttl: 3600)` | cache, key, ttl, match |
| Update cache after mutations | `@decorate cache_put(cache: MyCache, keys: [key])` | cache, keys, ttl |
| Invalidate cache entries | `@decorate cache_evict(cache: MyCache, keys: [key])` | cache, keys, before_invocation |
| **MONITORING & OBSERVABILITY** |
| Add telemetry events | `@decorate telemetry_span([:app, :operation])` | event, include, metadata |
| Add OpenTelemetry spans | `@decorate otel_span("operation.name")` | name, include, attributes |
| Log function calls | `@decorate log_call(level: :info)` | level, message, metadata |
| Add context to logs | `@decorate log_context([:user_id, :request_id])` | fields |
| Detect slow operations | `@decorate log_if_slow(threshold: 1000)` | threshold, level |
| Monitor memory usage | `@decorate track_memory(threshold: 10_000_000)` | threshold, level |
| Track errors in Sentry/etc | `@decorate capture_errors(reporter: Sentry)` | reporter, threshold |
| Log database queries | `@decorate log_query(slow_threshold: 500)` | slow_threshold, include_query |
| Send logs to external service | `@decorate log_remote(service: DatadogLogger)` | service, async, metadata |
| Benchmark performance | `@decorate benchmark(iterations: 1000)` | iterations, warmup, format |
| Measure execution time | `@decorate measure(unit: :millisecond)` | unit, label |
| **DEBUGGING** |
| Debug with dbg/2 | `@decorate debug()` | label, opts |
| Inspect values | `@decorate inspect(what: :both)` | what, label, opts |
| Add breakpoints | `@decorate pry(before: true)` | condition, before, after |
| Document trace points | `@decorate trace_vars(vars: [:x, :y])` | vars |
| **FUNCTION PURITY** |
| Mark/verify pure functions | `@decorate pure(verify: true)` | verify, strict, samples |
| Check determinism | `@decorate deterministic(samples: 5)` | samples, on_failure |
| Verify idempotency | `@decorate idempotent(calls: 3)` | calls, compare |
| Check memoization safety | `@decorate memoizable()` | verify, warn_impure |
| **COMPOSITION & FLOW** |
| Chain transformations | `@decorate pipe_through([&trim/1, &upcase/1])` | steps |
| Wrap with custom logic | `@decorate around(&wrapper_function/2)` | wrapper |
| Apply multiple decorators | `@decorate compose([{:cacheable, opts}, ...])` | decorators |
| **TESTING** |
| Load test fixtures | `@decorate with_fixtures(fixtures: [:user])` | fixtures, cleanup |
| Generate test data | `@decorate sample_data(generator: Faker)` | generator, count |
| Set test timeout | `@decorate timeout_test(timeout: 5000)` | timeout, on_timeout |
| Mock dependencies | `@decorate mock(module: API, functions: [...])` | module, functions |
| **TRACING & ANALYSIS** |
| Trace execution flow | `@decorate trace_calls(depth: 2)` | depth, filter, format |
| List called modules | `@decorate trace_modules()` | filter, unique |
| Track dependencies | `@decorate trace_dependencies(type: :external)` | type, format |

## Comprehensive Decorator List

### Caching Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `cacheable/1` | Events.Decorator.Caching | Read-through cache | `cache` | `key`, `key_generator`, `ttl`, `match`, `on_error` | All |
| `cache_put/1` | Events.Decorator.Caching | Write-through cache | `cache`, `keys` | `ttl`, `match`, `on_error` | All |
| `cache_evict/1` | Events.Decorator.Caching | Cache invalidation | `cache`, `keys` | `all_entries`, `before_invocation`, `on_error` | All |

### Telemetry & Observability Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `telemetry_span/1-2` | Events.Decorator.Telemetry | Erlang telemetry events | - | `event`, `include`, `metadata` | All |
| `otel_span/1-2` | Events.Decorator.Telemetry | OpenTelemetry spans | - | `name`, `include`, `attributes` | All |
| `log_call/1` | Events.Decorator.Telemetry | Log function entry | - | `level`, `message`, `metadata` | All |
| `log_context/1` | Events.Decorator.Telemetry | Set Logger metadata | `fields` | - | All |
| `log_if_slow/1` | Events.Decorator.Telemetry | Warn on slow ops | `threshold` | `level`, `message` | All |
| `track_memory/1` | Events.Decorator.Telemetry | Monitor memory usage | `threshold` | `level` | All |
| `capture_errors/1` | Events.Decorator.Telemetry | Report errors | `reporter` | `threshold` | All |
| `log_query/1` | Events.Decorator.Telemetry | DB query logging | - | `slow_threshold`, `level`, `slow_level`, `include_query` | All |
| `log_remote/1` | Events.Decorator.Telemetry | Remote logging | `service` | `async`, `metadata` | All |
| `benchmark/1` | Events.Decorator.Telemetry | Performance benchmarking | - | `iterations`, `warmup`, `format`, `memory` | All |
| `measure/1` | Events.Decorator.Telemetry | Simple timing | - | `unit`, `label`, `include_result` | All |

### Debugging Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `debug/1` | Events.Decorator.Debugging | IEx.Helpers.dbg/2 | - | `label`, `opts` | dev/test |
| `inspect/1` | Events.Decorator.Debugging | Inspect values | - | `what`, `label`, `opts` | All |
| `pry/1` | Events.Decorator.Debugging | Interactive breakpoints | - | `condition`, `before`, `after` | dev/test |
| `trace_vars/1` | Events.Decorator.Debugging | Compile-time trace hints | `vars` | - | All |

### Purity Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `pure/1` | Events.Decorator.Purity | Mark/verify purity | - | `verify`, `strict`, `allow_io`, `samples` | All (verify in dev/test) |
| `deterministic/1` | Events.Decorator.Purity | Check determinism | - | `samples`, `on_failure` | dev/test |
| `idempotent/1` | Events.Decorator.Purity | Verify idempotency | - | `calls`, `compare`, `comparator` | dev/test |
| `memoizable/1` | Events.Decorator.Purity | Check memoization safety | - | `verify`, `warn_impure` | All (verify in dev/test) |

### Pipeline & Composition Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `pipe_through/1` | Events.Decorator.Pipeline | Chain transformations | - | `steps` | All |
| `around/1` | Events.Decorator.Pipeline | Wrap with custom logic | `wrapper` | - | All |
| `compose/1` | Events.Decorator.Pipeline | Apply multiple decorators | - | `decorators` | All |

### Testing Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `with_fixtures/1` | Events.Decorator.Testing | Load test fixtures | `fixtures` | `cleanup` | test |
| `sample_data/1` | Events.Decorator.Testing | Generate test data | `generator` | `count` | test |
| `timeout_test/1` | Events.Decorator.Testing | Test timeout | `timeout` | `on_timeout` | test |
| `mock/1` | Events.Decorator.Testing | Mock documentation | `module`, `functions` | - | test |

### Tracing Decorators

| Decorator | Module | Purpose | Required Options | Optional Options | Environment |
|-----------|--------|---------|-----------------|------------------|-------------|
| `trace_calls/1` | Events.Decorator.Tracing | Trace function calls | - | `depth`, `filter`, `exclude`, `format` | dev/test |
| `trace_modules/1` | Events.Decorator.Tracing | List called modules | - | `filter`, `unique`, `exclude_stdlib` | dev/test |
| `trace_dependencies/1` | Events.Decorator.Tracing | Track dependencies | - | `type`, `format` | dev/test |

## Common Usage Patterns

### 1. Production API Endpoint
```elixir
@decorate compose([
  {:telemetry_span, [[:api, :users, :get]]},
  {:cacheable, [cache: UserCache, ttl: 300_000]},
  {:log_if_slow, [threshold: 1000]},
  {:capture_errors, [reporter: Sentry]}
])
def get_user(id) do
  Repo.get!(User, id)
end
```

### 2. Database Query with Monitoring
```elixir
@decorate compose([
  {:log_query, [slow_threshold: 500]},
  {:measure, [unit: :millisecond]},
  {:cache_put, [cache: QueryCache, keys: [query_key]]}
])
def complex_aggregation(params) do
  # Complex database query
end
```

### 3. Pure Function with Verification
```elixir
@decorate compose([
  {:pure, [verify: true]},
  {:deterministic, [samples: 10]},
  {:memoizable, []}
])
def calculate_fibonacci(n) do
  # Pure calculation
end
```

### 4. Development Debugging
```elixir
@decorate compose([
  {:debug, []},
  {:inspect, [what: :both]},
  {:trace_calls, [depth: 2]}
])
def problematic_function(data) do
  # Code to debug
end
```

### 5. Test Function with Setup
```elixir
@decorate compose([
  {:with_fixtures, [fixtures: [:user, :organization]]},
  {:timeout_test, [timeout: 5000]},
  {:sample_data, [generator: Faker, count: 10]}
])
def test_user_permissions(user, organization, sample_data) do
  # Test implementation
end
```

### 6. External API Call
```elixir
@decorate compose([
  {:around, [&RetryHelper.with_retry/2]},
  {:otel_span, ["external.api.call"]},
  {:log_remote, [service: DatadogLogger]},
  {:capture_errors, [reporter: Sentry]}
])
def call_external_api(params) do
  # API call implementation
end
```

## Environment-Specific Behavior

| Environment | Active Decorators | Notes |
|-------------|------------------|-------|
| **Production** | Caching, Telemetry, Limited Logging | Debug, Pry, Tracing disabled |
| **Development** | All decorators active | Full debugging capabilities |
| **Test** | Testing decorators, Purity verification | Mocking, fixtures enabled |

## Best Practices

1. **Layer decorators from general to specific**: telemetry → caching → error handling
2. **Use `compose/1` for reusable patterns**: Create common decorator combinations
3. **Environment awareness**: Heavy decorators (trace, debug) only in dev/test
4. **Performance first**: Put caching before expensive operations
5. **Error handling last**: Capture errors should wrap the entire operation
6. **Document purity**: Use purity decorators even without verification for documentation
7. **Test timeout discipline**: Always use timeout_test for integration tests