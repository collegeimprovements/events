# Events Decorator System

A comprehensive, composable decorator system for Elixir built on the `decorator` library, combining caching, telemetry, and advanced composition patterns.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Available Decorators](#available-decorators)
  - [Caching Decorators](#caching-decorators)
  - [Telemetry Decorators](#telemetry-decorators)
  - [Advanced Decorators](#advanced-decorators)
- [Usage Examples](#usage-examples)
- [Best Practices](#best-practices)
- [Architecture](#architecture)

## Features

- ✅ **Caching**: Read-through, write-through, and cache eviction with Nebulex
- ✅ **Telemetry**: Erlang telemetry and OpenTelemetry spans
- ✅ **Logging**: Structured logging with context propagation
- ✅ **Performance**: Monitor slow operations and memory usage
- ✅ **Composition**: Stack multiple decorators seamlessly
- ✅ **Type-Safe**: Compile-time validation with NimbleOptions
- ✅ **Zero Overhead**: All decorators applied at compile time
- ✅ **Pattern Matching**: Extensive use of pattern matching for clean code
- ✅ **Well Organized**: Clear module boundaries and helper utilities

## Installation

The decorator system is already integrated into the Events application. To use it in your modules:

```elixir
defmodule MyApp.MyModule do
  use Events.Decorator

  # Now you can use all decorators!
end
```

## Quick Start

### Simple Caching

```elixir
defmodule MyApp.Users do
  use Events.Decorator
  alias Events.{Repo, Cache}

  @decorate cacheable(cache: Cache, key: {User, id}, ttl: 3600)
  def get_user(id) do
    Repo.get(User, id)
  end
end
```

### With Telemetry

```elixir
@decorate cacheable(cache: Cache, key: {User, id})
@decorate telemetry_span([:my_app, :users, :get])
@decorate log_if_slow(threshold: 1000)
def get_user(id) do
  Repo.get(User, id)
end
```

### Composition

```elixir
@decorate compose([
  {:cacheable, [cache: Cache, key: id]},
  {:telemetry_span, [[:app, :get]]},
  {:log_if_slow, [threshold: 500]}
])
def get_item(id) do
  Repo.get(Item, id)
end
```

## Available Decorators

### Caching Decorators

#### `@cacheable` - Read-Through Caching

Caches function results. Only executes the function on cache miss.

**Options:**
- `cache:` - Cache module (required)
- `key:` - Explicit cache key
- `key_generator:` - Custom key generator module
- `ttl:` - Time-to-live in milliseconds
- `match:` - Match function for conditional caching
- `on_error:` - Error handling (`:raise` or `:nothing`)

**Examples:**

```elixir
# Simple caching
@decorate cacheable(cache: MyCache, key: {User, id})
def get_user(id), do: Repo.get(User, id)

# With TTL
@decorate cacheable(cache: MyCache, key: id, ttl: :timer.hours(1))
def get_user(id), do: Repo.get(User, id)

# Conditional caching (only cache found users)
@decorate cacheable(cache: MyCache, key: id, match: &match_found/1)
def get_user(id), do: Repo.get(User, id)

defp match_found(%User{}), do: true
defp match_found(nil), do: false

# Dynamic cache resolution
@decorate cacheable(cache: {MyApp, :get_cache, []}, key: id)
def get_user(id), do: Repo.get(User, id)
```

#### `@cache_put` - Write-Through Caching

Always executes the function and updates cache with results.

**Options:**
- `cache:` - Cache module (required)
- `keys:` - List of cache keys to update (required)
- `ttl:` - Time-to-live in milliseconds
- `match:` - Match function for conditional caching
- `on_error:` - Error handling

**Examples:**

```elixir
# Update multiple keys
@decorate cache_put(cache: MyCache, keys: [{User, user.id}, {User, user.email}])
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

# Only cache successful updates
@decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
def update_user(user, attrs) do
  user |> User.changeset(attrs) |> Repo.update()
end

defp match_ok({:ok, result}), do: {true, result}
defp match_ok(_), do: false
```

#### `@cache_evict` - Cache Invalidation

Removes entries from cache after (or before) function execution.

**Options:**
- `cache:` - Cache module (required)
- `keys:` - List of cache keys to evict (required)
- `all_entries:` - Delete all cache entries (boolean)
- `before_invocation:` - Evict before function runs (boolean)
- `on_error:` - Error handling

**Examples:**

```elixir
# Evict specific keys
@decorate cache_evict(cache: MyCache, keys: [{User, id}])
def delete_user(id) do
  Repo.delete(User, id)
end

# Evict all entries
@decorate cache_evict(cache: MyCache, all_entries: true)
def delete_all_users, do: Repo.delete_all(User)

# Evict before invocation (safer for critical operations)
@decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
def logout(token), do: revoke_session(token)
```

### Telemetry Decorators

#### `@telemetry_span` - Erlang Telemetry Events

Wraps function in `:telemetry.span/3`, emitting start/stop/exception events.

**Options:**
- `event:` - Event name as list of atoms (defaults to module.function)
- `include:` - Variable names to include in metadata
- `metadata:` - Additional static metadata

**Examples:**

```elixir
@decorate telemetry_span([:my_app, :users, :create])
def create_user(attrs) do
  Repo.insert(User.changeset(%User{}, attrs))
end

# With variable capture
@decorate telemetry_span([:app, :process], include: [:user_id, :result])
def process_data(user_id, data) do
  result = do_processing(data)
  {:ok, result}
end
```

**Events Emitted:**
- `[:my_app, :users, :create, :start]`
- `[:my_app, :users, :create, :stop]`
- `[:my_app, :users, :create, :exception]`

#### `@otel_span` - OpenTelemetry Spans

Creates OpenTelemetry spans for distributed tracing.

**Options:**
- `name:` - Span name (defaults to module.function)
- `include:` - Variable names to include as attributes
- `attributes:` - Additional static attributes

**Examples:**

```elixir
@decorate otel_span("user.create")
def create_user(attrs) do
  Repo.insert(User.changeset(%User{}, attrs))
end

# With attributes
@decorate otel_span("payment.process", include: [:amount, :currency])
def process_payment(amount, currency, card) do
  PaymentGateway.charge(amount, currency, card)
end
```

#### `@log_call` - Structured Logging

Logs function entry with configurable level and metadata.

**Options:**
- `level:` - Log level (`:info`, `:debug`, `:warn`, `:error`)
- `message:` - Custom log message
- `metadata:` - Additional metadata

**Examples:**

```elixir
@decorate log_call()
def important_operation do
  # Logs at :info: "Calling MyModule.important_operation/0"
end

@decorate log_call(:debug, message: "Starting background task")
def background_task(data) do
  # ...
end
```

#### `@log_context` - Logger Metadata

Sets Logger metadata from function arguments.

**Options:**
- `fields:` - List of argument names to include in metadata

**Examples:**

```elixir
@decorate log_context([:user_id, :request_id])
def handle_request(user_id, request_id, params) do
  Logger.info("Processing") # Includes user_id and request_id
  # ...
end
```

#### `@log_if_slow` - Performance Monitoring

Logs a warning if function exceeds threshold.

**Options:**
- `threshold:` - Threshold in milliseconds (required)
- `level:` - Log level (default: `:warn`)
- `message:` - Custom message

**Examples:**

```elixir
@decorate log_if_slow(threshold: 1000)
def potentially_slow_query(params) do
  Repo.all(complex_query(params))
end

@decorate log_if_slow(threshold: 500, level: :error)
def critical_path do
  # ...
end
```

#### `@track_memory` - Memory Profiling

Logs a warning if memory usage exceeds threshold.

**Options:**
- `threshold:` - Memory threshold in bytes (required)
- `level:` - Log level (default: `:warn`)

**Examples:**

```elixir
@decorate track_memory(threshold: 10_000_000) # 10MB
def memory_intensive_operation(data) do
  # Process large dataset
end
```

#### `@capture_errors` - Error Tracking

Captures exceptions and reports to error tracking service.

**Options:**
- `reporter:` - Error reporting module (e.g., `Sentry`)
- `threshold:` - Only report after N attempts (default: 1)

**Examples:**

```elixir
@decorate capture_errors(reporter: Sentry)
def risky_operation(data) do
  # Errors automatically reported
end

@decorate capture_errors(reporter: Sentry, threshold: 3)
def operation_with_retries(data) do
  # Only reports after 3 failures
end
```

### Advanced Decorators

#### `@pipe_through` - Function Pipeline

Passes function result through transformation steps.

**Options:**
- List of pipeline steps (functions or MFA tuples)

**Examples:**

```elixir
@decorate pipe_through([&String.trim/1, &String.upcase/1])
def get_name(user) do
  user.name
end

@decorate pipe_through([
  &validate_input/1,
  {DataProcessor, :transform, [:json]},
  &persist_to_db/1
])
def process_data(raw_data) do
  raw_data
end
```

#### `@around` - Around Advice

Wraps function with custom behavior (aspect-oriented programming).

**Wrapper Signature:**
```elixir
def wrapper(decorated_fn, ...original_args) do
  # before logic
  result = decorated_fn.(...original_args)
  # after logic
  result
end
```

**Examples:**

```elixir
# Performance measurement
@decorate around(&ProfileHelper.measure/2)
def expensive_calculation(x, y) do
  # Complex work
end

defmodule ProfileHelper do
  def measure(decorated_fn, x, y) do
    start = System.monotonic_time()
    result = decorated_fn.(x, y)
    duration = System.monotonic_time() - start
    Telemetry.record_duration(duration)
    result
  end
end

# Retry logic
@decorate around(&RetryHelper.with_retry/2)
def call_external_api(endpoint) do
  HTTPClient.get(endpoint)
end

defmodule RetryHelper do
  def with_retry(decorated_fn, endpoint, max_attempts \\ 3) do
    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      case decorated_fn.(endpoint) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, _} when attempt < max_attempts -> {:cont, nil}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
```

#### `@compose` - Decorator Composition

Combines multiple decorators into a single application.

**Examples:**

```elixir
@decorate compose([
  {:cacheable, [cache: MyCache, key: id, ttl: 3600]},
  {:telemetry_span, [[:app, :users, :get]]},
  {:log_if_slow, [threshold: 1000]}
])
def get_user(id) do
  Repo.get(User, id)
end

# Define reusable compositions
defmodule MyDecorators do
  def cached_and_monitored(cache_opts) do
    [
      {:cacheable, cache_opts},
      {:telemetry_span, [[:app, :cache, :access]]},
      {:log_if_slow, [threshold: 500]}
    ]
  end
end

@decorate compose(MyDecorators.cached_and_monitored(cache: MyCache, key: id))
def get_data(id), do: fetch_from_source(id)
```

## Usage Examples

See `lib/events/accounts.ex` for comprehensive examples demonstrating:
- Simple caching
- Conditional caching with match functions
- Write-through caching
- Cache eviction
- Telemetry spans
- Performance monitoring
- Memory tracking
- Error capture
- Pipeline transformations
- Around advice patterns
- Decorator composition

## Best Practices

### 1. Decorator Order Matters

Decorators are applied **from bottom to top**:

```elixir
@decorate log_call()       # Applied LAST (outermost)
@decorate cacheable(...)   # Applied SECOND
@decorate telemetry_span() # Applied FIRST (innermost)
def my_function, do: ...
```

Execution flow:
1. `log_call` logs entry
2. `cacheable` checks cache
3. If cache miss, `telemetry_span` wraps execution
4. Original function runs

### 2. Keep Decorators Focused

Each decorator should have a single responsibility:
- ✅ Good: `@cacheable`, `@telemetry_span`, `@log_if_slow`
- ❌ Bad: One decorator doing caching + telemetry + logging

### 3. Use Composition for Common Patterns

```elixir
# Define once
def standard_read(key) do
  [
    {:cacheable, [cache: Cache, key: key]},
    {:telemetry_span, [[:app, :read]]},
    {:log_if_slow, [threshold: 500]}
  ]
end

# Reuse everywhere
@decorate compose(standard_read({User, id}))
def get_user(id), do: Repo.get(User, id)

@decorate compose(standard_read({Post, id}))
def get_post(id), do: Repo.get(Post, id)
```

### 4. Match Functions for Conditional Behavior

Use match functions to control when caching/operations occur:

```elixir
# Only cache successful results
defp match_ok({:ok, result}), do: {true, result}
defp match_ok(_), do: false

# Only cache found entities
defp match_found(%User{} = user), do: {true, user}
defp match_found(nil), do: false

# Cache with transformed value
defp match_and_transform({:ok, user}) do
  {true, Map.take(user, [:id, :email, :name])}
end
defp match_and_transform(_), do: false
```

### 5. Cache Key Design

Use tuples for namespaced, collision-free keys:

```elixir
{User, id}                    # User by ID
{User, :email, email}         # User by email
{Session, session_id}         # Session data
{:config, :app_settings}      # Configuration
{Post, post_id, :comments}    # Post's comments
```

### 6. Performance Considerations

- All decorators are applied at **compile time** (zero runtime overhead for mechanism)
- Actual overhead comes from operations (cache lookups, telemetry events, etc.)
- Use `threshold` options to avoid excessive logging
- Use `sample_rate` for high-frequency operations (future feature)

## Architecture

### Module Structure

```
lib/events/
├── decorator/
│   ├── decorator.ex          # Main entry point
│   ├── define.ex             # Decorator registry
│   ├── ast.ex                # AST manipulation utilities
│   ├── context.ex            # Context struct
│   │
│   ├── caching/
│   │   ├── decorators.ex     # Caching decorators
│   │   └── helpers.ex        # Caching utilities
│   │
│   ├── telemetry/
│   │   ├── decorators.ex     # Telemetry decorators
│   │   └── helpers.ex        # Telemetry utilities
│   │
│   └── pipeline/
│       ├── decorators.ex     # Pipeline decorators
│       └── helpers.ex        # Pipeline utilities
│
├── cache/
│   └── key_generator.ex      # Key generation behavior
│
└── cache.ex                  # Nebulex cache module
```

### Design Principles

1. **Pattern Matching Everywhere** - All AST operations use pattern matching
2. **Composability** - Decorators can be stacked and composed
3. **Type Safety** - NimbleOptions validates all options at compile time
4. **Clean Code** - Clear module boundaries, helper utilities
5. **Context-Driven** - Rich context passed to all decorators
6. **Zero Overhead** - Compile-time transformations only

### How It Works

1. **Definition**: `use Events.Decorator.Define` registers decorators
2. **Application**: `@decorate decorator_name(opts)` applies to function
3. **Transformation**: Decorator receives `(opts, body, context)`
4. **AST Modification**: Decorator returns transformed AST
5. **Compilation**: Modified code is compiled

Example transformation:

```elixir
# Before
@decorate cacheable(cache: MyCache, key: id)
def get_user(id), do: Repo.get(User, id)

# After (simplified)
def get_user(id) do
  case MyCache.get(id) do
    nil ->
      result = Repo.get(User, id)
      MyCache.put(id, result)
      result
    cached -> cached
  end
end
```

## Contributing

When adding new decorators:
1. Add decorator definition to `Events.Decorator.Define`
2. Implement in appropriate module (`Caching`, `Telemetry`, `Pipeline`)
3. Create NimbleOptions schema for validation
4. Add comprehensive documentation
5. Add examples to this README
6. Add usage examples to `Events.Accounts`

## License

Internal to Events application.
