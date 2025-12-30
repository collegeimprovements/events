# Cross-Library Functionality Duplication Report

> Generated: 2024-12-31
> Status: Pending consolidation

## Executive Summary

Analysis of all 17 libraries found **significant code duplication** in 6 major areas, with ~800-1000 lines of duplicate code that could be consolidated into ~200 lines.

---

## 1. BACKOFF/JITTER CALCULATIONS (CRITICAL - 100% IDENTICAL CODE)

### Duplicate Locations

| Function | Location 1 | Location 2 | Location 3 |
|----------|------------|------------|------------|
| `apply_jitter/2` | `fn_types/retry.ex:329-335` | `fn_types/protocols/impls/recoverable/backoff.ex:141-147` | `effect/retry.ex:154-160` |
| Exponential backoff | `fn_types/retry.ex:268-276` | `fn_types/protocols/impls/recoverable/backoff.ex:47-56` | `effect/retry.ex:106-114` |
| Decorrelated jitter | `fn_types/retry.ex:288-295` | `fn_types/protocols/impls/recoverable/backoff.ex:120-129` | `effect/retry.ex:116-124` |
| Full jitter | `fn_types/retry.ex:297-304` | `fn_types/protocols/impls/recoverable/backoff.ex:162-170` | — |
| Equal jitter | `fn_types/retry.ex:306-314` | `fn_types/protocols/impls/recoverable/backoff.ex:185-194` | — |
| Linear backoff | `fn_types/retry.ex:278-282` | `fn_types/protocols/impls/recoverable/backoff.ex:76-81` | `effect/retry.ex:100-104` |
| Fixed delay | `fn_types/retry.ex:284-286` | `fn_types/protocols/impls/recoverable/backoff.ex:97-99` | `effect/retry.ex:96-98` |

### The Exact Duplicate Code

```elixir
# IDENTICAL in 3 places:
def apply_jitter(delay, jitter) when jitter == 0.0, do: delay
def apply_jitter(delay, jitter) when jitter > 0 and jitter <= 1 do
  jitter_range = delay * jitter
  offset = :rand.uniform() * 2 * jitter_range - jitter_range
  max(0, delay + offset)
end

# IDENTICAL formula in 3 places:
delay = base * :math.pow(2, attempt - 1)  # exponential
upper = base * :math.pow(3, attempt - 1)  # decorrelated
```

### Different Jitter Implementations (Inconsistent)

| Variant | Location | Formula |
|---------|----------|---------|
| Additive jitter | FnTypes.Retry, Backoff, Effect.Retry | `delay + offset` |
| Multiplicative jitter | OmApiClient.Middleware.Retry:222-231 | `delay * jitter_factor` |
| Integer-based jitter | FnTypes.AsyncResult:994-999 | `delay + :rand.uniform(variance * 2) - variance` |

### Recommendation

Extract to single `FnTypes.Backoff` module:

```elixir
defmodule FnTypes.Backoff do
  def calculate(attempt, strategy, opts)
  def apply_jitter(delay, jitter)
  # Strategies: :exponential, :linear, :fixed, :decorrelated, :full_jitter, :equal_jitter
end
```

Update all to delegate:
- `FnTypes.Retry`
- `FnTypes.Protocols.Impls.Recoverable.Backoff`
- `Effect.Retry`
- `OmApiClient.Middleware.Retry`

---

## 2. TIMING/DURATION MEASUREMENT (DUPLICATED PATTERNS)

### FnTypes.Timing Exists But Not Used Everywhere

| Module | Pattern Used | Should Use |
|--------|--------------|------------|
| `FnDecorator.Caching.Runtime:92-94` | `System.monotonic_time()` directly | `FnTypes.Timing.measure/1` |
| `FnDecorator.Caching.Entry:78-86` | Manual `monotonic_now()` helper | `FnTypes.Timing.Duration` |
| `FnTypes.Throttler:141-148` | Manual elapsed calculation | `FnTypes.Timing.duration_since/1` |
| `FnTypes.RateLimiter:116,150+` | Raw monotonic time storage | `FnTypes.Timing.Duration` |
| `FnDecorator.Telemetry:117-133` | Reimplements slow threshold | `FnTypes.Timing.slow?/2` |
| `OmScheduler.Execution:65-66` | `queue_time_ms`, `duration_ms` fields | `FnTypes.Timing.Duration` struct |

### The Duplicated Pattern (appears 10+ times)

```elixir
# This 3-line pattern appears in EVERY telemetry module:
start_time = System.monotonic_time()
# ... operation ...
duration = System.monotonic_time() - start_time
duration_ms = System.convert_time_unit(duration, :native, :millisecond)
```

### Recommendation

All should use `FnTypes.Timing.measure/1` which already provides this.

---

## 3. TELEMETRY SPAN PATTERN (DUPLICATED 6+ TIMES)

### The Same Span Pattern Implemented Independently

| Location | Lines | Notes |
|----------|-------|-------|
| `FnTypes.Telemetry.span/3` | ~30 lines | Safe wrapper with apply/3 |
| `FnDecorator.Caching.Telemetry.span/3` | ~40 lines | Cache-specific with ETS stats |
| `OmCrud.emit_telemetry/2` | ~50 lines | CRUD operations |
| `OmQuery.Executor` | ~60 lines | Query execution |
| `OmScheduler.Telemetry.span/3` | ~50 lines | Job scheduler |
| `OmScheduler.Workflow.Telemetry.span/3` | ~50 lines | Workflow orchestration |

### The Duplicated Structure

```elixir
# This EXACT pattern in 6+ places:
def span(suffix, meta, fun) do
  start_time = System.monotonic_time()
  :telemetry.execute([...] ++ [:start], %{system_time: System.system_time()}, meta)

  try do
    result = fun.()
    duration = System.monotonic_time() - start_time
    :telemetry.execute([...] ++ [:stop], %{duration: duration}, Map.put(meta, :result, result))
    result
  rescue
    exception ->
      duration = System.monotonic_time() - start_time
      :telemetry.execute([...] ++ [:exception], %{duration: duration}, ...)
      reraise exception, __STACKTRACE__
  catch
    kind, reason ->
      duration = System.monotonic_time() - start_time
      :telemetry.execute([...] ++ [:exception], %{duration: duration}, ...)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end
end
```

### Recommendation

Enhance `FnTypes.Telemetry.span/3` as canonical implementation, all others delegate.

---

## 4. ERROR STRUCTS (4 SEPARATE IMPLEMENTATIONS)

### Overlapping Error Types

| Library | Error Type | Key Fields | Protocol Support |
|---------|------------|------------|------------------|
| **FnTypes.Error** | Comprehensive | type, code, message, details, context, source, stacktrace, id, occurred_at, recoverable, step, cause | Normalizable, Recoverable |
| **Effect.Error** | Effect-specific | step, reason, tag, context, stacktrace, attempts, duration_ms, rollback_errors, execution_id | Uses Recoverable |
| **OmQuery.Error** | Query-specific | type, message, details + 5 exception types | None |
| **Dag.Error** | Graph-specific | 7 exception types (CycleDetected, NoPath, etc.) | None |

### Duplicate Features

| Feature | FnTypes.Error | Effect.Error | OmQuery.Error |
|---------|---------------|--------------|---------------|
| `with_context/2` | ✓ | ✓ | ✗ |
| `recoverable?/1` | ✓ | ✓ (via protocol) | ✗ |
| Cause chaining | ✓ (`cause`, `root_cause/1`) | ✗ | ✗ |
| Step tracking | ✓ (`step` field) | ✓ (`step` field) | ✗ |

### Recommendation

Consider unified error protocol or have domain errors implement `FnTypes.Protocols.Normalizable`.

---

## 5. FORMAT VALIDATORS (DUPLICATED REGEX)

### Same Validators in Two Libraries

| Validator | FnTypes.Validation | OmSchema.Validators | Regex Match? |
|-----------|-------------------|---------------------|--------------|
| Email | `:875-889` | `:37-39` | **Different!** |
| URL | `:891-905` | `:41-43` | Similar |
| UUID | `:907-921` | `:45-52` | Both v4 |
| Phone | `:923-937` | `:60-67` | Similar |
| Slug | `:939-953` | `:54-58` | Similar |

### The Actual Regex Difference

```elixir
# FnTypes.Validation (email):
~r/^[^\s]+@[^\s]+\.[^\s]+$/

# OmSchema.Validators (email):
~r/^[^\s]+@[^\s]+$/  # Missing TLD requirement!
```

### Also Duplicated

- min/max/between validators
- positive/non_negative validators
- min_length/max_length validators
- inclusion/exclusion validators
- Cross-field validators

### Recommendation

Extract to `FnTypes.Formats`:

```elixir
defmodule FnTypes.Formats do
  def email_regex, do: ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  def validate_email(value)
  def validate_url(value)
  # etc.
end
```

---

## 6. OPTION VALIDATION (TWO DIFFERENT APPROACHES)

### NimbleOptions (55+ Schemas in FnDecorator)

| Module | Schema Count |
|--------|-------------|
| FnDecorator.Caching.Validation | 8 |
| FnDecorator.Telemetry | 10+ |
| FnDecorator.Types.Decorators | 7 |
| FnDecorator.Security | 3 |
| FnDecorator.Debugging | 4 |
| OmScheduler.Config | 1+ |
| **Total** | **55+** |

### Manual Validation (OmCrud)

```elixir
# OmCrud.Options - uses plain lists, no schema library
@common_opts [:repo, :prefix, :timeout, :log]
@write_opts [:returning, :stale_error_field, ...]
```

### Recommendation

Standardize on NimbleOptions or create shared schema fragments.

---

## 7. EXCEPTION WRAPPING (DUPLICATED)

| Function | Location | Purpose |
|----------|----------|---------|
| `FnTypes.Result.try_with/1-2` | `result.ex:664-693` | Wraps function, catches exceptions |
| `FnTypes.Error.wrap/2` | `error.ex:261-273` | Wraps function, normalizes to Error |

Both handle rescue, catch :throw, catch :exit.

### Recommendation

One should delegate to the other.

---

## 8. ENVIRONMENT/CONFIG PATTERNS

### FnTypes.Config Not Used Consistently

| Library | Uses FnTypes.Config? | Pattern |
|---------|---------------------|---------|
| OmCache.Config | No | Direct `System.get_env` |
| OmS3.Config | No | Direct `System.get_env` |
| OmKillSwitch | No | Direct `System.get_env` |
| OmHealth.Environment | No | Direct `System.get_env` |
| OmScheduler.Config | No | NimbleOptions + Application.get_env |

### Recommendation

Use `FnTypes.Config` for consistent env var handling (fallback chains, trimming, type parsing).

---

## Priority Summary

### Critical (100% Code Duplication)

| Duplication | Files Affected | Suggested Module |
|-------------|----------------|------------------|
| Backoff strategies | 4 files | `FnTypes.Backoff` |
| Jitter calculations | 4 files | `FnTypes.Backoff.jitter/2` |
| Telemetry span | 6+ files | `FnTypes.Telemetry.span/3` |

### High (Significant Overlap)

| Duplication | Files Affected | Action |
|-------------|----------------|--------|
| Format validators | 2 libs | Extract to `FnTypes.Formats` |
| Timing measurement | 10+ places | Use `FnTypes.Timing` |
| Error structs | 4 libs | Create unified protocol |

### Medium (Different Approaches)

| Area | Issue | Action |
|------|-------|--------|
| Option validation | NimbleOptions vs manual | Standardize on NimbleOptions |
| Config access | FnTypes.Config vs System.get_env | Use FnTypes.Config |
| Exception wrapping | Result.try_with vs Error.wrap | One delegates to other |

---

## Statistics

| Category | Duplicate Instances | Lines of Duplicate Code | Priority |
|----------|--------------------|-----------------------|----------|
| Backoff/Jitter | 4 files × 7 functions | ~200 lines | **CRITICAL** |
| Telemetry Span | 6+ files | ~300 lines | **HIGH** |
| Timing Pattern | 10+ places | ~50 lines each | **HIGH** |
| Format Validators | 2 libs × 5 validators | ~100 lines | **HIGH** |
| Error Structs | 4 separate types | Overlap in design | **MEDIUM** |
| Exception Wrapping | 2 functions | ~60 lines | **LOW** |

**Total:** ~800-1000 lines that could be consolidated into ~200 lines.

---

## Consolidation Plan

### Phase 1: Extract FnTypes.Backoff (CRITICAL)

Create `fn_types/lib/fn_types/backoff.ex`, update all 4 files to delegate.

### Phase 2: Centralize Telemetry Span

Enhance `FnTypes.Telemetry.span/3`, update 6+ implementations.

### Phase 3: Extract Format Validators

Create `FnTypes.Formats`, update both validation libraries.

### Phase 4: Standardize Config Access

Update all libraries to use `FnTypes.Config`.
