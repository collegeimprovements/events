# OmMiddleware Cheatsheet

> Composable middleware chains with lifecycle hooks. For full docs, see `README.md`.

## Define Middleware

```elixir
defmodule LoggingMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    Logger.info("Starting", user_id: context[:user_id])
    {:ok, context}
  end

  @impl true
  def after_execute(result, _context) do
    Logger.info("Completed")
    {:ok, result}
  end

  @impl true
  def on_error(error, _context) do
    Logger.error("Failed: #{inspect(error)}")
    {:ok, error}                                   # propagate error
  end

  @impl true
  def on_complete(_result, _context) do
    :ok                                            # always runs (cleanup)
  end
end
```

---

## Lifecycle Hooks

| Hook | When | Returns |
|------|------|---------|
| `before_execute/1` | Before operation | `{:ok, context}` or `{:halt, reason}` |
| `after_execute/2` | After success | `{:ok, result}` or `{:error, reason}` |
| `on_error/2` | After failure | `{:ok, error}`, `{:retry, reason}`, `{:ignore, reason}` |
| `on_complete/2` | Always (finally) | `:ok` |

---

## Use Middleware

```elixir
# Basic
result = OmMiddleware.wrap(
  [LoggingMiddleware, MetricsMiddleware],
  %{user_id: 123},
  fn -> expensive_operation() end
)

# With options
result = OmMiddleware.wrap(
  [{RateLimitMiddleware, bucket: "api", limit: 1000}],
  %{user_id: 123},
  fn -> api_call() end
)
```

---

## Reusable Pipelines

```elixir
# Create pipeline
api_pipeline = OmMiddleware.pipe([
  AuthMiddleware,
  {RateLimitMiddleware, bucket: "api"},
  LoggingMiddleware,
  MetricsMiddleware
])

# Use later
api_pipeline.(%{user: current_user}, fn -> call_api() end)
```

---

## Composition

```elixir
# Compose middleware into a group
standard = OmMiddleware.compose([AuthMiddleware, LoggingMiddleware, MetricsMiddleware])

# Use group as single unit
OmMiddleware.wrap([standard, {RateLimitMiddleware, bucket: "special"}], ctx, &work/0)
```

---

## Run Individual Hooks

```elixir
# Before only
{:ok, validated_ctx} = OmMiddleware.run_before([AuthMiddleware], context)

# After only
{:ok, transformed} = OmMiddleware.run_after([TransformMiddleware], result, context)

# Error only
case OmMiddleware.run_error([RetryMiddleware], error, context) do
  {:ok, error} -> {:error, error}
  {:retry, _} -> schedule_retry()
  {:ignore, _} -> :ok
end

# Complete only (cleanup)
:ok = OmMiddleware.run_complete([MetricsMiddleware], result, context)
```

---

## Common Middleware Patterns

```elixir
# Auth
def before_execute(%{user: %{role: :admin}} = ctx), do: {:ok, ctx}
def before_execute(_), do: {:halt, :unauthorized}

# Rate limit
def before_execute(ctx) do
  case check_limit(ctx.middleware_opts[:bucket]) do
    :ok -> {:ok, ctx}
    :exceeded -> {:halt, :rate_limit_exceeded}
  end
end

# Retry
def on_error(error, ctx) do
  if retryable?(error) and ctx[:attempt] < ctx.middleware_opts[:max_retries] do
    {:retry, error}
  else
    {:ok, error}
  end
end

# Metrics
def before_execute(ctx), do: {:ok, Map.put(ctx, :started_at, System.monotonic_time())}
def on_complete(_result, ctx) do
  duration = System.monotonic_time() - ctx.started_at
  :telemetry.execute([:my_app, :op], %{duration: duration}, %{})
  :ok
end
```

---

## Execution Flow

```
before_execute (M1 → M2 → M3)        # in order
         │                │
     {:ok, ctx}      {:halt, reason}
         │                │
    Execute fun()    Return error
    │           │
{:ok, r}   {:error, e}
    │           │
after_execute   on_error              # reverse / in order
    │           │
    └─────┬─────┘
          │
   on_complete (all)                  # always runs
          │
     Return result
```

---

## Middleware Order

```elixir
# Order matters — auth before rate limit
[
  AuthMiddleware,         # 1st: authenticate
  RateLimitMiddleware,    # 2nd: rate limit (only authed)
  LoggingMiddleware,      # 3rd: log
  MetricsMiddleware       # 4th: metrics
]
```
