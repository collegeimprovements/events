# OmMiddleware

Composable middleware chains for Elixir with lifecycle hooks.

## Installation

```elixir
def deps do
  [{:om_middleware, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
# Define middleware
defmodule TimingMiddleware do
  use OmMiddleware
  alias FnTypes.Timing

  @impl true
  def before_execute(context) do
    {:ok, Map.put(context, :started_at, System.monotonic_time())}
  end

  @impl true
  def after_execute(result, context) do
    duration = Timing.duration_since(context.started_at)
    IO.puts("Took #{duration.ms}ms")  # Clear units, multiple formats available
    {:ok, result}
  end
end

# Use middleware chain
OmMiddleware.wrap([TimingMiddleware], %{}, fn ->
  expensive_operation()
end)
```

## Concepts

### Lifecycle Hooks

| Hook | When Called | Purpose |
|------|-------------|---------|
| `before_execute/1` | Before operation | Setup, validation, authorization |
| `after_execute/2` | After success | Transform results, logging |
| `on_error/2` | After failure | Error handling, retry decisions |
| `on_complete/2` | Always (finally) | Cleanup, metrics, resource release |

### Return Values

| Hook | Continue | Stop/Modify |
|------|----------|-------------|
| `before_execute` | `{:ok, context}` | `{:halt, reason}` |
| `after_execute` | `{:ok, result}` | `{:error, reason}` |
| `on_error` | `{:ok, error}` | `{:retry, reason}` or `{:ignore, reason}` |
| `on_complete` | `:ok` | - |

---

## Creating Middleware

### Basic Middleware

```elixir
defmodule LoggingMiddleware do
  use OmMiddleware
  require Logger

  @impl true
  def before_execute(context) do
    Logger.info("Starting operation", user_id: context[:user_id])
    {:ok, context}
  end

  @impl true
  def after_execute(result, context) do
    Logger.info("Operation completed", user_id: context[:user_id])
    {:ok, result}
  end

  @impl true
  def on_error(error, context) do
    Logger.error("Operation failed", user_id: context[:user_id], error: inspect(error))
    {:ok, error}
  end

  @impl true
  def on_complete(_result, context) do
    Logger.debug("Operation finished", user_id: context[:user_id])
    :ok
  end
end
```

### Middleware with Options

```elixir
defmodule RateLimitMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    opts = context.middleware_opts
    bucket = Keyword.get(opts, :bucket, "default")
    limit = Keyword.get(opts, :limit, 100)

    case check_rate_limit(bucket, limit) do
      :ok -> {:ok, context}
      :exceeded -> {:halt, :rate_limit_exceeded}
    end
  end

  defp check_rate_limit(bucket, limit) do
    # Your rate limiting logic
    :ok
  end
end

# Use with options
OmMiddleware.wrap(
  [{RateLimitMiddleware, bucket: "api", limit: 1000}],
  %{user_id: 123},
  fn -> api_call() end
)
```

### Authorization Middleware

```elixir
defmodule AuthMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    case context do
      %{user: %{role: :admin}} ->
        {:ok, Map.put(context, :authorized, true)}

      %{user: %{role: role}, required_role: required} when role == required ->
        {:ok, Map.put(context, :authorized, true)}

      %{user: _} ->
        {:halt, :forbidden}

      _ ->
        {:halt, :unauthorized}
    end
  end
end
```

### Retry Middleware

```elixir
defmodule RetryMiddleware do
  use OmMiddleware

  @impl true
  def on_error(error, context) do
    opts = context.middleware_opts
    max_retries = Keyword.get(opts, :max_retries, 3)
    current_attempt = Map.get(context, :attempt, 1)

    if retryable?(error) and current_attempt < max_retries do
      {:retry, error}
    else
      {:ok, error}
    end
  end

  defp retryable?({:error, :timeout}), do: true
  defp retryable?({:error, :connection_refused}), do: true
  defp retryable?(_), do: false
end
```

### Metrics Middleware

```elixir
defmodule MetricsMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    {:ok, Map.put(context, :started_at, System.monotonic_time())}
  end

  @impl true
  def on_complete(result, context) do
    duration = System.monotonic_time() - context.started_at
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    status = if match?({:ok, _}, result), do: :success, else: :failure

    :telemetry.execute(
      [:my_app, :operation],
      %{duration: duration_ms},
      %{status: status, operation: context[:operation_name]}
    )

    :ok
  end
end
```

### Transaction Middleware

```elixir
defmodule TransactionMiddleware do
  use OmMiddleware
  alias MyApp.Repo

  @impl true
  def before_execute(context) do
    # Start a transaction and store it in context
    {:ok, Map.put(context, :in_transaction, true)}
  end

  @impl true
  def after_execute(result, _context) do
    # Transaction will be committed by Repo
    {:ok, result}
  end

  @impl true
  def on_error(error, _context) do
    # Transaction will be rolled back by Repo
    {:ok, error}
  end
end

# Use with Repo.transaction
def perform_operation(data) do
  Repo.transaction(fn ->
    OmMiddleware.wrap(
      [TransactionMiddleware, ValidationMiddleware],
      %{data: data},
      fn -> do_database_work() end
    )
  end)
end
```

---

## Using Middleware

### Basic Usage

```elixir
middleware = [
  LoggingMiddleware,
  MetricsMiddleware,
  {RateLimitMiddleware, bucket: "api"}
]

result = OmMiddleware.wrap(middleware, %{user_id: 123}, fn ->
  {:ok, perform_work()}
end)

case result do
  {:ok, value} -> handle_success(value)
  {:error, reason} -> handle_error(reason)
  {:retry, reason} -> schedule_retry(reason)
end
```

### Creating Pipelines

```elixir
# Create a reusable pipeline
api_pipeline = OmMiddleware.pipe([
  AuthMiddleware,
  {RateLimitMiddleware, bucket: "api"},
  LoggingMiddleware,
  MetricsMiddleware
])

# Use it later
api_pipeline.(%{user: current_user}, fn ->
  call_external_api()
end)
```

### Composing Middleware

```elixir
# Create a composed middleware group
standard_middleware = OmMiddleware.compose([
  AuthMiddleware,
  LoggingMiddleware,
  MetricsMiddleware
])

# Use it as a single unit
OmMiddleware.wrap(
  [standard_middleware, {RateLimitMiddleware, bucket: "special"}],
  context,
  fn -> work() end
)
```

### Running Specific Hooks

```elixir
# Run only before hooks
case OmMiddleware.run_before([AuthMiddleware, ValidationMiddleware], context) do
  {:ok, validated_context} -> proceed(validated_context)
  {:halt, reason} -> abort(reason)
end

# Run only after hooks
{:ok, transformed} = OmMiddleware.run_after(
  [TransformMiddleware],
  {:ok, raw_result},
  context
)

# Run only error hooks
case OmMiddleware.run_error([RetryMiddleware], error, context) do
  {:ok, error} -> {:error, error}
  {:retry, _} -> schedule_retry()
  {:ignore, _} -> :ok
end

# Run only complete hooks (cleanup)
:ok = OmMiddleware.run_complete([MetricsMiddleware, CleanupMiddleware], result, context)
```

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        wrap(middleware, context, fun)           │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. run_before (in order)                                       │
│     ├─ M1.before_execute(ctx) → {:ok, ctx1}                    │
│     ├─ M2.before_execute(ctx1) → {:ok, ctx2}                   │
│     └─ M3.before_execute(ctx2) → {:ok, ctx3} OR {:halt, reason}│
└─────────────────────────────────────────────────────────────────┘
                    │                           │
           {:ok, ctx3}                   {:halt, reason}
                    │                           │
                    ▼                           ▼
┌───────────────────────────────┐    ┌──────────────────────────┐
│  2. Execute fun.()            │    │ Return {:error,          │
│     ├─ Success → {:ok, result}│    │         {:middleware_halt,│
│     └─ Failure → {:error, e}  │    │          reason}}        │
└───────────────────────────────┘    └──────────────────────────┘
           │               │
    {:ok, result}    {:error, error}
           │               │
           ▼               ▼
┌─────────────────┐ ┌─────────────────────────────────────────────┐
│  3. run_after   │ │  3. run_error (in order)                    │
│  (reverse order)│ │     ├─ {:ok, error} → continue as error     │
│                 │ │     ├─ {:retry, _} → return {:retry, _}     │
│                 │ │     └─ {:ignore, _} → return {:ok, :ignored}│
└─────────────────┘ └─────────────────────────────────────────────┘
           │               │
           └───────┬───────┘
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. run_complete (all middleware)                               │
│     ├─ M1.on_complete(result, ctx)                             │
│     ├─ M2.on_complete(result, ctx)                             │
│     └─ M3.on_complete(result, ctx)                             │
└─────────────────────────────────────────────────────────────────┘
                   │
                   ▼
            Return result
```

---

## Real-World Examples

### API Client Middleware Stack

```elixir
defmodule MyApp.ApiClient do
  @middleware [
    {RateLimitMiddleware, bucket: "external_api", limit: 100},
    {RetryMiddleware, max_retries: 3, backoff: :exponential},
    {CircuitBreakerMiddleware, threshold: 5, timeout: 30_000},
    MetricsMiddleware,
    LoggingMiddleware
  ]

  def call(endpoint, params) do
    OmMiddleware.wrap(@middleware, %{endpoint: endpoint}, fn ->
      HTTPClient.post(endpoint, params)
    end)
  end
end
```

### Job Processing Middleware

```elixir
defmodule MyApp.JobProcessor do
  @middleware [
    {TimeoutMiddleware, timeout: 30_000},
    {RetryMiddleware, max_retries: 3},
    TransactionMiddleware,
    MetricsMiddleware,
    ErrorReportingMiddleware
  ]

  def process(job) do
    OmMiddleware.wrap(@middleware, %{job: job}, fn ->
      perform_job(job)
    end)
  end
end
```

### Request Pipeline

```elixir
defmodule MyApp.RequestPipeline do
  def call(conn, handler) do
    context = %{
      conn: conn,
      user: conn.assigns[:current_user],
      request_id: Logger.metadata()[:request_id]
    }

    middleware = [
      AuthMiddleware,
      {RateLimitMiddleware, bucket: conn.request_path},
      InputValidationMiddleware,
      AuditLogMiddleware,
      MetricsMiddleware
    ]

    case OmMiddleware.wrap(middleware, context, fn -> handler.(conn) end) do
      {:ok, response} -> response
      {:error, :unauthorized} -> send_resp(conn, 401, "Unauthorized")
      {:error, :forbidden} -> send_resp(conn, 403, "Forbidden")
      {:error, :rate_limit_exceeded} -> send_resp(conn, 429, "Too Many Requests")
      {:error, reason} -> send_resp(conn, 500, inspect(reason))
    end
  end
end
```

---

## Best Practices

### 1. Keep Middleware Focused

```elixir
# Good: Single responsibility
defmodule LoggingMiddleware do
  # Only handles logging
end

defmodule MetricsMiddleware do
  # Only handles metrics
end

# Bad: Too many responsibilities
defmodule KitchenSinkMiddleware do
  # Handles logging, metrics, auth, rate limiting...
end
```

### 2. Order Matters

```elixir
# Good: Auth before rate limit (don't count unauthenticated requests)
middleware = [
  AuthMiddleware,
  RateLimitMiddleware,
  LoggingMiddleware
]

# Consider: Logging early to capture all requests
middleware = [
  LoggingMiddleware,  # Log everything
  AuthMiddleware,
  RateLimitMiddleware
]
```

### 3. Handle Errors Gracefully

```elixir
defmodule SafeMiddleware do
  use OmMiddleware

  @impl true
  def before_execute(context) do
    # Always return a valid response
    case risky_operation() do
      {:ok, result} -> {:ok, Map.put(context, :data, result)}
      {:error, _} -> {:ok, context}  # Continue without the data
    end
  end
end
```

### 4. Use Options for Configuration

```elixir
# Good: Configurable via options
{RateLimitMiddleware, bucket: "api", limit: 1000}

# Bad: Hardcoded values
defmodule HardcodedMiddleware do
  @bucket "api"
  @limit 1000
end
```

## License

MIT
