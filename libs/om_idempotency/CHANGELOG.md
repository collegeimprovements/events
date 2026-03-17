# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **OmSchema integration** - Replaced `Ecto.Schema` with `OmSchema` for enhanced schema features
- **OmMigration integration** - Replaced `Ecto.Migration` with `OmMigration` for enhanced migrations
- **FnTypes protocols** - Implemented `Recoverable`, `Identifiable`, and `Normalizable` protocols for Record
- **FnDecorator support** - Added decorators for telemetry, logging, and type safety
  - `@decorate returns_result` for type-safe result tuples
  - `@decorate telemetry_span` for automatic telemetry instrumentation
  - `@decorate log_if_slow` for performance monitoring
- **OmCrud.Multi integration** - Batch operations using transactions
- **OmQuery integration** - Query helpers for common operations
- **Batch operations module** (`OmIdempotency.Batch`)
  - `create_all/2` - Bulk create multiple records
  - `complete_all/2` - Complete multiple records in a transaction
  - `fail_all/2` - Fail multiple records in a transaction
  - `check_many/2` - Check multiple keys in parallel
  - `execute_all/2` - Execute multiple operations in parallel
  - `release_all/2` - Release multiple locks
  - `delete_by_ids/2` - Bulk delete records
- **Query helpers module** (`OmIdempotency.Query`)
  - `list_by_state/2` - List records by state
  - `list_stale_processing/1` - Find stale processing records
  - `list_expired/1` - Find expired records
  - `stats/1` - Get statistics grouped by state
  - `stats_by_scope/1` - Get statistics grouped by scope
  - `list_older_than/2` - Find records older than given age
  - `search_by_key/2` - Search records by key pattern
- **Enhanced error handling** (`OmIdempotency.Error`)
  - Structured error types using FnTypes.Error
  - Better error messages with metadata
- **Custom validators** (`OmIdempotency.Validators`)
  - TTL validation
  - State transition validation
  - Lock timeout validation
  - Response/error state validation
- **Health check module** (`OmIdempotency.HealthCheck`)
  - Database connectivity checks
  - Stale record monitoring
  - Expired record monitoring
  - Overall system statistics
- **Middleware module** (`OmIdempotency.Middleware`)
  - Plug support for Phoenix applications
  - OmMiddleware support for request pipelines
  - Req library integration
  - Automatic key extraction and generation
- **AsyncResult integration** - Parallel execution of idempotent operations
- **Telemetry improvements** - Better telemetry integration using FnDecorator.Telemetry.Helpers

### Changed

- **Schema** - Now uses `OmSchema` instead of `Ecto.Schema`
- **Migration** - Now uses `OmMigration` instead of `Ecto.Migration`
- **Improved type specs** - More precise type specifications throughout
- **Better error messages** - Structured errors with context and metadata

### Deprecated

- None

### Removed

- None

### Fixed

- None

### Security

- None

## [0.1.0] - 2024-XX-XX

### Added

- Initial release
- Database-backed idempotency key management
- Support for pending, processing, completed, and failed states
- Optimistic locking for concurrent request handling
- Configurable TTL and lock timeouts
- Telemetry events
- Recovery scheduler for stale records
- Cleanup utilities for expired records
- Request and Response behaviours for middleware integration

[Unreleased]: https://github.com/outermagic/om_idempotency/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/outermagic/om_idempotency/releases/tag/v0.1.0
