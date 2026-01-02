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
| `docs/claude/CACHING.md` | Caching presets, @cacheable API, custom presets |
| `docs/claude/CRUD.md` | CRUD system, Multi, Merge, options reference |
| `docs/claude/S3.md` | S3 API reference |
| `docs/claude/SCHEDULER.md` | Cron scheduler quick reference |
| `docs/claude/WORKFLOW.md` | Workflow system with DAG, dependencies, rollbacks |
| `docs/claude/DUPLICATION_REPORT.md` | Cross-library code duplication analysis (TODO) |

---

## Module Structure

### Extracted Libraries (libs/) - USE DIRECTLY

```
libs/
├── fn_types/        # FnTypes.* - Functional types
│   ├── Result, Maybe, Pipeline, AsyncResult, Validation
│   ├── Guards, Error, Lens, NonEmptyList, Timing, Retry
│   ├── Protocols: Normalizable, Recoverable, Identifiable
│   └── Protocols.Registry (protocol introspection)
├── fn_decorator/    # FnDecorator.* - Decorator system
│   ├── Caching, Telemetry, Debugging, Tracing
│   ├── Purity, Testing, Pipeline, Types
│   ├── Security, Validation
│   └── Telemetry.Helpers (span, emit, timed)
├── om_schema/       # OmSchema.* - Schema & validation
│   └── FieldNames (configurable field naming conventions)
├── om_migration/    # OmMigration.* - Migration DSL
├── om_query/        # OmQuery.* - Query builder
├── om_crud/         # OmCrud.* - CRUD operations
│   ├── Multi, Merge, Options, ChangesetBuilder
│   └── Context, Schema
├── om_api_client/   # OmApiClient.* - HTTP API client
├── om_idempotency/  # OmIdempotency.* - Idempotency support
├── om_kill_switch/  # OmKillSwitch.* - Service kill switches
│   └── Services: S3, Cache
├── om_middleware/   # OmMiddleware.* - Middleware chains
│   └── Composable processing pipelines with lifecycle hooks
├── om_behaviours/   # OmBehaviours.* - Common behaviour patterns
│   ├── Adapter (service adapter pattern)
│   ├── Service (supervised service pattern)
│   └── Builder (fluent builder pattern)
├── om_s3/           # OmS3.* - S3 operations
├── om_stripe/       # OmStripe.* - Stripe API client
├── om_google/       # OmGoogle.* - Google APIs
│   ├── ServiceAccount (JWT auth, TokenServer)
│   └── FCM (Firebase Cloud Messaging)
├── om_typst/        # OmTypst.* - Typst document compilation
├── om_ttyd/         # OmTtyd.* - Web terminal sharing
│   ├── Server, Session, SessionManager
│   └── Per-session terminal instances
├── om_credo/        # OmCredo.* - Configurable Credo checks
│   ├── PreferPatternMatching, NoBangRepoOperations
│   ├── RequireResultTuples, UseEnhancedSchema
│   ├── UseEnhancedMigration, UseDecorator
│   └── All checks are configurable via params
├── dag/             # Dag.* - Directed acyclic graph
└── effect/          # Effect.* - Effect system
```

### Events Application (lib/events/) - Events-specific code only

```
lib/events/
├── core/            # Events.Core.* - Database layer
│   ├── repo/        #   Events.Core.Repo (Ecto repo)
│   └── cache/       #   Events.Core.Cache
├── errors/          # Events.Errors.* - Events-specific errors
├── infra/           # Events.Infra.* - Infrastructure
│   └── decorator/   #   Events-specific decorators (scheduler, workflow)
├── support/         # Events.Support.* - Dev utilities (constants, iex_helpers)
└── domains/         # Events.Domains.* - Business logic
    └── accounts/    #   User accounts, auth, memberships
```

### Key Module Aliases

```elixir
# Functional types (from libs/fn_types)
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Validation, Guards, Error, Timing, Retry}

# Protocols (from libs/fn_types)
alias FnTypes.Protocols.{Normalizable, Recoverable, Identifiable}

# CRUD (from libs/om_crud)
alias OmCrud
alias OmCrud.{Multi, Merge, ChangesetBuilder, Options, Context}

# Query (from libs/om_query)
alias OmQuery
alias OmQuery.{Token, Result, DSL, Fragment}

# Schema (from libs/om_schema) - Events defaults via config
# use OmSchema in schema modules

# Scheduler & Workflow (from libs/om_scheduler)
alias OmScheduler
alias OmScheduler.Workflow

# Kill Switch (from libs/om_kill_switch)
alias OmKillSwitch
alias OmKillSwitch.{S3, Cache}

# S3 (from libs/om_s3)
alias OmS3

# Stripe (from libs/om_stripe)
alias OmStripe
alias OmStripe.Config, as: StripeConfig

# Google APIs (from libs/om_google)
alias OmGoogle.{ServiceAccount, FCM}

# Document compilation (from libs/om_typst)
alias OmTypst

# Web terminal (from libs/om_ttyd)
alias OmTtyd
alias OmTtyd.{Server, Session, SessionManager}

# Middleware (from libs/om_middleware)
alias OmMiddleware

# Behaviours (from libs/om_behaviours)
alias OmBehaviours.{Adapter, Service, Builder}

# Telemetry helpers (from libs/fn_decorator)
alias FnDecorator.Telemetry.Helpers, as: TelemetryHelpers

# Protocol registry (from libs/fn_types)
alias FnTypes.Protocols.Registry, as: ProtocolRegistry

# Field names (from libs/om_schema)
alias OmSchema.FieldNames

# Decorators (from libs/fn_decorator)
# use FnDecorator for standard decorators
# use Events.Infra.Decorator for Events-specific (scheduler, workflow)

# API Client (from libs/om_api_client)
alias OmApiClient
alias OmApiClient.Telemetry

# Repository (Events-specific)
alias Events.Core.{Repo, Cache}

# Domains (business logic)
alias Events.Domains.Accounts
```

### Direct Lib Usage

All libs are configured with Events defaults in `config/config.exs`:

| Lib | Config Key | Events Defaults |
|-----|------------|-----------------|
| `OmSchema` | `:om_schema` | `default_repo: Events.Core.Repo` |
| `OmQuery` | `:om_query` | `default_repo: Events.Core.Repo` |
| `OmCrud` | `:om_crud` | `default_repo: Events.Core.Repo` |
| `OmScheduler` | `:events, OmScheduler` | `repo: Events.Core.Repo` |
| `OmKillSwitch` | `:om_kill_switch` | `services: [:s3, :cache, :database, :email]` |
| `OmS3` | `:om_s3` | `bucket: System.get_env("S3_BUCKET")` |
| `OmStripe` | `:om_stripe` | `api_key: System.get_env("STRIPE_API_KEY")` |
| `OmGoogle` | `:om_google` | `credentials_path: ...` |
| `OmTypst` | `:om_typst` | Uses system typst binary |
| `OmTtyd` | `:om_ttyd` | Uses system ttyd binary |
| `FnTypes.Retry` | `:fn_types, FnTypes.Retry` | `default_repo: Events.Core.Repo` |
| `FnDecorator` | `:fn_decorator` | `telemetry_prefix: [:events]` |

**Events-specific modules (still needed):**

| Module | Why |
|--------|-----|
| `Events.Core.Repo` | Ecto Repo with Events database |
| `Events.Core.Cache` | Events cache configuration |
| `Events.Infra.Decorator` | Events-specific decorators (scheduler, workflow) |

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

### 3. Use OmSchema and OmMigration

```elixir
# CORRECT - Use libs directly
use OmSchema
use OmMigration

# WRONG - Raw Ecto without enhancements
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
# For standard decorators (caching, telemetry, debugging, etc.)
use FnDecorator

# For Events-specific decorators (scheduler, workflow)
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
| Execution timing | `FnTypes.Timing` | `Timing.measure(fn -> work() end)` |
| Retry with backoff | `FnTypes.Retry` | `Retry.execute(fn -> api() end)` |

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

### CRUD System (OmCrud)

Use `OmCrud` directly from `libs/om_crud`:

| Module | Purpose |
|--------|---------|
| `OmCrud` | Unified execution API (`run/1`, `create/3`, `fetch/3`) |
| `OmCrud.Multi` | Transaction composer (atomic multi-step operations) |
| `OmCrud.Merge` | PostgreSQL MERGE for complex upserts |
| `OmCrud.Options` | Option handling utilities |
| `OmCrud.ChangesetBuilder` | Changeset building utilities |
| `OmCrud.Context` | Context-level `crud User` macro |

**Common Options (all operations):**
- `:repo` - Custom repo module
- `:prefix` - Multi-tenant schema prefix
- `:timeout` - Query timeout (default: 15_000ms)
- `:log` - Logger level or `false` to disable

**Write Options:** `:changeset`, `:returning`, `:stale_error_field`, `:allow_stale`
**Update Options:** `:force` (mark fields as changed)
**Bulk Options:** `:placeholders` (reduce data transfer), `:conflict_target`, `:on_conflict`

```elixir
alias OmCrud
alias OmCrud.{Multi, Merge}

# Simple CRUD
OmCrud.create(User, attrs)
OmCrud.fetch(User, id, preload: [:account])
OmCrud.update(user, attrs, changeset: :admin_changeset)

# With options
OmCrud.create(User, attrs, timeout: 30_000, returning: true)
OmCrud.fetch(User, id, repo: MyApp.ReadOnlyRepo)

# Bulk with placeholders
placeholders = %{now: DateTime.utc_now(), org_id: org_id}
entries = Enum.map(data, &Map.put(&1, :org_id, {:placeholder, :org_id}))
OmCrud.create_all(User, entries, placeholders: placeholders, timeout: 120_000)

# Transactions with Multi
Multi.new()
|> Multi.create(:user, User, user_attrs)
|> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
|> OmCrud.run(timeout: 60_000)

# PostgreSQL MERGE
User
|> Merge.new(users_data)
|> Merge.match_on(:email)
|> Merge.when_matched(:update, [:name])
|> Merge.when_not_matched(:insert)
|> OmCrud.run(timeout: 60_000)

# Context macro (generates overridable CRUD functions)
defmodule MyApp.Accounts do
  use OmCrud.Context
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

### Decorators (FnDecorator)

Use `FnDecorator` directly from `libs/fn_decorator` for standard decorators:

| Category | Decorators |
|----------|-----------|
| Types | `returns_result`, `returns_maybe`, `returns_bang`, `normalize_result` |
| Cache | `cacheable`, `cache_put`, `cache_evict` |
| Telemetry | `telemetry_span`, `otel_span`, `log_call`, `log_if_slow`, `benchmark` |
| Security | `role_required`, `rate_limit`, `audit_log` |
| Debugging | `debug`, `inspect`, `pry`, `trace_vars` |
| Purity | `pure`, `deterministic`, `idempotent`, `memoizable` |
| Testing | `with_fixtures`, `sample_data`, `timeout_test`, `mock` |

**Events-specific decorators** (require `use Events.Infra.Decorator`):

| Category | Decorators |
|----------|-----------|
| Telemetry | `log_query`, `log_remote` |
| Scheduler | `scheduled` |
| Workflow | `step`, `graft`, `subworkflow` |

### Caching with `@cacheable`

Use `FnDecorator.Caching.Presets` for common caching patterns:

| Preset | TTL | Stale | Best For |
|--------|-----|-------|----------|
| `high_availability` | 5m | 24h | User-facing reads, tolerate staleness |
| `always_fresh` | 30s | - | Feature flags, permissions, critical config |
| `external_api` | 15m | 4h | Third-party APIs, rate-limited endpoints |
| `expensive` | 6h | 7d | Reports, aggregations, ML results |
| `session` | 30m | - | User sessions, shopping carts |
| `database` | 5m | 1h | Standard DB query caching |
| `minimal` | user | - | Simple caching, just TTL |

```elixir
alias FnDecorator.Caching.Presets

# Use a preset - high availability for user reads
@decorate cacheable(Presets.high_availability(cache: MyApp.Cache, key: {User, id}))
def get_user(id), do: Repo.get(User, id)

# Critical config - always fresh
@decorate cacheable(Presets.always_fresh(cache: MyApp.Cache, key: :feature_flags))
def get_flags, do: ConfigService.fetch()

# External API - resilient to outages
@decorate cacheable(Presets.external_api(cache: MyApp.Cache, key: {:weather, city}))
def get_weather(city), do: WeatherAPI.fetch(city)

# Override preset defaults
@decorate cacheable(Presets.high_availability(
  cache: MyApp.Cache,
  key: {User, id},
  ttl: :timer.minutes(10)  # Override default 5m TTL
))
def get_user(id), do: Repo.get(User, id)
```

**Creating Custom Presets** in your codebase:

```elixir
# lib/my_app/cache_presets.ex
defmodule MyApp.CachePresets do
  alias FnDecorator.Caching.Presets

  def microservice(opts \\ []) do
    Presets.merge([
      store: [ttl: :timer.seconds(30)],
      refresh: [on: :stale_access],
      serve_stale: [ttl: :timer.minutes(5)],
      prevent_thunder_herd: [max_wait: :timer.seconds(5)]
    ], opts)
  end

  def resilient_api(opts \\ []) do
    Presets.compose([Presets.high_availability(), opts])
  end
end

# Usage
@decorate cacheable(MyApp.CachePresets.microservice(cache: MyApp.Cache, key: {:orders, id}))
def get_orders(id), do: OrderService.fetch(id)
```

**Full `@cacheable` API** (when presets don't fit):

```elixir
@decorate cacheable(
  store: [cache: MyApp.Cache, key: {User, id}, ttl: :timer.minutes(5), only_if: &match?({:ok, _}, &1)],
  refresh: [on: [:stale_access, :immediately_when_expired], retries: 3],
  serve_stale: [ttl: :timer.hours(1)],
  prevent_thunder_herd: [max_wait: :timer.seconds(5), retries: 3, lock_timeout: :timer.seconds(30)],
  fallback: [on_refresh_failure: :serve_stale, on_cache_unavailable: {:call, &fallback/1}]
)
def get_user(id), do: Repo.get(User, id)
```

See `docs/claude/CACHING.md` for complete reference.

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
| `use Ecto.Schema` | `use OmSchema` |
| `use Ecto.Migration` | `use OmMigration` |
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
│   ├── CACHING.md            # Caching presets, @cacheable API
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
| `OmCredo.Checks.UseEnhancedSchema` | Ensures OmSchema usage over Ecto.Schema |
| `OmCredo.Checks.UseEnhancedMigration` | Ensures OmMigration usage over Ecto.Migration |
| `OmCredo.Checks.NoBangRepoOperations` | Prevents Repo.insert!/update! |
| `OmCredo.Checks.RequireResultTuples` | Ensures result tuple returns |
| `OmCredo.Checks.PreferPatternMatching` | Encourages case/with over if/else |
| `OmCredo.Checks.UseDecorator` | Encourages decorator usage |
- Remember this - specially opensourcing the functional types, schema, query and decorator system