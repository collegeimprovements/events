# Production Profiling Guide

## Overview

The Events profiling system provides production-safe performance analysis with minimal overhead. It includes multiple profiling strategies, automatic load detection, and seamless telemetry integration.

## Features

- ✅ **Production-Safe Sampling** - Configurable sampling rates (0.1%-1%)
- ✅ **Multiple Strategies** - Sample, call graph, memory, flame graphs
- ✅ **Load-Aware** - Automatically disables under high load
- ✅ **Zero-Overhead** - No impact when disabled
- ✅ **Telemetry Integration** - Automatic metrics emission
- ✅ **Async Profiling** - Non-blocking profiling
- ✅ **Environment-Based** - Different profiles per environment

---

## Quick Start

### Basic Profiling

```elixir
defmodule MyApp.Analytics do
  use Events.Decorator

  # Profile with 1% sampling rate
  @decorate profile(strategy: :sample, rate: 0.01)
  def compute_metrics(data) do
    # Expensive computation
    Enum.map(data, &process_item/1)
  end
end
```

### Profile Only Slow Operations

```elixir
@decorate profile_if_slow(threshold: 1000)
def potentially_slow_query(id) do
  # Only profiled if takes > 1 second
  Repo.get(User, id)
end
```

### Production Profiling

```elixir
@decorate profile_production(sample_rate: 0.001)
def critical_operation(params) do
  # Profile 0.1% of production requests
  process_payment(params)
end
```

---

## Profiling Strategies

### 1. Sampling Profiler (`:sample`)

**Best for**: Production profiling, continuous monitoring

**Overhead**: Very low (<1% with default settings)

**Use case**: Always-on profiling to identify hot spots

```elixir
@decorate profile(strategy: :sample, rate: 0.01, duration: 30_000)
def expensive_calculation(data) do
  # Sampled every 10ms for up to 30 seconds
  data
  |> Enum.map(&transform/1)
  |> Enum.reduce(&combine/2)
end
```

**How it works**:
- Samples stack traces at regular intervals
- Builds statistical profile with minimal overhead
- Safe for production use

---

### 2. Call Graph Profiler (`:call_graph`)

**Best for**: Development, detailed analysis

**Overhead**: High (10-50x slower)

**Use case**: Understanding call hierarchies and bottlenecks

```elixir
@decorate profile(strategy: :call_graph, env: [:dev, :test])
def complex_pipeline(input) do
  input
  |> step1()
  |> step2()
  |> step3()
end
```

**Output**: Complete call graph with timing per function

---

### 3. Memory Profiler (`:memory`)

**Best for**: Finding memory leaks, allocation hot spots

**Overhead**: Medium (2-5x slower)

**Use case**: Memory-intensive operations

```elixir
@decorate profile(strategy: :memory)
def allocate_buffers(size) do
  # Track memory allocations
  :binary.copy(<<0>>, size)
end
```

**Output**: Memory before/after, delta per memory type

---

### 4. Flame Graph Generator (`:flame_graph`)

**Best for**: Visual performance analysis

**Overhead**: High (10-50x slower)

**Use case**: Understanding time spent in each function visually

```elixir
@decorate flame_graph(output: "profile.svg", format: :svg)
def application_startup do
  # Generate visual flame graph
  initialize_services()
  |> start_workers()
  |> connect_databases()
end
```

**Output**: SVG/HTML flame graph visualization

---

### 5. Erlang Profilers

#### fprof - Function profiler

```elixir
@decorate profile(strategy: :fprof, env: [:dev])
def detailed_analysis do
  # Detailed per-function timing
end
```

#### eprof - Time profiler

```elixir
@decorate profile(strategy: :eprof, env: [:dev])
def time_analysis do
  # Time spent in each function
end
```

#### cprof - Call count profiler

```elixir
@decorate profile_calls()
def count_calls do
  # Count how many times each function is called
end
```

---

## Decorator Reference

### `@decorate profile(opts)`

General-purpose profiler with multiple strategies.

**Options**:
- `:strategy` - Profiling strategy (`:sample`, `:call_graph`, `:memory`, etc.)
- `:rate` - Sampling rate (0.0-1.0, default: 0.01)
- `:duration` - Max profiling duration in ms (default: 30_000)
- `:threshold` - Only profile if duration > threshold
- `:env` - Environments where enabled (default: `[:dev, :test, :prod]`)
- `:enabled` - Enable/disable (default: `true`)
- `:async` - Run asynchronously (default: `false`)
- `:emit_metrics` - Emit telemetry (default: `true`)
- `:check_load` - Check system load (default: `true`)
- `:metadata` - Additional metadata (default: `%{}`)

**Examples**:

```elixir
# Basic sampling
@decorate profile()
def default_profile do
  # 1% sampling rate, sample strategy
end

# High-frequency sampling in dev
@decorate profile(rate: 0.5, env: [:dev])
def dev_profile do
  # 50% sampling in dev only
end

# Async profiling
@decorate profile(async: true, strategy: :flame_graph)
def background_profile do
  # Generate flame graph in background
end

# Conditional profiling
@decorate profile(threshold: 1000, strategy: :memory)
def conditional_profile do
  # Only profile if takes > 1 second
end
```

---

### `@decorate profile_if_slow(threshold, opts)`

Profile only when function exceeds duration threshold.

**Options**:
- `:threshold` - Duration threshold in ms (required)
- `:strategy` - Profiling strategy (default: `:sample`)
- `:rate` - Sampling rate when slow (default: 0.1)
- `:env` - Environments where enabled (default: `[:dev, :test]`)

**Examples**:

```elixir
# Profile slow database queries
@decorate profile_if_slow(threshold: 500)
def complex_query(params) do
  # Profiled only if > 500ms
  Repo.all(from u in User, where: ...)
end

# High sampling for slow operations
@decorate profile_if_slow(threshold: 1000, rate: 0.5)
def api_call(endpoint) do
  # Profile 50% of calls that exceed 1 second
  HTTPoison.get(endpoint)
end
```

---

### `@decorate profile_production(opts)`

Production-optimized profiler with low sampling rate and load checks.

**Options**:
- `:sample_rate` - Production sampling rate (default: 0.001 = 0.1%)
- `:emit_metrics` - Emit metrics (default: `true`)
- `:check_load` - Check system load (default: `true`)

**Examples**:

```elixir
# Critical path profiling
@decorate profile_production(sample_rate: 0.001)
def process_payment(payment) do
  # Profile 0.1% of payments
  Payment.process(payment)
end

# Higher sampling for debugging
@decorate profile_production(sample_rate: 0.01)
def investigate_issue do
  # Temporarily increase to 1% for debugging
end
```

**Load Checks**:
- Automatically disables when scheduler utilization > 80%
- Automatically disables when memory usage > 90%
- Ensures minimal production impact

---

### `@decorate flame_graph(opts)`

Generate flame graph visualization.

**Options**:
- `:output` - Output file path (default: auto-generated)
- `:format` - Format (`:svg`, `:html`, `:json`, default: `:svg`)
- `:enabled` - Enable/disable (default: `true`)
- `:duration` - Profiling duration in ms (default: 10_000)

**Examples**:

```elixir
# SVG flame graph
@decorate flame_graph(output: "startup_profile.svg")
def application_startup do
  # Visual profile of startup
  MyApp.Application.start()
end

# HTML interactive flame graph
@decorate flame_graph(format: :html, output: "profile.html")
def request_handler(conn) do
  # Interactive flame graph
  handle_request(conn)
end

# Conditional flame graph
@decorate flame_graph(enabled: System.get_env("PROFILE") == "true")
def conditional_profile do
  # Only when PROFILE=true
end
```

---

### `@decorate profile_memory(opts)`

Profile memory allocations.

**Options**:
- `:env` - Environments where enabled (default: `[:dev, :test]`)
- `:threshold` - Only log if delta > threshold bytes
- `:emit_metrics` - Emit memory metrics (default: `true`)

**Examples**:

```elixir
# Basic memory profiling
@decorate profile_memory()
def allocate_buffers do
  # Track all allocations
  List.duplicate(<<0::8>>, 1_000_000)
end

# Large allocation threshold
@decorate profile_memory(threshold: 10_000_000)
def batch_process do
  # Only log if > 10MB allocated
  process_large_dataset()
end

# Production memory tracking
@decorate profile_memory(env: [:prod], threshold: 50_000_000)
def production_memory_check do
  # Track large allocations in prod
end
```

---

### `@decorate profile_calls(opts)`

Profile function call counts.

**Options**:
- `:env` - Environments where enabled (default: `[:dev, :test]`)
- `:emit_metrics` - Emit call metrics (default: `true`)

**Examples**:

```elixir
# Track recursive calls
@decorate profile_calls()
def fibonacci(n) when n <= 1, do: n
def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)

# Track database calls
@decorate profile_calls()
def fetch_related_data(id) do
  # How many queries?
  user = Repo.get(User, id)
  posts = Repo.all(assoc(user, :posts))
  comments = Repo.all(assoc(user, :comments))
  {user, posts, comments}
end
```

---

## Telemetry Integration

All profilers emit telemetry events that can be consumed for monitoring.

### Events

```elixir
[:events, :profiler, :start]
  %{system_time: integer()}
  metadata: %{strategy: atom(), opts: keyword()}

[:events, :profiler, :stop]
  %{duration: integer()}
  metadata: %{strategy: atom(), result: any()}

[:events, :profiler, :exception]
  %{}
  metadata: %{kind: atom(), reason: any(), stacktrace: list(), strategy: atom()}

[:events, :profiler, :sample]
  %{samples: integer()}
  metadata: %{module: atom(), function: atom()}

[:events, :profiler, :slow_operation]
  %{duration: integer(), threshold: integer()}
  metadata: %{module: atom(), function: atom()}

[:events, :profiler, :production]
  %{duration: integer()}
  metadata: %{module: atom(), function: atom()}

[:events, :profiler, :memory]
  %{before: integer(), after: integer(), delta: integer()}
  metadata: %{module: atom(), function: atom()}

[:events, :profiler, :calls]
  %{calls: integer()}
  metadata: %{module: atom(), function: atom()}

[:events, :profiler, :complete]
  %{duration: integer(), memory_delta: integer(), samples: integer()}
  metadata: %{module: atom(), function: atom(), strategy: atom()}
```

### Attach Handlers

```elixir
:telemetry.attach_many(
  "profiler-handler",
  [
    [:events, :profiler, :stop],
    [:events, :profiler, :slow_operation],
    [:events, :profiler, :production]
  ],
  &handle_profiler_event/4,
  nil
)

defp handle_profiler_event([:events, :profiler, :stop], measurements, metadata, _config) do
  Logger.info("Profile completed: #{metadata.strategy}, duration: #{measurements.duration}ms")
end

defp handle_profiler_event([:events, :profiler, :slow_operation], measurements, metadata, _) do
  # Alert on slow operations
  MyApp.Alerts.send_slow_operation_alert(metadata.function, measurements.duration)
end
```

---

## Production Patterns

### Pattern 1: Always-On Sampling

```elixir
defmodule MyApp.CriticalPath do
  use Events.Decorator

  # Always profile critical operations with low overhead
  @decorate profile_production(sample_rate: 0.001, emit_metrics: true)
  def process_order(order) do
    order
    |> validate_order()
    |> charge_payment()
    |> fulfill_order()
  end
end
```

**Benefits**:
- Continuous performance visibility
- Statistical profile over time
- Minimal overhead (0.1% sampling)

---

### Pattern 2: Conditional Deep Profiling

```elixir
defmodule MyApp.DiagnosticMode do
  use Events.Decorator

  # Enable deep profiling via environment variable
  @decorate profile(
    strategy: :flame_graph,
    enabled: System.get_env("DEEP_PROFILE") == "true",
    output: "production_profile.svg"
  )
  def investigate_performance_issue do
    # Temporarily enable for investigation
    do_suspect_operation()
  end
end
```

**Usage**:
```bash
# Enable deep profiling
DEEP_PROFILE=true mix phx.server

# Disable after investigation
unset DEEP_PROFILE
```

---

### Pattern 3: Automatic Slow Query Detection

```elixir
defmodule MyApp.Queries do
  use Events.Decorator

  @decorate profile_if_slow(threshold: 100, rate: 1.0)
  def find_users(filters) do
    # Auto-profile any query > 100ms
    # Profile 100% of slow queries
    User
    |> apply_filters(filters)
    |> Repo.all()
  end
end
```

**Benefits**:
- Automatic slow query detection
- No manual intervention needed
- Profile all slow queries for analysis

---

### Pattern 4: Memory Leak Detection

```elixir
defmodule MyApp.BackgroundJob do
  use Events.Decorator

  @decorate profile_memory(threshold: 50_000_000, env: [:prod])
  def process_large_batch(batch) do
    # Alert if job allocates > 50MB
    Enum.map(batch, &process_item/1)
  end
end
```

**Benefits**:
- Early memory leak detection
- Production memory monitoring
- Threshold-based alerting

---

### Pattern 5: A/B Performance Testing

```elixir
defmodule MyApp.Algorithm do
  use Events.Decorator

  @decorate profile_production(sample_rate: 0.05)
  def algorithm_v1(data) do
    # Old algorithm - 5% sampling
    old_implementation(data)
  end

  @decorate profile_production(sample_rate: 0.05)
  def algorithm_v2(data) do
    # New algorithm - 5% sampling
    new_implementation(data)
  end
end
```

**Compare performance** via telemetry metrics to determine which is faster.

---

## Best Practices

### 1. Start with Sampling

Begin with low-overhead sampling in production:

```elixir
@decorate profile_production(sample_rate: 0.001)
```

### 2. Use Environment Guards

Expensive profiling only in dev/test:

```elixir
@decorate profile(strategy: :flame_graph, env: [:dev, :test])
```

### 3. Threshold-Based Profiling

Only profile slow operations:

```elixir
@decorate profile_if_slow(threshold: 1000)
```

### 4. Check System Load

Automatically disable under high load:

```elixir
@decorate profile(check_load: true)
```

### 5. Emit Metrics

Always emit telemetry for observability:

```elixir
@decorate profile_production(emit_metrics: true)
```

### 6. Async Profiling

Use async for expensive profilers:

```elixir
@decorate profile(strategy: :flame_graph, async: true)
```

---

## Common Use Cases

### 1. Find Performance Bottlenecks

```elixir
@decorate profile(strategy: :sample, rate: 0.1, duration: 60_000)
def suspect_function do
  # Profile for 1 minute with 10% sampling
end
```

### 2. Debug Memory Leaks

```elixir
@decorate profile_memory(threshold: 10_000_000)
def memory_intensive_operation do
  # Alert if allocates > 10MB
end
```

### 3. Monitor Production Performance

```elixir
@decorate profile_production(sample_rate: 0.001, emit_metrics: true)
def critical_operation do
  # Continuous production monitoring
end
```

### 4. Generate Performance Reports

```elixir
@decorate flame_graph(output: "weekly_report.svg")
def generate_weekly_report do
  # Visual performance report
end
```

### 5. Detect Slow Queries

```elixir
@decorate profile_if_slow(threshold: 100)
def database_query do
  # Auto-profile slow queries
end
```

---

## Troubleshooting

### High Overhead

**Problem**: Profiling slows down application

**Solutions**:
1. Reduce sampling rate: `rate: 0.001`
2. Enable load checks: `check_load: true`
3. Use async profiling: `async: true`
4. Profile only in dev: `env: [:dev]`

### Missing Profiles

**Problem**: Profiles not generated

**Solutions**:
1. Check environment: Verify `Mix.env()` matches `:env` option
2. Check sampling: Increase `rate` temporarily
3. Check load: Disable `check_load` for testing
4. Check enabled: Verify `enabled: true`

### Memory Issues

**Problem**: Profiler uses too much memory

**Solutions**:
1. Reduce duration: `duration: 10_000`
2. Use sampling: `strategy: :sample` instead of `:call_graph`
3. Increase threshold: `threshold: 1000`

---

## Summary

The Events profiling system provides:

✅ **Production-Safe** - Low overhead, load-aware
✅ **Multiple Strategies** - Sample, memory, flame graphs, call graphs
✅ **Flexible** - Environment-based, threshold-based, conditional
✅ **Observable** - Telemetry integration, automatic metrics
✅ **Easy to Use** - Decorator-based, zero configuration

Use profiling decorators to make your application faster, find bottlenecks, and prevent performance regressions!
