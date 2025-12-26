# Test Migration Plan: Events to Libs

## Overview

This document outlines the plan to migrate tests from the Events application to their respective standalone libraries. The goal is to make each lib self-contained with its own comprehensive test suite.

## Current State

### Libs with Tests
| Lib | Test Files | Coverage |
|-----|------------|----------|
| `dag` | 4 | Good |
| `effect` | 1 | Basic |
| `fn_decorator` | 4 | Good |
| `fn_types` | 17 | Excellent |
| `om_crud` | 7 | Good |
| `om_field_names` | 1 | Basic |
| `om_health` | 3 | Good (new) |
| `om_idempotency` | 0 | Needs tests |
| `om_kill_switch` | 0 | Needs tests |
| `om_migration` | 2 | Basic |
| `om_query` | 1 | Minimal |
| `om_s3` | 4 | Good (new) |
| `om_scheduler` | 0 | Needs tests |
| `om_schema` | 5 | Good |

### Events Tests to Migrate

```
test/
├── schema/                  # 12 files -> om_schema
├── events/query/            # 7 files  -> om_query
├── events/api_client/       # 4 files  -> om_api_client
├── events/scheduler/        # 9 files  -> om_scheduler
├── events/idempotency_test.exs  -> om_idempotency
├── events/kill_switch/      # 1 file   -> om_kill_switch
└── events/crud_test.exs     # Keep in Events (integration)
```

---

## Phase 1: Query Tests (Priority: High)

**Target**: `libs/om_query`
**Events Tests**: `test/events/query/`

### Files to Migrate
1. `syntax_test.exs` - Query DSL syntax
2. `params_test.exs` - Parameter handling
3. `helpers_test.exs` - Query helpers
4. `cursor_inference_test.exs` - Cursor pagination
5. `execution_test.exs` - Query execution (may need Repo mock)
6. `dynamic_builder_formats_test.exs` - Dynamic query building
7. `pagination_validator_test.exs` - Pagination validation

### Migration Steps
1. Create `libs/om_query/test/om_query/` directory structure
2. Copy tests, update module aliases (`Events.Core.Query` -> `OmQuery`)
3. Remove `Events.TestCase` dependency, use plain `ExUnit.Case`
4. Create inline test schemas (already done in some tests)
5. Mock or stub Repo for execution tests
6. Run `cd libs/om_query && mix test`

### Estimated Effort
- Pure unit tests: Low effort
- Execution tests: Medium effort (need Repo abstraction)

---

## Phase 2: API Client Tests (Priority: High)

**Target**: `libs/om_api_client`
**Events Tests**: `test/events/api_client/`

### Files to Migrate
1. `request_test.exs` - Request building
2. `response_test.exs` - Response handling
3. `auth_test.exs` - Authentication
4. `middleware_test.exs` - Middleware chain

### Migration Steps
1. Create `libs/om_api_client/test/om_api_client/` directory
2. Copy tests, update aliases (`Events.Api.Client.*` -> `OmApiClient.*`)
3. These are mostly pure unit tests, should be straightforward
4. Run `cd libs/om_api_client && mix test`

### Estimated Effort: Low

---

## Phase 3: Scheduler/Workflow Tests (Priority: Medium)

**Target**: `libs/om_scheduler`
**Events Tests**: `test/events/scheduler/workflow/`

### Files to Migrate
1. `workflow_test.exs` - Workflow DSL
2. `step_test.exs` - Step definitions
3. `execution_test.exs` - Workflow execution
4. `state_machine_test.exs` - State transitions
5. `registry_test.exs` - Workflow registry
6. `store_test.exs` - State persistence
7. `telemetry_test.exs` - Telemetry events
8. `step/executable_test.exs` - Step execution

### Migration Steps
1. Create test directory structure
2. Copy tests, update module aliases
3. Create in-memory store for tests (no Repo dependency)
4. Mock telemetry events
5. Run `cd libs/om_scheduler && mix test`

### Estimated Effort: Medium-High (complex state management)

---

## Phase 4: Schema Tests (Priority: Medium)

**Target**: `libs/om_schema`
**Events Tests**: `test/schema/`

### Files to Migrate
1. `date_presets_test.exs` - Date field presets
2. `string_presets_test.exs` - String presets
3. `presets_extended_test.exs` - Extended presets
4. `field_level_validation_test.exs` - Field validation
5. `field_mappers_test.exs` - Field mappers
6. `mappers_test.exs` - General mappers
7. `number_enhancements_test.exs` - Number fields
8. `enhanced_field_test.exs` - Enhanced fields
9. `enhanced_field_phase2_test.exs` - Phase 2 enhancements
10. `schema_field_override_test.exs` - Override behavior
11. `schema_override_test.exs` - Schema overrides
12. `slug_uniqueness_test.exs` - Slug validation

### Migration Steps
1. Check which tests are Events-specific vs generic
2. Migrate generic preset/validator tests
3. Keep Events-specific tests in Events
4. Run `cd libs/om_schema && mix test`

### Estimated Effort: Medium (need to analyze each test)

---

## Phase 5: Infrastructure Tests (Priority: Low)

### om_idempotency
**Events Tests**: `test/events/idempotency_test.exs`
- Create basic tests for IdempotencyKey generation
- Test key format and uniqueness

### om_kill_switch
**Events Tests**: `test/events/kill_switch/cache_test.exs`
- Test switch state management
- Test cache integration

### Estimated Effort: Low

---

## Migration Guidelines

### 1. Test Structure
```elixir
# Before (Events)
defmodule Events.Core.Query.SyntaxTest do
  use Events.TestCase, async: true
  alias Events.Core.Query

  # Uses Events test support
end

# After (Lib)
defmodule OmQuery.SyntaxTest do
  use ExUnit.Case, async: true
  alias OmQuery

  # Self-contained, no Events dependencies
end
```

### 2. Handling Database Dependencies
```elixir
# Option A: In-memory mock
defmodule TestRepo do
  def all(_query), do: []
  def one(_query), do: nil
end

# Option B: Configurable repo
OmQuery.execute(query, repo: TestRepo)
```

### 3. Test Schema Patterns
```elixir
# Define inline test schemas
defmodule User do
  use Ecto.Schema
  schema "users" do
    field :name, :string
    field :email, :string
  end
end
```

### 4. Removing Events.TestCase
Replace with:
```elixir
use ExUnit.Case, async: true

# If needed for setup
setup do
  # Setup code here
  :ok
end
```

---

## Success Criteria

1. Each lib passes `mix test` independently
2. No Events.* imports in lib tests
3. `mix test.libs` passes with all libs
4. Main `mix test` still passes (may have fewer tests)
5. No duplicate tests between Events and libs

---

## Commands

```bash
# Test individual lib
cd libs/om_query && mix test

# Test all libs
mix test.libs

# Test main project
mix test

# Verify no regressions
mix test && mix test.libs
```

---

## Timeline Recommendation

| Phase | Libs | Priority | Complexity |
|-------|------|----------|------------|
| 1 | om_query | High | Medium |
| 2 | om_api_client | High | Low |
| 3 | om_scheduler | Medium | High |
| 4 | om_schema | Medium | Medium |
| 5 | om_idempotency, om_kill_switch | Low | Low |

Start with Phase 1-2 for quick wins, then tackle Phase 3-4 for deeper coverage.
