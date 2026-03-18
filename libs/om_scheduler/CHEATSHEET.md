# OmScheduler Cheatsheet

> Cron-based job scheduler with workflows, retries, and batch processing. For full docs, see `README.md`.

## Setup

```elixir
config :om_scheduler,
  enabled: true,
  store: :memory,                                # :memory | :database | :redis
  queues: [default: 10, critical: 5, imports: 20]

# application.ex
children = [OmScheduler.Supervisor]
```

---

## Scheduled Jobs (Decorator)

```elixir
defmodule MyApp.Jobs do
  use OmScheduler

  @decorate scheduled(cron: "0 6 * * *")
  def daily_report, do: Reports.generate_daily()

  @decorate scheduled(every: {5, :minutes}, unique: true)
  def sync_inventory, do: Inventory.sync_all()

  @decorate scheduled(cron: @hourly, queue: :critical, max_retries: 5)
  def process_payments, do: Payments.process_pending()
end
```

### Decorator Options

```elixir
@decorate scheduled(
  cron: "0 * * * *",            # or every: {5, :minutes}
  queue: :default,               # queue name
  timeout: 60_000,               # execution timeout (ms)
  priority: 0,                   # 0-9, lower = higher
  max_retries: 3,                # retry attempts
  retry_delay: 1_000,            # initial retry delay (ms)
  retry_backoff: :exponential,   # :fixed | :linear | :exponential
  unique: true,                  # prevent overlapping
  tags: [:reports],              # for filtering
  on_error: :continue,           # :continue | :stop | :raise
  dead_letter: true,             # send to DLQ on final failure
  global: true                   # one node only (cluster)
)
```

---

## Cron Expressions

```
┌───── minute (0-59)
│ ┌───── hour (0-23)
│ │ ┌───── day of month (1-31)
│ │ │ ┌───── month (1-12 or JAN-DEC)
│ │ │ │ ┌───── day of week (0-6 or SUN-SAT)
* * * * *
```

| Expression | Meaning |
|------------|---------|
| `"0 6 * * *"` | 6 AM daily |
| `"*/5 * * * *"` | Every 5 minutes |
| `"0 */2 * * *"` | Every 2 hours |
| `"0 6 * * MON-FRI"` | 6 AM weekdays |
| `"0 0 1 * *"` | Midnight 1st of month |
| `"0 6,12,18 * * *"` | 6 AM, noon, 6 PM |

### Macros

```elixir
@yearly   # "0 0 1 1 *"
@monthly  # "0 0 1 * *"
@weekly   # "0 0 * * 0"
@daily    # "0 0 * * *"
@hourly   # "0 * * * *"
@minutely # "* * * * *"
```

---

## Worker API

```elixir
defmodule MyApp.ExportWorker do
  use OmScheduler.Worker

  @impl true
  def schedule, do: [cron: "0 3 * * *", queue: :exports, max_retries: 5]

  @impl true
  def perform(%{attempt: attempt, args: args}) do
    case ExportService.run(args) do
      {:ok, result} -> {:ok, result}
      {:error, :rate_limited} when attempt < 5 -> {:retry, :timer.seconds(attempt * 30)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_success(_job, result), do: Notifications.send_complete(result)

  @impl true
  def on_failure(_job, error), do: Notifications.send_failed(error)
end
```

### Perform Return Values

| Return | Behavior |
|--------|----------|
| `:ok` / `{:ok, result}` | Success |
| `{:error, reason}` | Failure, triggers retry |
| `{:retry, delay_ms}` | Explicit retry with delay |
| `{:cancel, reason}` | Stop retries, mark cancelled |
| `{:discard, reason}` | Stop retries, skip DLQ |

---

## Runtime API

```elixir
# Job control
OmScheduler.run_now("sync")
OmScheduler.pause_job("sync")
OmScheduler.resume_job("sync")
OmScheduler.cancel_job("long_running")

# Queue management
OmScheduler.pause_queue(:default)
OmScheduler.resume_queue(:default)
OmScheduler.scale_queue(:default, 20)
OmScheduler.queue_stats()

# Monitoring
OmScheduler.running_jobs()
{:ok, status} = OmScheduler.status("sync")
{:ok, history} = OmScheduler.history("sync", limit: 10)
```

---

## Workflows

### Decorator API

```elixir
defmodule MyApp.OrderWorkflow do
  use OmScheduler.Workflow, name: :order_processing

  @decorate step()
  def validate(ctx), do: {:ok, %{order: Orders.get!(ctx.order_id)}}

  @decorate step(after: :validate, rollback: :release_inventory)
  def reserve(ctx), do: {:ok, %{reservation: Inventory.reserve(ctx.order)}}

  @decorate step(after: :reserve, rollback: :refund)
  def charge(ctx), do: {:ok, %{payment: Payments.charge(ctx.order)}}

  @decorate step(after: :charge)
  def notify(ctx), do: Mailer.send_confirmation(ctx.order)

  def release_inventory(ctx), do: Inventory.release(ctx.reservation)
  def refund(ctx), do: Payments.refund(ctx.payment)
end

{:ok, execution_id} = OmScheduler.Workflow.start(:order_processing, %{order_id: 123})
```

### Step Options

| Option | Description |
|--------|-------------|
| `after: :step_name` | Dependency |
| `rollback: :fn_name` | Rollback function |
| `group: :name` | Parallel group |
| `after_group: :name` | Fan-in (wait for group) |
| `when: &predicate/1` | Conditional execution |
| `await_approval: true` | Human-in-the-loop |

### Parallel Steps

```elixir
@decorate step(after: :fetch_data, group: :transforms)
def to_json(ctx), do: {:ok, %{json: Transform.to_json(ctx.data)}}

@decorate step(after: :fetch_data, group: :transforms)
def to_csv(ctx), do: {:ok, %{csv: Transform.to_csv(ctx.data)}}

@decorate step(after_group: :transforms)
def upload_all(ctx), do: S3.upload_all([ctx.json, ctx.csv])
```

### Workflow Control

```elixir
{:ok, id} = Workflow.start(:name, %{context: "data"})
{:ok, id} = Workflow.schedule_execution(:name, context: %{}, at: ~U[2025-01-15 10:00:00Z])

Workflow.pause(id)
Workflow.resume(id)
Workflow.cancel(id, reason: :manual, rollback: true)

{:ok, state} = Workflow.get_state(id)
Workflow.to_mermaid(:name)                        # Mermaid diagram
```

---

## Batch Processing

```elixir
defmodule MyApp.ImportWorker do
  use OmScheduler.Batch.Worker

  @impl true
  def schedule, do: [cron: "0 2 * * *", queue: :imports]

  @impl true
  def batch_options, do: [batch_size: 100, concurrency: 5, on_error: :continue]

  @impl true
  def fetch_items(cursor, opts) do
    items = Item |> where([i], i.id > ^(cursor || 0)) |> limit(^opts[:batch_size]) |> Repo.all()
    case items do
      [] -> {:done, []}
      items -> {:more, items, List.last(items).id}
    end
  end

  @impl true
  def process_item(item, _ctx), do: ImportService.import(item)
end
```

---

## Dead Letter Queue

```elixir
alias OmScheduler.DeadLetter

{:ok, entries} = DeadLetter.list(limit: 50, queue: :billing)
DeadLetter.retry("entry_id")
{:ok, count} = DeadLetter.retry_all(queue: :billing)
DeadLetter.delete("entry_id")
DeadLetter.stats()
```

---

## Telemetry Events

```
[:scheduler, :job,      :start | :stop | :exception | :retry]
[:scheduler, :queue,    :push | :pop | :scale]
[:scheduler, :workflow, :start | :stop]
[:scheduler, :workflow, :step, :start | :stop]
[:scheduler, :dead_letter, :insert | :retry | :prune]
```
