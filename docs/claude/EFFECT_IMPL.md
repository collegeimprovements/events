# Effect System - Final Implementation Plan

## Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Core (`new`, `step`, `run`) | ✅ Complete | DAG-based execution |
| Retry with backoff | ✅ Complete | fixed/linear/exponential/decorrelated_jitter |
| Saga rollback | ✅ Complete | Reverse-order execution |
| `parallel/4` | ✅ Complete | Concurrent steps with fail_fast/continue |
| `branch/5` | ✅ Complete | Conditional routing |
| `embed/4` | ✅ Complete | Nested effects |
| `each/5` | ✅ Complete | Collection iteration |
| `race/4` | ✅ Complete | First-success wins |
| `using/4` | ✅ Complete | Resource lifecycle |
| `checkpoint/3`, `resume/2` | ✅ Complete | Long workflow support |
| Telemetry | ✅ Complete | Full event emission |
| Visualization | ✅ Complete | ASCII/Mermaid/DOT |
| Testing utilities | ✅ Complete | mock_step, flaky_step, assertions |
| `assign/3`, `tap/3` | ✅ Complete | Context helpers |
| `require/4`, `validate/3` | ✅ Complete | Preconditions |
| Middleware | ✅ Complete | Onion model |
| Hooks | ✅ Complete | on_start, on_complete, on_error |
| `ensure/3` | ✅ Complete | Always-run cleanup |
| `run_async/3` | ⏳ Planned | Async execution |
| `merge/2`, `sequence/1` | ⏳ Planned | Effect composition |
| `group/4` | ⏳ Planned | Step organization |
| `dry_run/2` | ⏳ Planned | Simulation mode |

**Tests: 59 passing**

---

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Elixir | >= 1.19 | Uses modern pattern matching, guards |
| OTP | >= 28 | Required for Task improvements |
| telemetry | ~> 1.0 | Optional, for observability |
| opentelemetry_api | ~> 1.0 | Optional, for tracing |

---

## Design Philosophy: Req/Plug-Style Lazy Execution

Effect follows the **Req/Plug middleware pattern**:
- **Build phase**: Accumulate steps, configuration, middleware (no execution)
- **Run phase**: Execute only when `Effect.run/2` is called
- **Composable**: Effects can be merged, nested, and reused

```elixir
# Like Req - build up, run at end
Effect.new(:order)
|> Effect.step(:validate, &validate/1)
|> Effect.step(:charge, &charge/1, retry: [max: 3])
|> Effect.step(:fulfill, &fulfill/1, rollback: &refund/1)
|> Effect.run(context)  # <-- Execution happens HERE only
```

---

## API Quick Reference

| Function | Purpose | Example |
|----------|---------|---------|
| `new/2` | Create effect | `Effect.new(:order, label: "...", tags: [...], metadata: %{})` |
| `step/4` | Add step | `Effect.step(e, :name, fn ctx, services -> ... end, opts)` |
| `embed/4` | Nest effect | `Effect.embed(e, :pay, Payment.build(), context: ...)` |
| `parallel/4` | Concurrent steps | `Effect.parallel(e, :checks, [a: &a/1, b: &b/1])` |
| `branch/5` | Conditional path | `Effect.branch(e, :type, & &1.kind, %{a: A.build()})` |
| `each/5` | Iterate | `Effect.each(e, :all, & &1.items, Item.build())` |
| `race/4` | First wins | `Effect.race(e, :fetch, [Cache.build(), DB.build()])` |
| `using/4` | Resource mgmt | `Effect.using(e, :conn, acquire: ..., release: ...)` |
| `require/4` | Precondition | `Effect.require(e, :auth, & &1.admin?, :unauthorized)` |
| `validate/3` | Validation step | `Effect.validate(e, :amt, & if &1.amt > 0, do: :ok)` |
| `assign/3` | Set context | `Effect.assign(e, :ts, DateTime.utc_now())` |
| `tap/3` | Side effect | `Effect.tap(e, :log, & Logger.info(&1.id))` |
| `group/4` | Organize steps | `Effect.group(e, :validation, fn e -> ... end)` |
| `ensure/3` | Always cleanup | `Effect.ensure(e, :close, fn ctx, _ -> close() end)` |
| `run/3` | Execute | `Effect.run(effect, ctx, timeout: 30_000)` |
| `middleware/2` | Wrap steps | `Effect.middleware(e, fn step, ctx, next -> ... end)` |
| `checkpoint/3` | Pause point | `Effect.checkpoint(e, :name, store: ..., load: ...)` |
| `resume/3` | Resume | `Effect.resume(effect, :checkpoint, execution_id)` |
| `to_mermaid/2` | Diagram | `Effect.to_mermaid(effect)` |
| `to_ascii/2` | Text diagram | `Effect.to_ascii(effect)` |

---

## Naming Changes from Draft

| Old | New | Reason |
|-----|-----|--------|
| `guard/4` | `require/4` | Elixir-idiomatic, clear intent |
| `steps/4` | `embed/4` | Clearer that it embeds another effect |
| `if:` option | `when:` option | Reads like Elixir guard clause |
| `input:` option | `context:` option | Explicit context passing for nested effects |

---

## Full API Reference

### Type Definitions

#### Effect.t() Struct

```elixir
@type step_fun :: (context() -> result()) | (context(), services() -> result())
@type context :: map()
@type services :: map()
@type result :: {:ok, map()} | {:error, term()} | {:halt, term()}

defstruct [
  :name,                    # atom() - effect name
  :steps,                   # [Step.t()] - ordered list of steps
  :dag,                     # Dag.t() - dependency graph
  :middleware,              # [middleware_fun()] - middleware stack
  :hooks,                   # %{on_start: [...], on_complete: [...], ...}
  :services,                # %{atom() => module()} - service modules
  :metadata,                # map() - arbitrary metadata
  :label,                   # String.t() | nil - human-readable label
  :tags,                    # [atom()] - categorization tags
  :telemetry_prefix,        # [atom()] | nil - telemetry event prefix
  :checkpoints,             # %{atom() => checkpoint_config()}
  :ensure_fns               # [{atom(), cleanup_fun()}] - always-run cleanup
]
```

#### Step.t() Struct

```elixir
defstruct [
  :name,                    # atom() - unique step identifier
  :fun,                     # step_fun() - the step function
  :arity,                   # 1 | 2 - function arity (ctx or ctx+services)
  :type,                    # :step | :parallel | :branch | :embed | :each | :race | :using | :require | :validate | :tap | :assign

  # Dependencies
  :after,                   # atom() | [atom()] | nil - run after these steps

  # Timing
  :timeout,                 # pos_integer() | nil - per-attempt timeout (ms)

  # Retry
  :retry,                   # retry_opts() | nil

  # Conditional
  :when,                    # (context() -> boolean()) | nil - skip when false

  # Error handling
  :catch,                   # (error, context() -> result()) | nil
  :fallback,                # term() | nil - default value on error
  :fallback_when,           # [atom()] | nil - error tags to fallback on

  # Saga
  :rollback,                # (context() -> :ok) | nil
  :compensate,              # (context(), error() -> :ok) | nil

  # Circuit breaker
  :circuit,                 # circuit_opts() | nil

  # Rate limiting
  :rate_limit,              # rate_limit_opts() | nil

  # Observability
  :telemetry,               # [atom()] | nil - custom telemetry prefix
  :trace,                   # boolean() - OpenTelemetry span
  :redact,                  # [atom()] - keys to redact in logs

  # Metadata
  :meta                     # map() - arbitrary step metadata
]

@type retry_opts :: [
  max: pos_integer(),
  delay: pos_integer(),
  backoff: :fixed | :linear | :exponential | :decorrelated_jitter,
  max_delay: pos_integer(),
  jitter: float(),
  when: (term() -> boolean())
]

@type circuit_opts :: [
  name: atom(),
  threshold: pos_integer(),
  reset_timeout: pos_integer(),
  trips_on: (term() -> boolean())
]

@type rate_limit_opts :: [
  name: atom(),
  limit: pos_integer(),
  window: pos_integer(),
  on_exceeded: :queue | :drop | :error
]
```

#### Error.t() Struct

```elixir
defstruct [
  :step,                    # atom() - which step failed
  :reason,                  # term() - original error/reason
  :tag,                     # atom() | nil - error classification
  :context,                 # map() - context at time of failure
  :stacktrace,              # list() | nil - Elixir stacktrace
  :attempts,                # pos_integer() - how many attempts were made
  :duration_ms,             # non_neg_integer() - time spent before failure
  :rollback_errors,         # [%{step: atom(), error: term()}] - rollback failures
  :execution_id,            # String.t() - unique execution identifier
  :effect_name,             # atom() - which effect failed
  :metadata                 # map() - effect metadata at failure
]

# Constructor
@spec new(atom(), term(), keyword()) :: t()
def new(step, reason, opts \\ [])

# Helpers
@spec with_context(t(), map()) :: t()
@spec add_rollback_error(t(), atom(), term()) :: t()
@spec recoverable?(t()) :: boolean()  # Delegates to Recoverable protocol
```

#### Report.t() Struct

```elixir
defstruct [
  :effect_name,             # atom()
  :execution_id,            # String.t()
  :status,                  # :ok | :error | :halted
  :started_at,              # DateTime.t()
  :completed_at,            # DateTime.t()
  :total_duration_ms,       # non_neg_integer()
  :steps_completed,         # non_neg_integer()
  :steps_skipped,           # non_neg_integer()
  :error,                   # Error.t() | nil
  :halt_reason,             # term() | nil

  # Step details as simple list of maps (not nested structs)
  :steps                    # [%{name: atom(), status: atom(), duration_ms: integer(), ...}]
]

# Step entry is just a map, not a separate struct:
# %{name: :charge, status: :ok, duration_ms: 150, attempts: 2, added_keys: [:receipt]}
# %{name: :optional, status: :skipped, reason: :when_false}
# %{name: :payment, status: :rolled_back, rollback_status: :ok}
```

#### Handle.t() Struct (Async)

```elixir
defstruct [
  :execution_id,            # String.t()
  :effect_name,             # atom()
  :task_ref,                # reference() - Task reference
  :started_at,              # DateTime.t()
  :status,                  # :running | :completed | :failed | :cancelled
  :result                   # term() | nil - populated when done
]

# API
@spec await(Handle.t(), keyword()) :: {:ok, context()} | {:error, Error.t()}
@spec cancel(Handle.t()) :: :ok | {:error, :already_completed}
@spec status(Handle.t()) :: :running | :completed | :failed | :cancelled
```

---

### Creation

```elixir
@spec new(name :: atom(), opts :: keyword()) :: Effect.t()
Effect.new(:workflow_name)
Effect.new(:workflow_name,
  # ─── Observability ───
  telemetry: [:my_app, :workflow],  # Telemetry event prefix
  label: "Order Processing",         # Human-readable label
  tags: [:critical, :payment],       # Categorization tags

  # ─── Metadata (carried through execution) ───
  metadata: %{version: "1.0", team: "payments"},

  # ─── Services (simple module map) ───
  services: %{payment: StripeGateway, email: SendGrid}
)

# All options can be overridden at run time
```

### Step Building (Lazy - No Execution)

```elixir
# Basic step - takes context (and optionally services), returns one of:
#   {:ok, map}    - Continue, merge map into context
#   {:error, term} - Stop, trigger rollbacks
#   {:halt, term}  - Stop gracefully, run ensure, NO rollback

# Step function signatures:
#   1-arity: fn ctx -> result end              (no services needed)
#   2-arity: fn ctx, services -> result end    (explicit service access)

@spec step(Effect.t(), atom(), step_fun(), keyword()) :: Effect.t()
Effect.step(effect, :step_name, fn ctx -> {:ok, %{result: value}} end)
Effect.step(effect, :step_name, fn ctx, services ->
  services.payment.charge(ctx.amount)
end)
Effect.step(effect, :step_name, &module_fun/1, opts)

# Example with halt for fraud detection
Effect.step(effect, :fraud_check, fn ctx ->
  case FraudService.check(ctx.user, ctx.amount) do
    :passed -> {:ok, %{fraud_status: :passed}}
    :fraud  -> {:halt, %{reason: :fraud, user_id: ctx.user.id}}
    {:error, e} -> {:error, e}
  end
end)

# Embed - nest another effect as a single step
# The nested effect's steps are flattened into the parent DAG
# Context flows through: parent context → nested steps → merged back
@spec embed(Effect.t(), atom(), Effect.t(), keyword()) :: Effect.t()
Effect.embed(effect, :payment, PaymentFlow.build(), after: :validate)
# If PaymentFlow has [:authorize, :capture, :log], the DAG becomes:
#   validate → payment.authorize → payment.capture → payment.log → next_step
# The :payment step acts as a namespace prefix

# Parallel steps - run multiple steps concurrently
@spec parallel(Effect.t(), atom(), [{atom(), step_fun()}], keyword()) :: Effect.t()
Effect.parallel(effect, :checks, [
  {:fraud, &check_fraud/1},
  {:inventory, &check_inventory/1}
], after: :validate)

# Branch - conditional path selection
@spec branch(Effect.t(), atom(), selector_fun(), routes(), keyword()) :: Effect.t()
Effect.branch(effect, :fulfill, & &1.type, %{
  digital: DigitalFlow.build(),
  physical: PhysicalFlow.build()
}, after: :charge)

# Each - iterate over collection
@spec each(Effect.t(), atom(), collection_fun(), Effect.t(), keyword()) :: Effect.t()
Effect.each(effect, :notify_all, & &1.recipients, NotifyEffect.build(), after: :complete)

# Race - first success wins, others cancelled
@spec race(Effect.t(), atom(), [Effect.t()], keyword()) :: Effect.t()
Effect.race(effect, :fetch, [
  CacheEffect.build(),
  DatabaseEffect.build()
], after: :validate)

# Using - resource lifecycle (acquire → use → release always runs)
# Better name than "bracket" - clearer intent
@spec using(Effect.t(), atom(), keyword()) :: Effect.t()
Effect.using(effect, :db_connection,
  acquire: fn ctx -> {:ok, %{conn: Pool.checkout()}} end,
  use: fn ctx -> do_queries(ctx.conn) end,
  release: fn ctx, _result -> Pool.checkin(ctx.conn) end  # Always runs
)

# Ensure - cleanup that always runs (like try/after)
@spec ensure(Effect.t(), atom(), cleanup_fun()) :: Effect.t()
Effect.ensure(effect, :cleanup, fn ctx, result ->
  File.close(ctx.file_handle)
end)
```

### Context Helpers

```elixir
# Assign value to context
@spec assign(Effect.t(), atom(), term() | (context() -> term())) :: Effect.t()
Effect.assign(effect, :timestamp, DateTime.utc_now())
Effect.assign(effect, :config, fn ctx -> load_config(ctx.env) end)

# Transform a context key
@spec transform(Effect.t(), atom(), atom(), (term() -> result())) :: Effect.t()
Effect.transform(effect, :user, :full_name, fn user ->
  {:ok, "#{user.first} #{user.last}"}
end)

# Validate context (returns :ok or {:error, reason})
@spec validate(Effect.t(), atom(), validator_fun()) :: Effect.t()
Effect.validate(effect, :check_amount, fn ctx ->
  if ctx.amount > 0, do: :ok, else: {:error, :invalid_amount}
end)

# Require - assert condition, halt with error if false
# Unlike validate which is a step, require is a gate that doesn't advance the pipeline
@spec require(Effect.t(), atom(), condition_fun(), error_term()) :: Effect.t()
Effect.require(effect, :authorized, & &1.user.admin?, :unauthorized)
# Require is for preconditions: "this condition is required to proceed"
# They don't produce output, just validate invariants

# Tap - side effect, doesn't modify context
@spec tap(Effect.t(), atom(), side_effect_fun()) :: Effect.t()
Effect.tap(effect, :log, fn ctx -> Logger.info("Processing #{ctx.id}") end)
```

### Groups (Organization)

Groups organize related steps visually and logically:

```elixir
# Define a group of steps
@spec group(Effect.t(), atom(), (Effect.t() -> Effect.t()), keyword()) :: Effect.t()
Effect.group(effect, :validation, fn e ->
  e
  |> Effect.step(:check_user, &check_user/1)
  |> Effect.step(:check_permissions, &check_permissions/1)
  |> Effect.require(:authorized, & &1.authorized, :unauthorized)
end, after: :load)

# Groups help with:
# 1. Visualization - Steps grouped in subgraph
# 2. Scoping - Can apply options to entire group
# 3. Reusability - Group can be extracted as a function
# 4. Rollback scoping - Rollback only group's steps

# Group with options applied to all steps
Effect.group(effect, :external_calls,
  fn e ->
    e
    |> Effect.step(:fetch_user, &fetch_user/1)
    |> Effect.step(:fetch_orders, &fetch_orders/1)
  end,
  retry: [max: 3],           # Applied to all steps in group
  timeout: 5_000,            # Group-wide timeout
  circuit: [name: :external] # Shared circuit breaker
)
```

### Composition

```elixir
# Merge two effects (combine DAGs)
@spec merge(Effect.t(), Effect.t()) :: Effect.t()
Effect.merge(auth_effect, order_effect)

# Sequence multiple effects (chain in order)
@spec sequence([Effect.t()]) :: Effect.t()
Effect.sequence([validate_effect, process_effect, notify_effect])

# Prepend steps
@spec prepend(Effect.t(), Effect.t()) :: Effect.t()
Effect.prepend(main_effect, setup_effect)

# Append steps
@spec append(Effect.t(), Effect.t()) :: Effect.t()
Effect.append(main_effect, cleanup_effect)
```

### Execution (Single Entry Point)

```elixir
# Synchronous execution - returns one of:
#   {:ok, context}      - Completed successfully
#   {:error, Error.t()} - Failed, rollbacks executed
#   {:halted, term}     - Halted early via {:halt, _}, ensure ran, no rollback

@spec run(Effect.t(), context(), keyword()) ::
  {:ok, context()} | {:error, Error.t()} | {:halted, term()}
Effect.run(effect, %{order_id: 123})
Effect.run(effect, context, timeout: 30_000, telemetry: [:app, :order])

# Synchronous, raises on error
@spec run!(Effect.t(), context(), keyword()) :: context() | no_return()
Effect.run!(effect, context)

# Async execution - returns handle
@spec run_async(Effect.t(), context(), keyword()) :: {:ok, Handle.t()}
{:ok, handle} = Effect.run_async(effect, context)
Effect.await(handle)
Effect.await(handle, timeout: 60_000)
Effect.cancel(handle)
Effect.status(handle)  # :running | :completed | :failed | :cancelled
```

### Inspection & Visualization (No Execution)

```elixir
# List step names in execution order
@spec step_names(Effect.t()) :: [atom()]
Effect.step_names(effect)  #=> [:validate, :charge, :fulfill]

# Get step details
@spec step_info(Effect.t(), atom()) :: {:ok, Step.t()} | {:error, :not_found}
Effect.step_info(effect, :charge)

# Validate structure (cycles, missing deps)
@spec validate(Effect.t()) :: :ok | {:error, [Warning.t()]}
Effect.validate(effect)

# Get effect metadata
@spec name(Effect.t()) :: atom()
@spec metadata(Effect.t()) :: map()
Effect.name(effect)
Effect.metadata(effect)

# Dry run - simulate execution, log steps without side effects
@spec dry_run(Effect.t(), context()) :: {:ok, [atom()]} | {:error, term()}
Effect.dry_run(effect, context)
```

### Visualization

```elixir
# ASCII tree representation
@spec to_ascii(Effect.t(), keyword()) :: String.t()
Effect.to_ascii(effect)
# Output:
# process_order
# ├── load_order
# ├── check_status
# ├── verification (parallel)
# │   ├── fraud_check
# │   └── inventory_check
# ├── payment (group)
# │   ├── authorize
# │   ├── capture
# │   └── log_transaction
# └── mark_complete

# Mermaid diagram (for docs, GitHub, etc.)
@spec to_mermaid(Effect.t(), keyword()) :: String.t()
Effect.to_mermaid(effect)
# Output:
# graph TD
#   load_order --> check_status
#   check_status --> verification
#   subgraph verification[Verification]
#     fraud_check
#     inventory_check
#   end
#   verification --> payment
#   subgraph payment[Payment]
#     authorize --> capture --> log_transaction
#   end
#   payment --> mark_complete

# DOT format (for Graphviz)
@spec to_dot(Effect.t(), keyword()) :: String.t()
Effect.to_dot(effect)

# Inspect protocol - pretty print in IEx
iex> effect
#Effect<process_order, 8 steps, groups: [:verification, :payment]>

# Detailed inspection
@spec inspect(Effect.t(), keyword()) :: String.t()
Effect.inspect(effect, verbose: true)
# Output:
# Effect: process_order
# Steps: 8 (3 groups, 2 guards)
# Dependencies:
#   load_order -> check_status -> verification -> payment -> mark_complete
# Rollbacks: 3 steps with rollback handlers
# Services required: [PaymentGateway, FraudService]
```

### Middleware (Cross-Cutting Concerns)

Middleware wraps every step execution, similar to Plug/Req:

```elixir
# Middleware signature: fn step_name, context, next_fn -> result
@spec middleware(Effect.t(), middleware_fun()) :: Effect.t()

# Timing middleware
Effect.middleware(effect, fn step, ctx, next ->
  start = System.monotonic_time(:millisecond)
  result = next.()
  duration = System.monotonic_time(:millisecond) - start
  Logger.debug("[#{step}] completed in #{duration}ms")
  result
end)

# Auth middleware - check auth before each step
Effect.middleware(effect, fn step, ctx, next ->
  if authorized?(ctx.user, step) do
    next.()
  else
    {:error, :unauthorized}
  end
end)

# Tracing middleware
Effect.middleware(effect, fn step, ctx, next ->
  span = Tracer.start_span(step)
  try do
    result = next.()
    Tracer.set_status(span, :ok)
    result
  rescue
    e ->
      Tracer.set_status(span, :error)
      reraise e, __STACKTRACE__
  after
    Tracer.end_span(span)
  end
end)

# Multiple middleware (executed in order, like onion layers)
Effect.new(:order)
|> Effect.middleware(&timing_middleware/3)
|> Effect.middleware(&auth_middleware/3)
|> Effect.middleware(&tracing_middleware/3)
|> Effect.step(:process, &process/1)
# Execution: tracing → auth → timing → process → timing → auth → tracing
```

#### Idempotency Pattern

Effect doesn't have built-in idempotency, but it's easy to add via middleware:

```elixir
# Simple idempotency middleware
def idempotency_middleware(store \\ IdempotencyStore) do
  fn step, ctx, next ->
    # Only apply to steps marked as idempotent
    step_opts = Effect.step_opts(ctx, step)

    case step_opts[:idempotency_key] do
      nil ->
        next.()  # No idempotency for this step

      key_fn when is_function(key_fn) ->
        key = "#{ctx.__effect__}:#{step}:#{key_fn.(ctx)}"

        case store.get(key) do
          {:ok, cached_result} ->
            cached_result
          :not_found ->
            result = next.()
            if match?({:ok, _}, result), do: store.put(key, result, ttl: :timer.hours(24))
            result
        end
    end
  end
end

# Usage
Effect.new(:payment)
|> Effect.middleware(idempotency_middleware())
|> Effect.step(:charge, &charge/1,
    idempotency_key: & "#{&1.user_id}:#{&1.order_id}"  # Custom key
  )
|> Effect.step(:notify, &notify/1)  # No idempotency key = not idempotent
```

This pattern:
- Opt-in per step via `idempotency_key:` option
- Key is derived from context (user-controlled)
- Only caches successful results
- TTL prevents unbounded growth

### Checkpoint (Pause/Resume)

For long-running workflows that need persistence:

```elixir
@spec checkpoint(Effect.t(), atom(), keyword()) :: Effect.t()

# Add checkpoint after critical step
Effect.new(:order)
|> Effect.step(:payment, &charge/1)
|> Effect.checkpoint(:after_payment,
    store: &Checkpoints.save/2,  # Persistence callback
    load: &Checkpoints.load/1    # Recovery callback
  )
|> Effect.step(:fulfillment, &fulfill/1)

# On failure after checkpoint, can resume:
{:ok, ctx} = Effect.resume(effect, :after_payment, execution_id)

# Checkpoint stores:
# - Current context state
# - Completed steps
# - Execution metadata (timestamps, attempt counts)
```

### Hooks

```elixir
# Global hooks (run for every step)
@spec on_start(Effect.t(), hook_fun()) :: Effect.t()
@spec on_complete(Effect.t(), hook_fun()) :: Effect.t()
@spec on_error(Effect.t(), hook_fun()) :: Effect.t()
@spec on_rollback(Effect.t(), hook_fun()) :: Effect.t()

Effect.on_start(effect, fn step, ctx -> Logger.debug("Starting #{step}") end)
Effect.on_error(effect, fn step, error, ctx -> Sentry.capture(error) end)
```

---

## Step Options (Complete Reference)

```elixir
Effect.step(:name, fun,
  # ─── Dependencies ───
  after: :previous,            # Run after step (or list)

  # ─── Timing ───
  timeout: 5_000,              # Per-attempt timeout (ms)

  # ─── Retry (Recoverable-aware) ───
  retry: [
    max: 3,                    # Max attempts
    delay: 100,                # Initial delay
    backoff: :exponential,     # :fixed | :linear | :exponential | :decorrelated_jitter
    max_delay: 30_000,         # Cap
    jitter: 0.1,               # Randomness 0.0-1.0
    when: &Recoverable.recoverable?/1  # Only retry when predicate returns true
  ],

  # ─── Conditional ───
  when: fn ctx -> ctx.enabled end,   # Skip step when condition is false

  # ─── Error Handling ───
  catch: fn error, ctx -> {:ok, fallback} | {:error, e} end,
  fallback: default_value,
  fallback_when: [:not_found, :timeout],

  # ─── Saga / Rollback ───
  rollback: fn ctx -> :ok end,
  compensate: fn ctx, error -> :ok end,

  # ─── Circuit Breaker ───
  circuit: [
    name: :external_api,         # Circuit name (shared across calls)
    threshold: 5,                # Failures before opening
    reset_timeout: 30_000,       # Time before half-open
    trips_on: &Recoverable.trips_circuit?/1  # Which errors trip
  ],

  # ─── Rate Limiting ───
  rate_limit: [
    name: :api_calls,            # Rate limiter name
    limit: 100,                  # Max calls
    window: :timer.seconds(60),  # Per time window
    on_exceeded: :queue          # :queue | :drop | :error
  ],

  # ─── Telemetry / Tracing ───
  telemetry: [:my_app, :step],
  trace: true,                   # OpenTelemetry span
  redact: [:password, :token],

  # ─── Step Metadata ───
  meta: %{
    description: "Charges the customer credit card",
    owner: "payments-team",
    sla_ms: 5000,
    idempotent: true,
    external: true               # Marks as external call for monitoring
  }
)
```

### Timeout Semantics

```elixir
# Step timeout - per ATTEMPT (resets on retry)
Effect.step(:api_call, &call/1,
  timeout: 5_000,     # 5s per attempt
  retry: [max: 3]     # Each retry gets fresh 5s
)

# Effect total timeout - in run options
Effect.run(effect, ctx,
  timeout: 60_000     # 60s total for entire effect execution
)

# Both can be combined
Effect.step(:slow, &slow/1, timeout: 10_000)  # 10s per attempt
Effect.run(effect, ctx, timeout: 30_000)       # 30s total

# Timeout behavior:
# - Step timeout: raises, triggers retry if configured, else fails
# - Effect timeout: stops execution, triggers rollback of completed steps
```

---

## Semantic Clarifications

### Parallel Execution Semantics

When steps run in parallel via `parallel/4`:

1. **Failure Handling** (configurable via `on_error:` option):
   - `:fail_fast` (default) - Cancel running siblings immediately, trigger rollback
   - `:collect_all` - Wait for all to complete, collect all errors
   - `:continue` - Continue with successful results, log failures

2. **Cancellation**: Running steps receive a cancellation signal. Steps should
   check `Effect.cancelled?()` periodically for long operations.

3. **Result Merging**: Results from parallel steps are merged left-to-right
   by declaration order. Last writer wins for duplicate keys.

```elixir
Effect.parallel(effect, :checks, [
  {:a, fn _ -> {:ok, %{x: 1}} end},
  {:b, fn _ -> {:ok, %{x: 2, y: 3}} end}  # x: 2 wins
], on_error: :fail_fast)
```

### Context Model

Context is an immutable map that flows through steps:

1. **Isolation**: Each step receives a snapshot of the current context
2. **Accumulation**: Step results (`{:ok, map}`) are merged into context
3. **Parallel Snapshots**: Parallel steps all receive the same pre-parallel snapshot
4. **Merge Strategy**:
   - Sequential: Direct merge
   - Parallel: Merge in declaration order (last wins on conflict)
   - Nested effects: Merged into parent under the embed name namespace

```elixir
# Parallel merge example
# Pre-parallel context: %{a: 1}
# Step :x returns: %{b: 2, c: 3}
# Step :y returns: %{c: 4, d: 5}
# Post-parallel context: %{a: 1, b: 2, c: 4, d: 5}  # :y's c: 4 wins
```

### Conditional Execution (`when:`)

When a step's `when:` condition returns false:

1. **Step is skipped** - function not called, no result
2. **Dependents still run** - unless they also have false `when:` conditions
3. **Context unchanged** - skipped step adds nothing to context
4. **No rollback** - skipped steps have no rollback to execute
5. **Reported as skipped** - appears in Report with `status: :skipped`

```elixir
Effect.new(:example)
|> Effect.step(:a, &a/1)
|> Effect.step(:b, &b/1, when: fn ctx -> ctx.feature_enabled end)
|> Effect.step(:c, &c/1, after: :b)  # Runs even if :b skipped
```

### Resource Management (`using/4`)

`using/4` provides acquire/use/release semantics:

1. **Scope**: Wraps a single logical operation (not the whole effect)
2. **DAG Integration**: Acts as a single step in the DAG
3. **Release Guarantee**: `release` ALWAYS runs, even on error/halt
4. **Context Flow**: `acquire` adds to context, `use` can modify, `release` receives final

```elixir
# using is ONE step in the DAG
Effect.new(:example)
|> Effect.step(:prepare, &prepare/1)
|> Effect.using(:with_connection,        # This is step :with_connection
    acquire: fn ctx -> {:ok, %{conn: Pool.get()}} end,
    use: fn ctx -> do_work(ctx.conn) end,
    release: fn ctx, _result -> Pool.release(ctx.conn) end
  )
|> Effect.step(:finalize, &finalize/1)   # Runs after :with_connection
```

### Rollback Execution Order

Rollbacks execute in **reverse completion order**:

1. **Sequential**: Exact reverse of execution order
2. **Parallel**: Parallel steps' rollbacks run in parallel
3. **Nested Effects**: Nested rollbacks run before parent's rollback
4. **Failure Isolation**: One rollback failure doesn't stop others

```
Execution:  A → [B, C] (parallel) → D → E (fails)
Rollback:   D.rollback → [C.rollback, B.rollback] (parallel) → A.rollback
```

### Cancellation Behavior

```elixir
# Cancel an async effect
{:ok, handle} = Effect.run_async(effect, ctx)
:ok = Effect.cancel(handle)

# What happens on cancel:
# 1. Cancelled flag is set
# 2. Current running step completes (not interrupted mid-operation)
# 3. No further steps execute
# 4. `ensure` functions still run (cleanup)
# 5. NO rollback (cancellation is not an error)
# 6. Returns {:cancelled, partial_context}

# To check if cancelled (for long-running steps):
Effect.step(:long_task, fn ctx ->
  Enum.reduce_while(items, {:ok, %{}}, fn item, acc ->
    if Effect.cancelled?() do
      {:halt, {:ok, acc}}  # Stop gracefully
    else
      {:cont, process(item)}
    end
  end)
end)

# For graceful stop WITH rollback, return error:
Effect.step(:check, fn ctx ->
  if should_abort?(ctx), do: {:error, :aborted}, else: {:ok, %{}}
end)
```

---

## Recoverable Protocol Integration

Effect uses `FnTypes.Recoverable` for intelligent error handling:

```elixir
# Automatic retry based on error type
Effect.step(:api_call, &call_api/1,
  retry: [
    max: 5,
    when: &Recoverable.recoverable?/1,  # Only retry recoverable errors
    delay: fn error, attempt ->
      Recoverable.retry_delay(error, attempt)  # Error-specific delay
    end
  ]
)

# Automatic fallback from protocol
Effect.step(:fetch, &fetch/1,
  fallback: fn error ->
    case Recoverable.fallback(error) do
      {:ok, value} -> value
      nil -> raise error
    end
  end
)

# Circuit breaker integration
Effect.step(:external, &call_external/1,
  circuit: [
    name: :external_service,
    trips_on: &Recoverable.trips_circuit?/1  # Use protocol
  ]
)
```

---

## Saga Pattern (Rollback/Compensation)

```elixir
# Simple rollback
Effect.new(:order)
|> Effect.step(:reserve, &reserve/1, rollback: &release/1)
|> Effect.step(:charge, &charge/1, rollback: &refund/1)
|> Effect.step(:ship, &ship/1)
|> Effect.run(ctx)  # Auto-rollback on failure

# Compensation with error context
Effect.step(:charge, &charge/1,
  compensate: fn ctx, error ->
    # Can inspect the error that caused rollback
    case error do
      %{tag: :inventory_failed} -> partial_refund(ctx)
      _ -> full_refund(ctx)
    end
  end
)

# Rollback scope control
Effect.step(:nested, nested_effect,
  rollback: :all,        # Rollback all nested steps
  # or
  rollback: :completed,  # Only rollback completed nested steps
  # or
  rollback: :none        # Don't rollback nested (they handle own)
)
```

---

## Edge Cases & Behavior

| Scenario | Behavior |
|----------|----------|
| Empty effect (no steps) | `run/2` returns `{:ok, input_context}` immediately |
| Duplicate step names | `Effect.validate/1` returns `{:error, {:duplicate_step, name}}` |
| Circular embedded effects | Detected at build time, raises `Effect.CircularDependencyError` |
| `each` with empty collection | Returns `{:ok, %{step_name: []}}`, no iterations |
| `race` where all fail | Returns `{:error, %{failures: [...]}}` with all errors |
| `branch` no matching route | Returns `{:error, {:no_matching_branch, selector_result}}` or uses `:default` route |
| Rollback that fails | Error collected in `Error.rollback_errors`, continues other rollbacks |
| Timeout during rollback | Rollback killed, error logged, continues other rollbacks |
| Checkpoint save fails | Returns `{:error, {:checkpoint_failed, reason}}`, no rollback |
| Step returns invalid | Returns `{:error, {:invalid_step_return, step, value}}` |
| `nil` returned from step | Treated as `{:ok, %{}}` (empty merge) |

### Branch Default Route

```elixir
Effect.branch(effect, :type, & &1.kind, %{
  a: EffectA.build(),
  b: EffectB.build(),
  default: FallbackEffect.build()  # Special :default key
})
```

---

## Run Options

```elixir
Effect.run(effect, context,
  # ─── Execution ───
  timeout: 60_000,           # Total timeout
  async: false,              # Return handle for async

  # ─── Overrides (merge with Effect.new settings) ───
  metadata: %{trace_id: "abc"},  # Merged with build-time metadata
  services: %{payment: MockPayment},  # Overrides build-time services
  tags: [:test],                 # Appended to build-time tags

  # ─── Error Handling ───
  on_error: :fail_fast,      # :fail_fast | :collect_all
  normalize_errors: true,    # Use Normalizable protocol

  # ─── Observability ───
  telemetry: [:my_app, :effects],  # Overrides build-time
  trace: true,               # Capture execution trace
  report: true,              # Return {result, Report.t()}

  # ─── Testing ───
  mocks: %{step_name: fn ctx -> {:ok, %{}} end},
  dry_run: false
)

# Override behavior:
# - metadata: deep merge (run-time wins on conflict)
# - services: shallow merge (run-time wins on conflict)
# - tags: append (build-time ++ run-time)
# - other options: run-time overrides build-time
```

### Debug Options

Simple debugging for development:

```elixir
# Debug mode - logs every step with timing
Effect.run(effect, ctx, debug: true)
# Output:
# [Effect :order] Step :load_order completed in 5ms, added: [:order, :items]
# [Effect :order] Step :validate completed in 1ms
# [Effect :order] Step :charge completed in 150ms (2 attempts)

# Execution trace - capture events for inspection
{:ok, ctx, trace} = Effect.run(effect, ctx, trace: true)

trace.events
#=> [
#     %{step: :load_order, status: :ok, duration_ms: 5, added_keys: [:order, :items]},
#     %{step: :validate, status: :ok, duration_ms: 1},
#     %{step: :optional, status: :skipped, reason: :when_false},
#     %{step: :charge, status: :ok, duration_ms: 150, attempts: 2},
#     ...
#   ]

trace.total_duration_ms  #=> 200
trace.steps_completed    #=> 5
trace.steps_skipped      #=> 1
```

For complex debugging needs, use standard Elixir tools (IEx, :debugger, Observer).

---

## Performance Model

Effect is designed for **zero-cost abstractions** during build phase:

### Build Phase (Pure, Fast)
- All operations (`new`, `step`, `embed`, etc.) are pure data transformations
- No I/O, no side effects, no process spawning
- O(1) for most operations (list prepend, map put)
- DAG construction deferred until first `run` or explicit `validate`

### Run Phase (Execution)
- DAG sorted once per execution (cached if effect reused)
- Parallel steps use `Task.async_stream` with configurable max_concurrency
- Context passed by reference (no deep copying)
- Middleware overhead: ~1μs per layer per step

### Memory Model
- Effect struct: ~500 bytes base + ~200 bytes per step
- Context: user-controlled (Effect doesn't copy)
- Step results: merged (not accumulated as list)

### Benchmarks (Required)

```elixir
# Build phase benchmarks (target: < 1μs per operation)
Effect.new(:test)                           # < 500ns
|> Effect.step(:a, &identity/1)             # < 1μs per step
|> Effect.parallel(:p, [...])               # < 2μs
|> Effect.embed(:e, other)                  # < 1μs

# Run phase benchmarks (10 steps, no I/O)
Effect.run(effect, ctx)                     # < 100μs overhead
Effect.run(effect, ctx, report: true)       # < 150μs overhead
```

---

## Telemetry Events

Effect emits the following telemetry events (prefix configurable):

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:effect, :start]` | `system_time` | `effect, execution_id, context_keys` |
| `[:effect, :stop]` | `duration` | `effect, execution_id, status, step_count` |
| `[:effect, :exception]` | `duration` | `effect, execution_id, kind, reason, stacktrace` |
| `[:effect, :step, :start]` | `system_time` | `effect, step, attempt` |
| `[:effect, :step, :stop]` | `duration` | `effect, step, status, attempt` |
| `[:effect, :step, :exception]` | `duration` | `effect, step, kind, reason` |
| `[:effect, :step, :retry]` | `delay_ms` | `effect, step, attempt, reason` |
| `[:effect, :rollback, :start]` | `system_time` | `effect, step` |
| `[:effect, :rollback, :stop]` | `duration` | `effect, step, status` |
| `[:effect, :checkpoint, :save]` | `duration` | `effect, checkpoint, execution_id` |
| `[:effect, :checkpoint, :load]` | `duration` | `effect, checkpoint, execution_id` |

Custom prefix example:
```elixir
Effect.new(:order, telemetry: [:myapp, :orders])
# Events: [:myapp, :orders, :start], [:myapp, :orders, :step, :start], etc.
```

---

## Validation Rules

`Effect.validate/1` validates effect structure, returns `:ok` or `{:error, reason}`.

**Checks performed:**

1. **DAG Validity**
   - No cycles in step dependencies
   - All `after:` references exist

2. **Step Names**
   - All names are atoms
   - No duplicates (including across embedded effects)

3. **Type Consistency**
   - Step functions have correct arity (1 or 2)
   - Options have valid types

4. **Resource Safety**
   - All `using` blocks have `release` functions
   - No `ensure` references non-existent steps

5. **Branch Completeness** (optional, via `validate(effect, strict: true)`)
   - All branches have `:default` route
   - Embedded effects are also valid

```elixir
case Effect.validate(effect) do
  :ok -> :proceed
  {:error, {:cycle_detected, path}} -> ...
  {:error, {:duplicate_step, name}} -> ...
  {:error, {:missing_dependency, step, dep}} -> ...
  {:error, {:invalid_step_return_type, step}} -> ...
end
```

---

## Implementation Phases

### Phase 1: Core (P0) - Foundation

**Files to create:**
- `libs/effect/lib/effect.ex` - Main module, delegating facade
- `libs/effect/lib/effect/builder.ex` - Effect struct, step accumulation
- `libs/effect/lib/effect/step.ex` - Step struct, options parsing
- `libs/effect/lib/effect/runtime.ex` - Execution engine
- `libs/effect/lib/effect/context.ex` - Context management
- `libs/effect/lib/effect/middleware.ex` - Middleware chain
- `libs/effect/lib/effect/checkpoint.ex` - Checkpoint persistence

**Features:**
- [ ] Effect struct with steps list, metadata
- [ ] `new/2`, `step/4` - lazy step accumulation
- [ ] `run/3` - sequential execution
- [ ] Context accumulation (merge step results)
- [ ] Return handling: `{:ok, map}`, `{:error, term}`, `{:halt, term}`
- [ ] `after:` dependencies (linear chain)
- [ ] `middleware/2` - wrap step execution (onion model)
- [ ] `checkpoint/3` - persist state, enable resume
- [ ] `resume/3` - resume from checkpoint
- [ ] `services:` option - simple module map for DI
- [ ] `metadata:`, `label:`, `tags:` options
- [ ] Telemetry integration (start/stop events)

### Phase 2: Resilience (P0) - Error Recovery

**Files to create:**
- `libs/effect/lib/effect/retry.ex` - Retry logic with backoff
- `libs/effect/lib/effect/saga.ex` - Rollback orchestration
- `libs/effect/lib/effect/circuit.ex` - Circuit breaker
- `libs/effect/lib/effect/rate_limit.ex` - Rate limiting

**Features:**
- [ ] `retry:` option with all backoff strategies
- [ ] Recoverable protocol integration
- [ ] `rollback:` option per step
- [ ] `compensate:` with error context
- [ ] Reverse-order rollback execution
- [ ] Rollback error collection
- [ ] `circuit:` - circuit breaker per step/shared
- [ ] `rate_limit:` - rate limiting per step/shared

### Phase 3: Control Flow (P0) - DAG Execution

**Files to create:**
- `libs/effect/lib/effect/dag.ex` - DAG construction using `libs/dag`
- `libs/effect/lib/effect/parallel.ex` - Concurrent execution
- `libs/effect/lib/effect/branch.ex` - Conditional routing

**Features:**
- [ ] DAG validation (cycles, missing deps)
- [ ] Topological sort for execution order
- [ ] `parallel/4` - concurrent step groups
- [ ] `branch/5` - conditional paths
- [ ] `embed/4` - nested effects (was `steps`)
- [ ] `when:` conditional execution

### Phase 4: Advanced (P1)

**Files to create:**
- `libs/effect/lib/effect/each.ex` - Iteration
- `libs/effect/lib/effect/race.ex` - First-success
- `libs/effect/lib/effect/using.ex` - Resource management
- `libs/effect/lib/effect/timeout.ex` - Timeout handling

**Features:**
- [ ] `each/5` - iterate over collection
- [ ] `race/4` - first successful wins
- [ ] `using/4` - acquire/use/release
- [ ] Timeout per step and total
- [ ] `catch:`/`fallback:` error handling
- [ ] Async execution with handles

### Phase 5: Observability (P1)

**Files to create:**
- `libs/effect/lib/effect/report.ex` - Execution report
- `libs/effect/lib/effect/visualization.ex` - ASCII/Mermaid
- `libs/effect/lib/effect/error.ex` - Structured errors
- `libs/effect/lib/effect/telemetry.ex` - Telemetry + OpenTelemetry

**Features:**
- [ ] Execution report with timing, steps, errors
- [ ] `to_mermaid/2`, `to_ascii/2` using DAG lib
- [ ] `dry_run/2` - simulate without execution
- [ ] Structured Effect.Error type
- [ ] Rich telemetry events
- [ ] OpenTelemetry integration (`trace: true` option)
- [ ] Span creation, context propagation
- [ ] Attributes: step name, duration, status, error

### Phase 6: Testing & Polish (P1)

**Files to create:**
- `libs/effect/lib/effect/testing.ex` - Test utilities

**Features:**
- [ ] `mocks:` option in run
- [ ] Test assertions (assert_effect_ok, etc.)
- [ ] Step mocking utilities
- [ ] Inspect protocol implementation
- [ ] Documentation and examples

---

## File Structure

```
libs/effect/
├── mix.exs
├── lib/
│   ├── effect.ex                 # Main facade
│   └── effect/
│       ├── builder.ex            # Effect struct, accumulation
│       ├── step.ex               # Step struct, options
│       ├── runtime.ex            # Execution engine
│       ├── context.ex            # Context management
│       ├── middleware.ex         # Middleware chain (P1)
│       ├── checkpoint.ex         # Checkpoint/resume (P1)
│       ├── dag.ex                # DAG using libs/dag
│       ├── retry.ex              # Retry with Recoverable
│       ├── saga.ex               # Rollback orchestration
│       ├── circuit.ex            # Circuit breaker
│       ├── rate_limit.ex         # Rate limiting
│       ├── telemetry.ex          # Telemetry + OpenTelemetry
│       ├── parallel.ex           # Concurrent execution
│       ├── branch.ex             # Conditional routing
│       ├── each.ex               # Iteration
│       ├── race.ex               # First-success
│       ├── using.ex              # Resource management
│       ├── timeout.ex            # Timeout handling
│       ├── error.ex              # Structured errors
│       ├── report.ex             # Execution report
│       ├── visualization.ex      # ASCII/Mermaid
│       └── testing.ex            # Test utilities
└── test/
    ├── effect_test.exs
    └── effect/
        ├── runtime_test.exs
        ├── retry_test.exs
        ├── saga_test.exs
        ├── middleware_test.exs
        ├── checkpoint_test.exs
        └── ...
```

---

## Thorough Example: E-Commerce Order with Nested Effects

This example demonstrates:
- Nested effects (`steps`)
- Parallel execution
- Branching
- Saga rollback
- Resource management (`using`)
- Iteration (`each`)
- Error handling
- Recoverable integration

### Nested Effect: Payment Processing

```elixir
defmodule Payments.ProcessPayment do
  @moduledoc "Nested effect for payment processing"
  alias FnTypes.Effect
  alias FnTypes.Recoverable

  def build do
    Effect.new(:process_payment)

    # Authorize the payment (2-arity: ctx, services)
    |> Effect.step(:authorize, fn ctx, services ->
        case services.payment.authorize(ctx.card, ctx.amount) do
          {:ok, auth} -> {:ok, %{auth_id: auth.id, auth: auth}}
          {:error, reason} -> {:error, reason}
        end
      end,
      retry: [
        max: 3,
        backoff: :exponential,
        delay: 500,
        when: &Recoverable.recoverable?/1
      ],
      rollback: fn ctx ->
        # Void authorization if capture fails
        PaymentGateway.void(ctx.auth_id)
      end
    )

    # Capture the payment
    |> Effect.step(:capture, fn ctx ->
        case PaymentGateway.capture(ctx.auth_id, ctx.amount) do
          {:ok, capture} -> {:ok, %{capture_id: capture.id, receipt: capture.receipt}}
          {:error, reason} -> {:error, reason}
        end
      end,
      after: :authorize,
      timeout: 10_000,
      compensate: fn ctx, error ->
        # Refund on downstream failure
        Logger.warn("Refunding due to: #{inspect(error)}")
        PaymentGateway.refund(ctx.capture_id, ctx.amount)
      end
    )

    # Record transaction
    |> Effect.tap(:log_transaction, fn ctx ->
        TransactionLog.record(ctx.capture_id, ctx.amount, ctx.user_id)
      end,
      after: :capture
    )
  end
end
```

### Nested Effect: Digital Delivery

```elixir
defmodule Fulfillment.DigitalDelivery do
  @moduledoc "Nested effect for digital product delivery"
  alias FnTypes.Effect

  def build do
    Effect.new(:digital_delivery)

    # Generate download link
    |> Effect.step(:generate_link, fn ctx ->
        link = Downloads.create_link(ctx.product_id, ctx.user_id, expires_in: :timer.hours(72))
        {:ok, %{download_url: link.url, download_id: link.id}}
      end,
      rollback: fn ctx ->
        Downloads.revoke_link(ctx.download_id)
      end
    )

    # Send email with download link
    |> Effect.step(:send_email, fn ctx ->
        Mailer.send_download_email(ctx.user_email, ctx.download_url, ctx.product_name)
      end,
      after: :generate_link,
      retry: [max: 2, delay: 1000]
    )

    # Grant access in user account
    |> Effect.step(:grant_access, fn ctx ->
        UserLibrary.grant_access(ctx.user_id, ctx.product_id)
      end,
      after: :generate_link,  # Parallel with send_email
      rollback: fn ctx ->
        UserLibrary.revoke_access(ctx.user_id, ctx.product_id)
      end
    )
  end
end
```

### Nested Effect: Physical Shipping

```elixir
defmodule Fulfillment.PhysicalShipping do
  @moduledoc "Nested effect for physical product shipping"
  alias FnTypes.Effect

  def build do
    Effect.new(:physical_shipping)

    # Reserve from warehouse
    |> Effect.step(:reserve_stock, fn ctx ->
        case Warehouse.reserve(ctx.product_id, ctx.quantity, ctx.warehouse_id) do
          {:ok, reservation} -> {:ok, %{reservation_id: reservation.id}}
          {:error, :out_of_stock} -> {:error, :out_of_stock}
        end
      end,
      rollback: fn ctx ->
        Warehouse.release_reservation(ctx.reservation_id)
      end
    )

    # Create shipping label
    |> Effect.step(:create_label, fn ctx ->
        label = ShippingCarrier.create_label(
          from: ctx.warehouse_address,
          to: ctx.shipping_address,
          weight: ctx.package_weight
        )
        {:ok, %{tracking_number: label.tracking, label_url: label.pdf_url}}
      end,
      after: :reserve_stock,
      retry: [max: 3, backoff: :exponential]
    )

    # Queue for picking
    |> Effect.step(:queue_picking, fn ctx ->
        PickingQueue.add(ctx.reservation_id, ctx.tracking_number, priority: ctx.priority)
      end,
      after: :create_label
    )
  end
end
```

### Nested Effect: Notification

```elixir
defmodule Notifications.OrderNotification do
  @moduledoc "Send a single notification"
  alias FnTypes.Effect

  def build do
    Effect.new(:send_notification)
    |> Effect.step(:send, fn ctx ->
        case ctx.channel do
          :email -> Mailer.send(ctx.recipient, ctx.template, ctx.data)
          :sms -> SMS.send(ctx.phone, ctx.message)
          :push -> Push.send(ctx.device_token, ctx.title, ctx.body)
        end
      end,
      retry: [max: 2],
      catch: fn _error, ctx ->
        # Don't fail order for notification failure
        {:ok, %{notification_failed: true, channel: ctx.channel}}
      end
    )
  end
end
```

### Main Effect: Complete Order Processing

```elixir
defmodule Orders.ProcessOrder do
  @moduledoc """
  Complete order processing with nested effects.

  Flow:
  1. Validate order
  2. Check fraud & inventory (parallel)
  3. Process payment (nested effect)
  4. Branch: Digital or Physical fulfillment (nested effects)
  5. Notify all recipients (iteration with nested effect)
  6. Complete order

  Rollback: If any step fails, previous steps rollback in reverse order
  """
  alias FnTypes.Effect
  alias FnTypes.Recoverable

  def build do
    Effect.new(:process_order, telemetry: [:orders, :process])

    # ─── Validation ───
    |> Effect.step(:load_order, fn ctx ->
        case Orders.get_with_items(ctx.order_id) do
          nil -> {:error, :order_not_found}
          order -> {:ok, %{order: order, items: order.items, user: order.user}}
        end
      end
    )

    |> Effect.validate(:check_status, fn ctx ->
        if ctx.order.status == :pending, do: :ok, else: {:error, :already_processed}
      end
    )

    |> Effect.require(:has_items, & length(&1.items) > 0, :empty_order)

    # ─── Parallel Checks ───
    |> Effect.parallel(:verification, [
        {:fraud_check, fn ctx ->
          FraudService.check(ctx.user, ctx.order.total)
        end, timeout: 5_000, fallback: %{fraud_status: :pending_review}},

        {:inventory_check, fn ctx ->
          Inventory.check_availability(ctx.items)
        end}
      ],
      after: :check_status
    )

    |> Effect.require(:fraud_ok,
      fn ctx -> ctx.fraud_status in [:passed, :pending_review] end,
      :fraud_rejected
    )

    |> Effect.require(:inventory_ok,
      fn ctx -> ctx.inventory_available end,
      :out_of_stock
    )

    # ─── Payment Processing (Nested Effect) ───
    |> Effect.embed(:payment, Payments.ProcessPayment.build(),
      after: :inventory_ok,
      # Pass only needed context to nested effect
      context: fn ctx -> %{
        card: ctx.order.payment_method,
        amount: ctx.order.total,
        user_id: ctx.user.id
      } end,
      # Rollback entire payment on downstream failure
      rollback: :all
    )

    # ─── Fulfillment Branching ───
    |> Effect.branch(:fulfillment,
      fn ctx ->
        # Determine fulfillment type from first item
        # (In real app, might split order by fulfillment type)
        hd(ctx.items).type
      end,
      %{
        digital: Fulfillment.DigitalDelivery.build(),
        physical: Fulfillment.PhysicalShipping.build()
      },
      after: :payment,
      # Pass relevant context
      context: fn ctx -> %{
        product_id: hd(ctx.items).product_id,
        product_name: hd(ctx.items).name,
        user_id: ctx.user.id,
        user_email: ctx.user.email,
        quantity: hd(ctx.items).quantity,
        warehouse_id: ctx.order.warehouse_id,
        shipping_address: ctx.order.shipping_address
      } end,
      # Rollback completed fulfillment steps
      rollback: :completed
    )

    # ─── Notifications (Iterate with Nested Effect) ───
    |> Effect.assign(:recipients, fn ctx ->
        [
          %{channel: :email, recipient: ctx.user.email, template: :order_confirmation, data: ctx},
          %{channel: :push, device_token: ctx.user.device_token, title: "Order Confirmed", body: "Your order is on the way!"}
        ] ++ admin_notifications(ctx)
      end
    )

    |> Effect.each(:notify_all, & &1.recipients, Notifications.OrderNotification.build(),
      after: :fulfillment,
      # Continue even if some notifications fail
      on_item_error: :continue,
      max_concurrency: 5
    )

    # ─── Finalization ───
    |> Effect.step(:mark_complete, fn ctx ->
        Orders.update_status(ctx.order_id, :completed, %{
          tracking: ctx[:tracking_number],
          download_url: ctx[:download_url],
          receipt: ctx.receipt
        })
      end,
      after: :notify_all
    )

    # ─── Resource Cleanup (Using) ───
    |> Effect.using(:with_lock,
      acquire: fn ctx ->
        case Lock.acquire("order:#{ctx.order_id}", timeout: 30_000) do
          {:ok, lock} -> {:ok, %{lock: lock}}
          {:error, :locked} -> {:error, :order_locked}
        end
      end,
      use: fn ctx ->
        # All steps above run with lock held
        {:ok, ctx}
      end,
      release: fn ctx, _result ->
        # Always release lock, even on failure
        Lock.release(ctx.lock)
      end
    )

    # ─── Global Hooks ───
    |> Effect.on_error(fn step, error, ctx ->
        Logger.error("Order #{ctx.order_id} failed at #{step}: #{inspect(error)}")
        Metrics.increment("orders.failed", tags: [step: step])
      end)

    |> Effect.on_rollback(fn step, ctx ->
        Logger.info("Rolling back #{step} for order #{ctx.order_id}")
        AuditLog.record(:rollback, ctx.order_id, step)
      end)
  end

  def run(order_id, opts \\ []) do
    build()
    |> Effect.run(%{order_id: order_id}, Keyword.merge([
        timeout: 60_000,
        telemetry: [:orders, :process],
        trace: true
      ], opts))
  end

  defp admin_notifications(ctx) do
    if ctx.order.total > 10_000 do
      [%{channel: :email, recipient: "admin@example.com", template: :high_value_order, data: ctx}]
    else
      []
    end
  end
end
```

### Usage

```elixir
# Basic usage
{:ok, result} = Orders.ProcessOrder.run(order_id)

# With options
{:ok, result} = Orders.ProcessOrder.run(order_id,
  timeout: 120_000,
  mocks: %{
    fraud_check: fn _ctx -> {:ok, %{fraud_status: :passed}} end
  }
)

# Get execution report
{:ok, result, report} = Orders.ProcessOrder.build()
|> Effect.run(%{order_id: order_id}, report: true)

IO.puts(report.total_duration_ms)
IO.inspect(report.steps_completed)
IO.inspect(report.timing)  # %{load_order: 5, verification: 120, payment: 450, ...}

# Visualize the effect
Orders.ProcessOrder.build()
|> Effect.to_mermaid()
|> IO.puts()

# Output:
# graph TD
#   load_order --> check_status
#   check_status --> verification
#   verification --> fraud_ok
#   fraud_ok --> inventory_ok
#   inventory_ok --> payment
#   payment --> fulfillment
#   fulfillment --> notify_all
#   notify_all --> mark_complete
#   subgraph payment[Payment]
#     authorize --> capture --> log_transaction
#   end
#   subgraph fulfillment[Fulfillment]
#     subgraph digital[Digital]
#       generate_link --> send_email
#       generate_link --> grant_access
#     end
#   end
```

### Execution Flow (on success)

```
1. load_order          - Load order from DB
2. check_status        - Validate order status
3. has_items           - Require: items exist
4. verification        - PARALLEL:
   ├─ fraud_check      - Check fraud score (5s timeout)
   └─ inventory_check  - Check stock levels
5. fraud_ok            - Require: fraud check passed
6. inventory_ok        - Require: inventory available
7. payment             - EMBEDDED EFFECT:
   ├─ authorize        - Authorize card
   ├─ capture          - Capture payment
   └─ log_transaction  - Record transaction
8. fulfillment         - BRANCH on item type:
   ├─ (digital)        - NESTED:
   │  ├─ generate_link - Create download URL
   │  ├─ send_email    - Email download link
   │  └─ grant_access  - Add to user library
   └─ (physical)       - NESTED:
      ├─ reserve_stock - Reserve inventory
      ├─ create_label  - Generate shipping label
      └─ queue_picking - Queue for warehouse
9. recipients          - Build notification list
10. notify_all         - EACH recipient:
    └─ send            - Send notification (email/sms/push)
11. mark_complete      - Update order status
```

### Rollback Flow (on payment capture failure)

```
← mark_complete       (not started - skipped)
← notify_all          (not started - skipped)
← fulfillment         (not started - skipped)
← payment.capture     (FAILED - triggers rollback)
← payment.authorize   - PaymentGateway.void(auth_id)
← inventory_ok        (require - no rollback)
← fraud_ok            (require - no rollback)
← verification        (no rollback defined)
← has_items           (require - no rollback)
← check_status        (no rollback)
← load_order          (no rollback)
```

---

## Dependencies

- `libs/dag` - DAG operations (already created)
- `libs/fn_types` - Result, Recoverable protocol
- Telemetry - For observability

---

## Critical Files Summary

| File | Purpose |
|------|---------|
| `libs/effect/lib/effect.ex` | Main API facade |
| `libs/effect/lib/effect/runtime.ex` | Execution engine |
| `libs/effect/lib/effect/middleware.ex` | Middleware chain |
| `libs/effect/lib/effect/checkpoint.ex` | Checkpoint/resume |
| `libs/effect/lib/effect/retry.ex` | Recoverable-aware retry |
| `libs/effect/lib/effect/saga.ex` | Rollback orchestration |
| `libs/effect/lib/effect/circuit.ex` | Circuit breaker |
| `libs/effect/lib/effect/rate_limit.ex` | Rate limiting |
| `libs/effect/lib/effect/telemetry.ex` | Telemetry + OpenTelemetry |
| `libs/effect/lib/effect/parallel.ex` | Concurrent execution |
| `libs/effect/lib/effect/branch.ex` | Conditional routing |
| `libs/dag/lib/dag.ex` | DAG operations (exists) |

---

## Testing

### Test Helpers Module

```elixir
defmodule Effect.Testing do
  @moduledoc "Test utilities for Effect"

  # Assertions
  def assert_effect_ok(effect, ctx), do: ...
  def assert_effect_error(effect, ctx, expected_error), do: ...
  def assert_effect_halted(effect, ctx, expected_reason), do: ...
  def assert_step_called(report, step_name), do: ...
  def assert_step_skipped(report, step_name), do: ...
  def assert_rollback_called(report, step_name), do: ...

  # Mocking
  def mock_step(effect, step_name, mock_fn), do: ...
  def mock_service(effect, service_name, mock_module), do: ...

  # Inspection
  def execution_trace(report), do: ...  # Returns ordered list of executed steps
  def timing_breakdown(report), do: ...  # Returns %{step => duration_ms}
end
```

### Property Tests (StreamData)

```elixir
defmodule Effect.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  # Invariants to test:
  # 1. Build operations are pure (same input → same output)
  # 2. Rollbacks execute in reverse order
  # 3. Parallel results merge correctly
  # 4. Context accumulates correctly
  # 5. Halted effects don't trigger rollbacks

  property "build operations are pure" do
    check all steps <- list_of(step_generator(), min_length: 1, max_length: 20) do
      effect1 = build_effect(steps)
      effect2 = build_effect(steps)
      assert effect1 == effect2
    end
  end

  property "rollbacks execute in reverse completion order" do
    check all steps <- list_of(step_with_rollback(), min_length: 2, max_length: 10),
              fail_at <- integer(1..(length(steps) - 1)) do
      {_result, report} = run_with_failure_at(steps, fail_at)
      assert rollback_order(report) == Enum.reverse(completed_steps(report))
    end
  end
end
```

### Benchmarks (Benchee)

```elixir
# bench/effect_bench.exs
Benchee.run(%{
  "new/1" => fn -> Effect.new(:test) end,
  "step/3 (1 step)" => fn -> Effect.new(:test) |> Effect.step(:a, &id/1) end,
  "step/3 (10 steps)" => fn -> build_n_steps(10) end,
  "step/3 (100 steps)" => fn -> build_n_steps(100) end,
  "run/2 (10 steps, no I/O)" => fn -> Effect.run(ten_step_effect(), %{}) end,
  "run/2 (10 steps, with report)" => fn -> Effect.run(ten_step_effect(), %{}, report: true) end,
  "parallel/4 (5 concurrent)" => fn -> run_parallel_5() end,
  "validate/1 (50 steps)" => fn -> Effect.validate(fifty_step_effect()) end
})
```

---

## Package Configuration

### mix.exs

```elixir
defmodule Effect.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourorg/effect"

  def project do
    [
      app: :effect,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Effect",
      description: "Composable, resumable workflow orchestration for Elixir",
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  defp deps do
    [
      # Required
      {:dag, "~> 0.1"},  # Or inline if keeping as monorepo

      # Optional (for telemetry)
      {:telemetry, "~> 1.0", optional: true},
      {:opentelemetry_api, "~> 1.0", optional: true},

      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end

  defp docs do
    [
      main: "Effect",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [Effect, Effect.Builder, Effect.Step, Effect.Runtime],
        Resilience: [Effect.Retry, Effect.Saga, Effect.Circuit, Effect.RateLimit],
        "Control Flow": [Effect.Parallel, Effect.Branch, Effect.Each, Effect.Race],
        Observability: [Effect.Telemetry, Effect.Report, Effect.Visualization],
        Testing: [Effect.Testing]
      ],
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
```

### README.md Structure

```markdown
# Effect

Composable, resumable workflow orchestration for Elixir.

## Features
- DAG-based step execution
- Saga pattern with automatic rollback
- Parallel, branch, race, each primitives
- Circuit breaker & rate limiting
- Checkpoint/resume for long workflows
- Zero-cost build phase (pure data)

## Installation
## Quick Start
## Examples
## Documentation
## License
```

---

## Future Improvements (P2+)

Consider for later phases after core is stable:

### 1. on_skip Hook
```elixir
Effect.on_skip(effect, fn step, ctx ->
  Logger.info("Skipped #{step} due to when: condition")
end)
```
