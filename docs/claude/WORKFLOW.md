# Workflow System

A clean, composable workflow system for orchestrating multi-step job DAGs with dependencies, timeouts, scheduled execution, and saga-pattern rollbacks.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Builder API](#builder-api)
4. [Decorator API](#decorator-api)
5. [Step Configuration](#step-configuration)
6. [Dependency Patterns](#dependency-patterns)
7. [Error Handling & Retries](#error-handling--retries)
8. [Rollback (Saga Pattern)](#rollback-saga-pattern)
9. [Advanced Features](#advanced-features)
10. [Scheduling](#scheduling)
11. [Runtime Management](#runtime-management)
12. [Introspection & Visualization](#introspection--visualization)
13. [Real-World Examples](#real-world-examples)
14. [Best Practices](#best-practices)
15. [Telemetry Events](#telemetry-events)
16. [LiveView Dashboard](#liveview-dashboard)
17. [File Structure](#file-structure)

---

## Quick Start

### Using Decorator API (Recommended)

```elixir
defmodule MyApp.UserOnboarding do
  use OmScheduler.Workflow, name: :user_onboarding

  @decorate step()
  def create_account(ctx) do
    user = Users.create!(ctx.email, ctx.name)
    {:ok, %{user_id: user.id}}
  end

  @decorate step(after: :create_account)
  def setup_profile(ctx) do
    profile = Profiles.create!(ctx.user_id)
    {:ok, %{profile_id: profile.id}}
  end

  @decorate step(after: :setup_profile)
  def send_welcome_email(ctx) do
    Mailer.send_welcome(ctx.user_id)
    :ok
  end
end

# Start the workflow
{:ok, execution_id} = Workflow.start(:user_onboarding, %{
  email: "alice@example.com",
  name: "Alice"
})
```

### Using Builder API

```elixir
alias OmScheduler.Workflow

Workflow.new(:user_onboarding)
|> Workflow.step(:create_account, &create_account/1)
|> Workflow.step(:setup_profile, &setup_profile/1, after: :create_account)
|> Workflow.step(:send_welcome_email, &send_welcome_email/1, after: :setup_profile)
|> Workflow.build!()
|> Workflow.register()

# Start the workflow
{:ok, execution_id} = Workflow.start(:user_onboarding, %{
  email: "alice@example.com",
  name: "Alice"
})
```

---

## Core Concepts

### Workflow

A workflow is a **Directed Acyclic Graph (DAG)** of steps. Each step can depend on other steps, and the engine executes them in the correct order, running independent steps in parallel.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Step A    │────▶│   Step B    │────▶│   Step D    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                                       ▲
       │            ┌─────────────┐            │
       └───────────▶│   Step C    │────────────┘
                    └─────────────┘
```

### Step

A step is a single unit of work. It can be:
- An anonymous function: `fn ctx -> {:ok, result} end`
- A module with `perform/1`: `MyWorker`
- An MFA tuple: `{Module, :function, []}`
- A nested workflow: `{:workflow, :other_workflow}`

### Context (Token Pattern)

Context flows through the workflow, accumulating results from each step:

```elixir
# Initial context
%{email: "alice@example.com"}

# After create_account step
%{email: "alice@example.com", user_id: 123}

# After setup_profile step
%{email: "alice@example.com", user_id: 123, profile_id: 456}
```

### Step Return Values

| Return | Meaning |
|--------|---------|
| `{:ok, map}` | Success, merge map into context |
| `:ok` | Success, no context changes |
| `{:error, reason}` | Failure (triggers retry or error handling) |
| `{:skip, reason}` | Skip this step, continue workflow |
| `{:await, opts}` | Pause for human approval |
| `{:expand, steps}` | Graft expansion (dynamic steps) |
| `{:snooze, duration}` | Pause and retry after duration |

---

## Builder API

The Builder API provides a fluent, pipeline-style interface for constructing workflows.

### Basic Workflow

```elixir
alias OmScheduler.Workflow

Workflow.new(:data_export)
|> Workflow.step(:fetch_data, &fetch_data/1)
|> Workflow.step(:transform, &transform/1, after: :fetch_data)
|> Workflow.step(:upload, &upload/1, after: :transform)
|> Workflow.step(:notify, &notify/1, after: :upload)
|> Workflow.build!()
```

### Workflow Options

```elixir
Workflow.new(:critical_pipeline,
  # Total workflow timeout
  timeout: {1, :hour},

  # Workflow-level retries (entire workflow restarts)
  max_retries: 3,
  retry_delay: {5, :seconds},
  retry_backoff: :exponential,

  # Default step configuration
  step_timeout: {5, :minutes},
  step_max_retries: 3,
  step_retry_delay: {1, :second},

  # Handlers
  on_failure: :cleanup_handler,
  on_success: :success_handler,
  on_cancel: :cancel_handler,

  # Dead letter queue
  dead_letter: true,
  dead_letter_ttl: {30, :days},

  # Metadata
  tags: ["critical", "daily"],
  metadata: %{owner: "data-team"}
)
```

### Parallel Steps (Fan-out)

```elixir
Workflow.new(:multi_upload)
|> Workflow.step(:fetch, &fetch/1)
|> Workflow.step(:transform, &transform/1, after: :fetch)
|> Workflow.parallel(:transform, [
     {:upload_s3, &upload_s3/1},
     {:upload_gcs, &upload_gcs/1},
     {:upload_azure, &upload_azure/1}
   ])
|> Workflow.build!()
```

### Fan-in (Wait for Multiple Steps)

```elixir
Workflow.new(:aggregation)
|> Workflow.step(:start, &start/1)
|> Workflow.fan_out(:start, [
     {:fetch_api_a, &fetch_api_a/1},
     {:fetch_api_b, &fetch_api_b/1},
     {:fetch_api_c, &fetch_api_c/1}
   ])
|> Workflow.fan_in([:fetch_api_a, :fetch_api_b, :fetch_api_c], :aggregate, &aggregate/1)
|> Workflow.step(:save, &save/1, after: :aggregate)
|> Workflow.build!()
```

### Conditional Branching

```elixir
Workflow.new(:order_processing)
|> Workflow.step(:validate, &validate_order/1)
|> Workflow.step(:check_stock, &check_stock/1, after: :validate)
|> Workflow.branch(:check_stock, [
     {:process_immediate, condition: &in_stock?/1, job: &process_immediate/1},
     {:backorder, condition: &out_of_stock?/1, job: &create_backorder/1},
     {:notify_vendor, condition: &needs_restock?/1, job: &notify_vendor/1}
   ])
|> Workflow.step(:complete, &complete_order/1,
     after: [:process_immediate, :backorder, :notify_vendor])
|> Workflow.build!()
```

### Nested Workflows

```elixir
# Define a reusable notification workflow
Workflow.new(:send_notification)
|> Workflow.step(:format, &format_message/1)
|> Workflow.step(:send, &send_message/1)
|> Workflow.step(:log, &log_notification/1)
|> Workflow.register()

# Use it as a step in another workflow
Workflow.new(:user_signup)
|> Workflow.step(:create_user, &create_user/1)
|> Workflow.add_workflow(:welcome_notification, :send_notification, after: :create_user)
|> Workflow.step(:complete, &complete_signup/1, after: :welcome_notification)
|> Workflow.build!()
```

### Scheduling

```elixir
# Cron schedule
Workflow.new(:daily_report)
|> Workflow.step(:generate, &generate_report/1)
|> Workflow.step(:send, &send_report/1, after: :generate)
|> Workflow.schedule(cron: "0 6 * * *")  # Daily at 6 AM
|> Workflow.register()

# Multiple cron patterns
Workflow.new(:sync_job)
|> Workflow.step(:sync, &sync_data/1)
|> Workflow.schedule(cron: ["0 6 * * *", "0 12 * * *", "0 18 * * *"])
|> Workflow.register()

# Interval-based
Workflow.new(:health_check)
|> Workflow.step(:check, &check_health/1)
|> Workflow.schedule(every: {5, :minutes})
|> Workflow.register()

# Event-triggered
Workflow.new(:order_processor)
|> Workflow.step(:process, &process_order/1)
|> Workflow.on_event("order.created")
|> Workflow.register()
```

---

## Decorator API

The Decorator API provides a declarative, module-based approach that's often cleaner for complex workflows.

### Basic Decorator Usage

```elixir
defmodule MyApp.DataPipeline do
  use OmScheduler.Workflow,
    name: :data_pipeline,
    timeout: {1, :hour},
    step_timeout: {10, :minutes}

  @decorate step()
  def fetch_data(ctx) do
    data = DataSource.fetch(ctx.query)
    {:ok, %{data: data}}
  end

  @decorate step(after: :fetch_data)
  def validate(ctx) do
    case Validator.validate(ctx.data) do
      :ok -> {:ok, %{validated: true}}
      {:error, errors} -> {:error, {:validation_failed, errors}}
    end
  end

  @decorate step(after: :validate, timeout: {30, :minutes})
  def transform(ctx) do
    transformed = Transformer.transform(ctx.data)
    {:ok, %{transformed_data: transformed}}
  end

  @decorate step(after: :transform)
  def save(ctx) do
    Database.save(ctx.transformed_data)
    :ok
  end
end
```

### Step Decorator Options

```elixir
@decorate step(
  # Dependencies
  after: :previous_step,              # Single dependency
  after: [:step_a, :step_b],          # Multiple dependencies (all must complete)
  after_any: [:step_a, :step_b],      # Any dependency (first to complete)
  after_group: :parallel_group,       # Wait for parallel group
  after_graft: :dynamic_steps,        # Wait for graft expansion

  # Parallel grouping
  group: :upload_group,               # Add to parallel group

  # Conditions
  when: &(&1.should_run),             # Condition function

  # Timeout & Retries
  timeout: {5, :minutes},
  max_retries: 5,
  retry_delay: {1, :second},
  retry_backoff: :exponential,
  retry_max_delay: {5, :minutes},
  retry_jitter: true,
  retry_on: [:timeout, :connection_error],
  no_retry_on: [:validation_error],

  # Error handling
  on_error: :fail,                    # :fail | :skip | :continue
  rollback: :rollback_function,       # Compensation function name

  # Special behaviors
  await_approval: true,               # Human-in-the-loop
  cancellable: true,                  # Can be cancelled mid-execution
  context_key: :custom_key,           # Custom key for result in context

  # Circuit breaker
  circuit_breaker: :external_api,
  circuit_breaker_opts: [failure_threshold: 5, reset_timeout: {30, :seconds}]
)
def my_step(ctx), do: ...
```

### Parallel Groups (Fan-out/Fan-in)

```elixir
defmodule MyApp.MultiUpload do
  use OmScheduler.Workflow, name: :multi_upload

  @decorate step()
  def prepare(ctx) do
    {:ok, %{data: prepare_data(ctx.input)}}
  end

  # Fan-out: all steps in the same group run in parallel
  @decorate step(after: :prepare, group: :uploads)
  def upload_s3(ctx) do
    url = S3.upload(ctx.data)
    {:ok, %{s3_url: url}}
  end

  @decorate step(after: :prepare, group: :uploads)
  def upload_gcs(ctx) do
    url = GCS.upload(ctx.data)
    {:ok, %{gcs_url: url}}
  end

  @decorate step(after: :prepare, group: :uploads)
  def upload_azure(ctx) do
    url = Azure.upload(ctx.data)
    {:ok, %{azure_url: url}}
  end

  # Fan-in: waits for entire group to complete
  @decorate step(after_group: :uploads)
  def notify_complete(ctx) do
    Notifier.send("Uploaded to: #{ctx.s3_url}, #{ctx.gcs_url}, #{ctx.azure_url}")
    :ok
  end
end
```

### Conditional Execution

```elixir
defmodule MyApp.OrderFulfillment do
  use OmScheduler.Workflow, name: :order_fulfillment

  @decorate step()
  def validate_order(ctx) do
    order = Orders.get!(ctx.order_id)
    {:ok, %{order: order, amount: order.total}}
  end

  @decorate step(after: :validate_order)
  def check_inventory(ctx) do
    available = Inventory.check(ctx.order.items)
    {:ok, %{in_stock: available}}
  end

  # Only runs if in_stock is true
  @decorate step(after: :check_inventory, when: &(&1.in_stock))
  def reserve_inventory(ctx) do
    reservation = Inventory.reserve(ctx.order.items)
    {:ok, %{reservation_id: reservation.id}}
  end

  # Only runs if in_stock is false
  @decorate step(after: :check_inventory, when: &(not &1.in_stock))
  def create_backorder(ctx) do
    backorder = Backorders.create(ctx.order)
    {:ok, %{backorder_id: backorder.id}}
  end

  # Runs after either branch completes
  @decorate step(after_any: [:reserve_inventory, :create_backorder])
  def send_confirmation(ctx) do
    Mailer.send_order_confirmation(ctx.order)
    :ok
  end
end
```

---

## Step Configuration

### Timeout Formats

```elixir
# Tuple format (recommended)
timeout: {30, :seconds}
timeout: {5, :minutes}
timeout: {1, :hour}
timeout: {1, :day}

# Integer (milliseconds)
timeout: 30_000

# Infinity (no timeout - use with caution)
timeout: :infinity

# Dynamic timeout based on context
timeout: fn ctx ->
  case ctx.data_size do
    size when size > 1_000_000 -> {30, :minutes}
    size when size > 100_000 -> {10, :minutes}
    _ -> {2, :minutes}
  end
end
```

### Retry Configuration

```elixir
@decorate step(
  max_retries: 5,                     # Maximum retry attempts
  retry_delay: {1, :second},          # Initial delay
  retry_backoff: :exponential,        # :fixed | :exponential | :linear
  retry_max_delay: {5, :minutes},     # Cap for exponential backoff
  retry_jitter: true,                 # Add randomness to delays

  # Selective retry
  retry_on: [:timeout, :connection_error, {:error, :econnrefused}],
  no_retry_on: [:validation_error, :not_found, :unauthorized]
)
```

### Backoff Strategies

```elixir
# Fixed delay (always same delay)
retry_backoff: :fixed
retry_delay: {5, :seconds}
# => 5s, 5s, 5s, 5s...

# Exponential backoff (2^attempt * base_delay)
retry_backoff: :exponential
retry_delay: {1, :second}
retry_max_delay: {5, :minutes}
# => 1s, 2s, 4s, 8s, 16s... capped at 5m

# Linear backoff (attempt * base_delay)
retry_backoff: :linear
retry_delay: {10, :seconds}
retry_max_delay: {2, :minutes}
# => 10s, 20s, 30s, 40s... capped at 2m

# Custom function
retry_backoff: fn attempt, base_delay ->
  min(base_delay * :math.pow(1.5, attempt), 300_000)
end
```

---

## Dependency Patterns

### Sequential (Chain)

```elixir
# A → B → C → D
@decorate step()
def step_a(ctx), do: ...

@decorate step(after: :step_a)
def step_b(ctx), do: ...

@decorate step(after: :step_b)
def step_c(ctx), do: ...

@decorate step(after: :step_c)
def step_d(ctx), do: ...
```

### Parallel (Fan-out)

```elixir
#     ┌→ B
# A ──┼→ C
#     └→ D
@decorate step()
def step_a(ctx), do: ...

@decorate step(after: :step_a, group: :parallel)
def step_b(ctx), do: ...

@decorate step(after: :step_a, group: :parallel)
def step_c(ctx), do: ...

@decorate step(after: :step_a, group: :parallel)
def step_d(ctx), do: ...
```

### Join (Fan-in)

```elixir
# B ──┐
# C ──┼→ E
# D ──┘
@decorate step(after: [:step_b, :step_c, :step_d])
def step_e(ctx), do: ...

# Or using groups
@decorate step(after_group: :parallel)
def step_e(ctx), do: ...
```

### Diamond

```elixir
#     ┌→ B ─┐
# A ──┤     ├→ D
#     └→ C ─┘
@decorate step()
def step_a(ctx), do: ...

@decorate step(after: :step_a)
def step_b(ctx), do: ...

@decorate step(after: :step_a)
def step_c(ctx), do: ...

@decorate step(after: [:step_b, :step_c])
def step_d(ctx), do: ...
```

### First-to-Complete (Race)

```elixir
# Run B and C in parallel, continue when FIRST completes
@decorate step(after: :step_a, group: :race)
def step_b(ctx), do: ...

@decorate step(after: :step_a, group: :race)
def step_c(ctx), do: ...

@decorate step(after_any: [:step_b, :step_c])
def step_d(ctx), do: ...
```

---

## Error Handling & Retries

### Error Flow

```
Exception in step
       │
       ▼
   Catch & Normalize
       │
       ▼
   Should retry? ──Yes──▶ Wait, retry step
       │
       No
       ▼
   on_error setting?
       │
  ┌────┼────────┐
  │    │        │
:fail :skip :continue
  │    │        │
  ▼    ▼        ▼
Fail  Skip   Continue
workflow step   workflow
  │    │        │
  └────┴────────┘
       │
       ▼
   Workflow complete?
       │
  ┌────┴────┐
  │         │
Failed   Completed
  │         │
  ▼         ▼
on_failure on_success
handler    handler
  │
  ▼
Rollback?
```

### on_error Behaviors

```elixir
# Fail workflow immediately (default)
@decorate step(on_error: :fail)
def critical_step(ctx), do: ...

# Skip this step, continue workflow
@decorate step(on_error: :skip)
def optional_step(ctx), do: ...

# Record failure but continue workflow
@decorate step(on_error: :continue)
def non_critical_step(ctx), do: ...
```

### Error Handlers

```elixir
defmodule MyApp.RobustWorkflow do
  use OmScheduler.Workflow,
    name: :robust_workflow,
    on_failure: :handle_failure,
    on_success: :handle_success,
    on_cancel: :handle_cancel,
    on_step_error: :handle_step_error

  @decorate step()
  def risky_operation(ctx), do: ...

  # Called when any step fails (before retry)
  def handle_step_error(ctx, step_name, error, attempt) do
    Logger.error("Step #{step_name} failed (attempt #{attempt}): #{inspect(error)}")
    Alerts.send(:step_failure, step_name, error)
    :ok
  end

  # Called when entire workflow fails
  def handle_failure(ctx) do
    Logger.error("Workflow failed: #{inspect(ctx.__error__)}")
    cleanup_partial_state(ctx)
    notify_oncall(ctx)
    :ok
  end

  # Called when workflow completes successfully
  def handle_success(ctx) do
    Logger.info("Workflow completed successfully")
    record_metrics(ctx)
    :ok
  end

  # Called when workflow is cancelled
  def handle_cancel(ctx, reason) do
    Logger.warn("Workflow cancelled: #{reason}")
    cleanup_on_cancel(ctx)
    :ok
  end
end
```

### Accessing Error Information

```elixir
def handle_failure(ctx) do
  # Error context is added to ctx on failure
  %{
    __error__: error,           # The error that caused failure
    __error_step__: step_name,  # Which step failed
    __attempts__: attempts,     # How many attempts were made
    __stacktrace__: stacktrace  # If exception occurred
  } = ctx

  Logger.error("""
  Workflow failed:
    Step: #{step_name}
    Error: #{inspect(error)}
    Attempts: #{attempts}
  """)
end
```

---

## Rollback (Saga Pattern)

Rollbacks implement the Saga pattern for distributed transactions. When a workflow fails, completed steps are compensated in reverse order.

### Basic Rollback

```elixir
defmodule MyApp.PaymentWorkflow do
  use OmScheduler.Workflow, name: :payment_workflow

  @decorate step(rollback: :release_inventory)
  def reserve_inventory(ctx) do
    reservation = Inventory.reserve(ctx.items)
    {:ok, %{reservation_id: reservation.id}}
  end

  @decorate step(after: :reserve_inventory, rollback: :refund_payment)
  def charge_payment(ctx) do
    payment = Payments.charge(ctx.amount, ctx.payment_method)
    {:ok, %{payment_id: payment.id}}
  end

  @decorate step(after: :charge_payment, rollback: :cancel_order)
  def create_order(ctx) do
    order = Orders.create(ctx)
    {:ok, %{order_id: order.id}}
  end

  @decorate step(after: :create_order)
  def send_confirmation(ctx) do
    # No rollback - email can't be unsent
    Mailer.send_order_confirmation(ctx.order_id)
    :ok
  end

  # Rollback functions (called in reverse order on failure)
  def cancel_order(ctx) do
    Orders.cancel(ctx.order_id)
    :ok
  end

  def refund_payment(ctx) do
    Payments.refund(ctx.payment_id)
    :ok
  end

  def release_inventory(ctx) do
    Inventory.release(ctx.reservation_id)
    :ok
  end
end
```

**Rollback Execution Order:**

If `send_confirmation` fails:
1. No rollback (it doesn't have one)
2. `cancel_order` is called
3. `refund_payment` is called
4. `release_inventory` is called
5. `on_failure` handler is called

### Rollback with Workflow Cancel

```elixir
# Cancel with rollback
Workflow.cancel(execution_id, rollback: true)
```

---

## Advanced Features

### Human-in-the-Loop (Snooze/Pause)

```elixir
defmodule MyApp.ExpenseApproval do
  use OmScheduler.Workflow, name: :expense_approval

  @decorate step()
  def submit_expense(ctx) do
    expense = Expenses.create(ctx.data)
    {:ok, %{expense_id: expense.id, amount: expense.amount}}
  end

  @decorate step(after: :submit_expense, await_approval: true)
  def await_manager_approval(ctx) do
    if ctx.amount > 10_000 do
      # Pause workflow, notify manager
      {:await, notify: :email, timeout: {48, :hours}, approvers: ctx.manager_email}
    else
      # Auto-approve small expenses
      {:ok, %{approved: true, approver: "auto"}}
    end
  end

  @decorate step(after: :await_manager_approval)
  def process_reimbursement(ctx) do
    if ctx.approved do
      Payments.reimburse(ctx.expense_id)
      :ok
    else
      {:error, :rejected}
    end
  end
end

# Resume after human approval
Workflow.resume(execution_id, context: %{approved: true, approver: "manager@company.com"})
```

### Snooze (Delay and Retry)

```elixir
@decorate step()
def wait_for_external_event(ctx) do
  case ExternalAPI.check_status(ctx.reference_id) do
    {:ok, :completed} ->
      {:ok, %{external_status: :completed}}

    {:ok, :pending} ->
      # Snooze: pause workflow and retry this step later
      {:snooze, {5, :minutes}}

    {:error, reason} ->
      {:error, reason}
  end
end
```

### Dynamic Workflow Expansion (Grafting)

Grafting allows dynamic expansion of workflows at runtime - useful when you don't know the number of steps ahead of time.

```elixir
defmodule MyApp.BatchProcessor do
  use OmScheduler.Workflow, name: :batch_processor

  @decorate step()
  def fetch_batch(ctx) do
    items = Database.fetch_batch(ctx.batch_id)
    {:ok, %{items: items}}
  end

  # Graft placeholder - expands at runtime
  @decorate graft(after: :fetch_batch)
  def process_items(ctx) do
    # Create one step per item dynamically
    expansions = Enum.map(ctx.items, fn item ->
      {:"process_item_#{item.id}", fn _ -> process_single_item(item) end}
    end)
    {:expand, expansions}
  end

  # Runs after all dynamically created steps complete
  @decorate step(after_graft: :process_items)
  def summarize(ctx) do
    # Collect all results
    results = Enum.map(ctx.items, fn item ->
      Map.get(ctx, :"process_item_#{item.id}_result")
    end)
    {:ok, %{summary: aggregate(results)}}
  end

  defp process_single_item(item) do
    result = ItemProcessor.process(item)
    {:ok, %{result: result}}
  end
end
```

### Nested Workflows

```elixir
# Reusable notification workflow
defmodule MyApp.NotificationWorkflow do
  use OmScheduler.Workflow, name: :send_notification

  @decorate step()
  def format_message(ctx) do
    message = Templates.render(ctx.template, ctx.data)
    {:ok, %{message: message}}
  end

  @decorate step(after: :format_message)
  def send(ctx) do
    Notifier.send(ctx.channel, ctx.recipient, ctx.message)
    :ok
  end

  @decorate step(after: :send)
  def log(ctx) do
    AuditLog.record(:notification_sent, ctx)
    :ok
  end
end

# Parent workflow that uses nested workflow
defmodule MyApp.OrderWorkflow do
  use OmScheduler.Workflow, name: :order_workflow

  @decorate step()
  def create_order(ctx) do
    order = Orders.create(ctx)
    {:ok, %{order_id: order.id}}
  end

  # Embed notification workflow as a step
  # The nested workflow receives current context
  @decorate workflow(:send_notification, after: :create_order)
  def notify_customer(_ctx) do
    # Return context additions for the nested workflow
    %{
      template: :order_confirmation,
      channel: :email,
      recipient: ctx.customer_email
    }
  end

  @decorate step(after: :notify_customer)
  def complete(ctx) do
    Orders.mark_complete(ctx.order_id)
    :ok
  end
end
```

### Circuit Breaker Integration

```elixir
@decorate step(
  after: :prepare,
  circuit_breaker: :external_api,
  circuit_breaker_opts: [
    failure_threshold: 5,
    reset_timeout: {30, :seconds}
  ]
)
def call_external_api(ctx) do
  ExternalAPI.call(ctx.request)
end
```

---

## Scheduling

### Cron Expressions

```elixir
use OmScheduler.Workflow,
  name: :scheduled_workflow,
  schedule: [cron: "0 6 * * *"]  # Daily at 6 AM

# Multiple cron patterns
schedule: [cron: ["0 6 * * *", "0 12 * * *", "0 18 * * *"]]

# Common patterns
"* * * * *"       # Every minute
"0 * * * *"       # Every hour
"0 0 * * *"       # Daily at midnight
"0 6 * * 1"       # Weekly on Monday at 6 AM
"0 0 1 * *"       # Monthly on the 1st
"0 0 1 1 *"       # Yearly on Jan 1st
```

### Interval-based

```elixir
schedule: [every: {5, :minutes}]
schedule: [every: {1, :hour}]
schedule: [every: {30, :seconds}]
```

### One-time Execution

```elixir
# At specific datetime
schedule: [at: ~U[2025-12-25 00:00:00Z]]

# Relative delay
schedule: [in: {30, :minutes}]
schedule: [in: {2, :hours}]
```

### Event-triggered

```elixir
schedule: [on_event: "user.created"]
schedule: [on_event: ["order.placed", "order.updated"]]
```

### Combined Schedules

```elixir
schedule: [
  every: {1, :hour},
  start_at: ~U[2025-01-01 00:00:00Z],
  end_at: ~U[2025-01-31 23:59:59Z]
]
```

---

## Runtime Management

### Starting Workflows

```elixir
# Start immediately
{:ok, execution_id} = Workflow.start(:my_workflow, %{input: "data"})

# Schedule for later
{:ok, execution_id} = Workflow.schedule_execution(:my_workflow,
  context: %{input: "data"},
  at: ~U[2025-12-25 00:00:00Z]
)

# Schedule with delay
{:ok, execution_id} = Workflow.schedule_execution(:my_workflow,
  context: %{input: "data"},
  in: {30, :minutes}
)
```

### Monitoring

```elixir
# Get execution state
{:ok, state} = Workflow.get_state(execution_id)
# => %{
#   workflow: :my_workflow,
#   state: :running,
#   current_step: :transform,
#   progress: {2, 5},
#   context: %{...},
#   started_at: ~U[...],
#   duration_ms: 12345
# }

# List running executions
executions = Workflow.list_running(:my_workflow)
```

### Pause and Resume

```elixir
# Pause a running workflow
:ok = Workflow.pause(execution_id)

# Resume with additional context
:ok = Workflow.resume(execution_id, context: %{approved: true})
```

### Cancellation

```elixir
# Cancel single execution
:ok = Workflow.cancel(execution_id)

# Cancel with reason
:ok = Workflow.cancel(execution_id, reason: :user_requested)

# Cancel with cleanup
:ok = Workflow.cancel(execution_id, cleanup: true)

# Cancel with rollback (saga compensation)
:ok = Workflow.cancel(execution_id, rollback: true)

# Cancel all instances of a workflow
{:ok, count} = Workflow.cancel_all(:my_workflow, reason: :maintenance)
```

### Cooperative Cancellation

For long-running steps, check for cancellation:

```elixir
@decorate step(cancellable: true)
def process_large_batch(ctx) do
  Enum.reduce_while(ctx.items, {:ok, []}, fn item, {:ok, acc} ->
    if Workflow.cancelled?() do
      {:halt, {:cancelled, acc}}
    else
      result = process_item(item)
      {:cont, {:ok, [result | acc]}}
    end
  end)
end
```

---

## Introspection & Visualization

### Summary

```elixir
Workflow.summary(:user_onboarding)
# => %{
#   name: :user_onboarding,
#   version: 1,
#   steps: 5,
#   parallel_groups: 1,
#   grafts: 0,
#   nested_workflows: 1,
#   has_rollback: true,
#   estimated_timeout: 35000,
#   trigger: :manual,
#   schedule: nil,
#   tags: ["onboarding"]
# }
```

### Detailed Report

```elixir
Workflow.report(:user_onboarding)
# => %{
#   name: :user_onboarding,
#   version: 1,
#   module: MyApp.UserOnboarding,
#   steps: [...],
#   execution_order: [:create_account, :setup_profile, :send_welcome],
#   parallel_groups: %{notifications: [:email, :slack]},
#   grafts: [],
#   nested_workflows: %{notify: :send_notification},
#   critical_path: [:create_account, :setup_profile, :send_welcome],
#   total_timeout: 35000,
#   ...
# }
```

### Mermaid Diagram

```elixir
Workflow.to_mermaid(:order_processing)
# => """
# graph TD
#   validate[Validate Order]
#   check_stock[Check Stock]
#   reserve[Reserve Inventory]
#   charge[Charge Payment]
#   ship[Ship Order]
#   validate --> check_stock
#   check_stock --> reserve
#   reserve --> charge
#   charge --> ship
# """

# With execution state coloring
Workflow.to_mermaid(:order_processing, execution_id: exec_id)
# => """
# graph TD
#   validate[Validate Order]:::completed
#   check_stock[Check Stock]:::completed
#   reserve[Reserve Inventory]:::running
#   charge[Charge Payment]:::pending
#   ship[Ship Order]:::pending
#   classDef completed fill:#90EE90
#   classDef running fill:#FFD700
#   classDef pending fill:#D3D3D3
#   ...
# """

# With parallel groups
Workflow.to_mermaid(:data_export, show_groups: true)
```

### ASCII Table

```elixir
Workflow.to_table(:user_onboarding)
# =>
# ├────────────────────┼────────────────────┼──────────┼─────────┼──────────┤
# │ Step               │ Depends On         │ Timeout  │ Retries │ Rollback │
# ├────────────────────┼────────────────────┼──────────┼─────────┼──────────┤
# │ create_account     │ -                  │ 5m       │ 3       │ ✗        │
# │ setup_profile      │ create_account     │ 5m       │ 3       │ ✗        │
# │ send_welcome       │ setup_profile      │ 5m       │ 3       │ ✓        │
# ├────────────────────┼────────────────────┼──────────┼─────────┼──────────┤
```

### Graphviz DOT

```elixir
Workflow.to_dot(:order_processing)
# => """
# digraph order_processing {
#   rankdir=TB;
#   node [shape=box, style=rounded];
#   validate [label="Validate Order"];
#   check_stock [label="Check Stock"];
#   ...
#   validate -> check_stock;
#   check_stock -> reserve;
# }
# """
```

### List All Workflows

```elixir
Workflow.list_all()
# => [
#   %{name: :user_onboarding, steps: 5, trigger_type: :manual, ...},
#   %{name: :data_export, steps: 8, trigger_type: :scheduled, ...},
#   %{name: :order_processing, steps: 12, trigger_type: :event, ...}
# ]
```

---

## Real-World Examples

### E-Commerce Order Processing

```elixir
defmodule MyApp.Workflows.OrderProcessing do
  use OmScheduler.Workflow,
    name: :order_processing,
    timeout: {30, :minutes},
    on_failure: :handle_order_failure,
    dead_letter: true

  # ─────────────────────────────────────────────
  # Step 1: Validate the order
  # ─────────────────────────────────────────────
  @decorate step()
  def validate_order(ctx) do
    with {:ok, order} <- Orders.get(ctx.order_id),
         :ok <- Orders.validate(order) do
      {:ok, %{
        order: order,
        customer_id: order.customer_id,
        items: order.items,
        total: order.total
      }}
    end
  end

  # ─────────────────────────────────────────────
  # Step 2: Check fraud
  # ─────────────────────────────────────────────
  @decorate step(after: :validate_order, timeout: {10, :seconds})
  def check_fraud(ctx) do
    case FraudService.check(ctx.customer_id, ctx.total) do
      {:ok, :clear} -> {:ok, %{fraud_check: :passed}}
      {:ok, :review} -> {:await, notify: :fraud_team, timeout: {24, :hours}}
      {:ok, :reject} -> {:error, :fraud_detected}
    end
  end

  # ─────────────────────────────────────────────
  # Step 3: Check inventory (parallel with payment auth)
  # ─────────────────────────────────────────────
  @decorate step(after: :check_fraud, group: :pre_fulfillment, rollback: :release_inventory)
  def reserve_inventory(ctx) do
    case Inventory.reserve(ctx.items) do
      {:ok, reservation} -> {:ok, %{reservation_id: reservation.id}}
      {:error, :out_of_stock} -> {:error, :inventory_unavailable}
    end
  end

  # ─────────────────────────────────────────────
  # Step 4: Authorize payment (parallel with inventory)
  # ─────────────────────────────────────────────
  @decorate step(after: :check_fraud, group: :pre_fulfillment, rollback: :void_authorization)
  def authorize_payment(ctx) do
    case Payments.authorize(ctx.order.payment_method, ctx.total) do
      {:ok, auth} -> {:ok, %{payment_auth_id: auth.id}}
      {:error, reason} -> {:error, {:payment_failed, reason}}
    end
  end

  # ─────────────────────────────────────────────
  # Step 5: Capture payment (after both inventory and auth succeed)
  # ─────────────────────────────────────────────
  @decorate step(after_group: :pre_fulfillment, rollback: :refund_payment)
  def capture_payment(ctx) do
    case Payments.capture(ctx.payment_auth_id) do
      {:ok, capture} -> {:ok, %{payment_id: capture.id}}
      {:error, reason} -> {:error, {:capture_failed, reason}}
    end
  end

  # ─────────────────────────────────────────────
  # Step 6: Create shipment
  # ─────────────────────────────────────────────
  @decorate step(after: :capture_payment, rollback: :cancel_shipment)
  def create_shipment(ctx) do
    shipment = Shipping.create_shipment(ctx.order, ctx.reservation_id)
    {:ok, %{shipment_id: shipment.id, tracking_number: shipment.tracking}}
  end

  # ─────────────────────────────────────────────
  # Step 7: Send notifications (parallel)
  # ─────────────────────────────────────────────
  @decorate step(after: :create_shipment, group: :notifications, on_error: :continue)
  def send_confirmation_email(ctx) do
    Mailer.send_order_confirmation(ctx.order, ctx.tracking_number)
    :ok
  end

  @decorate step(after: :create_shipment, group: :notifications, on_error: :continue)
  def send_sms_notification(ctx) do
    SMS.send(ctx.order.customer_phone, "Order #{ctx.order.id} shipped!")
    :ok
  end

  @decorate step(after: :create_shipment, group: :notifications, on_error: :continue)
  def update_analytics(ctx) do
    Analytics.track(:order_fulfilled, ctx.order)
    :ok
  end

  # ─────────────────────────────────────────────
  # Step 8: Complete order
  # ─────────────────────────────────────────────
  @decorate step(after_group: :notifications)
  def complete_order(ctx) do
    Orders.mark_fulfilled(ctx.order_id)
    {:ok, %{status: :fulfilled}}
  end

  # ─────────────────────────────────────────────
  # Rollback Functions
  # ─────────────────────────────────────────────
  def release_inventory(ctx) do
    Inventory.release(ctx.reservation_id)
    :ok
  end

  def void_authorization(ctx) do
    Payments.void(ctx.payment_auth_id)
    :ok
  end

  def refund_payment(ctx) do
    Payments.refund(ctx.payment_id)
    :ok
  end

  def cancel_shipment(ctx) do
    Shipping.cancel(ctx.shipment_id)
    :ok
  end

  # ─────────────────────────────────────────────
  # Error Handler
  # ─────────────────────────────────────────────
  def handle_order_failure(ctx) do
    Orders.mark_failed(ctx.order_id, ctx.__error__)
    Mailer.send_order_failure(ctx.order, ctx.__error__)
    :ok
  end
end
```

### Data Pipeline with ETL

```elixir
defmodule MyApp.Workflows.DailyDataPipeline do
  use OmScheduler.Workflow,
    name: :daily_data_pipeline,
    timeout: {2, :hours},
    schedule: [cron: "0 2 * * *"],  # Run at 2 AM daily
    on_failure: :alert_data_team,
    tags: ["etl", "daily"]

  # ─────────────────────────────────────────────
  # Extract: Fetch data from multiple sources
  # ─────────────────────────────────────────────
  @decorate step()
  def prepare(ctx) do
    date = ctx[:date] || Date.utc_today() |> Date.add(-1)
    {:ok, %{date: date, started_at: DateTime.utc_now()}}
  end

  @decorate step(after: :prepare, group: :extract, timeout: {30, :minutes})
  def extract_sales(ctx) do
    data = SalesDB.fetch_for_date(ctx.date)
    {:ok, %{sales_data: data, sales_count: length(data)}}
  end

  @decorate step(after: :prepare, group: :extract, timeout: {30, :minutes})
  def extract_inventory(ctx) do
    data = InventoryDB.fetch_snapshot(ctx.date)
    {:ok, %{inventory_data: data}}
  end

  @decorate step(after: :prepare, group: :extract, timeout: {15, :minutes})
  def extract_customers(ctx) do
    data = CustomerDB.fetch_changes(ctx.date)
    {:ok, %{customer_data: data}}
  end

  # ─────────────────────────────────────────────
  # Transform: Clean and normalize data
  # ─────────────────────────────────────────────
  @decorate step(after_group: :extract, timeout: {45, :minutes})
  def transform_and_join(ctx) do
    transformed = DataTransformer.transform_and_join(
      ctx.sales_data,
      ctx.inventory_data,
      ctx.customer_data
    )
    {:ok, %{transformed_data: transformed, record_count: length(transformed)}}
  end

  @decorate step(after: :transform_and_join)
  def validate_data(ctx) do
    case DataValidator.validate(ctx.transformed_data) do
      {:ok, validated} -> {:ok, %{validated_data: validated}}
      {:error, errors} -> {:error, {:validation_failed, errors}}
    end
  end

  # ─────────────────────────────────────────────
  # Load: Write to destinations
  # ─────────────────────────────────────────────
  @decorate step(after: :validate_data, group: :load, timeout: {30, :minutes})
  def load_to_warehouse(ctx) do
    DataWarehouse.bulk_insert(ctx.validated_data)
    {:ok, %{warehouse_loaded: true}}
  end

  @decorate step(after: :validate_data, group: :load, timeout: {15, :minutes})
  def load_to_elasticsearch(ctx) do
    Elasticsearch.bulk_index(ctx.validated_data)
    {:ok, %{elasticsearch_loaded: true}}
  end

  @decorate step(after: :validate_data, group: :load, timeout: {10, :minutes})
  def update_cache(ctx) do
    Cache.refresh_daily_aggregates(ctx.date, ctx.validated_data)
    {:ok, %{cache_updated: true}}
  end

  # ─────────────────────────────────────────────
  # Finalize
  # ─────────────────────────────────────────────
  @decorate step(after_group: :load)
  def generate_report(ctx) do
    report = Reports.generate_daily_summary(ctx.date, ctx.record_count)
    {:ok, %{report_url: report.url}}
  end

  @decorate step(after: :generate_report)
  def send_notifications(ctx) do
    duration = DateTime.diff(DateTime.utc_now(), ctx.started_at, :minute)

    Slack.post(:data_team, """
    ✅ Daily ETL Complete
    Date: #{ctx.date}
    Records: #{ctx.record_count}
    Duration: #{duration} minutes
    Report: #{ctx.report_url}
    """)
    :ok
  end

  def alert_data_team(ctx) do
    PagerDuty.alert(:data_team, "Daily ETL failed: #{inspect(ctx.__error__)}")
    :ok
  end
end
```

### User Onboarding with Verification

```elixir
defmodule MyApp.Workflows.UserOnboarding do
  use OmScheduler.Workflow,
    name: :user_onboarding,
    timeout: {7, :days},  # Long timeout for human interactions
    on_failure: :cleanup_failed_signup

  # ─────────────────────────────────────────────
  # Step 1: Create account
  # ─────────────────────────────────────────────
  @decorate step(rollback: :delete_account)
  def create_account(ctx) do
    user = Users.create!(%{
      email: ctx.email,
      name: ctx.name,
      password_hash: Bcrypt.hash_pwd_salt(ctx.password)
    })
    {:ok, %{user_id: user.id, user: user}}
  end

  # ─────────────────────────────────────────────
  # Step 2: Send verification email
  # ─────────────────────────────────────────────
  @decorate step(after: :create_account)
  def send_verification_email(ctx) do
    token = Tokens.generate_email_verification(ctx.user_id)
    Mailer.send_verification(ctx.email, token)
    {:ok, %{verification_token: token}}
  end

  # ─────────────────────────────────────────────
  # Step 3: Wait for email verification (human-in-the-loop)
  # ─────────────────────────────────────────────
  @decorate step(after: :send_verification_email, await_approval: true)
  def await_email_verification(ctx) do
    # This will pause the workflow until resumed
    {:await,
      timeout: {24, :hours},
      on_timeout: :resend_or_expire
    }
  end

  # Called when user clicks verification link
  # Workflow.resume(execution_id, context: %{email_verified: true})

  # ─────────────────────────────────────────────
  # Step 4: Setup profile (parallel tasks)
  # ─────────────────────────────────────────────
  @decorate step(after: :await_email_verification, when: &(&1.email_verified), group: :setup)
  def create_default_settings(ctx) do
    settings = Settings.create_defaults(ctx.user_id)
    {:ok, %{settings_id: settings.id}}
  end

  @decorate step(after: :await_email_verification, when: &(&1.email_verified), group: :setup)
  def create_default_workspace(ctx) do
    workspace = Workspaces.create_personal(ctx.user_id)
    {:ok, %{workspace_id: workspace.id}}
  end

  @decorate step(after: :await_email_verification, when: &(&1.email_verified), group: :setup)
  def provision_storage(ctx) do
    bucket = Storage.provision_user_bucket(ctx.user_id)
    {:ok, %{storage_bucket: bucket}}
  end

  # ─────────────────────────────────────────────
  # Step 5: Grant trial subscription
  # ─────────────────────────────────────────────
  @decorate step(after_group: :setup)
  def create_trial_subscription(ctx) do
    subscription = Subscriptions.create_trial(ctx.user_id, days: 14)
    {:ok, %{subscription_id: subscription.id, trial_ends_at: subscription.ends_at}}
  end

  # ─────────────────────────────────────────────
  # Step 6: Send welcome series
  # ─────────────────────────────────────────────
  @decorate step(after: :create_trial_subscription, on_error: :continue)
  def send_welcome_email(ctx) do
    Mailer.send_welcome(ctx.user, ctx.trial_ends_at)
    :ok
  end

  @decorate step(after: :create_trial_subscription, on_error: :continue)
  def schedule_onboarding_emails(ctx) do
    EmailSequences.schedule(:onboarding, ctx.user_id, [
      {1, :day, :getting_started},
      {3, :days, :first_project},
      {7, :days, :power_features},
      {12, :days, :trial_ending}
    ])
    :ok
  end

  # ─────────────────────────────────────────────
  # Step 7: Track analytics
  # ─────────────────────────────────────────────
  @decorate step(after: :send_welcome_email, on_error: :continue)
  def track_signup(ctx) do
    Analytics.track(:user_signup, %{
      user_id: ctx.user_id,
      source: ctx[:source] || "organic",
      referrer: ctx[:referrer]
    })
    :ok
  end

  # ─────────────────────────────────────────────
  # Rollback and Cleanup
  # ─────────────────────────────────────────────
  def delete_account(ctx) do
    Users.hard_delete(ctx.user_id)
    :ok
  end

  def cleanup_failed_signup(ctx) do
    # Clean up any partial state
    if ctx[:user_id] do
      Users.mark_signup_failed(ctx.user_id)
    end
    :ok
  end
end
```

### Batch Processing with Dynamic Steps

```elixir
defmodule MyApp.Workflows.ImageProcessing do
  use OmScheduler.Workflow,
    name: :batch_image_processing,
    timeout: {1, :hour},
    step_concurrency: 10  # Process 10 images at a time

  @decorate step()
  def fetch_images(ctx) do
    images = ImageStore.list_pending(ctx.batch_id)
    {:ok, %{images: images, total_count: length(images)}}
  end

  # Dynamic expansion - creates one step per image
  @decorate graft(after: :fetch_images)
  def process_images(ctx) do
    expansions = Enum.map(ctx.images, fn image ->
      step_name = :"process_#{image.id}"
      step_fn = fn _ -> process_single_image(image) end
      {step_name, step_fn}
    end)
    {:expand, expansions}
  end

  @decorate step(after_graft: :process_images)
  def aggregate_results(ctx) do
    # Collect results from all dynamic steps
    results = Enum.map(ctx.images, fn image ->
      key = :"process_#{image.id}"
      Map.get(ctx, key)
    end)

    succeeded = Enum.count(results, &(&1.status == :ok))
    failed = Enum.count(results, &(&1.status == :error))

    {:ok, %{
      processed: succeeded,
      failed: failed,
      results: results
    }}
  end

  @decorate step(after: :aggregate_results)
  def send_report(ctx) do
    Reports.send_batch_summary(ctx.batch_id, %{
      total: ctx.total_count,
      processed: ctx.processed,
      failed: ctx.failed
    })
    :ok
  end

  defp process_single_image(image) do
    with {:ok, resized} <- ImageProcessor.resize(image, [800, 600]),
         {:ok, optimized} <- ImageProcessor.optimize(resized),
         {:ok, url} <- ImageStore.upload(optimized) do
      {:ok, %{status: :ok, url: url}}
    else
      {:error, reason} ->
        {:ok, %{status: :error, error: reason}}
    end
  end
end
```

### Multi-Tenant Data Migration

```elixir
defmodule MyApp.Workflows.TenantMigration do
  use OmScheduler.Workflow,
    name: :tenant_migration,
    timeout: {4, :hours},
    on_failure: :rollback_migration

  @decorate step(rollback: :restore_backup)
  def create_backup(ctx) do
    backup = Backups.create(ctx.tenant_id)
    {:ok, %{backup_id: backup.id, backup_path: backup.path}}
  end

  @decorate step(after: :create_backup, rollback: :unlock_tenant)
  def lock_tenant(ctx) do
    Tenants.set_maintenance_mode(ctx.tenant_id, true)
    {:ok, %{locked_at: DateTime.utc_now()}}
  end

  @decorate step(after: :lock_tenant)
  def wait_for_active_sessions(ctx) do
    case Sessions.wait_for_drain(ctx.tenant_id, timeout: {5, :minutes}) do
      :ok -> {:ok, %{sessions_drained: true}}
      :timeout -> {:snooze, {1, :minute}}  # Try again in a minute
    end
  end

  @decorate step(after: :wait_for_active_sessions, timeout: {2, :hours})
  def migrate_data(ctx) do
    Migration.run(ctx.tenant_id, ctx.migration_version)
    {:ok, %{migration_complete: true}}
  end

  @decorate step(after: :migrate_data)
  def validate_migration(ctx) do
    case Migration.validate(ctx.tenant_id) do
      {:ok, report} -> {:ok, %{validation_report: report}}
      {:error, issues} -> {:error, {:validation_failed, issues}}
    end
  end

  @decorate step(after: :validate_migration)
  def unlock_tenant(ctx) do
    Tenants.set_maintenance_mode(ctx.tenant_id, false)
    {:ok, %{unlocked_at: DateTime.utc_now()}}
  end

  @decorate step(after: :unlock_tenant)
  def notify_stakeholders(ctx) do
    duration = DateTime.diff(ctx.unlocked_at, ctx.locked_at, :minute)

    Email.send_to_tenant_admins(ctx.tenant_id, :migration_complete, %{
      duration: duration,
      validation_report: ctx.validation_report
    })
    :ok
  end

  # Rollbacks
  def restore_backup(ctx) do
    Backups.restore(ctx.backup_id)
    :ok
  end

  def rollback_migration(ctx) do
    Tenants.set_maintenance_mode(ctx.tenant_id, false)
    notify_failure(ctx)
    :ok
  end

  defp notify_failure(ctx) do
    PagerDuty.alert(:platform_team, "Migration failed for tenant #{ctx.tenant_id}")
  end
end
```

---

## Best Practices

### 1. Keep Steps Focused

Each step should do one thing well. If a step is doing too much, split it.

```elixir
# Bad: One step doing everything
@decorate step()
def process_order(ctx) do
  order = validate_order(ctx)
  inventory = reserve_inventory(order)
  payment = charge_payment(order)
  shipment = create_shipment(order)
  send_email(order)
  {:ok, %{order: order}}
end

# Good: Separate steps with clear responsibilities
@decorate step()
def validate_order(ctx), do: ...

@decorate step(after: :validate_order)
def reserve_inventory(ctx), do: ...

@decorate step(after: :reserve_inventory)
def charge_payment(ctx), do: ...
```

### 2. Use Rollbacks for Side Effects

Any step that creates external state should have a rollback.

```elixir
@decorate step(rollback: :release_reservation)
def reserve_inventory(ctx), do: ...

@decorate step(rollback: :refund_payment)
def charge_payment(ctx), do: ...
```

### 3. Use Groups for Parallel Work

When steps are independent, group them for parallel execution.

```elixir
@decorate step(after: :prepare, group: :notifications)
def send_email(ctx), do: ...

@decorate step(after: :prepare, group: :notifications)
def send_sms(ctx), do: ...

@decorate step(after: :prepare, group: :notifications)
def send_push(ctx), do: ...
```

### 4. Use on_error: :continue for Non-Critical Steps

Notifications and analytics shouldn't fail the workflow.

```elixir
@decorate step(on_error: :continue)
def track_analytics(ctx), do: ...

@decorate step(on_error: :continue)
def send_slack_notification(ctx), do: ...
```

### 5. Set Appropriate Timeouts

Different steps need different timeouts.

```elixir
@decorate step(timeout: {5, :seconds})
def quick_validation(ctx), do: ...

@decorate step(timeout: {30, :minutes})
def large_data_processing(ctx), do: ...

@decorate step(timeout: {24, :hours}, await_approval: true)
def await_human_approval(ctx), do: ...
```

### 6. Use Descriptive Names

Step names should clearly describe what they do.

```elixir
# Good
def validate_order_items(ctx), do: ...
def reserve_inventory_for_order(ctx), do: ...
def send_order_confirmation_email(ctx), do: ...

# Bad
def step1(ctx), do: ...
def do_stuff(ctx), do: ...
def process(ctx), do: ...
```

---

## Telemetry Events

All events are prefixed with `[:events, :scheduler, :workflow]`:

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:start]` | - | workflow_name, execution_id, trigger_type |
| `[:stop]` | duration | workflow_name, execution_id, state |
| `[:fail]` | - | workflow_name, execution_id, error, error_step |
| `[:cancel]` | - | workflow_name, execution_id, reason |
| `[:pause]` | - | workflow_name, execution_id, step_name |
| `[:resume]` | - | workflow_name, execution_id |
| `[:step, :start]` | - | workflow_name, execution_id, step_name, attempt |
| `[:step, :stop]` | duration | workflow_name, execution_id, step_name, result |
| `[:step, :skip]` | - | workflow_name, execution_id, step_name, reason |
| `[:step, :exception]` | duration | workflow_name, execution_id, step_name, kind, reason |
| `[:rollback, :start]` | - | workflow_name, execution_id, steps |
| `[:rollback, :stop]` | duration | workflow_name, execution_id, steps |

### Attaching Handlers

```elixir
# In your application.ex or telemetry.ex
:telemetry.attach_many(
  "workflow-metrics",
  [
    [:events, :scheduler, :workflow, :start],
    [:events, :scheduler, :workflow, :stop],
    [:events, :scheduler, :workflow, :step, :stop]
  ],
  &MyApp.Telemetry.handle_workflow_event/4,
  nil
)

defmodule MyApp.Telemetry do
  def handle_workflow_event(
    [:events, :scheduler, :workflow, :stop],
    %{duration: duration},
    %{workflow_name: name, execution_id: id, state: state},
    _config
  ) do
    :telemetry.execute(
      [:my_app, :workflow, :duration],
      %{value: duration},
      %{workflow: name, state: state}
    )
  end
end
```

---

## LiveView Dashboard

A built-in LiveView dashboard is available at `/workflows` for monitoring workflow executions.

### Features

- **Overview**: See all registered workflows with stats
- **Running Executions**: Real-time view of currently running workflows
- **Execution Details**: Step-by-step progress with timeline
- **Statistics**: Success rates, average durations, error counts

### Setup

The dashboard is already configured in the router:

```elixir
# In router.ex
scope "/workflows", EventsWeb do
  pipe_through :browser

  live "/", WorkflowDashboardLive, :index
  live "/executions/:id", WorkflowDashboardLive, :execution
  live "/:name", WorkflowDashboardLive, :workflow
end
```

### Production Considerations

In production, add authentication:

```elixir
scope "/workflows", EventsWeb do
  pipe_through [:browser, :require_admin]

  live "/", WorkflowDashboardLive, :index
  # ...
end
```

---

## File Structure

```
lib/events/infra/scheduler/workflow/
├── workflow.ex              # Workflow struct + Builder API
├── step.ex                  # Step struct
├── execution.ex             # Execution tracking
├── engine.ex                # Execution engine (GenServer)
├── state_machine.ex         # State transitions + dependency resolution
├── registry.ex              # In-memory workflow registry
├── store.ex                 # Database persistence
├── telemetry.ex             # Telemetry events
├── step/
│   ├── behaviour.ex         # Step.Behaviour callbacks
│   ├── worker.ex            # Using macro
│   └── executable.ex        # Protocol for step execution
├── decorator/
│   ├── step.ex              # @decorate step(...)
│   ├── graft.ex             # @decorate graft(...)
│   └── workflow.ex          # @decorate workflow(:name, ...)
└── introspection/
    ├── summary.ex           # summary/1, report/1
    ├── mermaid.ex           # to_mermaid/2
    ├── dot.ex               # to_dot/2 (Graphviz)
    └── table.ex             # to_table/2 (ASCII)
```
