# AsyncResult Reference

> **Comprehensive reference for concurrent operations with Result types.**
> For basic overview, see `FUNCTIONAL.md`.

## Quick Reference

| Function | Returns | Use Case |
|----------|---------|----------|
| `parallel/2` | `{:ok, [values]}` or settlement | Execute tasks in parallel |
| `parallel_map/3` | `{:ok, [values]}` or settlement | Map over items in parallel |
| `race/2` | `{:ok, value}` | First success wins |
| `hedge/3` | `{:ok, value}` | Hedged request with backup |
| `stream/3` | `Stream` | Large collections with backpressure |
| `retry/2` | `{:ok, value}` | Retry with exponential backoff |
| `fire_and_forget/2` | `{:ok, pid}` | Side-effects only |
| `batch/2` | `{:ok, [values]}` | Execute in batches |
| `first_ok/1` | `{:ok, value}` | Sequential until success |
| `lazy/1` + `run_lazy/1` | `{:ok, value}` | Deferred computation |

---

## Parallel Execution

### `parallel/2` - Execute tasks in parallel

```elixir
# Fail-fast (default)
{:ok, [user, orders, prefs]} = AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end,
  fn -> fetch_prefs(id) end
])

# Settlement mode - collect all results
%{ok: [...], errors: [...]} = AsyncResult.parallel(tasks, settle: true)

# With options
AsyncResult.parallel(tasks,
  max_concurrency: 5,
  timeout: 10_000,
  supervisor: MyApp.TaskSupervisor,
  on_progress: fn done, total -> IO.puts("#{done}/#{total}") end
)
```

### `parallel_map/3` - Map over items in parallel

```elixir
{:ok, users} = AsyncResult.parallel_map(ids, &fetch_user/1)

# With settlement
%{ok: [...], errors: [...]} = AsyncResult.parallel_map(ids, &fetch/1, settle: true)

# Track which inputs failed
%{ok: [{1, val}], errors: [{2, reason}]} =
  AsyncResult.parallel_map(ids, &fetch/1, settle: true, indexed: true)
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:max_concurrency` | schedulers * 2 | Maximum concurrent tasks |
| `:timeout` | 5000 | Per-task timeout (ms) |
| `:ordered` | true | Preserve input order |
| `:settle` | false | Collect all results instead of fail-fast |
| `:indexed` | false | Include input with result (requires settle) |
| `:supervisor` | nil | Task.Supervisor for crash isolation |
| `:telemetry` | nil | Event prefix for telemetry |
| `:on_progress` | nil | Callback `fn(done, total)` |

---

## Racing

### `race/2` - First success wins

```elixir
{:ok, data} = AsyncResult.race([
  fn -> fetch_from_cache() end,
  fn -> fetch_from_db() end,
  fn -> fetch_from_api() end
])

# Only fails if ALL tasks fail
{:error, [:cache_miss, :db_down, :api_error]} = AsyncResult.race([...])
```

### `hedge/3` - Hedged request

Starts backup if primary is slow.

```elixir
# If primary takes > 100ms, also try backup
AsyncResult.hedge(
  fn -> fetch_from_primary() end,
  fn -> fetch_from_replica() end,
  delay: 100,
  timeout: 5000
)
```

---

## Streaming

### `stream/3` - Lazy stream with backpressure

```elixir
# Process large dataset efficiently
large_dataset
|> AsyncResult.stream(&transform/1, max_concurrency: 20)
|> Stream.each(&save/1)
|> Stream.run()

# Error handling strategies
AsyncResult.stream(items, &fetch/1, on_error: :skip)    # Skip errors
AsyncResult.stream(items, &fetch/1, on_error: :include) # Include errors
AsyncResult.stream(items, &fetch/1, on_error: {:default, nil}) # Replace errors
```

| `:on_error` | Behavior |
|-------------|----------|
| `:halt` (default) | Stop on first error |
| `:skip` | Skip errors, only yield successes |
| `:include` | Yield both successes and errors |
| `{:default, val}` | Replace errors with value |

---

## Task Handles

### `async/1` + `await/2` - Explicit control

```elixir
handle = AsyncResult.async(fn -> expensive_op() end)
# ... do other work ...
{:ok, result} = AsyncResult.await(handle)

# Unlinked task (crash isolation)
handle = AsyncResult.async(fn -> risky_op() end, supervisor: MySupervisor)
```

### `await_many/2` - Await multiple

```elixir
{:ok, [r1, r2]} = AsyncResult.await_many([h1, h2])

# With settlement
%{ok: [...], errors: [...]} = AsyncResult.await_many(handles, settle: true)
```

### `yield/2` - Non-blocking check

```elixir
case AsyncResult.yield(handle) do
  {:ok, result} -> handle_result(result)
  nil -> :still_running
end
```

### `shutdown/2` - Terminate task

```elixir
AsyncResult.shutdown(handle)
AsyncResult.shutdown(handle, brutal_kill: true)
```

### `completed/1` - Pre-computed result

```elixir
handles = Enum.map(items, fn item ->
  case Cache.get(item) do
    {:ok, cached} -> AsyncResult.completed({:ok, cached})
    :miss -> AsyncResult.async(fn -> fetch(item) end)
  end
end)
AsyncResult.await_many(handles)
```

---

## Retry

### `retry/2` - Exponential backoff

```elixir
AsyncResult.retry(fn -> flaky_api() end,
  max_attempts: 5,
  initial_delay: 100,
  max_delay: 5000,
  multiplier: 2,
  jitter: true
)

# Only retry specific errors
AsyncResult.retry(fn -> api_call() end,
  when: fn
    {:error, :rate_limited} -> true
    {:error, :timeout} -> true
    _ -> false
  end
)

# With callback between attempts
AsyncResult.retry(fn -> api_call() end,
  on_retry: fn attempt, error, delay ->
    Logger.warn("Attempt #{attempt} failed, retrying in #{delay}ms")
  end
)
```

---

## Fire-and-Forget

### `fire_and_forget/2` - Don't wait for result

```elixir
{:ok, pid} = AsyncResult.fire_and_forget(fn -> send_analytics(event) end)

# With supervisor
AsyncResult.fire_and_forget(fn -> send_email(user) end,
  supervisor: MyApp.TaskSupervisor
)
```

### `run_all/3` - Execute all, ignore results

```elixir
:ok = AsyncResult.run_all(users, &send_notification/1, max_concurrency: 50)
```

---

## Batch & Sequential

### `batch/2` - Execute in batches

```elixir
AsyncResult.batch(tasks,
  batch_size: 10,
  delay_between_batches: 1000
)
```

### `first_ok/1` - Sequential until success

```elixir
{:ok, data} = AsyncResult.first_ok([
  fn -> check_l1_cache() end,
  fn -> check_l2_cache() end,
  fn -> fetch_from_db() end
])
```

---

## Lazy Execution

### `lazy/1` - Deferred computation

```elixir
lazy = AsyncResult.lazy(fn -> expensive_computation() end)
# Nothing runs yet

{:ok, result} = AsyncResult.run_lazy(lazy)
# Now it runs
```

### `run_lazy/1` - Execute lazy

```elixir
# Single
{:ok, result} = AsyncResult.run_lazy(lazy)

# Multiple in parallel
{:ok, results} = AsyncResult.run_lazy([lazy1, lazy2, lazy3])

# With settlement
%{ok: [...], errors: [...]} = AsyncResult.run_lazy(lazies, settle: true)
```

### `lazy_then/2` - Chain lazy computations

```elixir
lazy = AsyncResult.lazy(fn -> fetch_user(id) end)
|> AsyncResult.lazy_then(fn user ->
  AsyncResult.lazy(fn -> fetch_orders(user.id) end)
end)

{:ok, orders} = AsyncResult.run_lazy(lazy)
```

---

## Utilities

### `safe/1` - Wrap exceptions

```elixir
AsyncResult.safe(fn -> String.to_integer("bad") end)
#=> {:error, %ArgumentError{...}}
```

### `timeout/2` - Execute with timeout

```elixir
{:ok, result} = AsyncResult.timeout(fn -> fast_op() end, 1000)
{:error, :timeout} = AsyncResult.timeout(fn -> slow_op() end, 100)
```

---

## Settlement Helpers

Use `AsyncResult.Settlement` module for working with settlement results:

```elixir
alias AsyncResult.Settlement

result = AsyncResult.parallel(tasks, settle: true)

Settlement.ok(result)       # Extract successes
Settlement.errors(result)   # Extract errors
Settlement.ok?(result)      # Check if all succeeded
Settlement.failed?(result)  # Check if any failed
Settlement.split(result)    # {successes, failures} tuple
```

---

## Function Reference

### Parallel Execution
| Function | Signature | Description |
|----------|-----------|-------------|
| `parallel/2` | `[task_fun] -> Result \| settlement` | Execute tasks in parallel |
| `parallel_map/3` | `[a], (a -> Result) -> Result \| settlement` | Map in parallel |

### Task Handles
| Function | Signature | Description |
|----------|-----------|-------------|
| `async/1` | `task_fun -> handle` | Start async task |
| `await/2` | `handle -> Result` | Await task result |
| `await_many/2` | `[handle] -> Result \| settlement` | Await multiple |
| `yield/2` | `handle -> {:ok, Result} \| nil` | Non-blocking check |
| `shutdown/2` | `handle -> {:ok, Result} \| nil` | Terminate task |
| `completed/1` | `Result -> handle` | Pre-computed result |

### Racing
| Function | Signature | Description |
|----------|-----------|-------------|
| `race/2` | `[task_fun] -> Result` | First success wins |
| `hedge/3` | `task_fun, task_fun -> Result` | Hedged request |

### Streaming
| Function | Signature | Description |
|----------|-----------|-------------|
| `stream/3` | `Enum, (a -> Result) -> Stream` | Lazy stream |

### Retry
| Function | Signature | Description |
|----------|-----------|-------------|
| `retry/2` | `task_fun -> Result` | Retry with backoff |

### Fire-and-Forget
| Function | Signature | Description |
|----------|-----------|-------------|
| `fire_and_forget/2` | `task_fun -> {:ok, pid}` | Start without waiting |
| `run_all/3` | `[a], (a -> term) -> :ok` | Execute all, ignore results |

### Batch & Sequential
| Function | Signature | Description |
|----------|-----------|-------------|
| `batch/2` | `[task_fun] -> Result` | Execute in batches |
| `first_ok/1` | `[task_fun] -> Result` | Sequential until success |

### Lazy
| Function | Signature | Description |
|----------|-----------|-------------|
| `lazy/1` | `task_fun -> Lazy.t` | Create deferred computation |
| `run_lazy/1` | `Lazy.t \| [Lazy.t] -> Result` | Execute lazy |
| `lazy_then/2` | `Lazy.t, (a -> Lazy.t) -> Lazy.t` | Chain lazy |

### Utilities
| Function | Signature | Description |
|----------|-----------|-------------|
| `safe/1` | `(-> a) -> Result` | Wrap exceptions |
| `timeout/2` | `task_fun, ms -> Result` | Execute with timeout |

---

## Related Modules

- `FnTypes.Debouncer` - Debounce rapid calls (wait for quiet)
- `FnTypes.Throttler` - Throttle to max rate
- `FnTypes.RateLimiter` - Token bucket rate limiting
- `Events.Api.Client.Middleware.CircuitBreaker` - Circuit breaker pattern
