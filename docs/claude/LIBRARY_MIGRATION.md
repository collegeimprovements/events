# Library Migration: lib → libs

This document outlines the migration from wrapper modules in `lib/events/` to direct usage of extracted libraries in `libs/`.

## Overview

The Events project has extracted reusable functionality into standalone libraries in `libs/`. However, `lib/events/` contains thin wrapper modules that simply delegate to these libraries. This creates unnecessary indirection.

**Goal**: Remove delegation layers and use `libs/` modules directly.

## Status Summary

| Wrapper Module | Library | Delegation % | Events-Specific Parts | Action |
|---------------|---------|--------------|----------------------|--------|
| `Events.Core.Crud` | `OmCrud` | 100% | None | **REMOVE** |
| `OmQuery` | `OmQuery` | 100% | Protocol implementations for CRUD | **KEEP protocols.ex only** |
| `Events.Infra.Decorator` | `FnDecorator` | 88% | 6 decorators (scheduler, workflow, telemetry) | **SIMPLIFY** |
| `Events.Api.Client.Telemetry` | `OmApiClient.Telemetry` | 95% | Custom prefix `[:events, :api_client]` | **REMOVE** (configure prefix) |

## What Each Library Covers

### OmCrud (Full Coverage)
- `run/2`, `execute/2`, `transaction/2`, `execute_merge/2`
- `create/3`, `update/3-4`, `delete/2-3`
- `fetch/3`, `get/3`, `exists?/2-3`, `fetch_all/2`, `count/1`
- `create_all/3`, `upsert_all/3`, `update_all/3`, `delete_all/2`
- `OmCrud.Multi`, `OmCrud.Merge`, `OmCrud.Options`, `OmCrud.ChangesetBuilder`
- `OmCrud.Context`, `OmCrud.Schema`
- Protocols: `Executable`, `Validatable`, `Debuggable`

### OmQuery (Full Coverage)
- All query construction: `new/1`, `filter/5`, `order/4`, `join/4`, `select/2`, etc.
- All execution: `execute/2`, `execute!/2`, `stream/2`, `batch/2`
- All shortcuts: `first/2`, `one/2`, `all/2`, `count/2`, `exists?/2`
- Submodules: `Token`, `Builder`, `Executor`, `Result`, `DSL`, `Fragment`, `Search`, `FacetedSearch`

### FnDecorator (46 decorators)
- **Caching**: `cacheable`, `cache_put`, `cache_evict`
- **Telemetry**: `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `benchmark`, `measure`
- **Debugging**: `debug`, `inspect`, `pry`, `trace_vars`
- **Tracing**: `trace_calls`, `trace_modules`, `trace_dependencies`
- **Purity**: `pure`, `deterministic`, `idempotent`, `memoizable`
- **Testing**: `with_fixtures`, `sample_data`, `timeout_test`, `mock`
- **Pipeline**: `pipe_through`, `around`, `compose`
- **Types**: `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `returns_pipeline`, `normalize_result`
- **Security**: `role_required`, `rate_limit`, `audit_log`
- **Validation**: `validate_schema`, `coerce_types`, `serialize`

### OmApiClient.Telemetry (Full Coverage)
- `events/0`, `events/1`
- `emit_start/3`, `emit_stop/4`, `emit_exception/6`, `emit_retry/5`
- `span/4`
- `attach_default_handlers/1`, `attach_logger/1`, `detach_logger/0`

---

## Events-Specific Additions (MUST KEEP)

### 1. Query-CRUD Protocol Integration
**File**: `lib/events/core/query/protocols.ex`

```elixir
# Enables: User |> Query.new() |> Query.where(...) |> Crud.run()
defimpl OmCrud.Executable, for: OmQuery.Token
defimpl OmCrud.Validatable, for: OmQuery.Token
defimpl OmCrud.Debuggable, for: OmQuery.Token
```

**Solution**: Move these implementations to OmQuery, OR keep minimal `lib/events/core/query/protocols.ex`.

### 2. Events-Specific Decorators
**Location**: `lib/events/infra/decorator/` and `lib/events/infra/scheduler/`

| Decorator | Purpose | Implementation |
|-----------|---------|----------------|
| `log_query/1` | Query logging with Events.Core.Repo | `lib/events/infra/decorator/telemetry/decorators.ex` |
| `log_remote/1` | Remote logging with Events.TaskSupervisor | `lib/events/infra/decorator/telemetry/decorators.ex` |
| `scheduled/1` | Cron job scheduling | `lib/events/infra/scheduler/decorator/scheduled.ex` |
| `step/0,1` | Workflow step definition | `lib/events/infra/scheduler/workflow/decorator/step.ex` |
| `graft/0,1` | Dynamic workflow grafting | `lib/events/infra/scheduler/workflow/decorator/graft.ex` |
| `subworkflow/1,2` | Nested workflows | `lib/events/infra/scheduler/workflow/decorator/workflow.ex` |

---

## Migration Plan

### Phase 1: Remove Events.Core.Crud (SAFE - Pure Delegation)

**Files to delete**:
- `lib/events/core/crud.ex` (contains all wrapper modules)

**Find & Replace**:
```elixir
# Aliases
Events.Core.Crud → OmCrud
Events.Core.Crud.Multi → OmCrud.Multi
Events.Core.Crud.Merge → OmCrud.Merge
Events.Core.Crud.Options → OmCrud.Options
Events.Core.Crud.ChangesetBuilder → OmCrud.ChangesetBuilder
Events.Core.Crud.Context → OmCrud.Context
Events.Core.Crud.Schema → OmCrud.Schema

# Use statements
use Events.Core.Crud.Context → use OmCrud.Context
use Events.Core.Crud.Schema → use OmCrud.Schema
```

**Affected files** (~5):
- `lib/events/support/iex_helpers.ex`
- `.iex.exs`
- `examples/query/crud_example.ex`
- `test/events/crud_test.exs`
- `CLAUDE.md`

### Phase 2: Remove Events.Api.Client.Telemetry

**File to delete**:
- `lib/events/api/client/telemetry.ex`

**Change**: Configure prefix in `OmApiClient.Telemetry` calls or application config.

### Phase 3: Simplify Events.Infra.Decorator

**Current**: `use Events.Infra.Decorator` → loads `Events.Infra.Decorator.Define` which delegates to FnDecorator

**Simplified**:
```elixir
defmodule Events.Infra.Decorator do
  defmacro __using__(_opts) do
    quote do
      # Use FnDecorator directly for all standard decorators
      use FnDecorator

      # Add Events-specific decorators
      use Events.Infra.Decorator.EventsSpecific
    end
  end
end

defmodule Events.Infra.Decorator.EventsSpecific do
  use Decorator.Define,
    log_query: 1,
    log_remote: 1,
    scheduled: 1,
    step: 0,
    step: 1,
    graft: 0,
    graft: 1,
    subworkflow: 1,
    subworkflow: 2

  # Only Events-specific implementations here
  defdelegate log_query(opts, body, context), to: Events.Infra.Decorator.Telemetry
  defdelegate log_remote(opts, body, context), to: Events.Infra.Decorator.Telemetry
  defdelegate scheduled(opts, body, context), to: OmScheduler.Decorator.Scheduled
  # ... etc
end
```

### Phase 4: Refactor OmQuery (Complex)

**Option A**: Keep minimal wrapper
- Delete all files in `lib/events/core/query/` EXCEPT `protocols.ex`
- Change `OmQuery` to just re-export `OmQuery` with protocol registration

**Option B**: Move protocols to OmQuery
- Add protocol implementations to `libs/om_query/`
- Delete entire `lib/events/core/query/` directory

**Recommended**: Option A (less disruptive, protocols stay with Events)

```elixir
# New minimal lib/events/core/query.ex
defmodule OmQuery do
  @moduledoc "Re-exports OmQuery with CRUD protocol integration"

  # Re-export everything from OmQuery
  defdelegate new(schema), to: OmQuery
  defdelegate filter(token, field, op, value, opts \\ []), to: OmQuery
  # ... all other functions

  # Protocol implementations stay in Events
  # lib/events/core/query/protocols.ex remains
end
```

---

## Verification Commands

```bash
# After each phase
mix compile --warnings-as-errors
mix test
mix credo --strict

# Check for remaining references
grep -r "Events.Core.Crud" lib/ test/ --include="*.ex"
grep -r "Events.Api.Client.Telemetry" lib/ test/ --include="*.ex"
```

---

## Updated Usage After Migration

```elixir
# CRUD - use OmCrud directly
alias OmCrud
alias OmCrud.{Multi, Merge}

OmCrud.create(User, attrs)
Multi.new() |> Multi.create(:user, User, attrs) |> OmCrud.run()

# Query - use OmQuery directly (or OmQuery for CRUD integration)
alias OmQuery
OmQuery.new(User) |> OmQuery.filter(:active, :eq, true) |> OmQuery.execute()

# Decorators - use FnDecorator for standard, Events.Infra.Decorator for workflow
use FnDecorator  # Standard decorators
use Events.Infra.Decorator  # When you need scheduler/workflow decorators

# API Client Telemetry - use OmApiClient.Telemetry directly
alias OmApiClient.Telemetry
Telemetry.span(:my_client, fn -> ... end, %{}, [:my_app, :api])
```
