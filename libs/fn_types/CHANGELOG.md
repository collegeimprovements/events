# Changelog

All notable changes to FnTypes will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Testing module**: Updated `assert_just/1` and `assert_nothing/1` to use correct `{:some, value}` and `:none` types (matching Maybe module)
- **README**: Fixed documentation to use `{:some, value}` / `:none` instead of `{:just, value}` / `:nothing`
- **README**: Replaced non-existent `recover_with/2` and `try_recover/2` with correct `or_else/2` usage

### Added

- **Test Coverage**: Added comprehensive tests for previously untested modules:
  - `Lazy` module - 58 tests covering deferred computation, transformations, streaming, pagination, batch processing
  - `Testing` module - 78 tests covering all assertions and helper functions
  - `SideEffects` module - 42 tests covering annotations, introspection, and composition

## [0.1.0] - 2024-01-01

### Added

- **Core Types**

  - `FnTypes.Result` - Monadic error handling with `{:ok, value}` / `{:error, reason}`
    - Transformations: `map/2`, `map_error/2`, `bimap/3`
    - Chaining: `and_then/2`, `or_else/2`
    - Extraction: `unwrap/2`, `unwrap!/1`, `unwrap_or_else/2`
    - Collections: `collect/1`, `partition/1`, `traverse/2`, `filter_ok/1`, `filter_error/1`
    - Guards: `is_ok/1`, `is_error/1` (via `FnTypes.Guards`)

  - `FnTypes.Maybe` - Optional value handling with `{:some, value}` / `:none`
    - Transformations: `map/2`, `and_then/2`, `filter/2`
    - Extraction: `unwrap_or/2`, `unwrap_or_else/2`, `to_result/2`
    - Creation: `from_nilable/1`, `some/1`, `none/0`
    - Collections: `first_some/1`, `collect/1`
    - Guards: `is_some/1`, `is_none/1` (via `FnTypes.Guards`)

  - `FnTypes.Pipeline` - Multi-step workflows with context accumulation
    - Steps: `step/3`, `step/4` with conditions, rollback support
    - Parallel: `parallel/2`, `parallel/3` for concurrent step execution
    - Branching: `branch/3`, `then_if/3`, `then_unless/3`
    - Execution: `run/1`, `run_with_rollback/1`
    - Context: `assign/3`, `update/3`, `checkpoint/2`, `resume/1`
    - Transaction support: `run_in_transaction/2`

  - `FnTypes.AsyncResult` - Concurrent operations with error handling
    - Parallel: `parallel/2`, `parallel_map/3` with max_concurrency, timeout
    - Settlement: `settle: true` option for collecting all results
    - Race: `race/2` for first successful result
    - Retry: `retry/2` with exponential backoff
    - Hedged requests: `hedge/3` for latency-sensitive operations
    - Streaming: `stream/3` for memory-efficient processing
    - Task handles: `async/1`, `await/2`

  - `FnTypes.Validation` - Accumulating validation errors
    - Field validation: `field/4` with validators
    - Nested validation: `nested/4` for embedded structures
    - Collection validation: `each/4` for list items
    - Cross-field: `check/3` for multi-field validation
    - Built-in validators: `required/0`, `min/1`, `max/1`, `format/1`, `in_list/1`
    - Combination: `all/1`, `map2/4`, `map3/5`

- **Utility Types**

  - `FnTypes.Guards` - Guard macros for pattern matching
    - `is_ok/1`, `is_error/1` for Result types
    - `is_some/1`, `is_none/1` for Maybe types

  - `FnTypes.Error` - Structured error type
    - Creation: `new/3` with type, code, and metadata
    - Wrapping: `wrap/2` for exceptions
    - Normalization: `normalize/1` for various error formats

  - `FnTypes.Lens` - Functional lenses for nested data access
    - Creation: `key/1`, `index/1`, `path/1`
    - Operations: `view/2`, `set/3`, `over/3`
    - Composition: `compose/1`, `then/2`

  - `FnTypes.NonEmptyList` - Non-empty list type with guarantees
    - Creation: `new/1`, `from_list/1`
    - Operations: `head/1`, `tail/1`, `map/2`, `reduce/2`
    - Conversion: `to_list/1`

- **Timing and Performance**

  - `FnTypes.Timing` - Execution timing and benchmarking
    - Measurement: `measure/1`, `measure!/1`, `measure_safe/1`
    - Callbacks: `timed/2`, `timed_if_slow/3`
    - Benchmarking: `benchmark/2` with statistics
    - Duration struct with unit conversions (ns, μs, ms, s)

  - `FnTypes.Retry` - Unified retry engine
    - Execution: `execute/2` with configurable options
    - Backoff strategies: exponential, linear, fixed, decorrelated, full_jitter, equal_jitter
    - Callbacks: `on_retry` for logging/metrics
    - Selective retry: `when` option for error filtering
    - Database transactions: `transaction/2`

  - `FnTypes.Backoff` - Backoff calculation strategies
    - Strategies: `exponential/2`, `linear/2`, `fixed/2`
    - Jitter: `decorrelated/2`, `full_jitter/2`, `equal_jitter/2`

- **Lazy Evaluation**

  - `FnTypes.Lazy` - Deferred computation with caching
    - Creation: `defer/1`, `pure/1`
    - Transformations: `map/2`, `and_then/2`
    - Execution: `force/1`, `force_unsafe/1`
    - Streaming: `stream/2`, `stream/3` for Result streams
    - Pagination: `paginate/4` for cursor-based iteration
    - Batching: `batch/3`, `batch_with_errors/3`

- **Rate Limiting**

  - `FnTypes.RateLimiter` - Composable rate limiting
    - Algorithms: token bucket, sliding window, fixed window
    - Operations: `check/2`, `acquire/2`, `release/2`
    - Configuration: `new/2` with customizable options

  - `FnTypes.Debouncer` - Function call debouncing
    - Leading/trailing edge debounce
    - Configurable delay

  - `FnTypes.Throttler` - Function call throttling
    - Time-window based throttling
    - Configurable rate

- **Resource Management**

  - `FnTypes.Resource` - Safe resource acquisition/release
    - Bracket pattern: `bracket/3` for guaranteed cleanup
    - Operations: `acquire/1`, `release/1`, `use/2`

- **Data Structures**

  - `FnTypes.Diff` - Structural diff for data comparison
    - Operations: `diff/2`, `patch/2`, `inverse/1`
    - Supports nested structures

  - `FnTypes.Ior` - "Inclusive Or" type (both/left/right)
    - Accumulates warnings while collecting results
    - Operations: `left/1`, `right/1`, `both/2`

- **Side Effects**

  - `FnTypes.SideEffects` - Side effect annotations
    - Annotation: `@side_effects [:db_read, :db_write, ...]`
    - Introspection: `get/3`, `list/1`, `with_effect/2`
    - Validation: `validate/1`, `pure?/3`
    - Composition: `combine/2`, `classify/1`

- **Testing Utilities**

  - `FnTypes.Testing` - ExUnit assertions for functional types
    - Result: `assert_ok/1`, `assert_ok/2`, `assert_error/1`, `assert_error/2`, `assert_error_type/2`
    - Maybe: `assert_some/1`, `assert_none/1`
    - Pipeline: `assert_pipeline_ok/1`, `assert_pipeline_error/2`
    - Collections: `assert_all_ok/1`, `assert_any_error/1`
    - Helpers: `ok_values/1`, `error_reasons/1`, `wrap_ok/1`, `wrap_error/1`
    - Mocking: `always_ok/1`, `always_error/1`, `flaky_fn/3`, `eventually_ok_fn/3`

- **Behaviours**

  - `FnTypes.Behaviours.Chainable` - Monad interface (pure, bind, map)
  - `FnTypes.Behaviours.Combinable` - Applicative interface (pure, ap, map)
  - `FnTypes.Behaviours.Mappable` - Functor interface (map)
  - `FnTypes.Behaviours.Reducible` - Foldable interface (fold_left, fold_right)
  - `FnTypes.Behaviours.Traversable` - Traverse interface (traverse, sequence)

- **Protocols**

  - `FnTypes.Protocols.Normalizable` - Error normalization protocol
  - `FnTypes.Protocols.Recoverable` - Error recovery protocol
  - `FnTypes.Protocols.Identifiable` - Entity identification protocol
  - `FnTypes.Protocols.Registry` - Protocol introspection

- **Configuration**

  - `FnTypes.Config` - Runtime configuration access
  - Telemetry integration support

### Technical Details

- Zero runtime dependencies for core types
- Comprehensive test coverage (1100+ tests)
- Dialyzer-clean codebase
- Comprehensive @spec annotations
- Detailed @moduledoc and @doc documentation
