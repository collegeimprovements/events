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
| `docs/claude/DECORATORS.md` | Decorator quick reference |
| `docs/claude/S3.md` | S3 API reference |

---

## Module Structure

```
lib/events/
├── types/           # Events.Types.*     - Functional data types
│   ├── result.ex    #   Result monad ({:ok, v} | {:error, r})
│   ├── maybe.ex     #   Maybe monad ({:some, v} | :none)
│   ├── pipeline.ex  #   Multi-step workflows
│   ├── async_result.ex  # Concurrent operations
│   ├── validation.ex    # Validation accumulator
│   ├── guards.ex    #   Guards and pattern macros
│   └── error.ex     #   Base error struct
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
│   ├── repo/        #   Repository + SQL scope
│   └── cache/       #   Caching layer
├── api/             # Events.Api.*       - External APIs
│   ├── client/      #   API client with middleware
│   └── clients/     #   Specific clients (Google, Stripe)
├── infra/           # Events.Infra.*     - Infrastructure
│   ├── decorator/   #   Decorator system
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
# Types (functional data structures)
alias Events.Types.{Result, Maybe, Pipeline, AsyncResult, Validation, Guards, Error}

# Protocols
alias Events.Protocols.{Normalizable, Recoverable, Identifiable}

# Core (database)
alias Events.Core.{Schema, Migration, Query, Repo, Cache}

# Infrastructure
alias Events.Infra.{Decorator, KillSwitch, SystemHealth, Idempotency}

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
alias Events.Types.{Result, Maybe, Pipeline, AsyncResult}

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
| Fallible operation | `Events.Types.Result` | `Result.and_then(result, &process/1)` |
| Optional value | `Events.Types.Maybe` | `Maybe.from_nilable(value)` |
| Multi-step workflow | `Events.Types.Pipeline` | `Pipeline.step(p, :name, &fun/1)` |
| Concurrent tasks | `Events.Types.AsyncResult` | `AsyncResult.parallel(tasks)` |
| Guard clauses | `Events.Types.Guards` | `when is_ok(result)` |
| Accumulating errors | `Events.Types.Validation` | `Validation.validate(v, &check/1)` |

### Pipeline + AsyncResult Composition

| Feature | AsyncResult | Pipeline |
|---------|-------------|----------|
| Parallel execution | `parallel/2` | `parallel/3` |
| Race (first wins) | `race/2` | Use inside step |
| Retry | `retry/2` | `step_with_retry/4` |
| Batch | `batch/2` | Use inside step |
| Context | — | `step/3`, `assign/3` |
| Rollback | — | `run_with_rollback/1` |

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
alias Events.Types.AsyncResult

AsyncResult.parallel([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])
```

### Multi-Step Workflow

```elixir
alias Events.Types.Pipeline

Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:create, &create/1)
|> Pipeline.step(:notify, &notify/1)
|> Pipeline.run()
```

### Race with Fallback

```elixir
alias Events.Types.AsyncResult

AsyncResult.race([
  fn -> Cache.get(key) end,
  fn -> DB.get(key) end
])
```

### Retry with Backoff

```elixir
alias Events.Types.AsyncResult

AsyncResult.retry(fn -> api_call() end,
  max_attempts: 3,
  initial_delay: 100,
  max_delay: 5000
)
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
│   ├── SCHEMA.md             # Schema/Migration reference
│   ├── DECORATORS.md         # Decorator reference
│   └── S3.md                 # S3 API reference
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
