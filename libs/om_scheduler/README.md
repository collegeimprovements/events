# OmScheduler

Cron-based job scheduler with workflows, retries, and pluggable backends.

## Installation

```elixir
def deps do
  [{:om_scheduler, "~> 0.1.0"}]
end
```

## Quick Start

### 1. Configure

```elixir
# config/config.exs
config :om_scheduler,
  enabled: true,
  store: :memory,  # or :database for production
  queues: [default: 10, critical: 5]
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

## Cron Expressions

```elixir
@decorate scheduled(cron: "0 6 * * *")      # 6 AM daily
@decorate scheduled(cron: "*/15 * * * *")   # Every 15 minutes
@decorate scheduled(cron: "0 0 * * MON")    # Midnight every Monday

# Cron macros
@decorate scheduled(cron: @hourly)
@decorate scheduled(cron: @daily)
@decorate scheduled(cron: @weekly)
@decorate scheduled(cron: @monthly)
```

## Intervals

```elixir
@decorate scheduled(every: {30, :seconds})
@decorate scheduled(every: {5, :minutes})
@decorate scheduled(every: {1, :hour})
```

## Options

```elixir
@decorate scheduled(
  cron: "0 * * * *",
  queue: :default,          # Queue name
  timeout: 60_000,          # Execution timeout
  max_retries: 3,           # Retry attempts
  unique: true,             # Prevent overlapping
  tags: [:reports],         # Tags for filtering
  priority: 0               # 0-9, lower is higher
)
```

## Runtime API

```elixir
# Job management
OmScheduler.insert(%{name: "cleanup", cron: "0 2 * * *", ...})
OmScheduler.pause_job("cleanup")
OmScheduler.resume_job("cleanup")
OmScheduler.run_now("cleanup")
OmScheduler.cancel_job("cleanup")

# Queue management
OmScheduler.pause_queue(:default)
OmScheduler.resume_queue(:default)
OmScheduler.scale_queue(:default, 20)

# Monitoring
OmScheduler.queue_stats()
OmScheduler.running_jobs()
OmScheduler.history("cleanup", limit: 10)
OmScheduler.status("cleanup")
```

## Worker API

For complex jobs with lifecycle hooks:

```elixir
defmodule MyApp.ExportWorker do
  use OmScheduler.Worker

  @impl true
  def schedule do
    [cron: "0 3 * * *", max_retries: 5, timeout: 300_000]
  end

  @impl true
  def perform(%{attempt: attempt, args: args}) do
    # Your job logic
    :ok
  end

  @impl true
  def on_failure(job, error) do
    # Handle failure
  end
end
```

## Workflows

DAG-based workflows with dependencies:

```elixir
defmodule MyApp.OrderWorkflow do
  use OmScheduler.Workflow, name: :order_processing

  @decorate step()
  def validate(ctx), do: {:ok, %{order: Orders.get!(ctx.order_id)}}

  @decorate step(after: :validate)
  def reserve_inventory(ctx), do: {:ok, %{reservation: Inventory.reserve(ctx.order)}}

  @decorate step(after: :reserve_inventory, rollback: :release_inventory)
  def charge_payment(ctx), do: {:ok, %{payment: Payments.charge(ctx.order)}}

  @decorate step(after: :charge_payment)
  def send_confirmation(ctx), do: Mailer.send_confirmation(ctx.order)

  def release_inventory(ctx), do: Inventory.release(ctx.reservation)
end

# Start workflow
{:ok, execution_id} = OmScheduler.Workflow.start(:order_processing, %{order_id: 123})
```

## License

MIT
