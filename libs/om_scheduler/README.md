# OmScheduler

Cron-based job scheduler with workflows, retries, batch processing, and pluggable backends.

## Installation

```elixir
def deps do
  [{:om_scheduler, "~> 0.1.0"}]
end
```

## Why OmScheduler?

```
Raw cron/Task approach:                 With OmScheduler:
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│ # External crontab               │   │ defmodule MyApp.Jobs do          │
│ */5 * * * * /app/bin/sync        │   │   use OmScheduler                │
│                                  │   │                                  │
│ # No retry on failure            │   │   @decorate scheduled(           │
│ # No visibility into runs        │   │     every: {5, :minutes},        │
│ # No dead letter queue           │   │     max_retries: 5,              │
│ # No cluster coordination        │   │     unique: true                 │
│ # Manual error handling          │   │   )                              │
│                                  │   │   def sync, do: Sync.run()       │
│ def sync do                      │   │ end                              │
│   # Hope it works...             │   │                                  │
│   case do_work() do              │   │ # Automatic retries              │
│     :ok -> :ok                   │   │ # Job history & monitoring       │
│     {:error, _} ->               │   │ # Dead letter queue              │
│       # Log and forget?          │   │ # Cluster-aware (one node runs)  │
│       # Manual retry?            │   │ # Telemetry & observability      │
│   end                            │   │ # Queue management               │
│ end                              │   │ # Workflow orchestration         │
└──────────────────────────────────┘   └──────────────────────────────────┘
```

---

## Quick Start

### 1. Configure

```elixir
# config/config.exs
config :om_scheduler,
  enabled: true,
  store: :memory,  # or :database for production
  queues: [default: 10, critical: 5, imports: 20]
```

### 2. Define Jobs

```elixir
defmodule MyApp.Jobs do
  use OmScheduler

  @decorate scheduled(cron: "0 6 * * *")
  def daily_report do
    Reports.generate_daily()
  end

  @decorate scheduled(every: {5, :minutes}, unique: true)
  def sync_inventory do
    Inventory.sync_all()
  end

  @decorate scheduled(cron: @hourly, queue: :critical, max_retries: 5)
  def process_payments do
    Payments.process_pending()
  end
end
```

### 3. Start Scheduler

```elixir
# application.ex
children = [
  MyApp.Repo,
  OmScheduler.Supervisor
]
```

---

## Cron Expressions

Standard 5-field cron format:

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

```elixir
# Time-based
@decorate scheduled(cron: "0 6 * * *")      # 6 AM daily
@decorate scheduled(cron: "30 9 * * *")     # 9:30 AM daily
@decorate scheduled(cron: "0 0 * * *")      # Midnight

# Intervals
@decorate scheduled(cron: "*/5 * * * *")    # Every 5 minutes
@decorate scheduled(cron: "*/15 * * * *")   # Every 15 minutes
@decorate scheduled(cron: "0 */2 * * *")    # Every 2 hours

# Day-based
@decorate scheduled(cron: "0 0 * * MON")    # Midnight every Monday
@decorate scheduled(cron: "0 6 * * MON-FRI") # 6 AM weekdays
@decorate scheduled(cron: "0 18 * * SAT,SUN") # 6 PM weekends

# Monthly
@decorate scheduled(cron: "0 0 1 * *")      # Midnight on 1st of month
@decorate scheduled(cron: "0 0 15 * *")     # Midnight on 15th of month
@decorate scheduled(cron: "0 0 L * *")      # Last day of month

# Multiple times
@decorate scheduled(cron: "0 6,12,18 * * *") # 6 AM, noon, 6 PM
@decorate scheduled(cron: "0 0 1,15 * *")    # 1st and 15th of month
```

### Cron Macros

Built-in macros for common schedules:

```elixir
@decorate scheduled(cron: @yearly)          # "0 0 1 1 *"
@decorate scheduled(cron: @monthly)         # "0 0 1 * *"
@decorate scheduled(cron: @weekly)          # "0 0 * * 0"
@decorate scheduled(cron: @daily)           # "0 0 * * *"
@decorate scheduled(cron: @hourly)          # "0 * * * *"
@decorate scheduled(cron: @minutely)        # "* * * * *"
```

### Multiple Schedules

```elixir
# Run at multiple times
@decorate scheduled(cron: ["0 6 * * *", "0 18 * * *"])
def sync_twice_daily do
  ExternalService.sync()
end
```

---

## Intervals

For simpler scheduling without cron syntax:

```elixir
@decorate scheduled(every: {30, :seconds})
def poll_queue, do: Queue.process_pending()

@decorate scheduled(every: {5, :minutes})
def sync_cache, do: Cache.refresh()

@decorate scheduled(every: {1, :hour})
def cleanup_temp, do: TempFiles.cleanup()

@decorate scheduled(every: {6, :hours})
def generate_reports, do: Reports.generate_all()

@decorate scheduled(every: {1, :day})
def daily_maintenance, do: Maintenance.run()
```

---

## Decorator Options

Full list of `@decorate scheduled()` options:

```elixir
@decorate scheduled(
  # Schedule (one required)
  cron: "0 * * * *",              # Cron expression or list
  every: {5, :minutes},           # Interval tuple

  # Execution
  queue: :default,                # Queue name
  timeout: 60_000,                # Execution timeout (ms)
  priority: 0,                    # 0-9, lower = higher priority

  # Retries
  max_retries: 3,                 # Retry attempts on failure
  retry_delay: 1_000,             # Initial retry delay (ms)
  retry_backoff: :exponential,    # :fixed, :linear, :exponential
  retry_max_delay: 60_000,        # Max delay between retries
  retry_jitter: 0.25,             # Random jitter (0-1)

  # Uniqueness
  unique: true,                   # Prevent overlapping runs
  unique_period: {5, :minutes},   # Uniqueness window

  # Metadata
  tags: [:reports, :daily],       # Tags for filtering
  meta: %{tenant: "acme"},        # Custom metadata

  # Error handling
  on_error: :continue,            # :continue, :stop, :raise
  dead_letter: true,              # Send to DLQ on final failure

  # Cluster
  global: true                    # Run on one node only
)
```

---

## Worker API

For complex jobs with lifecycle hooks, use the Worker behaviour:

```elixir
defmodule MyApp.ExportWorker do
  use OmScheduler.Worker

  @impl true
  def schedule do
    [
      cron: "0 3 * * *",
      queue: :exports,
      max_retries: 5,
      timeout: 300_000
    ]
  end

  @impl true
  def perform(%{attempt: attempt, args: args, job: job}) do
    Logger.info("Export attempt #{attempt} for #{inspect(args)}")

    case ExportService.run(args) do
      {:ok, result} ->
        {:ok, result}

      {:error, :rate_limited} when attempt < 5 ->
        {:retry, :timer.seconds(attempt * 30)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def on_start(job) do
    Logger.info("Starting export job: #{job.name}")
  end

  @impl true
  def on_success(job, result) do
    Logger.info("Export completed: #{inspect(result)}")
    Notifications.send_export_complete(job.meta[:user_id])
  end

  @impl true
  def on_failure(job, error) do
    Logger.error("Export failed: #{inspect(error)}")
    Notifications.send_export_failed(job.meta[:user_id], error)
  end

  @impl true
  def on_cancel(job, reason) do
    Logger.warning("Export cancelled: #{inspect(reason)}")
    cleanup_partial_export(job)
  end
end
```

### Worker Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `schedule/0` | Yes | Returns schedule configuration |
| `perform/1` | Yes | Main job logic |
| `on_start/1` | No | Called before execution |
| `on_success/2` | No | Called on successful completion |
| `on_failure/2` | No | Called on final failure |
| `on_cancel/2` | No | Called when job is cancelled |

### Perform Return Values

| Return | Behavior |
|--------|----------|
| `:ok` | Success |
| `{:ok, result}` | Success with result |
| `{:error, reason}` | Failure, triggers retry |
| `{:retry, delay_ms}` | Explicit retry with delay |
| `{:cancel, reason}` | Stop retries, mark as cancelled |
| `{:discard, reason}` | Stop retries, don't save to DLQ |

---

## Runtime API

Manage jobs programmatically:

### Job CRUD

```elixir
# Create/update a job dynamically
OmScheduler.insert(%{
  name: "cleanup",
  module: MyApp.Jobs,
  function: :cleanup,
  cron: "0 2 * * *",
  queue: :maintenance,
  tags: [:cleanup, :nightly]
})

# Get a job
{:ok, job} = OmScheduler.get_job("cleanup")

# List jobs with filters
{:ok, jobs} = OmScheduler.list_jobs(queue: :default, tags: [:reports])

# Update a job
OmScheduler.update("cleanup", %{cron: "0 3 * * *"})

# Delete a job
OmScheduler.delete("cleanup")
```

### Job Control

```elixir
# Pause/resume scheduling
OmScheduler.pause_job("sync")
OmScheduler.resume_job("sync")

# Run immediately (bypass schedule)
OmScheduler.run_now("sync")

# Cancel a running job
OmScheduler.cancel_job("long_running_export")
OmScheduler.cancel_job("report", reason: :timeout)
```

### Queue Management

```elixir
# Pause/resume queues
OmScheduler.pause_queue(:default)
OmScheduler.resume_queue(:default)

# Scale queue concurrency
OmScheduler.scale_queue(:default, 20)

# Get queue statistics
OmScheduler.queue_stats()
#=> %{
#     default: %{running: 3, pending: 12, paused: false},
#     critical: %{running: 2, pending: 0, paused: false}
#   }
```

### Monitoring

```elixir
# Get currently running jobs
OmScheduler.running_jobs()
#=> ["sync", "export_data"]

# Get job execution history
{:ok, history} = OmScheduler.history("sync", limit: 10, since: ~U[2024-01-01 00:00:00Z])

# Get job status
{:ok, status} = OmScheduler.status("sync")
#=> %{
#     name: "sync",
#     state: :active,
#     last_run_at: ~U[2024-01-15 10:00:00Z],
#     next_run_at: ~U[2024-01-15 10:05:00Z],
#     run_count: 1234,
#     error_count: 5,
#     last_result: :ok,
#     last_error: nil
#   }
```

---

## Workflows

DAG-based workflows for multi-step job orchestration:

```
┌───────────┐
│  validate │
└─────┬─────┘
      │
      ▼
┌───────────┐
│  reserve  │ ◄── rollback: release_inventory
└─────┬─────┘
      │
      ▼
┌───────────┐
│  charge   │ ◄── rollback: refund
└─────┬─────┘
      │
      ▼
┌───────────┐
│   ship    │
└─────┬─────┘
      │
      ▼
┌───────────┐
│  notify   │
└───────────┘
```

### Decorator API (Recommended)

```elixir
defmodule MyApp.OrderWorkflow do
  use OmScheduler.Workflow, name: :order_processing

  @decorate step()
  def validate(ctx) do
    case Orders.get(ctx.order_id) do
      {:ok, order} -> {:ok, %{order: order}}
      {:error, _} = error -> error
    end
  end

  @decorate step(after: :validate, rollback: :release_inventory)
  def reserve_inventory(ctx) do
    case Inventory.reserve(ctx.order) do
      {:ok, reservation} -> {:ok, %{reservation: reservation}}
      {:error, _} = error -> error
    end
  end

  @decorate step(after: :reserve_inventory, rollback: :refund)
  def charge_payment(ctx) do
    case Payments.charge(ctx.order) do
      {:ok, payment} -> {:ok, %{payment: payment}}
      {:error, _} = error -> error
    end
  end

  @decorate step(after: :charge_payment)
  def ship_order(ctx) do
    case Shipping.create_shipment(ctx.order) do
      {:ok, shipment} -> {:ok, %{shipment: shipment}}
      {:error, _} = error -> error
    end
  end

  @decorate step(after: :ship_order)
  def send_confirmation(ctx) do
    Mailer.send_order_confirmation(ctx.order, ctx.shipment)
  end

  # Rollback functions
  def release_inventory(ctx) do
    Inventory.release(ctx.reservation)
  end

  def refund(ctx) do
    Payments.refund(ctx.payment)
  end
end

# Start workflow
{:ok, execution_id} = OmScheduler.Workflow.start(:order_processing, %{order_id: 123})
```

### Builder API

```elixir
alias OmScheduler.Workflow

Workflow.new(:order_processing, timeout: {1, :hour})
|> Workflow.step(:validate, &validate/1)
|> Workflow.step(:reserve, &reserve_inventory/1, after: :validate, rollback: &release/1)
|> Workflow.step(:charge, &charge_payment/1, after: :reserve, rollback: &refund/1)
|> Workflow.step(:ship, &ship_order/1, after: :charge)
|> Workflow.step(:notify, &send_confirmation/1, after: :ship)
|> Workflow.build!()
|> Workflow.register()
```

### Parallel Steps (Fan-Out)

```elixir
defmodule MyApp.DataPipeline do
  use OmScheduler.Workflow, name: :data_pipeline

  @decorate step()
  def fetch_data(ctx), do: {:ok, %{data: DataSource.fetch(ctx.source_id)}}

  # Parallel group
  @decorate step(after: :fetch_data, group: :transforms)
  def transform_json(ctx), do: {:ok, %{json: Transform.to_json(ctx.data)}}

  @decorate step(after: :fetch_data, group: :transforms)
  def transform_csv(ctx), do: {:ok, %{csv: Transform.to_csv(ctx.data)}}

  @decorate step(after: :fetch_data, group: :transforms)
  def transform_parquet(ctx), do: {:ok, %{parquet: Transform.to_parquet(ctx.data)}}

  # Fan-in: wait for all transforms
  @decorate step(after_group: :transforms)
  def upload_all(ctx) do
    S3.upload("data.json", ctx.json)
    S3.upload("data.csv", ctx.csv)
    S3.upload("data.parquet", ctx.parquet)
    {:ok, %{uploaded: true}}
  end
end
```

### Conditional Branching

```elixir
@decorate step()
def check_inventory(ctx), do: {:ok, %{in_stock: Inventory.check(ctx.order)}}

# Conditional steps
@decorate step(after: :check_inventory, when: &(&1.in_stock))
def ship_immediately(ctx), do: Shipping.ship(ctx.order)

@decorate step(after: :check_inventory, when: &(not &1.in_stock))
def create_backorder(ctx), do: Backorders.create(ctx.order)
```

### Human-in-the-Loop

```elixir
@decorate step(after: :calculate_discount, await_approval: true)
def apply_large_discount(ctx) when ctx.discount > 50 do
  # Workflow pauses here until approved
  Orders.apply_discount(ctx.order, ctx.discount)
end

# Resume with approval
Workflow.resume(execution_id, approval: :approved)
```

### Scheduled Workflows

```elixir
defmodule MyApp.DailyReport do
  use OmScheduler.Workflow,
    name: :daily_report,
    schedule: [cron: "0 6 * * *"]

  @decorate step()
  def fetch_data(ctx), do: {:ok, %{data: Reports.fetch_data(ctx.date)}}

  @decorate step(after: :fetch_data)
  def generate_pdf(ctx), do: {:ok, %{pdf: Reports.to_pdf(ctx.data)}}

  @decorate step(after: :generate_pdf)
  def email_report(ctx), do: Mailer.send_report(ctx.pdf)
end
```

### Workflow Control

```elixir
# Start
{:ok, execution_id} = Workflow.start(:order_processing, %{order_id: 123})

# Schedule for later
{:ok, execution_id} = Workflow.schedule_execution(:order_processing,
  context: %{order_id: 123},
  at: ~U[2025-01-15 10:00:00Z]
)

# Pause/Resume
Workflow.pause(execution_id)
Workflow.resume(execution_id, context: %{additional: "data"})

# Cancel
Workflow.cancel(execution_id, reason: :manual, rollback: true)

# Get state
{:ok, state} = Workflow.get_state(execution_id)
#=> %{
#     state: :running,
#     current_step: :charge_payment,
#     completed_steps: [:validate, :reserve_inventory],
#     context: %{order: ..., reservation: ...},
#     started_at: ~U[...],
#     ...
#   }

# List running executions
Workflow.list_running(:order_processing)
```

### Workflow Introspection

```elixir
# Get summary
Workflow.summary(:order_processing)

# Generate Mermaid diagram
Workflow.to_mermaid(:order_processing)
#=> """
#   graph TD
#     validate --> reserve_inventory
#     reserve_inventory --> charge_payment
#     ...
#   """

# Generate DOT (Graphviz)
Workflow.to_dot(:order_processing)

# ASCII table
Workflow.to_table(:order_processing)
```

---

## Batch Processing

Process large datasets in chunks:

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
      batch_size: 100,        # Items per batch
      concurrency: 5,         # Parallel item processing
      on_error: :continue,    # :continue, :stop, :retry
      checkpoint_interval: 50 # Save progress every N items
    ]
  end

  @impl true
  def fetch_items(cursor, opts) do
    limit = opts[:batch_size] || 100

    items =
      Item
      |> where([i], i.id > ^(cursor || 0))
      |> where([i], i.status == "pending")
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
      {:error, :rate_limited} -> {:retry, "Rate limited"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Batch Results

```elixir
{:ok, result} = OmScheduler.Batch.run(MyApp.ImportWorker, job, opts)
#=> %{
#     status: :completed,  # :completed, :partial, :failed
#     processed: 5000,
#     failed: 12,
#     errors: [...],
#     cursor: 5012,
#     duration_ms: 45000
#   }
```

---

## Dead Letter Queue

Failed jobs are automatically sent to the DLQ:

```elixir
alias OmScheduler.DeadLetter

# List failed jobs
{:ok, entries} = DeadLetter.list(limit: 50)
{:ok, entries} = DeadLetter.list(queue: :billing, error_class: :timeout)

# Get details
{:ok, entry} = DeadLetter.get("entry_id")
#=> %DeadLetter.Entry{
#     id: "abc123",
#     job_name: "sync_data",
#     queue: :default,
#     error: %{type: :timeout, message: "..."},
#     error_class: :retryable,
#     attempts: 5,
#     first_failed_at: ~U[...],
#     last_failed_at: ~U[...],
#     stacktrace: "..."
#   }

# Retry failed jobs
DeadLetter.retry("entry_id")
{:ok, count} = DeadLetter.retry_all(queue: :billing)

# Delete entries
DeadLetter.delete("entry_id")
{:ok, count} = DeadLetter.prune(before: ~U[2024-01-01 00:00:00Z])

# Statistics
DeadLetter.stats()
#=> %{
#     total: 150,
#     by_queue: %{default: 100, billing: 50},
#     by_error_class: %{timeout: 80, rate_limited: 70}
#   }
```

### DLQ Configuration

```elixir
config :om_scheduler,
  dead_letter: [
    enabled: true,
    max_age: {30, :days},
    max_entries: 10_000,
    on_dead_letter: &MyApp.Notifications.job_failed/1
  ]
```

---

## Cluster Support

OmScheduler supports distributed clusters:

```elixir
config :om_scheduler,
  peer: OmScheduler.Peer.Postgres,  # or :global
  store: :database
```

### Peer Strategies

| Strategy | Description |
|----------|-------------|
| `Peer.Global` | Uses Erlang's `:global` module |
| `Peer.Postgres` | PostgreSQL advisory locks |

### Cluster API

```elixir
# Check if current node is leader
OmScheduler.leader?()

# Get leader node
OmScheduler.leader_node()

# List all peers
OmScheduler.peers()
#=> [
#     %{node: :"app@host1", leader: true, started_at: ~U[...]},
#     %{node: :"app@host2", leader: false, started_at: ~U[...]}
#   ]
```

---

## Testing

Testing utilities for job and workflow testing:

```elixir
defmodule MyApp.WorkerTest do
  use ExUnit.Case
  use OmScheduler.Testing

  setup do
    OmScheduler.Testing.start_sandbox()
    :ok
  end

  test "job is enqueued" do
    {:ok, _job} = MyApp.SyncWorker.enqueue(%{user_id: 123})

    assert_enqueued worker: MyApp.SyncWorker
    assert_enqueued worker: MyApp.SyncWorker, args: %{user_id: 123}
  end

  test "job executes successfully" do
    assert :ok = perform_job(MyApp.SyncWorker, %{user_id: 123})
  end

  test "job with specific queue" do
    {:ok, _} = MyApp.CriticalWorker.enqueue(%{data: "test"})
    assert_enqueued worker: MyApp.CriticalWorker, queue: "critical"
  end

  test "no duplicate jobs" do
    perform_job(MyApp.UniqueWorker, %{id: 1})
    refute_enqueued worker: MyApp.UniqueWorker, args: %{id: 1}
  end
end
```

### Workflow Testing

```elixir
test "workflow executes all steps" do
  {:ok, execution_id} = start_workflow(:order_processing, %{order_id: 123})

  {:ok, result} = wait_for_workflow(execution_id, timeout: 5000)

  assert result.state == :completed
  assert_step_executed(execution_id, :validate)
  assert_step_executed(execution_id, :charge_payment)
  assert_workflow_completed(execution_id)
end

test "workflow handles failure" do
  {:ok, execution_id} = start_workflow(:order_processing, %{order_id: :invalid})

  {:ok, result} = wait_for_workflow(execution_id)

  assert result.state == :failed
  assert_workflow_failed(execution_id)
end
```

### Test Configuration

```elixir
# config/test.exs
config :om_scheduler,
  testing: :manual,  # :manual or :inline
  enabled: false
```

---

## Telemetry Events

OmScheduler emits telemetry events for observability:

### Job Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:scheduler, :job, :start]` | `%{system_time: t}` | `%{job_name, queue}` |
| `[:scheduler, :job, :stop]` | `%{duration: ms}` | `%{job_name, queue, result}` |
| `[:scheduler, :job, :exception]` | `%{duration: ms}` | `%{job_name, queue, error}` |
| `[:scheduler, :job, :retry]` | `%{attempt: n}` | `%{job_name, queue, delay}` |

### Queue Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:scheduler, :queue, :push]` | `%{count: 1}` | `%{queue}` |
| `[:scheduler, :queue, :pop]` | `%{count: 1}` | `%{queue}` |
| `[:scheduler, :queue, :scale]` | `%{concurrency: n}` | `%{queue}` |

### Workflow Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:scheduler, :workflow, :start]` | `%{system_time: t}` | `%{workflow, execution_id}` |
| `[:scheduler, :workflow, :stop]` | `%{duration: ms}` | `%{workflow, execution_id, state}` |
| `[:scheduler, :workflow, :step, :start]` | `%{system_time: t}` | `%{workflow, step}` |
| `[:scheduler, :workflow, :step, :stop]` | `%{duration: ms}` | `%{workflow, step, result}` |

### Dead Letter Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:scheduler, :dead_letter, :insert]` | `%{system_time: t}` | `%{job_name, error_class}` |
| `[:scheduler, :dead_letter, :retry]` | `%{count: 1}` | `%{job_name}` |
| `[:scheduler, :dead_letter, :prune]` | `%{count: n}` | `%{}` |

### Attaching Handlers

```elixir
# In application.ex
defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_job_complete(_event, measurements, metadata, _config) do
    Logger.info("Job #{metadata.job_name} completed in #{measurements.duration}ms")
  end

  def handle_job_failure(_event, _measurements, metadata, _config) do
    Sentry.capture_message("Job failed: #{metadata.job_name}", extra: metadata)
  end
end

# Attach handlers
:telemetry.attach_many(
  "scheduler-handlers",
  [
    [:scheduler, :job, :stop],
    [:scheduler, :job, :exception]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

---

## Real-World Examples

### 1. E-commerce Order Processing

```elixir
defmodule MyApp.OrderWorkflow do
  use OmScheduler.Workflow,
    name: :order_processing,
    timeout: {30, :minutes},
    on_failure: :handle_failure,
    dead_letter: true

  @decorate step()
  def validate_order(ctx) do
    with {:ok, order} <- Orders.get(ctx.order_id),
         :ok <- Orders.validate(order) do
      {:ok, %{order: order}}
    end
  end

  @decorate step(after: :validate_order, rollback: :void_authorization)
  def authorize_payment(ctx) do
    case Payments.authorize(ctx.order) do
      {:ok, auth} -> {:ok, %{authorization: auth}}
      {:error, _} = error -> error
    end
  end

  @decorate step(after: :authorize_payment, rollback: :release_inventory)
  def reserve_inventory(ctx) do
    case Inventory.reserve(ctx.order.items) do
      {:ok, reservation} -> {:ok, %{reservation: reservation}}
      {:error, :insufficient_stock} -> {:error, :out_of_stock}
    end
  end

  @decorate step(after: :reserve_inventory)
  def capture_payment(ctx) do
    Payments.capture(ctx.authorization)
  end

  @decorate step(after: :capture_payment, group: :notifications)
  def send_confirmation(ctx) do
    Mailer.send_order_confirmation(ctx.order)
  end

  @decorate step(after: :capture_payment, group: :notifications)
  def update_analytics(ctx) do
    Analytics.track_purchase(ctx.order)
  end

  @decorate step(after_group: :notifications)
  def finalize(ctx) do
    Orders.mark_confirmed(ctx.order)
  end

  # Rollbacks
  def void_authorization(ctx), do: Payments.void(ctx.authorization)
  def release_inventory(ctx), do: Inventory.release(ctx.reservation)

  # Error handler
  def handle_failure(ctx) do
    Orders.mark_failed(ctx.order_id)
    Mailer.send_order_failed(ctx.order_id)
  end
end
```

### 2. Data Pipeline with Batch Processing

```elixir
defmodule MyApp.DataSyncWorker do
  use OmScheduler.Batch.Worker

  @impl true
  def schedule do
    [
      cron: "0 */4 * * *",
      queue: :sync,
      max_retries: 3,
      timeout: :timer.hours(2)
    ]
  end

  @impl true
  def batch_options do
    [
      batch_size: 500,
      concurrency: 10,
      on_error: :continue,
      checkpoint_interval: 100
    ]
  end

  @impl true
  def fetch_items(cursor, opts) do
    since = cursor || Sync.last_sync_time()

    items =
      ExternalAPI.list_changes(since: since, limit: opts[:batch_size])
      |> Enum.map(&normalize_item/1)

    case items do
      [] -> {:done, []}
      items -> {:more, items, List.last(items).updated_at}
    end
  end

  @impl true
  def process_item(item, _context) do
    case Sync.upsert(item) do
      {:ok, _} -> :ok
      {:error, :conflict} -> resolve_conflict(item)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_item(raw), do: # ...
  defp resolve_conflict(item), do: # ...
end
```

### 3. Multi-tenant Report Generation

```elixir
defmodule MyApp.ReportGenerator do
  use OmScheduler

  @decorate scheduled(cron: "0 6 * * MON", queue: :reports)
  def weekly_summary do
    Tenants.active()
    |> Enum.each(fn tenant ->
      Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn ->
        generate_for_tenant(tenant)
      end)
    end)
  end

  defp generate_for_tenant(tenant) do
    data = Analytics.weekly_summary(tenant.id)
    pdf = Reports.generate_pdf(data)
    S3.upload("reports/#{tenant.id}/weekly_#{Date.utc_today()}.pdf", pdf)
    Mailer.send_weekly_report(tenant, pdf)
  end
end
```

### 4. Webhook Retry Handler

```elixir
defmodule MyApp.WebhookWorker do
  use OmScheduler.Worker

  @impl true
  def schedule do
    [
      queue: :webhooks,
      max_retries: 10,
      retry_backoff: :exponential,
      retry_delay: 1_000,
      retry_max_delay: 3_600_000,  # 1 hour
      dead_letter: true
    ]
  end

  @impl true
  def perform(%{args: %{"url" => url, "payload" => payload}, attempt: attempt}) do
    case HTTPClient.post(url, payload, timeout: 30_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} when status in [429, 503] ->
        # Rate limited or service unavailable
        {:retry, :timer.seconds(attempt * 60)}

      {:ok, %{status: status}} when status >= 400 ->
        {:error, {:http_error, status}}

      {:error, :timeout} ->
        {:retry, :timer.seconds(30)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 5. Scheduled Cleanup Jobs

```elixir
defmodule MyApp.MaintenanceJobs do
  use OmScheduler

  # Clean up expired sessions
  @decorate scheduled(cron: "0 * * * *", unique: true)
  def cleanup_sessions do
    Sessions.delete_expired()
  end

  # Archive old data
  @decorate scheduled(cron: "0 3 * * *", timeout: :timer.hours(2))
  def archive_old_data do
    cutoff = Date.add(Date.utc_today(), -90)

    Orders.archive_before(cutoff)
    Logs.archive_before(cutoff)
    Analytics.archive_before(cutoff)
  end

  # Database maintenance
  @decorate scheduled(cron: "0 4 * * SUN", queue: :maintenance)
  def vacuum_tables do
    Repo.query!("VACUUM ANALYZE users")
    Repo.query!("VACUUM ANALYZE orders")
    Repo.query!("REINDEX TABLE orders")
  end

  # Health check
  @decorate scheduled(every: {1, :minute})
  def health_check do
    checks = [
      {:database, Repo.connected?()},
      {:redis, Redis.ping() == :pong},
      {:s3, S3.accessible?()}
    ]

    unless Enum.all?(checks, fn {_, ok} -> ok end) do
      Alerts.send_health_alert(checks)
    end
  end
end
```

---

## Best Practices

### 1. Use Unique Jobs for Idempotency

```elixir
# Good: Prevents overlapping runs
@decorate scheduled(every: {5, :minutes}, unique: true)
def sync_external_api do
  # Safe from duplicate runs
end

# Bad: May run multiple times if slow
@decorate scheduled(every: {5, :minutes})
def slow_sync do
  # Could overlap if takes > 5 minutes
end
```

### 2. Set Appropriate Timeouts

```elixir
# Good: Explicit timeout based on expected duration
@decorate scheduled(cron: @hourly, timeout: :timer.minutes(10))
def generate_report do
  # 10 minute timeout for report generation
end

# Bad: Default timeout may be too short
@decorate scheduled(cron: @hourly)
def generate_large_report do
  # May timeout unexpectedly
end
```

### 3. Use Queues for Resource Isolation

```elixir
config :om_scheduler,
  queues: [
    default: 10,      # General jobs
    critical: 5,      # Payment processing (limited concurrency)
    imports: 20,      # High-concurrency data imports
    reports: 3        # Resource-intensive reports
  ]

@decorate scheduled(cron: @hourly, queue: :critical)
def process_payments, do: # ...

@decorate scheduled(cron: @daily, queue: :reports)
def generate_reports, do: # ...
```

### 4. Handle Errors Gracefully

```elixir
@impl true
def perform(%{args: args, attempt: attempt}) do
  case do_work(args) do
    {:ok, result} ->
      {:ok, result}

    {:error, :rate_limited} when attempt < 5 ->
      # Explicit retry with backoff
      {:retry, :timer.seconds(attempt * 30)}

    {:error, :invalid_data} ->
      # Permanent error, don't retry
      {:discard, :invalid_data}

    {:error, reason} ->
      # Retryable error
      {:error, reason}
  end
end
```

### 5. Use Workflows for Complex Processes

```elixir
# Good: Multi-step process as workflow
defmodule MyApp.OnboardingWorkflow do
  use OmScheduler.Workflow, name: :user_onboarding

  @decorate step()
  def create_account(ctx), do: # ...

  @decorate step(after: :create_account, rollback: :delete_account)
  def setup_billing(ctx), do: # ...

  @decorate step(after: :setup_billing)
  def send_welcome(ctx), do: # ...
end

# Bad: All-in-one job that's hard to debug/retry
def onboard_user(user_data) do
  # Everything in one function
  # Hard to track progress
  # No partial rollback
end
```

---

## Configuration Reference

```elixir
config :om_scheduler,
  # Enable/disable scheduler
  enabled: true,

  # Storage backend
  store: :memory,  # :memory, :database, :redis

  # Queue configuration
  queues: [
    default: 10,
    critical: 5
  ],

  # Cluster coordination
  peer: false,  # false, :global, OmScheduler.Peer.Postgres

  # Polling interval for scheduled jobs
  poll_interval: 1_000,

  # Shutdown grace period
  shutdown_timeout: 30_000,

  # Dead letter queue
  dead_letter: [
    enabled: true,
    max_age: {30, :days},
    max_entries: 10_000,
    on_dead_letter: &MyApp.handle_dlq/1
  ],

  # Telemetry prefix
  telemetry_prefix: [:my_app, :scheduler],

  # Testing mode
  testing: :manual  # :manual, :inline
```

### Database Store Configuration

```elixir
config :om_scheduler,
  store: :database,
  repo: MyApp.Repo

# Run migrations
mix ecto.gen.migration add_scheduler_tables

defmodule MyApp.Repo.Migrations.AddSchedulerTables do
  use Ecto.Migration

  def change do
    OmScheduler.Store.Database.Migration.up()
  end
end
```

### Redis Store Configuration

```elixir
config :om_scheduler,
  store: :redis,
  redis: [
    host: "localhost",
    port: 6379,
    database: 0
  ]
```

---

## License

MIT
