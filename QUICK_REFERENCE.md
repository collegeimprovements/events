# Events Decorator System - Quick Reference Card

## Most Common Decorators (80% Use Cases)

```elixir
# Cache expensive operations
@decorate cacheable(cache: MyCache, ttl: 3600)

# Add telemetry
@decorate telemetry_span([:app, :action])

# Log slow operations
@decorate log_if_slow(threshold: 1000)

# Debug in development
@decorate debug()  # or inspect(what: :both)

# Chain transformations
@decorate pipe_through([&trim/1, &upcase/1])

# Wrap with custom logic
@decorate around(&wrapper_fn/2)
```

## By Category - One-Line Usage

### 🚀 Performance
```elixir
@decorate cacheable(cache: Cache, ttl: 3600)          # Cache results
@decorate cache_put(cache: Cache, keys: [key])        # Update cache
@decorate cache_evict(cache: Cache, keys: [key])      # Clear cache
@decorate measure(unit: :millisecond)                 # Time execution
@decorate benchmark(iterations: 100)                  # Benchmark performance
```

### 📊 Monitoring
```elixir
@decorate telemetry_span([:app, :operation])          # Telemetry events
@decorate otel_span("operation.name")                 # OpenTelemetry
@decorate log_call(level: :info)                      # Log calls
@decorate log_if_slow(threshold: 1000)                # Warn if slow
@decorate capture_errors(reporter: Sentry)            # Error tracking
```

### 🐛 Debugging
```elixir
@decorate debug()                                      # Use dbg/2
@decorate inspect(what: :both)                        # Show args & result
@decorate pry(before: true)                           # Breakpoint
@decorate trace_calls(depth: 2)                       # Trace execution
```

### ✅ Verification
```elixir
@decorate pure(verify: true)                          # Verify purity
@decorate deterministic(samples: 5)                   # Check determinism
@decorate idempotent(calls: 3)                        # Verify idempotency
@decorate memoizable()                                # Safe to memoize?
```

### 🔄 Composition
```elixir
@decorate pipe_through([...steps...])                 # Chain functions
@decorate around(&wrapper/2)                          # Wrap with logic
@decorate compose([{:decorator, opts}, ...])          # Multiple decorators
```

### 🧪 Testing
```elixir
@decorate with_fixtures(fixtures: [:user])            # Load fixtures
@decorate sample_data(generator: Faker)               # Generate data
@decorate timeout_test(timeout: 5000)                 # Test timeout
```

## Common Patterns

### API Endpoint
```elixir
@decorate compose([
  {:telemetry_span, [[:api, :endpoint]]},
  {:cacheable, [cache: Cache, ttl: 300]},
  {:log_if_slow, [threshold: 1000]},
  {:capture_errors, [reporter: Sentry]}
])
```

### Background Job
```elixir
@decorate compose([
  {:log_call, [level: :info]},
  {:timeout_test, [timeout: 30_000]},
  {:capture_errors, [reporter: Sentry]},
  {:measure, []}
])
```

### Database Query
```elixir
@decorate compose([
  {:log_query, [slow_threshold: 500]},
  {:cacheable, [cache: QueryCache, ttl: 60]},
  {:measure, [unit: :millisecond]}
])
```

### Pure Calculation
```elixir
@decorate compose([
  {:pure, [verify: true]},
  {:memoizable, []},
  {:benchmark, [iterations: 100]}
])
```

## Decision Matrix

| Need | Use | Example |
|------|-----|---------|
| **Speed up repeated calls** | `cacheable` | `@decorate cacheable(cache: C, ttl: 60)` |
| **Track performance** | `telemetry_span` | `@decorate telemetry_span([:app, :op])` |
| **Find slow code** | `log_if_slow` | `@decorate log_if_slow(threshold: 1000)` |
| **Debug issues** | `debug` or `inspect` | `@decorate debug()` |
| **Ensure purity** | `pure` | `@decorate pure(verify: true)` |
| **Transform output** | `pipe_through` | `@decorate pipe_through([...])` |
| **Add cross-cutting concerns** | `around` | `@decorate around(&auth_check/2)` |
| **Test with data** | `sample_data` | `@decorate sample_data(generator: F)` |
| **Trace execution** | `trace_calls` | `@decorate trace_calls(depth: 2)` |
| **Report errors** | `capture_errors` | `@decorate capture_errors(reporter: S)` |

## Environment Behavior

| Decorator | Production | Dev/Test | Notes |
|-----------|------------|----------|-------|
| `cacheable` | ✅ Active | ✅ Active | Always active |
| `telemetry_span` | ✅ Active | ✅ Active | Always active |
| `debug` | ❌ No-op | ✅ Active | Dev/test only |
| `pry` | ❌ No-op | ✅ Active | Dev/test only |
| `trace_calls` | ❌ No-op | ✅ Active | Dev/test only |
| `pure(verify: true)` | ❌ No verify | ✅ Verifies | Verification in dev/test |

## Module Imports

```elixir
# In your module
defmodule MyModule do
  use Events.Decorator  # Enables all decorators

  # Or import specific categories:
  use Events.Decorator.Caching
  use Events.Decorator.Telemetry
  use Events.Decorator.Debugging
  use Events.Decorator.Purity
  use Events.Decorator.Pipeline
  use Events.Decorator.Testing
  use Events.Decorator.Tracing
end
```

## Tips

1. **Stack Order**: Apply decorators from general → specific
2. **Compose Reusable**: Define common patterns with `compose`
3. **Environment Aware**: Heavy decorators only in dev/test
4. **Cache First**: Put caching before expensive operations
5. **Errors Last**: Error handlers should wrap everything
6. **Document Intent**: Use purity decorators for documentation
7. **Test Discipline**: Always use timeouts in integration tests