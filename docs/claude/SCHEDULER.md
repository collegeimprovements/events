# Scheduler Quick Reference

## Overview

The Events Scheduler provides cron-based job scheduling with:
- **Decorator API**: `@decorate scheduled(...)` for simple jobs
- **Worker API**: `use OmScheduler.Worker` for complex jobs
- **Runtime API**: Dynamic job management
- **Clustering**: Leader election (only one node runs jobs)
- **Persistence**: In-memory (dev) or PostgreSQL (prod)

---

## Decorator API

```elixir
defmodule MyApp.ScheduledJobs do
  use OmScheduler

  # Interval-based
  @decorate scheduled(every: {5, :minutes})
  def sync_inventory, do: Inventory.sync_all()

  # Cron expression
  @decorate scheduled(cron: "0 6 * * *", zone: "America/New_York")
  def daily_report, do: Reports.generate_daily()

  # Built-in macro
  @decorate scheduled(cron: @hourly)
  def aggregate_metrics, do: Metrics.aggregate()

  # Multiple schedules (6am, 3pm, 9pm)
  @decorate scheduled(cron: ["0 6 * * *", "0 15 * * *", "0 21 * * *"])
  def sync_erp, do: ExternalSystems.sync()

  # With options
  @decorate scheduled(
    cron: "0 2 * * *",
    timeout: {2, :hours},
    max_retries: 5,
    queue: :maintenance,
    unique: true,
    tags: ["cleanup"]
  )
  def cleanup, do: Data.cleanup()

  # Run once at boot
  @decorate scheduled(cron: @reboot)
  def warm_caches, do: Cache.warm_all()
end
```

### Decorator Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `every` | duration | — | Interval: `{5, :minutes}`, `{30, :seconds}` |
| `cron` | string/list | — | Cron expression(s) or macro |
| `zone` | string | `"Etc/UTC"` | Timezone for cron |
| `queue` | atom | `:default` | Queue name |
| `timeout` | duration | `{1, :minute}` | Max execution time |
| `max_retries` | integer | `3` | Retry attempts on failure |
| `unique` | boolean | `false` | Prevent overlapping runs |
| `tags` | list | `[]` | Tags for filtering |
| `priority` | 0-9 | `0` | Lower = higher priority |

---

## Worker API

For complex jobs with custom logic:

```elixir
defmodule MyApp.DataExportWorker do
  use OmScheduler.Worker

  @impl true
  def schedule do
    [
      cron: "0 3 * * *",
      zone: "UTC",
      timeout: {2, :hours},
      max_retries: 3,
      queue: :exports
    ]
  end

  @impl true
  def perform(%{attempt: attempt} = _context) do
    with {:ok, data} <- fetch_data(),
         {:ok, file} <- generate_file(data),
         {:ok, _} <- upload(file) do
      {:ok, %{records: length(data)}}
    else
      {:error, :unavailable} when attempt < 3 ->
        {:retry, :unavailable}  # Will retry
      {:error, reason} ->
        {:error, reason}        # Give up
    end
  end

  # Optional: custom backoff
  @impl true
  def backoff(attempt) do
    min(:timer.minutes(attempt * attempt), :timer.minutes(15))
  end
end
```

### Context Map

```elixir
%{
  attempt: 1,                           # Current attempt (1-based)
  job: %Job{...},                       # Job struct
  scheduled_at: ~U[2024-01-15 06:00:00Z], # When it was scheduled
  meta: %{                              # Metadata
    "scheduled" => true,
    "schedule_expr" => "0 6 * * *"
  }
}
```

### Return Values

| Return | Effect |
|--------|--------|
| `{:ok, result}` | Success, store result |
| `{:error, reason}` | Failure, may retry |
| `{:retry, reason}` | Explicit retry request |
| `:ok` | Success (no result stored) |

---

## Runtime API

```elixir
alias OmScheduler

# ═══════════════════════════════════════════════════════════════
# CRUD
# ═══════════════════════════════════════════════════════════════

Scheduler.insert(%{
  name: "cleanup",
  module: MyApp.Jobs,
  function: :cleanup,
  cron: "0 2 * * *"
})

Scheduler.update("cleanup", cron: "0 3 * * *")
Scheduler.delete("cleanup")
Scheduler.all()
Scheduler.get_job("cleanup")

# ═══════════════════════════════════════════════════════════════
# JOB CONTROL
# ═══════════════════════════════════════════════════════════════

Scheduler.pause_job("export")
Scheduler.resume_job("export")
Scheduler.run_now("report")      # Trigger immediately
Scheduler.cancel_job("export")   # Cancel running job
Scheduler.cancel_job("export", reason: :timeout)
Scheduler.running_jobs()         # List running jobs

# ═══════════════════════════════════════════════════════════════
# QUEUE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

Scheduler.pause_queue(:maintenance)
Scheduler.resume_queue(:maintenance)
Scheduler.scale_queue(:billing, 20)  # Change concurrency
Scheduler.queue_stats()

# ═══════════════════════════════════════════════════════════════
# MONITORING
# ═══════════════════════════════════════════════════════════════

Scheduler.history("report", limit: 10)
Scheduler.status("report")
Scheduler.is_leader?()
Scheduler.leader_node()
```

---

## Cron Expressions

5-field format: `minute hour day-of-month month day-of-week`

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12 or JAN-DEC)
│ │ │ │ ┌───────────── day of week (0-6 or SUN-SAT)
│ │ │ │ │
* * * * *
```

### Examples

| Expression | Description |
|------------|-------------|
| `0 * * * *` | Every hour (at minute 0) |
| `*/15 * * * *` | Every 15 minutes |
| `0 6 * * *` | Daily at 6 AM |
| `0 6,12,18 * * *` | At 6 AM, 12 PM, 6 PM |
| `0 9-17 * * MON-FRI` | Hourly 9-5 on weekdays |
| `0 0 1 * *` | 1st of month at midnight |
| `0 0 * * 0` | Every Sunday at midnight |

### Special Characters

| Char | Meaning | Example |
|------|---------|---------|
| `*` | Any value | `* * * * *` (every minute) |
| `,` | List | `0,30 * * * *` (0 and 30) |
| `-` | Range | `9-17 * * * *` (9 through 17) |
| `/` | Step | `*/15 * * * *` (every 15) |

### Built-in Macros

| Macro | Expression | Description |
|-------|------------|-------------|
| `@yearly` | `0 0 1 1 *` | January 1st, midnight |
| `@monthly` | `0 0 1 * *` | 1st of month, midnight |
| `@weekly` | `0 0 * * 0` | Sunday, midnight |
| `@daily` | `0 0 * * *` | Every day, midnight |
| `@hourly` | `0 * * * *` | Every hour |
| `@reboot` | — | Once at application start |

---

## Configuration

### Development (In-Memory)

```elixir
# config/dev.exs
config :events, OmScheduler,
  enabled: true,
  store: :memory,
  peer: OmScheduler.Peer.Global,
  queues: [default: 5]
```

### Production (PostgreSQL, Clustered)

```elixir
# config/prod.exs
config :events, OmScheduler,
  enabled: true,
  repo: Events.Core.Repo,
  store: :database,
  peer: OmScheduler.Peer.Postgres,
  queues: [
    default: 10,
    realtime: 20,
    notifications: 10,
    maintenance: 5
  ],
  plugins: [
    OmScheduler.Plugins.Cron,
    {OmScheduler.Plugins.Pruner, max_age: {7, :days}}
  ]
```

### Web Nodes (No Processing)

```elixir
# For web nodes that shouldn't run jobs
config :events, OmScheduler,
  enabled: true,
  peer: false,      # Never become leader
  queues: false     # Don't process jobs
```

### All Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable scheduler |
| `repo` | atom | — | Ecto repo (required for database store) |
| `store` | `:memory`/`:database` | `:memory` | Storage backend |
| `peer` | module/false | `Peer.Global` | Leader election module |
| `queues` | keyword/false | `[default: 10]` | Queue concurrency |
| `plugins` | list/false | `[]` | Plugins to enable |
| `poll_interval` | duration | `{1, :second}` | Job polling interval |

---

## Telemetry Events

```elixir
# Job lifecycle
[:events, :scheduler, :job, :start]
[:events, :scheduler, :job, :stop]
[:events, :scheduler, :job, :exception]
[:events, :scheduler, :job, :skip]      # unique conflict, paused
[:events, :scheduler, :job, :discard]   # max retries exceeded
[:events, :scheduler, :job, :cancel]    # job cancelled
[:events, :scheduler, :job, :preempt]   # job preempted by higher priority
[:events, :scheduler, :job, :resume]    # preempted job resumed

# Batch processing
[:events, :scheduler, :batch, :start]
[:events, :scheduler, :batch, :stop]

# Leadership
[:events, :scheduler, :peer, :election]
[:events, :scheduler, :peer, :resignation]

# Queues
[:events, :scheduler, :queue, :pause]
[:events, :scheduler, :queue, :resume]
[:events, :scheduler, :queue, :scale]
```

### Attaching Handlers

```elixir
:telemetry.attach_many(
  "scheduler-logger",
  [
    [:events, :scheduler, :job, :stop],
    [:events, :scheduler, :job, :exception]
  ],
  &MyApp.Telemetry.handle_scheduler_event/4,
  nil
)
```

---

## Testing

```elixir
# In test config
config :events, OmScheduler,
  enabled: false

# In specific tests
use OmScheduler.Testing

test "job executes correctly" do
  # Run job synchronously
  {:ok, result} = Scheduler.Testing.run_job("my_job")
  assert result == :expected

  # Or drain all pending jobs
  Scheduler.Testing.drain_queue(:default)
  assert_job_executed("my_job")
end
```

---

## Common Patterns

### Overlap Prevention

```elixir
# Prevent same job from running twice concurrently
@decorate scheduled(every: {1, :minute}, unique: true)
def long_running_job do
  # If previous run isn't done, this run is skipped
end
```

### Retry with Backoff

```elixir
@decorate scheduled(
  cron: @hourly,
  max_retries: 5,
  retry_delay: {1, :minute}  # Base delay, increases exponentially
)
def flaky_external_api do
  ExternalApi.call()
end
```

### Queue Isolation

```elixir
# Critical jobs in dedicated queue
@decorate scheduled(cron: "0 * * * *", queue: :billing)
def process_payments, do: ...

# Low-priority jobs in separate queue
@decorate scheduled(cron: "0 2 * * *", queue: :maintenance, priority: 9)
def cleanup, do: ...
```

### Timezone-Aware

```elixir
# Run at 9 AM in user's timezone
@decorate scheduled(cron: "0 9 * * *", zone: "America/New_York")
def morning_digest, do: ...
```

---

## Job Cancellation

Cancel running jobs at runtime:

```elixir
alias OmScheduler

# Cancel a running job
Scheduler.cancel_job("data_export")
Scheduler.cancel_job("data_export", reason: :user_requested)

# List currently running jobs
Scheduler.running_jobs()
# => ["data_export", "sync_inventory"]

# Queue-level cancellation
{:ok, producer} = Scheduler.get_producer(:exports)
Producer.cancel(producer, "data_export", :timeout)
Producer.running_jobs(producer)
```

### Cancel Return Values

| Return | Meaning |
|--------|---------|
| `:ok` | Job cancelled successfully |
| `{:error, :not_found}` | Job or queue not found |
| `{:error, :not_running}` | Job not currently executing |

### Telemetry

```elixir
[:events, :scheduler, :job, :cancel]
# Metadata: %{job_name: "...", queue: :default, cancel_reason: :user_requested}
```

---

## Batch Processing

Process large datasets in configurable chunks with progress tracking:

```elixir
defmodule MyApp.ImportWorker do
  use OmScheduler.Batch.Worker

  @impl true
  def schedule do
    [cron: "0 2 * * *", queue: :imports]
  end

  @impl true
  def batch_options do
    [
      batch_size: 100,       # Items per batch
      concurrency: 5,        # Parallel item processing
      on_error: :continue,   # :continue | :stop | :retry
      max_items: 10_000      # Optional limit
    ]
  end

  @impl true
  def fetch_items(cursor, opts) do
    limit = opts[:batch_size]

    items =
      Item
      |> where([i], i.id > ^(cursor || 0))
      |> order_by(:id)
      |> limit(^limit)
      |> Repo.all()

    case items do
      [] -> {:done, []}
      items -> {:more, items, List.last(items).id}
    end
  end

  @impl true
  def process_item(item, _context) do
    case ImportService.import(item) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Batch Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `schedule/0` | Yes | Schedule configuration |
| `fetch_items/2` | Yes | Fetch next batch |
| `process_item/2` | Yes | Process single item |
| `batch_options/0` | No | Batch configuration |

### Fetch Return Values

| Return | Meaning |
|--------|---------|
| `{:more, items, cursor}` | More items available |
| `{:done, items}` | Last batch |

### Process Return Values

| Return | Effect |
|--------|--------|
| `:ok` | Success |
| `{:ok, result}` | Success with result |
| `{:error, reason}` | Failure (may continue/stop) |
| `{:retry, reason}` | Retry this item (up to 3x) |

### Error Handling Strategies

| Strategy | Behavior |
|----------|----------|
| `:continue` | Log error, process next item |
| `:stop` | Stop batch immediately, mark failed |
| `:retry` | Retry item up to 3 times, then continue |

### Batch Result

```elixir
%{
  status: :completed | :partial | :failed,
  processed: 9850,
  failed: 150,
  errors: [...],  # Up to 10 recent errors
  cursor: cursor,
  duration_ms: 45_000
}
```

### Telemetry

```elixir
[:events, :scheduler, :batch, :start]
# Metadata: %{job_name: "...", batch_size: 100, concurrency: 5}

[:events, :scheduler, :batch, :stop]
# Metadata: %{job_name: "...", processed: 9850, failed: 150, status: :completed}
```

---

## Priority Preemption

Higher-priority jobs can preempt lower-priority running jobs:

```elixir
# config/prod.exs
config :events, OmScheduler,
  queues: [default: 10],
  preemption: true  # Enable preemption
```

### How It Works

1. Job A (priority 5) is running
2. Job B (priority 1) arrives, queue is full
3. Job A is suspended (`:erlang.suspend_process/1`)
4. Job B starts executing
5. When Job B completes, Job A resumes

### Priority Scale

| Priority | Level | Use Case |
|----------|-------|----------|
| 0-1 | Critical | Billing, alerts |
| 2-3 | High | User requests |
| 4-5 | Normal | Standard jobs |
| 6-7 | Low | Background sync |
| 8-9 | Lowest | Maintenance |

### Example

```elixir
# Normal priority (default)
@decorate scheduled(cron: @hourly, priority: 5)
def sync_inventory, do: ...

# High priority - can preempt normal jobs
@decorate scheduled(cron: "*/5 * * * *", priority: 1)
def process_urgent_orders, do: ...
```

### Queue Stats with Preemption

```elixir
Scheduler.queue_stats(:default)
# =>
%{
  queue: :default,
  running: 10,
  running_jobs: ["job_a", "job_b", ...],
  preempted: 2,
  preempted_jobs: ["job_c", "job_d"],
  preemption_enabled: true,
  concurrency: 10,
  paused: false,
  available: 0
}
```

### Telemetry

```elixir
[:events, :scheduler, :job, :preempt]
# Metadata: %{
#   preempted_job: "sync_inventory",
#   preempted_priority: 5,
#   incoming_job: "urgent_billing",
#   incoming_priority: 1,
#   queue: :default
# }

[:events, :scheduler, :job, :resume]
# Metadata: %{job_name: "sync_inventory", queue: :default, reason: :preemption_ended}
```

---

## Lifeline / Rescue System

Detects and rescues stuck jobs via heartbeat monitoring:

```elixir
# config/prod.exs
config :events, OmScheduler,
  lifeline: [
    enabled: true,
    interval: {1, :minute},       # Check frequency
    rescue_after: {5, :minutes}   # Mark stuck after no heartbeat
  ]
```

### How It Works

1. Running jobs emit heartbeats every 30 seconds
2. Lifeline process checks for jobs with stale heartbeats
3. Stuck jobs are marked as `:rescued` and locks released
4. Other nodes can then re-attempt the job

### Manual Intervention

```elixir
alias OmScheduler.Lifeline

# Manually trigger a rescue check
Lifeline.check_now()

# Record heartbeat (usually automatic)
Lifeline.heartbeat("my_job")
```

### Telemetry

```elixir
[:events, :scheduler, :lifeline, :rescue]
# Metadata: %{job_name: "...", execution_id: "...", stuck_duration_ms: 350000}
```

---

## Rate Limiting

Token bucket rate limiting per queue, worker, or globally:

```elixir
# config/prod.exs
config :events, OmScheduler,
  rate_limits: [
    # Queue-level: 100 jobs per minute
    queues: [
      billing: {100, :minute},
      notifications: {1000, :minute}
    ],
    # Worker-level: per worker module
    workers: [
      MyApp.EmailWorker: {50, :minute},
      MyApp.SmsWorker: {10, :minute}
    ],
    # Global limit across all queues
    global: {5000, :minute}
  ]
```

### Behavior

- Jobs exceeding rate limits are rescheduled with backoff
- Rate limited jobs emit `:skip` telemetry with reason `:rate_limited`
- Token buckets refill continuously based on limit/period

### Runtime API

```elixir
alias OmScheduler.RateLimiter

# Check if rate limited
RateLimiter.acquire(:queues, :billing, :default)
# => :ok | {:error, :rate_limited, retry_after_ms}

# Get bucket status
RateLimiter.status(:queues, :billing)
# => %{tokens: 45, capacity: 100, refill_rate: 1.67}
```

### Telemetry

```elixir
[:events, :scheduler, :job, :skip]
# Metadata: %{job_name: "...", queue: :billing, reason: :rate_limited}
```

---

## Enhanced Unique Jobs

Flexible uniqueness constraints beyond simple job-level uniqueness:

```elixir
@decorate scheduled(
  cron: @hourly,
  unique: [
    by: [:name, :queue, {:args, [:user_id]}],  # What makes it unique
    states: [:running, :scheduled],             # Prevent if in these states
    period: {1, :hour}                          # Time window for uniqueness
  ]
)
def sync_user_data(args) do
  user_id = args["user_id"]
  # Only one sync per user_id per hour
end
```

### Unique Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `by` | list | `[:name]` | Fields for uniqueness key |
| `states` | list | `[:running]` | Block if job exists in these states |
| `period` | duration | `nil` | Time window (nil = forever) |

### Unique By Fields

| Field | Description |
|-------|-------------|
| `:name` | Job name |
| `:queue` | Queue name |
| `:args` | Full args map |
| `{:args, [:key]}` | Specific arg keys |

### Examples

```elixir
# Only one running at a time (default)
unique: true

# One per user, any state
unique: [by: [{:args, [:user_id]}], states: [:running, :scheduled, :completed]]

# One per day globally
unique: [by: [:name], period: {1, :day}]

# One per queue + args combination
unique: [by: [:queue, :args]]
```

### Conflict Handling

When a unique conflict is detected:
- Job is skipped (not enqueued)
- `:skip` telemetry emitted with reason `:unique_conflict`
- Original job continues unaffected

---

## Middleware Chain

Intercept job lifecycle for cross-cutting concerns:

```elixir
# config/prod.exs
config :events, OmScheduler,
  middleware: [
    OmScheduler.Middleware.Logging,
    OmScheduler.Middleware.Telemetry,
    {OmScheduler.Middleware.ErrorReporter, reporter: &Sentry.capture/2}
  ]
```

### Built-in Middleware

| Module | Purpose |
|--------|---------|
| `Middleware.Logging` | Log job start/complete/error |
| `Middleware.Telemetry` | Emit middleware-specific telemetry |
| `Middleware.ErrorReporter` | Report errors to external services |

### Custom Middleware

```elixir
defmodule MyApp.Middleware.Timing do
  @behaviour OmScheduler.Middleware
  alias FnTypes.Timing

  @impl true
  def before_execute(job, context) do
    {:ok, Map.put(context, :started_at, System.monotonic_time())}
  end

  @impl true
  def after_execute(job, result, context) do
    duration = Timing.duration_since(context.started_at)
    Logger.info("Job #{job.name} took #{duration.ms}ms")  # Clear units
    {:ok, result}
  end

  @impl true
  def on_error(job, error, context) do
    Logger.error("Job #{job.name} failed: #{inspect(error)}")
    {:ok, error}
  end

  @impl true
  def on_complete(job, result, context) do
    # Always called, success or failure
    :ok
  end
end
```

### Lifecycle Hooks

| Hook | When Called | Return |
|------|-------------|--------|
| `before_execute/2` | Before job starts | `{:ok, context}` or `{:halt, reason}` |
| `after_execute/3` | After success | `{:ok, result}` or `{:error, reason}` |
| `on_error/3` | After failure | `{:ok, error}`, `{:retry, reason}`, `{:ignore, reason}` |
| `on_complete/3` | Always (optional) | `:ok` |

### Execution Order

1. `before_execute` - all middleware in order
2. Job executes
3. `after_execute` - all middleware in **reverse** order (success)
4. `on_error` - all middleware in order (failure)
5. `on_complete` - all middleware in order (always)

### Context

Middleware can store data in context for later hooks:

```elixir
def before_execute(job, context) do
  {:ok, Map.put(context, :request_id, generate_request_id())}
end

def after_execute(job, result, context) do
  # Access request_id from context
  Logger.info("Request #{context.request_id} completed")
  {:ok, result}
end
```

### Halting Execution

Middleware can prevent job execution:

```elixir
def before_execute(job, context) do
  case RateLimiter.check(job) do
    :ok -> {:ok, context}
    :limited -> {:halt, :rate_limited}
  end
end
```

When halted, job returns `{:error, {:middleware_halt, reason}}`.

---

## Circuit Breaker

Protects against cascading failures by tracking job failures per circuit:

```elixir
# config/prod.exs
config :events, OmScheduler,
  circuit_breakers: [
    external_api: [
      failure_threshold: 5,
      success_threshold: 2,
      reset_timeout: {30, :seconds}
    ],
    payment_gateway: [
      failure_threshold: 3,
      reset_timeout: {1, :minute}
    ]
  ]
```

### Usage with Jobs

```elixir
@decorate scheduled(
  cron: "0 * * * *",
  meta: %{circuit_breaker: :external_api}
)
def sync_data do
  ExternalApi.sync()
end
```

### Circuit States

| State | Behavior |
|-------|----------|
| **Closed** | Normal operation, jobs execute |
| **Open** | Threshold exceeded, jobs skip immediately |
| **Half-Open** | Testing recovery, limited executions allowed |

### State Transitions

```
Closed  ──[failures >= threshold]──>  Open
   ^                                    │
   │                                    │
   └──[successes >= threshold]──  Half-Open  <──[reset_timeout]──┘
```

### Runtime API

```elixir
alias OmScheduler.CircuitBreaker

# Check circuit state
CircuitBreaker.get_state(:external_api)
#=> %{state: :closed, failure_count: 2, ...}

# Get all circuits
CircuitBreaker.get_all_states()

# Manually reset a circuit
CircuitBreaker.reset(:external_api)

# Register a new circuit at runtime
CircuitBreaker.register(:new_api, failure_threshold: 3)
```

### Telemetry

```elixir
[:scheduler, :circuit_breaker, :state_change]
# Metadata: %{circuit: :external_api, from: :closed, to: :open}

[:scheduler, :circuit_breaker, :trip]
# Metadata: %{circuit: :external_api, failure_count: 5, error: ...}

[:scheduler, :circuit_breaker, :reject]
# Metadata: %{circuit: :external_api}
```

---

## Error Classification

Smart retry decisions based on error type:

```elixir
alias OmScheduler.ErrorClassifier

# Classify an error
ErrorClassifier.classify(:timeout)
#=> %{class: :retryable, retryable: true, max_retries: 5, strategy: :exponential, ...}

ErrorClassifier.classify(:not_found)
#=> %{class: :terminal, retryable: false, max_retries: 0, ...}
```

### Error Classes

| Class | Behavior | Examples |
|-------|----------|----------|
| **Retryable** | Exponential backoff, 5 retries | timeout, connection_refused, rate_limited |
| **Transient** | Quick fixed delay, 3 retries | busy, overloaded, temporary_failure |
| **Degraded** | Slower backoff, 2 retries | service_unavailable, bad_gateway |
| **Terminal** | No retries, discard | not_found, unauthorized, validation_error |

### Smart Retry Flow

```
Error occurs
    │
    ▼
ErrorClassifier.next_action(error, attempt)
    │
    ├─ {:retry, delay_ms}  → Retry after delay
    │
    ├─ :dead_letter        → Send to DLQ (retries exhausted)
    │
    └─ :discard            → Terminal error, don't retry
```

### Custom Error Classification

Implement the `Recoverable` protocol for custom errors:

```elixir
defimpl Events.Protocols.Recoverable, for: MyApp.PaymentError do
  def recoverable?(%{code: :soft_decline}), do: true
  def recoverable?(_), do: false

  def strategy(%{code: :soft_decline}), do: :retry_with_backoff
  def strategy(_), do: :fail_fast

  def severity(%{code: :soft_decline}), do: :transient
  def severity(_), do: :permanent

  def trips_circuit?(%{code: :gateway_error}), do: true
  def trips_circuit?(_), do: false

  def max_attempts(_), do: 3
  def retry_delay(_, attempt), do: 1000 * attempt
  def fallback(_), do: nil
end
```

---

## Dead Letter Queue

Stores jobs that fail after exhausting retries:

```elixir
# config/prod.exs
config :events, OmScheduler,
  dead_letter: [
    enabled: true,
    max_age: {30, :days},
    max_entries: 10_000,
    on_dead_letter: &MyApp.notify_failure/1
  ]
```

### Viewing Dead Letters

```elixir
alias OmScheduler.DeadLetter

# List entries
DeadLetter.list(limit: 50)
DeadLetter.list(queue: :billing, error_class: :retryable)

# Get specific entry
DeadLetter.get("entry_id")

# Get statistics
DeadLetter.stats()
#=> %{total: 42, by_queue: %{default: 30, billing: 12}, by_error_class: %{retryable: 35, terminal: 7}}
```

### Retrying Dead Letters

```elixir
# Retry a single entry
DeadLetter.retry("entry_id")

# Retry all entries matching filter
DeadLetter.retry_all(queue: :billing)
DeadLetter.retry_all(error_class: :retryable, limit: 100)
```

### Cleanup

```elixir
# Delete specific entry
DeadLetter.delete("entry_id")

# Prune old entries
DeadLetter.prune(before: ~U[2024-01-01 00:00:00Z])
```

### Entry Structure

```elixir
%DeadLetter.Entry{
  id: "abc123",
  job_name: "sync_data",
  queue: :default,
  module: "MyApp.Jobs",
  function: "sync",
  args: %{user_id: 123},
  error: %{type: :timeout},
  error_class: :retryable,
  attempts: 5,
  first_failed_at: ~U[2024-01-15 10:00:00Z],
  last_failed_at: ~U[2024-01-15 10:15:00Z],
  stacktrace: "...",
  meta: %{}
}
```

### Telemetry

```elixir
[:scheduler, :dead_letter, :insert]
# Metadata: %{job_name: "...", queue: :default, error_class: :retryable, attempts: 5}

[:scheduler, :dead_letter, :retry]
# Metadata: %{job_name: "...", queue: :default}

[:scheduler, :dead_letter, :prune]
# Measurements: %{count: 150}
```

---

## Workflow System

Multi-step DAG workflows with dependencies, conditions, and scheduling.

### Quick Start

```elixir
# Decorator API (Recommended)
defmodule MyApp.Onboarding do
  use OmScheduler.Workflow, name: :user_onboarding

  @decorate step()
  def create_account(ctx), do: {:ok, %{user_id: Users.create!(ctx.email)}}

  @decorate step(after: :create_account)
  def send_welcome(ctx), do: Mailer.send_welcome(ctx.user_id)

  @decorate step(after: :send_welcome)
  def notify_team(ctx), do: Slack.notify(ctx.user_id)
end

# Builder API
alias OmScheduler.Workflow

Workflow.new(:data_pipeline)
|> Workflow.step(:fetch, &fetch/1)
|> Workflow.step(:transform, &transform/1, after: :fetch)
|> Workflow.step(:upload, &upload/1, after: :transform)
|> Workflow.schedule(cron: "0 6 * * *")
|> Workflow.register()
```

### Workflow Scheduling

```elixir
# Enable the workflow scheduler plugin
config :events, OmScheduler,
  plugins: [
    OmScheduler.Plugins.Cron,
    {OmScheduler.Workflow.Scheduler,
      interval: {1, :minute},  # Check frequency
      limit: 50}               # Max workflows per tick
  ]

# Define scheduled workflow
defmodule MyApp.DailyExport do
  use OmScheduler.Workflow,
    name: :daily_export,
    schedule: [cron: "0 6 * * *"]  # Daily at 6 AM

  @decorate step()
  def fetch_data(ctx), do: ...
end

# Schedule options
schedule: [cron: "0 6 * * *"]              # Cron expression
schedule: [cron: ["0 6 * * *", "0 18 * * *"]]  # Multiple
schedule: [every: {30, :minutes}]           # Interval
schedule: [at: ~U[2025-12-25 00:00:00Z]]   # One-time
schedule: [
  every: {1, :hour},
  start_at: ~U[2025-01-01 00:00:00Z],
  end_at: ~U[2025-01-31 23:59:59Z]
]
```

### Step Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `after` | atom/list | nil | Dependencies (all must complete) |
| `after_any` | list | nil | Any dependency (first wins) |
| `when` | function | nil | Condition `fn ctx -> bool end` |
| `rollback` | atom | nil | Compensation function |
| `timeout` | duration | 5 min | Step timeout |
| `max_retries` | int | 3 | Max retry attempts |
| `on_error` | atom | `:fail` | `:fail`, `:skip`, `:continue` |

### Runtime API

```elixir
alias OmScheduler.Workflow

# Start workflow
{:ok, exec_id} = Workflow.start(:user_onboarding, %{email: "user@example.com"})

# Schedule for later
{:ok, exec_id} = Workflow.schedule_execution(:user_onboarding,
  context: %{email: "user@example.com"},
  at: ~U[2025-12-25 00:00:00Z]
)

# Control
Workflow.pause(exec_id)
Workflow.resume(exec_id, context: %{approved: true})
Workflow.cancel(exec_id, reason: :user_requested, rollback: true)

# Query
{:ok, state} = Workflow.get_state(exec_id)
running = Workflow.list_running(:user_onboarding)
```

### Workflow Telemetry

```elixir
# Workflow lifecycle
[:events, :scheduler, :workflow, :start]
[:events, :scheduler, :workflow, :stop]
[:events, :scheduler, :workflow, :exception]
[:events, :scheduler, :workflow, :pause]
[:events, :scheduler, :workflow, :resume]
[:events, :scheduler, :workflow, :cancel]
[:events, :scheduler, :workflow, :fail]

# Step lifecycle
[:events, :scheduler, :workflow, :step, :start]
[:events, :scheduler, :workflow, :step, :stop]
[:events, :scheduler, :workflow, :step, :exception]
[:events, :scheduler, :workflow, :step, :skip]
[:events, :scheduler, :workflow, :step, :retry]

# Rollback
[:events, :scheduler, :workflow, :rollback, :start]
[:events, :scheduler, :workflow, :rollback, :stop]
[:events, :scheduler, :workflow, :rollback, :exception]
```

### Introspection

```elixir
# Summary
Workflow.summary(:user_onboarding)

# Generate Mermaid diagram
Workflow.to_mermaid(:user_onboarding)

# ASCII table
Workflow.to_table(:user_onboarding)

# List all workflows
Workflow.list_all()
```
