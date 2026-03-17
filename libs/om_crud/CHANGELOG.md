# Changelog

All notable changes to `om_crud` will be documented in this file.

## [Unreleased]

### Added

- **Rich Error Types** (`OmCrud.Error`)
  - Structured error information with type, schema, operation, and field details
  - Smart constructors: `not_found/3`, `from_changeset/2`, `constraint_violation/3`, `validation_error/3`, `step_failed/3`, `transaction_error/2`, `stale_entry/3`
  - Message generation with `message/1`
  - HTTP status mapping with `to_http_status/1`
  - JSON-friendly conversion with `to_map/1`
  - Query helpers: `is_type?/2`, `on_field?/2`

- **Atomic Operations Helper** (`OmCrud.Atomic`)
  - `atomic/1`, `atomic/2` - Execute functions in database transactions
  - `atomic_with_context/2`, `atomic_with_context/3` - Execute with initial context
  - `step!/1`, `step!/2` - Unwrap results, raise on error with step names
  - `step/2` - Non-raising step that returns result tuple with step context
  - `optional_step!/2` - Unwrap results, return `nil` for `:not_found` errors
  - `run_step/2` - Execute step function, return result tuple
  - `accumulate/3` - Build up context across steps
  - `accumulate_optional/3` - Accumulate with `nil` for not_found
  - `finalize/1`, `finalize/2` - Wrap accumulated context in success tuple
  - Telemetry events: `[:om_crud, :atomic, :start|:stop|:exception]`
  - Transaction modes: `:read_only`, `:read_write` via `:mode` option
  - Logger warning on unexpected return values

- **Single-Record Upsert** (`OmCrud.upsert/3`)
  - Convenience function for single-record upserts
  - Supports `:conflict_target`, `:on_conflict`, `:changeset`, `:returning`, `:preload` options

- **Soft Delete Support** (`OmCrud.SoftDelete`)
  - `delete/2`, `delete/3` - Soft delete by setting `deleted_at`
  - `restore/2`, `restore/3` - Restore soft-deleted records
  - `multi_delete/4`, `multi_restore/4` - Multi integration
  - Query helpers: `exclude_deleted/2`, `only_deleted/2`
  - Predicates: `deleted?/2`, `deleted_at/2`
  - Configurable field name (default: `:deleted_at`)

- **Batch Operations** (`OmCrud.Batch`)
  - `each/3` - Process records in batches with callback
  - `process/3` - Process with result tracking and error handling
  - `update/3` - Batch updates with transformation function
  - `delete/2` - Batch deletions
  - `create_all/3` - Chunked inserts for large datasets
  - `upsert_all/3` - Chunked upserts
  - `stream/2`, `stream_chunks/2` - Memory-efficient streaming
  - `parallel/3` - Concurrent batch processing
  - Error handling strategies: `:halt`, `:continue`, `:collect`

- **Conditional Multi Helpers** (`OmCrud.Multi`)
  - `when_cond/3` - Conditionally add operations based on predicate
  - `unless/3` - Conditionally skip operations
  - `branch/4` - Choose between two operation sets
  - `each/4` - Iterate over list and add operations
  - `when_value/4` - Execute based on previous result value
  - `when_match/4` - Execute based on pattern matching previous result

## [0.1.0] - Initial Release

- Token-based transaction builder (`OmCrud.Multi`)
- PostgreSQL MERGE support (`OmCrud.Merge`)
- Unified execution API (`OmCrud.run/1`)
- Convenience functions: `create/3`, `update/3`, `delete/2`, `fetch/3`
- Bulk operations: `create_all/3`, `upsert_all/3`, `update_all/3`, `delete_all/2`
- Query execution: `fetch_all/2`, `count/1`, `exists?/2`
- Context macro for generating CRUD functions
- Telemetry integration
