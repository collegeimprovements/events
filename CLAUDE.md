# Claude Code Instructions for Events Project

## Required Reading

| Document | Purpose |
|----------|---------|
| `docs/development/AGENTS.md` | Project conventions, code style, patterns |
| `docs/EVENTS_REFERENCE.md` | Schema, Migration, Decorator reference |
| `docs/claude/PATTERNS.md` | Code patterns with examples |
| `docs/claude/FUNCTIONAL.md` | Result, Maybe, Pipeline, AsyncResult, Guards |
| `docs/claude/ASYNC_RESULT.md` | AsyncResult comprehensive reference |
| `docs/claude/EXAMPLES.md` | Real-world Pipeline + AsyncResult examples |
| `docs/claude/SCHEMA.md` | Schema and Migration quick reference |
| `docs/claude/SCHEMA_CHANGESET_REFERENCE.md` | Full Schema, Field, Changeset reference |
| `docs/claude/DECORATORS.md` | Decorator quick reference |
| `docs/claude/CRUD.md` | CRUD system, Multi, Merge, options reference |
| `docs/claude/S3.md` | S3 API reference |
| `docs/claude/SCHEDULER.md` | Cron scheduler quick reference |
| `docs/claude/WORKFLOW.md` | Workflow system with DAG, dependencies, rollbacks |

---

## Module Structure

```
lib/events/
├── (functional types in libs/fn_types) # FnTypes.* - Result, Maybe, Pipeline, AsyncResult, etc.
├── protocols/       # Events.Protocols.* - Protocol definitions
│   ├── normalizable.ex  # Error normalization
│   ├── recoverable.ex   # Error recovery strategies
│   └── identifiable.ex  # Entity identification
├── errors/          # Events.Errors.*    - Error wrappers
│   ├── http_error.ex    # HTTP errors
│   └── posix_error.ex   # System errors
├── core/            # Events.Core.*      - Database layer
│   ├── schema/      #   Schema macros and helpers
│   ├── migration/   #   Migration DSL
│   ├── query/       #   Query builder
│   ├── crud/        #   CRUD operations (Multi, Merge, Context)
│   ├── repo/        #   Repository + SQL scope
│   └── cache/       #   Caching layer
├── api/             # Events.Api.*       - External APIs
│   ├── client/      #   API client with middleware
│   └── clients/     #   Specific clients (Google, Stripe)
├── infra/           # Events.Infra.*     - Infrastructure
│   ├── decorator/   #   Decorator system
│   ├── scheduler/   #   Cron scheduler + workflow system
│   │   └── workflow/    #   DAG-based workflow orchestration
│   ├── kill_switch/ #   Service kill switches
│   ├── idempotency/ #   Idempotency support
│   └── system_health/   # Health checks
├── services/        # Events.Services.*  - External services
│   └── s3/          #   S3/AWS integration
├── support/         # Events.Support.*   - Dev utilities
│   ├── behaviours/  #   Behavior definitions
│   └── credo/       #   Custom Credo checks
└── domains/         # Events.Domains.*   - Business logic
    └── accounts/    #   User accounts, auth, memberships
```

### Key Module Aliases

```elixir
# Functional types (from fn_types library)
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Validation, Guards, Error}

# Protocols
alias FnTypes.Protocols.{Normalizable, Recoverable, Identifiable}

# Core (database)
alias Events.Core.{Schema, Migration, Query, Crud, Repo, Cache}
alias Events.Core.Crud.{Multi, Merge, ChangesetBuilder, Options}

# Infrastructure
alias Events.Infra.{Decorator, KillSwitch, SystemHealth, Idempotency}
alias Events.Infra.Scheduler.Workflow

# API
alias Events.Api.Client
alias Events.Api.Clients.{Google, Stripe}

# Domains (business logic)
alias Events.Domains.Accounts
```

---

## Golden Rules

### 1. Pattern Matching Over Conditionals

```elixir
# CORRECT
def process({:ok, value}), do: {:ok, transform(value)}
def process({:error, reason}), do: {:error, reason}
def process(nil), do: {:error, :nil_input}

# WRONG - Never use if/else
def process(result) do
  if result, do: ..., else: ...
end
```

### 2. Result Tuples Everywhere

```elixir
# All fallible functions return {:ok, value} | {:error, reason}
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{} |> User.changeset(attrs) |> Repo.insert()
end
```

### 3. Use Events.Core.Schema and Events.Core.Migration

```elixir
# CORRECT
use Events.Core.Schema
use Events.Core.Migration

# WRONG
use Ecto.Schema
use Ecto.Migration
```

### 4. Use Functional Modules

```elixir
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult}

# Result for error handling
Result.and_then(result, &process/1)

# Maybe for optional values
Maybe.from_nilable(value) |> Maybe.unwrap_or(default)

# Pipeline for multi-step workflows
Pipeline.new(%{}) |> Pipeline.step(:name, &fun/1) |> Pipeline.run()

# AsyncResult for concurrent operations
AsyncResult.parallel([fn -> task1() end, fn -> task2() end])
```

### 5. Use Decorators

```elixir
use Events.Infra.Decorator

@decorate returns_result(ok: User.t(), error: :atom)
@decorate telemetry_span([:app, :users, :get])
def get_user(id), do: ...
```

---

## Quick Reference Tables

### Functional Modules

| Need | Module | Example |
|------|--------|---------|
| Fallible operation | `FnTypes.Result` | `Result.and_then(result, &process/1)` |
| Optional value | `FnTypes.Maybe` | `Maybe.from_nilable(value)` |
| Multi-step workflow | `FnTypes.Pipeline` | `Pipeline.step(p, :name, &fun/1)` |
| Concurrent tasks | `FnTypes.AsyncResult` | `AsyncResult.parallel(tasks)` |
| Guard clauses | `FnTypes.Guards` | `when is_ok(result)` |
| Accumulating errors | `FnTypes.Validation` | `Validation.validate(v, &check/1)` |

### Pipeline + AsyncResult Composition

| Feature | AsyncResult | Pipeline |
|---------|-------------|----------|
| Parallel execution | `parallel/2` | `parallel/3` |
| Race (first wins) | `race/2` | Use inside step |
| Retry | `retry/2` | `step_with_retry/4` |
| Batch | `batch/2` | Use inside step |
| Context | — | `step/3`, `assign/3` |
| Rollback | — | `run_with_rollback/1` |

### Workflow System

| Feature | Builder API | Decorator API |
|---------|-------------|---------------|
| Create workflow | `Workflow.new(:name)` | `use Workflow, name: :name` |
| Add step | `Workflow.step(w, :name, &fn/1)` | `@decorate step()` |
| Dependencies | `after: :step_a` | `@decorate step(after: :step_a)` |
| Parallel | `Workflow.parallel/3` | `group: :parallel_group` |
| Fan-in | `Workflow.fan_in/4` | `after_group: :group_name` |
| Conditional | `Workflow.branch/3` | `when: &condition/1` |
| Rollback | `rollback: &rollback_fn/1` | `@decorate step(rollback: :fn)` |
| Human approval | — | `await_approval: true` |
| Nested workflow | `Workflow.add_workflow/4` | `@decorate workflow(:name)` |
| Dynamic steps | `Workflow.add_graft/3` | `@decorate graft()` |
| Schedule | `Workflow.schedule(cron: "...")` | `schedule: [cron: "..."]` |

```elixir
# Decorator API (recommended)
defmodule MyApp.OrderWorkflow do
  use Events.Infra.Scheduler.Workflow, name: :order_processing

  @decorate step()
  def validate(ctx), do: {:ok, %{order: Orders.get!(ctx.order_id)}}

  @decorate step(after: :validate, rollback: :release_inventory)
  def reserve_inventory(ctx), do: {:ok, %{reservation: Inventory.reserve(ctx.order)}}

  @decorate step(after: :reserve_inventory, rollback: :refund)
  def charge_payment(ctx), do: {:ok, %{payment: Payments.charge(ctx.order)}}

  @decorate step(after: :charge_payment)
  def send_confirmation(ctx), do: Mailer.send_confirmation(ctx.order)

  def release_inventory(ctx), do: Inventory.release(ctx.reservation)
  def refund(ctx), do: Payments.refund(ctx.payment)
end

# Start workflow
{:ok, execution_id} = Workflow.start(:order_processing, %{order_id: 123})
```

See `docs/claude/WORKFLOW.md` for complete reference with real-world examples.

### CRUD System

| Module | Purpose |
|--------|---------|
| `Events.Core.Crud` | Unified execution API (`run/1`, `create/3`, `fetch/3`) |
| `Events.Core.Crud.Multi` | Transaction composer (atomic multi-step operations) |
| `Events.Core.Crud.Merge` | PostgreSQL MERGE for complex upserts |
| `Events.Core.Crud.Op` | Pure changeset/options builders |
| `Events.Core.Crud.Context` | Context-level `crud User` macro |

**Common Options (all operations):**
- `:repo` - Custom repo module
- `:prefix` - Multi-tenant schema prefix
- `:timeout` - Query timeout (default: 15_000ms)
- `:log` - Logger level or `false` to disable

**Write Options:** `:changeset`, `:returning`, `:stale_error_field`, `:allow_stale`
**Update Options:** `:force` (mark fields as changed)
**Bulk Options:** `:placeholders` (reduce data transfer), `:conflict_target`, `:on_conflict`

```elixir
# Simple CRUD
Crud.create(User, attrs)
Crud.fetch(User, id, preload: [:account])
Crud.update(user, attrs, changeset: :admin_changeset)

# With options
Crud.create(User, attrs, timeout: 30_000, returning: true)
Crud.fetch(User, id, repo: MyApp.ReadOnlyRepo)

# Bulk with placeholders
placeholders = %{now: DateTime.utc_now(), org_id: org_id}
entries = Enum.map(data, &Map.put(&1, :org_id, {:placeholder, :org_id}))
Crud.create_all(User, entries, placeholders: placeholders, timeout: 120_000)

# Transactions with Multi
Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
|> Crud.run(timeout: 60_000)

# PostgreSQL MERGE
User
|> Merge.new(users_data)
|> Merge.match_on(:email)
|> Merge.when_matched(:update, [:name])
|> Merge.when_not_matched(:insert)
|> Crud.run(timeout: 60_000)

# Context macro (generates overridable CRUD functions)
defmodule MyApp.Accounts do
  use Events.Core.Crud.Context
  crud User                           # All CRUD functions
  crud Role, only: [:create, :fetch]  # Specific functions
end
```

See `docs/claude/CRUD.md` for complete options reference.

### Schema

| Preset | Use |
|--------|-----|
| `email()` | Email validation |
| `username()` | Alphanumeric 3-30 |
| `password()` | Min 8 chars |
| `slug()` | URL-safe |

| Field Group | Adds |
|-------------|------|
| `type_fields()` | type, subtype |
| `status_fields()` | status, substatus |
| `audit_fields()` | created_by, updated_by |
| `timestamps()` | inserted_at, updated_at |

### Decorators

| Category | Decorators |
|----------|-----------|
| Types | `returns_result`, `returns_maybe`, `returns_bang`, `normalize_result` |
| Cache | `cacheable`, `cache_put`, `cache_evict` |
| Telemetry | `telemetry_span`, `log_call`, `log_if_slow` |
| Security | `role_required`, `rate_limit`, `audit_log` |

---

## Common Patterns

### Sequential Operations

```elixir
with {:ok, user} <- create_user(attrs),
     {:ok, _} <- send_welcome_email(user),
     {:ok, _} <- create_settings(user) do
  {:ok, user}
end
```

### Parallel Operations

```elixir
alias FnTypes.AsyncResult

AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])
```

### Multi-Step Workflow

```elixir
alias FnTypes.Pipeline

Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:create, &create/1)
|> Pipeline.step(:notify, &notify/1)
|> Pipeline.run()
```

### Race with Fallback

```elixir
alias FnTypes.AsyncResult

AsyncResult.race([
  fn -> Cache.get(key) end,
  fn -> DB.get(key) end
])
```

### Retry with Backoff

```elixir
alias FnTypes.AsyncResult

AsyncResult.retry(fn -> api_call() end,
  max_attempts: 3,
  initial_delay: 100,
  max_delay: 5000
)
```

### Scheduled Workflow with Dependencies

```elixir
defmodule MyApp.DailyReport do
  use Events.Infra.Scheduler.Workflow,
    name: :daily_report,
    schedule: [cron: "0 6 * * *"]

  @decorate step()
  def fetch_data(ctx), do: {:ok, %{data: Reports.fetch(ctx.date)}}

  @decorate step(after: :fetch_data, group: :process)
  def generate_pdf(ctx), do: {:ok, %{pdf: Reports.to_pdf(ctx.data)}}

  @decorate step(after: :fetch_data, group: :process)
  def generate_csv(ctx), do: {:ok, %{csv: Reports.to_csv(ctx.data)}}

  @decorate step(after_group: :process)
  def send_email(ctx), do: Mailer.send_report(ctx.pdf, ctx.csv)
end
```

---

## Anti-Patterns

| Never | Always |
|-------|--------|
| `if...else` | `case`, `cond`, pattern matching |
| `Repo.insert!()` | `Repo.insert()` |
| `use Ecto.Schema` | `use Events.Core.Schema` |
| `use Ecto.Migration` | `use Events.Core.Migration` |
| Nested case | `with` statement |
| Macros for logic | Functions + pattern matching |
| Raising errors | Return `{:error, reason}` |

---

## File Locations

```
docs/
├── claude/                    # Quick references (read these)
│   ├── PATTERNS.md           # Code patterns
│   ├── FUNCTIONAL.md         # Result, Maybe, Pipeline, AsyncResult
│   ├── EXAMPLES.md           # Real-world examples
│   ├── SCHEMA.md             # Schema/Migration quick reference
│   ├── SCHEMA_CHANGESET_REFERENCE.md  # Full Schema, Field, Changeset guide
│   ├── DECORATORS.md         # Decorator reference
│   ├── S3.md                 # S3 API reference
│   ├── SCHEDULER.md          # Cron scheduler reference
│   └── WORKFLOW.md           # Workflow system (DAG, dependencies, rollbacks)
├── development/
│   ├── AGENTS.md             # Full conventions guide
│   ├── ARCHITECTURE.md       # System architecture
│   └── PROTOCOLS.md          # Protocol documentation
├── examples/                  # Example code
├── functional/
│   └── OVERVIEW.md           # Comprehensive functional docs
└── EVENTS_REFERENCE.md       # Complete Schema/Migration/Decorator docs
```

---

## Consistency Checks

```bash
# Run before committing
mix credo --strict
mix consistency.check
mix dialyzer
```

| Check | Description |
|-------|-------------|
| `UseEventsSchema` | Ensures Events.Core.Schema usage |
| `UseEventsMigration` | Ensures Events.Core.Migration usage |
| `NoBangRepoOperations` | Prevents Repo.insert!/update! |
| `RequireResultTuples` | Ensures result tuple returns |
| `PreferPatternMatching` | Encourages case/with over if/else |
- Remember this - specially opensourcing the functional types, schema, query and decorator system