# Effect System - Comprehensive Design Plan

## Executive Summary

A production-ready Effect system for Elixir providing lazy, composable, typed effects with:
- Step-based DAG execution
- First-class error handling and recovery
- Built-in resilience patterns (retry, circuit breaker, rate limiting, bulkhead)
- Human-in-the-loop approval workflows
- Full observability (telemetry, tracing, inspection)
- Saga pattern with rollback/compensation

---

## Core Design Principles

1. **Explicit over implicit** - No magic, everything visible
2. **Step-based, not monadic** - `step`/`steps` instead of `flat_map`
3. **Parallel by default** - Steps without dependencies run concurrently
4. **Lazy until run** - Effects are descriptions until `Effect.run`
5. **Production-ready** - Cancellation, idempotency, rate limiting built-in

---

## Core API

### Building Effects

```elixir
# Create effect
Effect.new(name)

# Single operation
Effect.step(effect, name, function, opts \\ [])

# Nested workflow (multiple steps)
Effect.steps(effect, name, workflow, opts \\ [])

# Concurrent operations
Effect.parallel(effect, name, specs, opts \\ [])

# Conditional path
Effect.branch(effect, name, selector, routes, opts \\ [])

# Iteration
Effect.each(effect, name, collection_fn, workflow, opts \\ [])

# First success wins
Effect.race(effect, name, workflows, opts \\ [])

# Resource management
Effect.bracket(effect, name, acquire:, use:, release:)

# Human approval (see Human-in-the-Loop section)
Effect.await_approval(effect, name, opts \\ [])
Effect.checkpoint(effect, name, opts \\ [])
```

### Composition

```elixir
Effect.sequence(effects)    # Run in order
Effect.merge(effects)       # Combine DAGs
```

### Hooks

```elixir
Effect.on_start(effect, callback)
Effect.on_complete(effect, callback)
Effect.on_error(effect, callback)
Effect.on_rollback(effect, callback)
```

### Execution

```elixir
Effect.run(effect, context, opts \\ [])
Effect.cancel(handle, opts \\ [])
Effect.status(handle)
Effect.await(handle, opts \\ [])

# Human-in-the-loop
Effect.approve(handle, step_name, opts \\ [])
Effect.reject(handle, step_name, reason)
Effect.pending_approvals(handle)
```

### Inspection

```elixir
Effect.validate(effect)
Effect.validate!(effect)
Effect.analyze(effect)
Effect.to_ascii(effect)
Effect.to_mermaid(effect)
Effect.to_docs(effect)
```

---

## Step Options (Complete Reference)

```elixir
Effect.step(:name, function,
  # ─── Metadata ───
  label: "Human readable description",
  tags: [:critical, :payment],
  pure: true,                          # Side-effect free, enables caching
  redact: [:password, :token],         # Hide from logs/traces

  # ─── Dependencies ───
  after: :previous,                    # Run after this step
  after: [:a, :b],                     # Run after ALL of these
  after_any: [:a, :b],                 # Run after ANY of these

  # ─── Timing ───
  timeout: 5_000,                      # Per-attempt timeout (ms)
  total_timeout: 30_000,               # Total including retries

  # ─── Retry ───
  retry: [
    max: 3,                            # Max attempts
    delay: 100,                        # Initial delay (ms)
    backoff: :exponential,             # :fixed | :linear | :exponential
    max_delay: 10_000,                 # Cap delay
    jitter: 0.1,                       # Randomness (0.0 - 1.0)
    when: &Recoverable.recoverable?/1  # Only retry if true
  ],

  # ─── Circuit Breaker ───
  circuit: [
    name: :service_name,               # Shared across steps
    threshold: 5,                      # Open after N failures
    reset_after: 30_000                # Try again after (ms)
  ],

  # ─── Rate Limiting ───
  rate_limit: [
    name: :api_name,                   # Shared limiter
    max: 100,                          # Max requests
    per: 1_000,                        # Per milliseconds
    on_limit: :queue                   # :queue | :drop | :error
  ],

  # ─── Bulkhead (Isolation) ───
  bulkhead: [
    name: :external_service,
    max_concurrent: 10,                # Max parallel calls
    max_queue: 100,                    # Queue size
    on_full: :error                    # :error | :drop | :wait
  ],

  # ─── Idempotency ───
  idempotency_key: fn ctx -> "key_#{ctx.id}" end,
  idempotency_ttl: :timer.hours(24),

  # ─── Caching ───
  cache: [
    ttl: :timer.minutes(5),
    key: fn ctx -> {ctx.a, ctx.b} end,
    store: :ets                        # :ets | :redis | Module
  ],

  # ─── Conditional ───
  when: fn ctx -> ctx.enabled end,     # Skip if false
  unless: fn ctx -> ctx.skip end,      # Skip if true

  # ─── Error Handling ───
  catch: fn error, ctx -> {:ok, %{}} | {:error, error} end,
  fallback: %{default: :value},        # Use on specific errors
  fallback_when: [:not_found, :timeout],

  # ─── Saga / Rollback ───
  rollback: fn ctx -> :ok end,
  compensate: fn ctx, error -> :ok end,  # Receives the error

  # ─── Hooks ───
  before: fn ctx -> {:cont, ctx} | {:halt, {:error, reason}} end,
  after: fn ctx, result, duration_ms -> result end,
  on_success: fn ctx, value -> :ok end,
  on_error: fn ctx, error -> :ok end,
  on_retry: fn ctx, error, attempt -> :ok end,

  # ─── Telemetry ───
  telemetry: [
    event: [:my_app, :custom, :event],
    metadata: fn ctx -> %{user_id: ctx.user_id} end
  ]
)
```

---

## Run Options (Complete Reference)

```elixir
Effect.run(effect, ctx,
  # ─── Execution Mode ───
  async: false,                        # Return Task if true
  report: false,                       # Return {result, Report.t()} if true
  debug: false,                        # Enable step-through debugging
  dry_run: false,                      # Validate only, don't execute

  # ─── Observability ───
  observe: fn event -> :ok end,        # Live event callback
  trace: true,                         # Capture execution trace
  trace_id: "correlation-id",          # For distributed tracing
  parent_span: span,                   # OpenTelemetry parent

  # ─── Timing ───
  timeout: 60_000,                     # Total effect timeout
  deadline: ~U[2024-01-15 17:00:00Z],  # Absolute deadline

  # ─── Error Handling ───
  on_error: :fail_fast,                # :fail_fast | :collect
  normalize_errors: true,              # Auto-normalize via protocol

  # ─── Idempotency ───
  idempotency_key: "unique_operation_key",
  on_duplicate: :return_cached,        # :return_cached | :error | :allow

  # ─── Resilience (Global) ───
  rate_limiters: %{
    external_api: {100, :timer.seconds(1)}
  },
  bulkheads: %{
    external_service: 10
  },

  # ─── Shutdown ───
  shutdown: [
    timeout: 30_000,                   # Wait for completion
    on_shutdown: :finish_step,         # :finish_step | :rollback | :force
    checkpoint: true                   # Save state for resume
  ],

  # ─── Telemetry ───
  telemetry: [:my_app, :effects],
  telemetry_metadata: %{request_id: "abc"},

  # ─── Services / DI ───
  services: %{
    repo: MyApp.Repo,
    http: MyApp.HTTP
  },

  # ─── Testing ───
  mocks: %{
    step_name: fn ctx -> {:ok, %{mocked: true}} end
  }
)
```

---

## Human-in-the-Loop Support

### Approval Points

```elixir
Effect.new(:high_value_order)
|> Effect.step(:validate, &validate/1)
|> Effect.step(:calculate_total, &calculate/1)

# Pause for human approval
|> Effect.await_approval(:manager_approval,
     label: "Manager approval required",
     when: fn ctx -> ctx.total > 10_000 end,  # Only for high-value
     timeout: :timer.hours(24),               # Max wait time
     notify: fn ctx ->
       Slack.notify("#approvals", "Order #{ctx.order_id} needs approval")
     end,
     on_timeout: :reject,                     # :reject | :auto_approve | :escalate
     escalate_after: :timer.hours(4),         # Escalate if no response
     escalate_to: fn ctx -> ctx.manager.supervisor end
   )

|> Effect.step(:charge, &charge/1, after: :manager_approval)
|> Effect.step(:fulfill, &fulfill/1, after: :charge)
```

### Checkpoints (Save & Resume)

```elixir
Effect.new(:long_running_process)
|> Effect.step(:phase1, &phase1/1)

# Save state - can resume from here
|> Effect.checkpoint(:after_phase1,
     storage: MyApp.EffectStore,             # Persistence backend
     ttl: :timer.days(7),                    # How long to keep
     on_resume: fn ctx, saved_at ->
       # Validate state is still valid
       if stale?(ctx, saved_at), do: {:error, :stale}, else: {:ok, ctx}
     end
   )

|> Effect.step(:phase2, &phase2/1, after: :after_phase1)
|> Effect.step(:phase3, &phase3/1, after: :phase2)
```

### Manual Intervention

```elixir
Effect.new(:order_with_review)
|> Effect.step(:auto_process, &auto_process/1)

# Human review step
|> Effect.manual(:review,
     label: "Manual review required",
     form: [
       {:approved, :boolean, required: true},
       {:notes, :string, required: false},
       {:adjusted_amount, :decimal, required: false}
     ],
     assigned_to: fn ctx -> ctx.reviewer_id end,
     timeout: :timer.hours(48)
   )

|> Effect.step(:finalize, fn ctx ->
     if ctx.review.approved do
       {:ok, %{status: :approved, notes: ctx.review.notes}}
     else
       {:error, :rejected}
     end
   end, after: :review)
```

### Interacting with Paused Effects

```elixir
# Start effect (will pause at approval point)
{:ok, handle} = Effect.run(effect, ctx, async: true)

# Check status
Effect.status(handle)
#=> %{
#     status: :awaiting_approval,
#     pending_step: :manager_approval,
#     context: %{order_id: 123, total: 15000},
#     waiting_since: ~U[...],
#     timeout_at: ~U[...]
#   }

# List all pending approvals
Effect.pending_approvals(handle)
#=> [%{step: :manager_approval, context: %{...}, waiting_since: ~U[...]}]

# Approve
Effect.approve(handle, :manager_approval,
  approved_by: "manager@example.com",
  notes: "Approved for VIP customer",
  context_updates: %{discount: 0.1}  # Optional: modify context
)

# Or reject
Effect.reject(handle, :manager_approval,
  rejected_by: "manager@example.com",
  reason: "Exceeds credit limit"
)

# Resume from checkpoint
{:ok, handle} = Effect.resume("effect_id_123",
  from: :after_phase1,
  storage: MyApp.EffectStore
)
```

### Approval with Branching

```elixir
Effect.new(:loan_application)
|> Effect.step(:assess_risk, &assess_risk/1)

|> Effect.branch(:approval_route, & &1.risk_level, %{
     low: Effect.new(:auto_approve)
          |> Effect.step(:approve, fn ctx -> {:ok, %{approved: true}} end),

     medium: Effect.new(:single_approval)
             |> Effect.await_approval(:credit_officer,
                  timeout: :timer.hours(8)
                ),

     high: Effect.new(:dual_approval)
           |> Effect.await_approval(:credit_officer,
                timeout: :timer.hours(8)
              )
           |> Effect.await_approval(:risk_committee,
                after: :credit_officer,
                timeout: :timer.hours(24)
              )
   }, after: :assess_risk)

|> Effect.step(:disburse, &disburse/1, after: :approval_route)
```

---

## Effect vs Workflow Comparison

### Feature Comparison

| Feature | **Effect** | **Workflow** |
|---------|-----------|--------------|
| **Execution Model** |
| Lazy/Declarative | Yes - AST until run | Yes - DAG built first |
| In-memory execution | Primary mode | Always persisted |
| Database persistence | Optional (checkpoints) | Always |
| Background jobs | Via async + checkpoint | Native |
| Scheduled execution | Not built-in | Cron support |
| **Composition** |
| Step chaining | `step`, `steps` | `step` decorator |
| Parallel execution | `parallel`, auto | Groups |
| Branching | `branch` | `when:` condition |
| Iteration | `each` | Grafts |
| Nesting | `steps` | Sub-workflows |
| **Error Handling** |
| Structured errors | Effect.Error | Raw errors |
| Error normalization | Protocol-based | Manual |
| Retry | Rich options | Step-level |
| Circuit breaker | Built-in | Not built-in |
| Rate limiting | Built-in | Not built-in |
| Bulkhead | Built-in | Not built-in |
| **Saga / Rollback** |
| Rollback support | Per-step, nested | Reverse order |
| Compensation | Receives error | No error context |
| Partial rollback | `:all`, `:completed` | All or nothing |
| **Human-in-the-Loop** |
| Approval points | `await_approval` | `await_approval: true` |
| Checkpoints | `checkpoint` | Automatic (DB) |
| Manual intervention | `manual` step | Via state |
| Timeout handling | Configurable | Configurable |
| Escalation | Built-in | Manual |
| **Observability** |
| Telemetry | Rich, configurable | Built-in |
| Tracing | OpenTelemetry ready | Basic spans |
| Visualization | ASCII, Mermaid, DOT | Mermaid |
| Debug mode | Step-through | Not available |
| Live status | `status/1` | Query DB |
| **Context** |
| Context passing | Accumulated map | Accumulated map |
| Input transformation | `input:` option | Manual |
| Output transformation | `output:` option | Manual |
| Secrets redaction | Built-in | Manual |
| **Testing** |
| Mocking | `mocks:` option | Manual |
| Dry run | `dry_run: true` | Not available |
| Test helpers | Effect.Testing | Manual |
| **Performance** |
| Overhead | Minimal (in-memory) | DB writes per step |
| Latency | Sub-millisecond | DB latency |
| Throughput | High | DB-limited |

### When to Use Each

#### Use **Effect** When:
- Request/response flows (API handlers)
- Complex business logic orchestration
- Need sub-millisecond latency
- Want rich error handling
- Need resilience patterns (circuit breaker, rate limit)
- In-memory is acceptable
- Testing is important

#### Use **Workflow** When:
- Long-running background jobs
- Need durability (survive restarts)
- Scheduled/cron tasks
- Need audit trail in database
- Multi-day processes
- External system integration with delays

#### Use **Both** Together:
```elixir
# Effect for request handling, Workflow for background
defmodule OrderController do
  def create(conn, params) do
    # Effect: Fast, in-memory order validation and creation
    result = OrderEffect.build()
             |> Effect.run(params)

    case result do
      {:ok, order} ->
        # Workflow: Durable background fulfillment
        Workflow.start(:order_fulfillment, %{order_id: order.id})
        json(conn, order)

      {:error, error} ->
        error_response(conn, error)
    end
  end
end
```

### Migration Path

| Current | Recommended | Notes |
|---------|-------------|-------|
| Simple Pipeline | Effect | More features, similar simplicity |
| Complex Pipeline | Effect | Better error handling, parallel |
| Request-time Workflow | Effect | Lower latency |
| Background Workflow | Keep Workflow | Durability needed |
| Scheduled Workflow | Keep Workflow | Cron support |
| Mixed (request + background) | Effect + Workflow | Best of both |

---

## Structured Errors

```elixir
defmodule Effect.Error do
  @type t :: %__MODULE__{
    # Identity
    tag: atom(),
    message: String.t(),

    # Location
    step: atom(),
    effect: atom(),
    path: [atom()],                    # [:order, :payment, :charge]

    # Context
    context: map(),
    input: term(),

    # Timing
    started_at: DateTime.t(),
    failed_at: DateTime.t(),
    duration_ms: non_neg_integer(),
    attempt: pos_integer(),

    # Classification
    recoverable: boolean(),
    retryable: boolean(),
    user_facing: boolean(),

    # Recovery
    suggested_action: :retry | :skip | :abort | :fallback,
    retry_after_ms: pos_integer() | nil,
    fallback_value: term() | nil,

    # Debugging
    stacktrace: Exception.stacktrace(),
    caused_by: t() | Exception.t() | nil,
    metadata: map()
  }
end

# Creation
Effect.Error.new(:not_found,
  message: "User not found",
  user_facing: true,
  suggested_action: :abort
)

# Automatic wrapping - step returns {:error, :not_found}
# System wraps as Effect.Error with full context
```

---

## Execution Report

```elixir
defmodule Effect.Report do
  @type t :: %__MODULE__{
    effect: atom(),
    status: :completed | :failed | :cancelled | :timeout,
    result: {:ok, term()} | {:error, Effect.Error.t()},

    # Timing
    started_at: DateTime.t(),
    completed_at: DateTime.t(),
    total_duration_ms: non_neg_integer(),

    # Steps
    steps_completed: [atom()],
    steps_failed: [atom()],
    steps_skipped: [atom()],
    steps_rolled_back: [atom()],

    # Trace
    trace: [StepTrace.t()],

    # Issues
    errors: [Effect.Error.t()],
    warnings: [Warning.t()],

    # Performance
    timing: %{atom() => non_neg_integer()},
    slowest_step: {atom(), non_neg_integer()},

    # Context
    initial_context: map(),
    final_context: map(),

    # Correlation
    trace_id: String.t()
  }
end
```

---

## Testing Utilities

```elixir
defmodule Effect.Testing do
  # Run with captured side effects
  def run_capture(effect, ctx, opts \\ [])
  #=> {:ok, result, %{calls: [...], telemetry: [...], rolled_back: [...]}}

  # Deterministic execution (controlled randomness)
  def run_deterministic(effect, ctx, seed: seed)

  # Time control
  def run_with_time(effect, ctx,
    start: ~U[...],
    advance: fn step -> milliseconds end
  )

  # Structure assertions
  def assert_step_exists(effect, step_name)
  def assert_depends_on(effect, step, dependency)
  def assert_has_rollback(effect, step_name)
  def assert_has_retry(effect, step_name)

  # Generators for property testing
  def gen_context(schema)
  def gen_failures(effect)
end

# Usage
test "handles payment failure with rollback" do
  {:ok, _result, capture} =
    OrderEffect.build()
    |> Effect.Testing.run_capture(ctx,
         mocks: %{
           charge: fn _ -> {:error, :declined} end
         }
       )

  assert :reserve_inventory in capture.rolled_back
  assert {:telemetry, [:my_app, :payment, :failed], _} in capture.telemetry
end
```

---

## Complete Example

```elixir
defmodule MyApp.Orders.ProcessOrder do
  def build do
    Effect.new(:order_processing)

    # ─── Validation ───
    |> Effect.step(:validate, &validate/1,
         label: "Validate order",
         pure: true
       )

    # ─── Parallel checks ───
    |> Effect.parallel(:checks, [
         {:fraud, &check_fraud/1,
           timeout: 5_000,
           fallback: %{fraud_status: :pending_review},
           fallback_when: [:timeout]
         },
         {:inventory, &check_inventory/1,
           retry: [max: 2, delay: 100]
         }
       ], after: :validate)

    # ─── Reserve with rollback ───
    |> Effect.step(:reserve, &reserve_inventory/1,
         after: :checks,
         rollback: &release_inventory/1,
         idempotency_key: fn ctx -> "reserve_#{ctx.order_id}" end
       )

    # ─── High-value approval ───
    |> Effect.await_approval(:manager_approval,
         after: :reserve,
         when: fn ctx -> ctx.total > 10_000 end,
         label: "Manager approval for high-value order",
         timeout: :timer.hours(24),
         notify: &notify_manager/1
       )

    # ─── Nested payment ───
    |> Effect.steps(:payment, PaymentFlow,
         after: :manager_approval,
         rollback: :all,
         input: fn ctx -> Map.take(ctx, [:user, :total]) end,
         circuit: [name: :payment_gateway, threshold: 5],
         rate_limit: [name: :payment_api, max: 100, per: 1_000]
       )

    # ─── Branch fulfillment ───
    |> Effect.branch(:fulfill, &fulfillment_type/1, %{
         digital: DigitalFlow,
         physical: PhysicalFlow
       }, after: :payment, rollback: :completed)

    # ─── Notify all recipients ───
    |> Effect.each(:notify, &recipients/1, NotificationFlow,
         after: :fulfill,
         max: 5,
         on_error: :continue
       )

    # ─── Complete ───
    |> Effect.step(:complete, &complete_order/1,
         after: :notify,
         redact: [:payment_token]
       )

    # ─── Global hooks ───
    |> Effect.on_error(&report_error/2)
    |> Effect.on_rollback(&log_rollback/2)
  end

  def run(order_id, opts \\ []) do
    build()
    |> Effect.run(
         build_context(order_id),
         Keyword.merge([
           telemetry: [:my_app, :orders],
           trace: true,
           normalize_errors: true
         ], opts)
       )
  end
end
```

---

## Minimal Examples

### Example 1: `steps` - Nested Workflow

```elixir
# Nested workflow module
defmodule PaymentFlow do
  def build do
    Effect.new(:payment)
    |> Effect.step(:authorize, fn ctx ->
         {:ok, %{auth_id: "auth_#{ctx.amount}"}}
       end)
    |> Effect.step(:capture, fn ctx ->
         {:ok, %{captured: true, receipt: "rcpt_#{ctx.auth_id}"}}
       end, after: :authorize)
  end
end

# Main workflow using steps
defmodule OrderFlow do
  def build do
    Effect.new(:order)
    |> Effect.step(:validate, fn ctx ->
         {:ok, %{validated: true}}
       end)
    |> Effect.steps(:payment, PaymentFlow,
         after: :validate,
         input: fn ctx -> %{amount: ctx.amount} end
       )
    |> Effect.step(:ship, fn ctx ->
         {:ok, %{shipped: true, tracking: "TRK123"}}
       end, after: :payment)
  end
end

# Run it
{:ok, result} = OrderFlow.build() |> Effect.run(%{amount: 100})
# result => %{validated: true, auth_id: "auth_100", captured: true, ...}
```

### Example 2: `branch` - Conditional Path

```elixir
# Branch target workflows
defmodule DigitalDelivery do
  def build do
    Effect.new(:digital)
    |> Effect.step(:generate_link, fn ctx ->
         {:ok, %{download_url: "https://example.com/#{ctx.order_id}"}}
       end)
    |> Effect.step(:send_email, fn ctx ->
         {:ok, %{emailed: true}}
       end, after: :generate_link)
  end
end

defmodule PhysicalDelivery do
  def build do
    Effect.new(:physical)
    |> Effect.step(:create_label, fn ctx ->
         {:ok, %{label: "SHIP_#{ctx.order_id}"}}
       end)
    |> Effect.step(:dispatch, fn ctx ->
         {:ok, %{dispatched: true, tracking: "TRK_#{ctx.label}"}}
       end, after: :create_label)
  end
end

# Main workflow with branch
defmodule FulfillmentFlow do
  def build do
    Effect.new(:fulfillment)
    |> Effect.step(:prepare, fn ctx ->
         {:ok, %{prepared: true}}
       end)
    |> Effect.branch(:deliver, & &1.item_type, %{
         digital: DigitalDelivery,
         physical: PhysicalDelivery
       }, after: :prepare)
    |> Effect.step(:complete, fn ctx ->
         {:ok, %{completed: true}}
       end, after: :deliver)
  end
end

# Run it - digital path
{:ok, result} = FulfillmentFlow.build()
                |> Effect.run(%{order_id: 1, item_type: :digital})
# result => %{prepared: true, download_url: "...", emailed: true, completed: true}

# Run it - physical path
{:ok, result} = FulfillmentFlow.build()
                |> Effect.run(%{order_id: 2, item_type: :physical})
# result => %{prepared: true, label: "SHIP_2", dispatched: true, ...}
```

---

## Implementation Phases

### Phase 1: Core (P0)
- [ ] Effect struct and builder
- [ ] `step`, `steps`, `parallel`
- [ ] Basic `run` execution
- [ ] Context accumulation
- [ ] Error handling (`catch`, `fallback`)
- [ ] Retry with backoff
- [ ] Rollback/compensation
- [ ] Basic telemetry

### Phase 2: Control Flow (P0)
- [ ] `branch` conditional routing
- [ ] `each` iteration
- [ ] `race` first-success
- [ ] `after` dependencies
- [ ] DAG validation

### Phase 3: Production Features (P1)
- [ ] Cancellation support
- [ ] Circuit breaker
- [ ] Rate limiting
- [ ] Secrets redaction
- [ ] Structured Error type
- [ ] Execution Report

### Phase 4: Human-in-the-Loop (P1)
- [ ] `await_approval` step
- [ ] `checkpoint` persistence
- [ ] `manual` intervention
- [ ] Approval/reject API
- [ ] Timeout and escalation

### Phase 5: Observability (P1)
- [ ] Rich telemetry events
- [ ] OpenTelemetry integration
- [ ] `to_ascii`, `to_mermaid`
- [ ] `analyze` static analysis
- [ ] Debug mode

### Phase 6: Advanced (P2)
- [ ] Bulkhead isolation
- [ ] Idempotency
- [ ] Caching/memoization
- [ ] Deadlines
- [ ] Graceful shutdown
- [ ] Testing utilities

### Phase 7: Composition (P2)
- [ ] `sequence` combinator
- [ ] `merge` combinator
- [ ] `bracket` resource management
- [ ] Compile-time validation

---

## File Structure

```
libs/effect/
├── lib/
│   ├── effect.ex                    # Main module, delegating facade
│   ├── effect/
│   │   ├── builder.ex               # Effect struct and builder API
│   │   ├── step.ex                  # Step struct and options
│   │   ├── dag.ex                   # DAG construction and validation
│   │   ├── runtime.ex               # Execution engine
│   │   ├── context.ex               # Context management
│   │   │
│   │   ├── control/
│   │   │   ├── branch.ex            # Conditional routing
│   │   │   ├── each.ex              # Iteration
│   │   │   ├── race.ex              # First-success
│   │   │   └── parallel.ex          # Parallel execution
│   │   │
│   │   ├── resilience/
│   │   │   ├── retry.ex             # Retry with backoff
│   │   │   ├── circuit_breaker.ex   # Circuit breaker
│   │   │   ├── rate_limiter.ex      # Rate limiting
│   │   │   ├── bulkhead.ex          # Isolation
│   │   │   └── timeout.ex           # Timeout handling
│   │   │
│   │   ├── saga/
│   │   │   ├── rollback.ex          # Rollback execution
│   │   │   └── compensation.ex      # Compensation handling
│   │   │
│   │   ├── human/
│   │   │   ├── approval.ex          # Approval points
│   │   │   ├── checkpoint.ex        # Checkpointing
│   │   │   └── manual.ex            # Manual intervention
│   │   │
│   │   ├── observability/
│   │   │   ├── telemetry.ex         # Telemetry integration
│   │   │   ├── tracing.ex           # Distributed tracing
│   │   │   └── debug.ex             # Debug mode
│   │   │
│   │   ├── inspection/
│   │   │   ├── ascii.ex             # ASCII visualization
│   │   │   ├── mermaid.ex           # Mermaid diagrams
│   │   │   ├── analyzer.ex          # Static analysis
│   │   │   └── docs.ex              # Documentation generation
│   │   │
│   │   ├── error.ex                 # Structured error type
│   │   ├── report.ex                # Execution report
│   │   ├── warning.ex               # Warning type
│   │   │
│   │   └── testing.ex               # Test utilities
│   │
│   └── mix.exs
│
├── test/
│   ├── effect_test.exs
│   ├── effect/
│   │   ├── builder_test.exs
│   │   ├── runtime_test.exs
│   │   ├── control/
│   │   ├── resilience/
│   │   ├── saga/
│   │   └── human/
│   └── support/
│       └── test_helpers.ex
```

---

## Summary

The Effect system provides:

1. **Simple, explicit API** - `step`, `steps`, `parallel`, `branch`, `each`
2. **Production resilience** - Retry, circuit breaker, rate limiting, bulkhead
3. **Rich error handling** - Structured errors, normalization, fallbacks
4. **Saga pattern** - Rollback and compensation
5. **Human-in-the-loop** - Approvals, checkpoints, manual steps
6. **Full observability** - Telemetry, tracing, visualization, debugging
7. **Testing support** - Mocks, dry run, test utilities
8. **Workflow compatibility** - Can work alongside or replace Workflow

Effect is for **in-memory, request-time orchestration**.
Workflow is for **durable, background job orchestration**.
Use both together for comprehensive coverage.
