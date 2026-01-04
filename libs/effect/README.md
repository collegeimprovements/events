# Effect

Composable, resumable workflow orchestration for Elixir with DAG-based execution, saga patterns, and checkpoints.

## Installation

```elixir
def deps do
  [
    {:effect, "~> 0.1.0"},
    {:dag, "~> 0.1.0"}  # Dependency for DAG algorithms
  ]
end
```

## Why Effect?

Complex workflows involve multiple steps that depend on each other, may need retrying, and require cleanup on failure:

```
Traditional approach:
┌─────────────────────────────────────────────────────────────────────┐
│  with {:ok, validated} <- validate(order),                         │
│       {:ok, reserved} <- reserve_inventory(validated),              │
│       {:ok, charged} <- charge_payment(reserved),                   │
│       {:ok, shipped} <- create_shipment(charged) do                 │
│    {:ok, shipped}                                                   │
│  else                                                               │
│    {:error, reason} ->                                              │
│      # Manual cleanup... what if multiple steps need rollback?      │
│      # What about retries? Parallel execution? Long-running?        │
│  end                                                                │
└─────────────────────────────────────────────────────────────────────┘

With Effect:
┌─────────────────────────────────────────────────────────────────────┐
│  Effect.new(:order_fulfillment)                                     │
│  |> Effect.step(:validate, &validate/1)                             │
│  |> Effect.step(:reserve, &reserve_inventory/1, rollback: &release/1)│
│  |> Effect.step(:charge, &charge_payment/1,                         │
│       retry: [max: 3], rollback: &refund/1)                         │
│  |> Effect.step(:ship, &create_shipment/1, after: :charge)          │
│  |> Effect.run(order)                                               │
│                                                                     │
│  # Automatic: DAG ordering, retries, rollbacks on failure           │
└─────────────────────────────────────────────────────────────────────┘
```

Effect provides:
- **DAG-based execution** - Steps run in dependency order
- **Saga pattern** - Automatic rollback on failure
- **Retry with backoff** - Configurable retry strategies
- **Parallel execution** - Run independent steps concurrently
- **Branching** - Conditional paths through workflows
- **Checkpoints** - Pause and resume long-running workflows
- **Middleware** - Cross-cutting concerns (logging, metrics)
- **Testing utilities** - Mock steps, assertions, reports

## Quick Start

```elixir
# Define a workflow
Effect.new(:order_processing)
|> Effect.step(:validate, fn ctx ->
  if ctx.amount > 0, do: {:ok, %{validated: true}}, else: {:error, :invalid_amount}
end)
|> Effect.step(:charge, fn ctx ->
  case PaymentGateway.charge(ctx.customer_id, ctx.amount) do
    {:ok, payment_id} -> {:ok, %{payment_id: payment_id}}
    {:error, reason} -> {:error, reason}
  end
end, retry: [max: 3, delay: 1000])
|> Effect.step(:fulfill, fn ctx ->
  {:ok, %{fulfilled: true, order_id: ctx.order_id}}
end, rollback: fn ctx ->
  PaymentGateway.refund(ctx.payment_id)
  :ok
end)
|> Effect.run(%{order_id: 123, amount: 99_00, customer_id: "cus_abc"})

# Returns {:ok, final_context} or {:error, %Effect.Error{}}
```

---

## Step Return Values

Every step function must return one of:

| Return | Behavior |
|--------|----------|
| `{:ok, map}` | Continue, merge map into context |
| `{:error, term}` | Stop, trigger rollbacks for completed steps |
| `{:halt, term}` | Stop gracefully, NO rollback, run ensure hooks |

```elixir
# Success - adds keys to context
fn ctx -> {:ok, %{user: fetch_user(ctx.user_id)}} end

# Error - triggers rollback chain
fn ctx -> {:error, :payment_declined} end

# Halt - graceful early exit
fn ctx -> {:halt, :already_processed} end
```

---

## Building Effects

### Creating an Effect

```elixir
# Basic
effect = Effect.new(:order_workflow)

# With options
effect = Effect.new(:order_workflow,
  label: "Order Processing Pipeline",
  tags: [:critical, :payment],
  metadata: %{version: "1.0"},
  services: %{payment: StripeGateway, mailer: SendGrid}
)
```

### Adding Steps

```elixir
effect
|> Effect.step(:validate, &validate/1)
|> Effect.step(:process, &process/1, after: :validate)
|> Effect.step(:notify, &notify/1, after: :process)
```

### Step Options

| Option | Description |
|--------|-------------|
| `:after` | Step(s) that must complete first |
| `:timeout` | Per-attempt timeout (ms) |
| `:retry` | Retry configuration |
| `:when` | Condition to skip step |
| `:rollback` | Rollback function on failure |
| `:catch` | Error handler function |
| `:fallback` | Default value on error |
| `:meta` | Arbitrary metadata |

```elixir
Effect.step(effect, :charge,
  &charge_payment/1,
  after: :validate,
  timeout: 30_000,
  retry: [max: 3, delay: 1000, backoff: :exponential],
  when: fn ctx -> ctx.amount > 0 end,
  rollback: &refund/1,
  meta: %{critical: true}
)
```

### Assign (Static Values)

```elixir
effect
|> Effect.assign(:timestamp, DateTime.utc_now())
|> Effect.assign(:config, fn ctx -> load_config(ctx.env) end)
```

### Tap (Side Effects)

```elixir
# Run side effect without modifying context
effect
|> Effect.tap(:log_start, fn ctx ->
  Logger.info("Processing order #{ctx.order_id}")
end)
```

### Require (Preconditions)

```elixir
# Halt with error if condition is false
effect
|> Effect.require(:authorized, fn ctx -> ctx.user.admin? end, :unauthorized)
|> Effect.require(:has_items, fn ctx -> length(ctx.items) > 0 end, :empty_order)
```

### Validate

```elixir
effect
|> Effect.validate(:amount_valid, fn ctx ->
  if ctx.amount > 0, do: :ok, else: {:error, :invalid_amount}
end)
```

---

## Retry Configuration

Configure automatic retries for transient failures:

```elixir
Effect.step(effect, :api_call, &call_external_api/1,
  retry: [
    max: 5,                    # Maximum attempts
    delay: 1000,               # Initial delay (ms)
    backoff: :exponential,     # :fixed | :linear | :exponential | :decorrelated_jitter
    max_delay: 30_000,         # Cap delay at 30s
    jitter: 0.1,               # Add 10% random jitter
    when: fn error ->          # Only retry specific errors
      match?({:error, :timeout}, error) or
      match?({:error, {:http, 503}}, error)
    end
  ]
)
```

### Backoff Strategies

| Strategy | Formula | Use Case |
|----------|---------|----------|
| `:fixed` | `delay` | Constant wait between retries |
| `:linear` | `delay * attempt` | Gradually increasing |
| `:exponential` | `delay * 2^attempt` | Aggressive backoff |
| `:decorrelated_jitter` | Randomized exponential | Best for distributed systems |

---

## Rollback (Saga Pattern)

When a step fails, previously completed steps with rollback functions are called in reverse order:

```elixir
Effect.new(:order_saga)
|> Effect.step(:reserve_inventory, fn ctx ->
  {:ok, %{reservation_id: Inventory.reserve(ctx.items)}}
end, rollback: fn ctx ->
  Inventory.release(ctx.reservation_id)
  :ok
end)
|> Effect.step(:charge_payment, fn ctx ->
  {:ok, %{charge_id: Payments.charge(ctx.amount)}}
end, rollback: fn ctx ->
  Payments.refund(ctx.charge_id)
  :ok
end)
|> Effect.step(:ship_order, fn ctx ->
  # If this fails, charge_payment and reserve_inventory rollbacks run
  {:ok, %{shipment_id: Shipping.create(ctx.order_id)}}
end)
```

```
Execution flow:
  reserve_inventory ✓ → charge_payment ✓ → ship_order ✗
                                              │
  release_inventory ← refund_payment ←────────┘
                                        (rollbacks in reverse)
```

---

## Parallel Execution

Run independent steps concurrently:

```elixir
effect
|> Effect.parallel(:checks, [
  {:fraud_check, &check_fraud/1},
  {:inventory_check, &check_inventory/1},
  {:credit_check, &check_credit/1}
], after: :validate)
```

### Parallel Options

| Option | Values | Description |
|--------|--------|-------------|
| `:on_error` | `:fail_fast` (default), `:continue` | Stop on first error or run all |
| `:timeout` | milliseconds | Per-step timeout |
| `:max_concurrency` | integer | Limit concurrent tasks |

```elixir
# Continue even if some validations fail (collect all errors)
effect
|> Effect.parallel(:validations, [
  {:email_valid, &validate_email/1},
  {:phone_valid, &validate_phone/1},
  {:address_valid, &validate_address/1}
], on_error: :continue, timeout: 5_000)
```

---

## Branching

Select different execution paths based on context:

```elixir
effect
|> Effect.branch(:fulfill_order, fn ctx -> ctx.order_type end, %{
  :digital => fn ctx ->
    {:ok, %{delivery: send_download_link(ctx)}}
  end,
  :physical => fn ctx ->
    {:ok, %{delivery: create_shipment(ctx)}}
  end,
  :subscription => SubscriptionFlow.build(),  # Nested effect
  :default => fn ctx ->
    {:ok, %{delivery: :pending_review}}
  end
}, after: :payment)
```

---

## Each (Iteration)

Process a collection with a nested effect:

```elixir
# Define item processor
item_processor = Effect.new(:process_item)
|> Effect.step(:validate_item, fn ctx ->
  {:ok, %{valid: true}}
end)
|> Effect.step(:process_item, fn ctx ->
  {:ok, %{processed: transform(ctx.item)}}
end)

# Use in parent effect
effect
|> Effect.each(:process_items, fn ctx -> ctx.items end, item_processor,
  as: :current_item,         # Key for current item in context
  collect: :processed_items, # Key to collect results
  concurrency: 5             # Process 5 items concurrently
)
```

---

## Race (First Wins)

Run multiple strategies, use first successful result:

```elixir
# Define competing strategies
cache_lookup = Effect.new(:cache)
|> Effect.step(:get, fn ctx -> Cache.get(ctx.key) end)

db_lookup = Effect.new(:database)
|> Effect.step(:query, fn ctx -> Repo.get(User, ctx.user_id) end)

api_lookup = Effect.new(:api)
|> Effect.step(:fetch, fn ctx -> API.fetch_user(ctx.user_id) end)

# Race them
effect
|> Effect.race(:get_user, [cache_lookup, db_lookup, api_lookup],
  timeout: 5_000
)
```

---

## Embedding (Nested Effects)

Compose effects by embedding one inside another:

```elixir
# Payment flow as separate effect
payment_flow = Effect.new(:payment)
|> Effect.step(:authorize, &authorize_card/1)
|> Effect.step(:capture, &capture_payment/1)

# Embed in order flow
order_flow = Effect.new(:order)
|> Effect.step(:validate, &validate_order/1)
|> Effect.embed(:payment, payment_flow, after: :validate,
  context: fn ctx -> %{amount: ctx.total, card: ctx.payment_method} end
)
|> Effect.step(:fulfill, &fulfill_order/1, after: :payment)
```

---

## Resource Management (Using)

Safely acquire and release resources:

```elixir
effect
|> Effect.using(:database_connection, [
  acquire: fn ctx ->
    {:ok, %{conn: DBConnection.checkout(pool)}}
  end,
  release: fn ctx, _result ->
    DBConnection.checkin(pool, ctx.conn)
  end,
  body: Effect.new(:db_operations)
    |> Effect.step(:query, fn ctx ->
      {:ok, %{result: DBConnection.query(ctx.conn, ctx.sql)}}
    end)
])
```

The `release` function always runs, even on error (like `try/after`).

---

## Checkpoints (Pause/Resume)

Pause long-running workflows for external events:

```elixir
effect = Effect.new(:approval_workflow)
|> Effect.step(:submit, &submit_for_approval/1)
|> Effect.checkpoint(:await_approval,
  store: fn execution_id, state ->
    MyStore.save(execution_id, state)
  end,
  load: fn execution_id ->
    MyStore.load(execution_id)
  end
)
|> Effect.step(:process_approval, fn ctx ->
  {:ok, %{approved: true}}
end, after: :await_approval)

# First run - pauses at checkpoint
case Effect.run(effect, %{request_id: 123}) do
  {:checkpoint, execution_id, :await_approval, ctx} ->
    # Store execution_id, notify approver
    send_approval_request(ctx.request_id, execution_id)

  {:ok, result} ->
    # Workflow completed
    :done
end

# Later, after approval received
{:ok, result} = Effect.resume(effect, execution_id)
```

---

## Middleware

Add cross-cutting concerns that wrap every step:

```elixir
effect
|> Effect.middleware(fn step_name, ctx, next ->
  start = System.monotonic_time(:millisecond)
  result = next.()
  duration = System.monotonic_time(:millisecond) - start

  Logger.info("[#{step_name}] completed in #{duration}ms")

  :telemetry.execute(
    [:my_app, :effect, :step],
    %{duration: duration},
    %{step: step_name, effect: ctx.__effect_name__}
  )

  result
end)
```

### Built-in Middleware Pattern

```elixir
defmodule MyApp.Effect.Middleware do
  def timing do
    fn step, ctx, next ->
      start = System.monotonic_time(:millisecond)
      result = next.()
      duration = System.monotonic_time(:millisecond) - start
      Logger.debug("[Effect] #{step} took #{duration}ms")
      result
    end
  end

  def error_reporting do
    fn step, ctx, next ->
      case next.() do
        {:error, reason} = error ->
          Sentry.capture_message("Effect step failed",
            extra: %{step: step, reason: reason}
          )
          error

        result ->
          result
      end
    end
  end
end

# Usage
effect
|> Effect.middleware(MyApp.Effect.Middleware.timing())
|> Effect.middleware(MyApp.Effect.Middleware.error_reporting())
```

---

## Lifecycle Hooks

React to workflow events:

```elixir
effect
|> Effect.on_start(fn name, ctx ->
  Logger.info("Starting effect #{name}")
end)
|> Effect.on_complete(fn name, ctx ->
  Logger.info("Completed effect #{name}")
end)
|> Effect.on_error(fn step, reason, ctx ->
  Logger.error("Step #{step} failed: #{inspect(reason)}")
  Sentry.capture_exception(reason, extra: %{step: step})
end)
|> Effect.on_rollback(fn step, ctx ->
  Logger.warning("Rolling back step #{step}")
end)
```

### Ensure (Always Runs)

```elixir
# Like try/after - cleanup that always runs
effect
|> Effect.ensure(:cleanup, fn ctx, result ->
  TempFile.delete(ctx.temp_file)
  Metrics.record_completion(ctx.workflow_id, result)
end)
```

---

## Execution

### Basic Run

```elixir
case Effect.run(effect, %{order_id: 123}) do
  {:ok, context} ->
    # Success - context contains all step results
    IO.puts("Order #{context.order_id} processed")

  {:error, %Effect.Error{} = error} ->
    # Failure - rollbacks already executed
    IO.puts("Failed at step #{error.step}: #{inspect(error.reason)}")

  {:halted, reason} ->
    # Graceful halt via {:halt, reason}
    IO.puts("Workflow halted: #{inspect(reason)}")
end
```

### Run Options

```elixir
Effect.run(effect, context,
  timeout: 60_000,           # Total execution timeout
  report: true,              # Return execution report
  debug: true,               # Log step execution
  services: %{               # Override services
    payment: MockPaymentGateway
  }
)
```

### With Report

```elixir
{{:ok, result}, report} = Effect.run(effect, ctx, report: true)

# Inspect execution
Effect.Report.executed_steps(report)   # [:validate, :charge, :fulfill]
Effect.Report.skipped_steps(report)    # [:optional_notify]
Effect.Report.total_duration(report)   # 1523 (ms)
Effect.Report.step_duration(report, :charge)  # 892 (ms)
```

### Run! (Raising)

```elixir
# Raises on error
result = Effect.run!(effect, context)
```

---

## Dependency Injection

Pass service implementations at runtime:

```elixir
# Define effect with service parameter
effect = Effect.new(:order, services: %{
  payment: nil,  # To be injected
  mailer: nil
})
|> Effect.step(:charge, fn ctx, services ->
  services.payment.charge(ctx.amount)
end)
|> Effect.step(:notify, fn ctx, services ->
  services.mailer.send(ctx.user.email, "Order confirmed")
end)

# Production
Effect.run(effect, ctx, services: %{
  payment: StripeGateway,
  mailer: SendGrid
})

# Testing
Effect.run(effect, ctx, services: %{
  payment: MockPaymentGateway,
  mailer: InMemoryMailer
})
```

---

## Visualization

### ASCII Diagram

```elixir
effect |> Effect.to_ascii() |> IO.puts()

# Output:
# ┌─────────────────────────────────┐
# │         order_workflow          │
# └─────────────────────────────────┘
#              │
#              ▼
#        ┌──────────┐
#        │ validate │
#        └────┬─────┘
#              │
#              ▼
#        ┌──────────┐
#        │  charge  │ [retry: 3]
#        └────┬─────┘
#              │
#              ▼
#        ┌──────────┐
#        │ fulfill  │ [rollback]
#        └──────────┘
```

### Mermaid Diagram

```elixir
effect |> Effect.to_mermaid() |> IO.puts()

# Output:
# flowchart TD
#     validate --> charge
#     charge --> fulfill
#     style charge stroke:#f66
```

### Summary

```elixir
Effect.summary(effect)
#=> %{
#     name: :order_workflow,
#     step_count: 5,
#     has_rollbacks: true,
#     has_retries: true,
#     parallel_groups: 1,
#     checkpoints: 0
#   }
```

---

## Testing

### Assertions

```elixir
import Effect.Testing

test "order workflow succeeds" do
  effect = OrderWorkflow.build()

  result = assert_effect_success(effect, %{
    order_id: 123,
    amount: 99_00
  })

  assert result.fulfilled == true
end

test "validates amount" do
  effect = OrderWorkflow.build()

  assert_effect_error(effect, %{amount: 0}, :validate,
    match: :invalid_amount
  )
end

test "halts on duplicate order" do
  effect = OrderWorkflow.build()

  assert_effect_halted(effect, %{duplicate: true}, :already_processed)
end
```

### Mocking Steps

```elixir
import Effect.Testing

test "with mocked payment" do
  effect =
    OrderWorkflow.build()
    |> mock_step(:charge, fn ctx ->
      {:ok, %{payment_id: "mock_pay_123"}}
    end)
    |> mock_step(:send_email, fn _ctx ->
      {:ok, %{}}  # Skip real email
    end)

  {:ok, result} = Effect.run(effect, %{order_id: 123})
  assert result.payment_id == "mock_pay_123"
end
```

### Execution Reports

```elixir
import Effect.Testing

test "executes steps in order" do
  effect = OrderWorkflow.build()
  report = run_with_report(effect, %{order_id: 123})

  assert_steps_executed(report, [:validate, :charge, :fulfill, :notify])
  assert_steps_skipped(report, [:optional_analytics])
end
```

### Testing Retry Behavior

```elixir
import Effect.Testing

test "retries on transient failure" do
  # Create step that fails twice, then succeeds
  flaky = flaky_step(2, {:ok, %{result: :success}})

  effect =
    Effect.new(:test)
    |> Effect.step(:api_call, flaky, retry: [max: 3])

  {:ok, result} = Effect.run(effect)
  assert result.result == :success
end
```

### Timing Tests

```elixir
import Effect.Testing

test "slow step timing" do
  slow_fn = fn _ctx ->
    Process.sleep(100)
    {:ok, %{}}
  end

  {step_fn, get_duration} = timed_step(slow_fn)

  effect =
    Effect.new(:test)
    |> Effect.step(:slow, step_fn)

  Effect.run(effect, %{})

  assert get_duration.() >= 100
end
```

---

## Real-World Examples

### E-commerce Order Processing

```elixir
defmodule MyApp.OrderWorkflow do
  def build do
    Effect.new(:order_processing,
      label: "E-commerce Order Flow",
      tags: [:critical, :payment]
    )
    |> Effect.assign(:timestamp, DateTime.utc_now())
    |> Effect.require(:has_items, fn ctx -> length(ctx.items) > 0 end, :empty_order)
    |> Effect.step(:validate, &validate_order/1)
    |> Effect.parallel(:checks, [
      {:fraud, &check_fraud/1},
      {:inventory, &check_inventory/1}
    ], after: :validate)
    |> Effect.step(:reserve_inventory, &reserve_inventory/1,
      after: :checks,
      rollback: &release_inventory/1
    )
    |> Effect.step(:charge_payment, &charge_payment/1,
      after: :reserve_inventory,
      retry: [max: 3, delay: 1000, backoff: :exponential],
      rollback: &refund_payment/1
    )
    |> Effect.branch(:fulfill, fn ctx -> ctx.order_type end, %{
      digital: &send_download_link/1,
      physical: &create_shipment/1
    }, after: :charge_payment)
    |> Effect.tap(:notify, fn ctx ->
      Mailer.send_confirmation(ctx.customer_email, ctx)
    end, after: :fulfill)
    |> Effect.on_error(&log_order_error/3)
    |> Effect.middleware(&timing_middleware/3)
  end

  # Step implementations
  defp validate_order(ctx) do
    case Validator.validate(ctx) do
      :ok -> {:ok, %{validated: true}}
      {:error, errors} -> {:error, {:validation_failed, errors}}
    end
  end

  defp check_fraud(ctx) do
    case FraudService.check(ctx.customer_id, ctx.total) do
      :ok -> {:ok, %{fraud_check: :passed}}
      {:suspicious, reason} -> {:error, {:fraud_detected, reason}}
    end
  end

  defp check_inventory(ctx) do
    case Inventory.check_availability(ctx.items) do
      :available -> {:ok, %{inventory_check: :passed}}
      {:unavailable, items} -> {:error, {:out_of_stock, items}}
    end
  end

  defp reserve_inventory(ctx) do
    {:ok, reservation} = Inventory.reserve(ctx.items)
    {:ok, %{reservation_id: reservation.id}}
  end

  defp release_inventory(ctx) do
    Inventory.release(ctx.reservation_id)
    :ok
  end

  defp charge_payment(ctx) do
    case PaymentGateway.charge(ctx.customer_id, ctx.total) do
      {:ok, charge} -> {:ok, %{charge_id: charge.id}}
      {:error, :declined} -> {:error, :payment_declined}
      {:error, :timeout} -> {:error, :payment_timeout}
    end
  end

  defp refund_payment(ctx) do
    PaymentGateway.refund(ctx.charge_id)
    :ok
  end

  defp send_download_link(ctx) do
    url = Downloads.generate_link(ctx.items)
    {:ok, %{delivery_type: :digital, download_url: url}}
  end

  defp create_shipment(ctx) do
    {:ok, shipment} = Shipping.create(ctx.order_id, ctx.address)
    {:ok, %{delivery_type: :physical, tracking_number: shipment.tracking}}
  end

  defp log_order_error(step, reason, ctx) do
    Logger.error("Order #{ctx.order_id} failed at #{step}: #{inspect(reason)}")
  end

  defp timing_middleware(step, ctx, next) do
    start = System.monotonic_time(:millisecond)
    result = next.()
    duration = System.monotonic_time(:millisecond) - start

    :telemetry.execute(
      [:my_app, :order, :step],
      %{duration: duration},
      %{step: step, order_id: ctx[:order_id]}
    )

    result
  end
end

# Usage
{:ok, result} = MyApp.OrderWorkflow.build()
|> Effect.run(%{
  order_id: "ord_123",
  customer_id: "cus_456",
  customer_email: "user@example.com",
  items: [%{sku: "WIDGET", qty: 2}],
  order_type: :physical,
  total: 49_99,
  address: %{city: "NYC", zip: "10001"}
})
```

### Approval Workflow with Checkpoint

```elixir
defmodule MyApp.ApprovalWorkflow do
  def build do
    Effect.new(:expense_approval)
    |> Effect.step(:submit, fn ctx ->
      {:ok, %{submitted_at: DateTime.utc_now()}}
    end)
    |> Effect.step(:auto_approve?, fn ctx ->
      if ctx.amount < 100_00 do
        {:ok, %{auto_approved: true, approved: true}}
      else
        {:ok, %{auto_approved: false}}
      end
    end)
    |> Effect.checkpoint(:await_manager_approval,
      when: fn ctx -> not ctx.auto_approved end,
      store: &CheckpointStore.save/2,
      load: &CheckpointStore.load/1
    )
    |> Effect.step(:process_approval, fn ctx ->
      if ctx.approved do
        {:ok, %{processed: true}}
      else
        {:halt, :rejected}
      end
    end, after: :await_manager_approval)
    |> Effect.step(:reimburse, &process_reimbursement/1,
      after: :process_approval
    )
  end

  # First submission
  def submit(expense) do
    case Effect.run(build(), expense) do
      {:ok, result} ->
        {:ok, result}

      {:checkpoint, execution_id, :await_manager_approval, ctx} ->
        Notifications.notify_manager(ctx.manager_id, execution_id)
        {:pending_approval, execution_id}
    end
  end

  # Manager approves
  def approve(execution_id) do
    effect = build()
    # Update stored context with approval
    CheckpointStore.update(execution_id, %{approved: true})
    Effect.resume(effect, execution_id)
  end

  # Manager rejects
  def reject(execution_id) do
    effect = build()
    CheckpointStore.update(execution_id, %{approved: false})
    Effect.resume(effect, execution_id)
  end
end
```

### Data Pipeline with Fan-out/Fan-in

```elixir
defmodule MyApp.DataPipeline do
  def build do
    Effect.new(:data_pipeline)
    |> Effect.step(:fetch_data, &fetch_from_source/1)
    |> Effect.each(:process_records, fn ctx -> ctx.records end,
      record_processor(),
      concurrency: 10,
      collect: :processed_records
    )
    |> Effect.step(:aggregate, fn ctx ->
      summary = Enum.reduce(ctx.processed_records, %{}, &aggregate/2)
      {:ok, %{summary: summary}}
    end, after: :process_records)
    |> Effect.parallel(:output, [
      {:save_to_db, &save_to_database/1},
      {:upload_to_s3, &upload_to_s3/1},
      {:notify_slack, &notify_slack/1}
    ], after: :aggregate)
  end

  defp record_processor do
    Effect.new(:record)
    |> Effect.step(:transform, fn ctx ->
      {:ok, %{transformed: transform(ctx.item)}}
    end)
    |> Effect.step(:validate, fn ctx ->
      case validate_record(ctx.transformed) do
        :ok -> {:ok, %{valid: true}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
```

---

## Error Handling

### Error Structure

```elixir
%Effect.Error{
  step: :charge_payment,           # Step that failed
  reason: :payment_declined,       # Error reason
  context: %{...},                 # Context at failure
  execution_id: "abc123",          # Unique execution ID
  effect_name: :order_processing,  # Effect name
  duration_ms: 892,                # Time until failure
  attempts: 3,                     # Retry attempts made
  rollback_errors: []              # Any rollback failures
}
```

### Catching Errors

```elixir
Effect.step(effect, :risky_operation, &risky/1,
  catch: fn error, ctx ->
    Logger.warning("Caught error: #{inspect(error)}")
    {:ok, %{fallback_used: true, result: default_value()}}
  end
)
```

### Fallback Values

```elixir
Effect.step(effect, :optional_fetch, &fetch_optional/1,
  fallback: %{optional_data: nil},
  fallback_when: [:not_found, :timeout]  # Only fallback on these errors
)
```

---

## Configuration Reference

### Step Options

| Option | Type | Description |
|--------|------|-------------|
| `:after` | `atom \| [atom]` | Dependencies |
| `:timeout` | `pos_integer` | Per-attempt timeout (ms) |
| `:retry` | `keyword` | Retry configuration |
| `:when` | `function` | Condition to run step |
| `:rollback` | `function` | Saga rollback function |
| `:catch` | `function` | Error handler |
| `:fallback` | `term` | Default on error |
| `:meta` | `map` | Arbitrary metadata |

### Retry Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:max` | `pos_integer` | 3 | Maximum attempts |
| `:delay` | `pos_integer` | 1000 | Initial delay (ms) |
| `:backoff` | `atom` | `:exponential` | Backoff strategy |
| `:max_delay` | `pos_integer` | 30_000 | Maximum delay (ms) |
| `:jitter` | `float` | 0.1 | Jitter factor |
| `:when` | `function` | - | Condition to retry |

### Run Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:timeout` | `pos_integer` | - | Total timeout (ms) |
| `:report` | `boolean` | `false` | Return execution report |
| `:debug` | `boolean` | `false` | Log step execution |
| `:services` | `map` | `%{}` | Service overrides |

## License

MIT
