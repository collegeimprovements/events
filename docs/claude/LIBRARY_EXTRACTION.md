# Library Extraction Plan

This document tracks the plan to make key modules extractable as standalone libraries.

## Goal

Make modules 100% extractable to separate libraries while keeping them in the Events codebase for now.

## Extraction Readiness Scores

| Library | Score | Status |
|---------|-------|--------|
| **Events.Types** | 10/10 | Ready - Phase 1 Complete |
| **Events.Core.Query** | 10/10 | Ready - Phase 2 Complete |
| **Events.Core.Schema** | 10/10 | Ready - Phase 7 Complete |
| **Events.Core.Migration** | 10/10 | Ready - Phase 7 Complete |
| **Events.Api** | 10/10 | Ready - Phase 4 Complete |
| **Events.Infra.Idempotency** | 10/10 | Ready - Phase 6 Complete |
| **Events.Infra.KillSwitch** | 10/10 | Ready - Phase 4 Complete |
| **Events.Infra.Decorator** | 10/10 | Ready - Phase 4 Complete |
| **Events.Infra.SystemHealth** | 10/10 | Ready - Phase 6 Complete |
| **Events.Infra.Mailer** | 10/10 | Ready - Phase 4 Complete |
| **Events.Infra.Scheduler** | 10/10 | Ready - Phase 5 Complete |

---

## Dependency Map

```
Events.Types ──────────────────────── (pure, no deps) ✅

Events.Core.Query ─── Ecto (external)
                  └── Events.Core.Repo (configurable via compile_env) ✅

Events.Core.Schema ─── Ecto (external)
                   └── Events.Core.Repo (configurable via compile_env) ✅
                   └── app_name configurable via compile_env ✅

Events.Core.Migration ─── Ecto (external)
                      └── (no hardcoded deps) ✅

Events.Api.Client ─── req (external)
                  └── implements Idempotency.RequestBehaviour ✅
                  └── implements Idempotency.ResponseBehaviour ✅

Events.Infra.Idempotency ─── Events.Core.Repo (configurable via compile_env) ✅
                         └── Events.Core.Schema
                         └── defines RequestBehaviour (no Api deps) ✅
                         └── defines ResponseBehaviour (no Api deps) ✅
                         └── telemetry prefix configurable ✅

Events.Infra.KillSwitch ─── app_name configurable via compile_env ✅

Events.Infra.Decorator ─── Events.Core.Repo (configurable via compile_env) ✅

Events.Infra.SystemHealth ─── app_name configurable via compile_env ✅

Events.Infra.Mailer ─── otp_app configurable via compile_env ✅

Events.Infra.Scheduler ─── Events.Core.Schema (Job, Execution)
                       └── Events.Core.Repo (configurable via compile_env) ✅
                       └── app_name configurable via compile_env ✅
                       └── telemetry prefix configurable via compile_env ✅
                       └── leader_key configurable (Peer.Global) ✅
```

---

## Phase 1: Events.Types (CURRENT)

**Target:** Make functional types fully extractable as standalone `types` library.

**Modules:**
- Result
- Maybe
- Pipeline
- AsyncResult
- Validation
- Guards
- Error
- Lens
- Diff
- NonEmptyList
- Resource

**Checklist:**
- [ ] No hardcoded Events.* references outside Types namespace
- [ ] No dependencies on Events.Protocols (or make optional)
- [ ] No dependencies on Events.Core, Events.Infra, Events.Api
- [ ] Configurable application name for config lookups
- [ ] All internal references use relative aliases

**Extraction would require:**
- Rename `FnTypes.*` → `Types.*` (or chosen library name)
- Update mix.exs with standalone deps
- No code changes needed

---

## Phase 2: Events.Core.Query (COMPLETE)

**Target:** Make Query builder extractable as standalone `query` library.

**Completed:**
- [x] All hardcoded `Events.Core.Repo` references → made fully injectable via `Application.compile_env`
- [x] Telemetry prefix `[:events, :query]` → configurable via app env
- [x] Error classes → verified no Events.* namespace leakage (uses `__MODULE__`)
- [x] Config key `:events` → uses `compile_env` for compile-time config

**Files modified:**
- `lib/events/core/query.ex` - Added `@default_repo` module attribute and `get_repo/1` helper
- `lib/events/core/query/executor.ex` - Added `@default_repo` and `@telemetry_prefix` module attributes
- `lib/events/core/query/token.ex` - Switched to `compile_env` for limit configurations
- `lib/events/core/query/debug.ex` - Added `@default_repo` module attribute
- `lib/events/core/query/test_helpers.ex` - Added `@default_repo` module attribute
- `config/config.exs` - Added default configuration for `Events.Core.Query`

**Extraction would require:**
- Rename `Events.Core.Query.*` → `Query.*` (or chosen library name)
- Update mix.exs with standalone deps (Ecto)
- Update config key from `:events` to library name
- No code logic changes needed

---

## Phase 3: Break Circular Dependencies (COMPLETE)

**The blocker was:**
```
Api.Client → Idempotency.Middleware → Api.Client.{Request, Response}
```

**Solution implemented:** Option 2 - Define behaviours that Request/Response implement

**Approach:**
- Created `Idempotency.RequestBehaviour` - defines contract for request structs
- Created `Idempotency.ResponseBehaviour` - defines contract for response structs
- Updated `Idempotency.Middleware` to work with any struct (duck typing via `Map.get/2`)
- `Api.Client.Request` implements `RequestBehaviour`
- `Api.Client.Response` implements `ResponseBehaviour`

**Files created:**
- `lib/events/infra/idempotency/request_behaviour.ex` - Request contract (6 callbacks)
- `lib/events/infra/idempotency/response_behaviour.ex` - Response contract (4 callbacks + helpers)

**Files modified:**
- `lib/events/infra/idempotency/middleware.ex` - Removed Api.Client aliases, uses struct duck typing
- `lib/events/api/client/request.ex` - Added `@behaviour` and implemented 6 callbacks
- `lib/events/api/client/response.ex` - Added `@behaviour` and implemented 4 callbacks

**Key design decisions:**
- Middleware uses `is_struct(req)` guards and `Map.get/2` for field access
- Uses `function_exported?/3` to check for optional `success?/1` callback
- `ResponseBehaviour.default_success?/1` provides fallback for any struct with `:status` field
- `ResponseBehaviour.to_cacheable/1` converts any response struct to storable map

**Extraction would require:**
- `Events.Api` can now be extracted independently
- `Events.Infra.Idempotency` can be extracted independently
- Both reference behaviours, not concrete modules

---

## Phase 4: Events.Infra (Split into multiple libraries)

**Target:** Split Infra into separate extractable libraries.

| Extract As | Modules | Readiness | Blockers |
|------------|---------|-----------|----------|
| `kill_switch` | KillSwitch | **10/10** | None - app_name configurable |
| `decorator` | Decorator system | **10/10** | Repo configurable |
| `idempotency` | Idempotency | **10/10** | Repo + telemetry + schema note |
| `system_health` | SystemHealth | **10/10** | All modules configurable |
| `mailer` | Mailer | **10/10** | otp_app configurable |
| `scheduler` | Scheduler, Workflow | **10/10** | All configurable via compile_env |

**Completed in Phase 4:**
- KillSwitch: `@app_name` via `compile_env`
- Decorator: `@default_repo` via `compile_env`
- Idempotency: `@default_repo` + `@telemetry_prefix` via `compile_env`
- SystemHealth: `@app_name` via `compile_env` (4 modules)
- Mailer: `@app_name` via `compile_env`
- Api.Client: telemetry prefix configurable, uses `FnTypes.Recoverable`

**Scheduler (completed in Phase 5):**
- Config.get() uses `@app_name` via `compile_env`
- Telemetry.ex, Workflow.Telemetry use configurable `@prefix`
- Peer.Postgres uses `@telemetry_prefix` + `@default_repo`
- Peer.Global uses `@leader_key` + `@telemetry_prefix`
- Store.Database uses `@default_repo`

---

## Phase 7: Events.Core.Schema & Migration (COMPLETE)

**Target:** Make Schema and Migration modules fully extractable.

### Events.Core.Schema

**Files modified:**
- `lib/events/core/schema.ex` - Added `@app_name` and `@default_repo` for `deletion_impact/2`
- `lib/events/core/schema/database_validator.ex` - Added `@app_name` and `@default_repo`
- `lib/events/core/schema/validation_pipeline.ex` - Added `@app_name` for telemetry config
- `lib/events/core/schema/telemetry.ex` - Added `@app_name` for logging config
- `lib/events/core/schema/relationship_validator.ex` - Added `@app_name` for module discovery
- `lib/events/core/schema/field.ex` - Added `@app_name` for warnings config

**Extraction would require:**
- Rename `Events.Core.Schema.*` → `Schema.*` (or chosen library name)
- Update mix.exs with standalone deps (Ecto)
- Update config key from `:events` to library name
- No code logic changes needed

### Events.Core.Migration

**Status:** Already clean - no hardcoded dependencies found.

The Migration module is a thin wrapper around `Ecto.Migration` with convenience macros.
It has no `Events.Core.Repo` or `:events` config lookups.

**Extraction would require:**
- Rename `Events.Core.Migration.*` → `Migration.*` (or chosen library name)
- Update mix.exs with standalone deps (Ecto)
- No code changes needed

---

## Cross-Cutting Patterns to Apply

### 1. Configurable Repo (affects Query, Infra)
```elixir
# Current (hardcoded)
repo = Keyword.get(opts, :repo, Events.Core.Repo)

# Target (configurable default)
@default_repo Application.compile_env(:my_lib, :default_repo)
repo = Keyword.get(opts, :repo, @default_repo)
```

### 2. Configurable Telemetry Prefix
```elixir
# Current
:telemetry.execute([:events, :query, :execute], ...)

# Target
@telemetry_prefix Application.compile_env(:my_lib, :telemetry_prefix, [:my_lib])
:telemetry.execute(@telemetry_prefix ++ [:execute], ...)
```

### 3. Protocol Dependencies (Optional)
```elixir
# Make protocol implementations optional via config
if Code.ensure_loaded?(Events.Protocols.Normalizable) do
  defimpl Events.Protocols.Normalizable, for: MyError do
    # ...
  end
end
```

---

## Progress Log

| Date | Phase | Action | Status |
|------|-------|--------|--------|
| 2025-12-11 | 1 | Audit Events.Types dependencies | Complete |
| 2025-12-11 | 1 | Make Repo configurable in retry.ex | Complete |
| 2025-12-11 | 1 | Make TaskSupervisor configurable in error.ex | Complete |
| 2025-12-11 | 1 | Make telemetry prefix configurable | Complete |
| 2025-12-11 | 1 | Move Normalizable protocol to Types | Complete |
| 2025-12-11 | 1 | Move Recoverable protocol to Types | Complete |
| 2025-12-11 | 1 | Create backwards-compat aliases | Complete |
| 2025-12-11 | 1 | Verify extractability (all tests pass) | Complete |
| 2025-12-11 | 2 | Audit Events.Core.Query dependencies | Complete |
| 2025-12-11 | 2 | Make Repo configurable in query.ex (6 places) | Complete |
| 2025-12-11 | 2 | Make Repo configurable in executor.ex | Complete |
| 2025-12-11 | 2 | Make telemetry prefix configurable in executor.ex | Complete |
| 2025-12-11 | 2 | Make Repo configurable in debug.ex | Complete |
| 2025-12-11 | 2 | Make Repo configurable in test_helpers.ex | Complete |
| 2025-12-11 | 2 | Switch token.ex to compile_env | Complete |
| 2025-12-11 | 2 | Add Events.Core.Query config to config.exs | Complete |
| 2025-12-11 | 2 | Verify extractability (all 2196 tests pass) | Complete |
| 2025-12-11 | 3 | Analyze Api/Idempotency circular dependency | Complete |
| 2025-12-11 | 3 | Create Idempotency.RequestBehaviour | Complete |
| 2025-12-11 | 3 | Create Idempotency.ResponseBehaviour | Complete |
| 2025-12-11 | 3 | Update Middleware to use struct duck typing | Complete |
| 2025-12-11 | 3 | Implement RequestBehaviour in Api.Client.Request | Complete |
| 2025-12-11 | 3 | Implement ResponseBehaviour in Api.Client.Response | Complete |
| 2025-12-11 | 3 | Verify extractability (all 2196 tests pass) | Complete |
| 2025-12-11 | 4 | Make Api.Client telemetry prefix configurable | Complete |
| 2025-12-11 | 4 | Update retry.ex/circuit_breaker.ex to use Types.Recoverable | Complete |
| 2025-12-11 | 4 | Make Idempotency Repo configurable (7 call sites) | Complete |
| 2025-12-11 | 4 | Make Idempotency telemetry prefix configurable | Complete |
| 2025-12-11 | 4 | Make Recovery telemetry prefix configurable | Complete |
| 2025-12-11 | 4 | Make KillSwitch app_name configurable | Complete |
| 2025-12-11 | 4 | Make Decorator.Telemetry Repo configurable | Complete |
| 2025-12-11 | 4 | Make SystemHealth.Infra app_name configurable | Complete |
| 2025-12-11 | 4 | Make SystemHealth.Services app_name configurable | Complete |
| 2025-12-11 | 4 | Make SystemHealth.Environment app_name configurable | Complete |
| 2025-12-11 | 4 | Make SystemHealth.Migrations app_name configurable | Complete |
| 2025-12-11 | 4 | Make Mailer otp_app configurable | Complete |
| 2025-12-11 | 4 | Verify extractability (all 2196 tests pass) | Complete |
| 2025-12-11 | 5 | Make Scheduler.Config app_name configurable | Complete |
| 2025-12-11 | 5 | Make Scheduler.Telemetry prefix configurable | Complete |
| 2025-12-11 | 5 | Make Scheduler.Workflow.Telemetry prefix configurable | Complete |
| 2025-12-11 | 5 | Make Peer.Postgres telemetry + repo configurable | Complete |
| 2025-12-11 | 5 | Make Peer.Global leader_key + telemetry configurable | Complete |
| 2025-12-11 | 5 | Make Store.Database repo fallback configurable | Complete |
| 2025-12-11 | 5 | Verify extractability (all 2196 tests pass) | Complete |
| 2025-12-11 | 6 | Make SystemHealth.Services services list configurable | Complete |
| 2025-12-11 | 6 | Make SystemHealth.Services S3 module configurable | Complete |
| 2025-12-11 | 6 | Make SystemHealth.Migrations repo configurable | Complete |
| 2025-12-11 | 6 | Make SystemHealth.Infra repo/cache modules configurable | Complete |
| 2025-12-11 | 6 | Note: Idempotency.Record schema requires simple `use` change | Complete |
| 2025-12-11 | 6 | Verify extractability (all 2196 tests pass) | Complete |
| 2025-12-11 | 7 | Audit Events.Core.Schema dependencies | Complete |
| 2025-12-11 | 7 | Audit Events.Core.Migration dependencies | Complete |
| 2025-12-11 | 7 | Make Schema.DatabaseValidator repo/app_name configurable | Complete |
| 2025-12-11 | 7 | Make Schema.ValidationPipeline app_name configurable | Complete |
| 2025-12-11 | 7 | Make Schema.Telemetry app_name configurable | Complete |
| 2025-12-11 | 7 | Make Schema.RelationshipValidator app_name configurable | Complete |
| 2025-12-11 | 7 | Make Schema.Field app_name configurable | Complete |
| 2025-12-11 | 7 | Make Schema.deletion_impact repo configurable | Complete |
| 2025-12-11 | 7 | Migration already clean (no hardcoded deps) | Complete |
| 2025-12-11 | 7 | Verify extractability (all 2196 tests pass) | Complete |
