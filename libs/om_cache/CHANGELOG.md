# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `OmCache.Error` - Structured error type with protocol implementations
  - `FnTypes.Protocols.Normalizable` for error normalization
  - `FnTypes.Protocols.Recoverable` for retry detection
  - Smart constructors for common error types
- `OmCache.Helpers` - Result tuple wrappers for cache operations
  - `fetch/3` - Get with `{:ok, value} | {:error, reason}` tuples
  - `fetch!/3` - Get or raise on error
  - `put_safe/4` - Put with error handling and TTL validation
  - `delete_safe/3` - Delete with error handling
  - `get_or_fetch/4` - Cache-aside pattern with loader function
  - `fetch_batch/3` - Batch fetch with individual error tracking
  - `put_batch/3` - Batch put with error handling
  - `exists?/3` - Check key existence
  - `ttl/3` - Get remaining TTL
- `OmCache.Stats` - Cache performance metrics and statistics
  - Hit/miss ratio tracking
  - Operation latency percentiles (p50, p95, p99)
  - Memory usage tracking
  - Eviction rate monitoring
  - Error rate tracking by type
- `OmCache.Invalidation` - Cache invalidation strategies
  - Pattern-based invalidation
  - Tag-based invalidation
  - Group invalidation
  - Force expire stale entries
- `OmCache.Batch` - Enhanced batch operations
  - Parallel fetching with `AsyncResult`
  - Automatic fallback for missing keys
  - Batch warming from source
  - Redis pipeline support
- `OmCache.CircuitBreaker` - Graceful degradation
  - Auto-disable cache on repeated failures
  - Threshold-based circuit opening
  - Latency-based circuit breaker
  - Fallback to source when cache unavailable
- `OmCache.MultiLevel` - Multi-tier caching
  - L1 (process dict/ETS) and L2 (Redis) coordination
  - Automatic promotion from L2 to L1
  - Write-through to all levels
  - Consistent invalidation across levels
- `OmCache.Warming` - Cache warming utilities
  - Preload frequently accessed data
  - Batch warming with custom loaders
  - Scheduled warming with cron support
- `OmCache.TestHelpers` - Testing utilities
  - Test cache setup/teardown
  - Cache assertion helpers
  - Temporary cache disabling

### Changed

- `OmCache.Telemetry` - Enhanced telemetry integration
  - Custom event emitters for cache operations
  - Hit/miss event tracking
  - Error event tracking with categorization
  - Eviction event tracking

### Fixed

- N/A

## [0.1.0] - 2025-01-26

### Added

- Initial release
- `OmCache` macro for defining cache modules
- `OmCache.Config` - Environment-based configuration
  - Auto-adapter selection via `CACHE_ADAPTER` env var
  - Support for Redis, Local, Partitioned, Replicated, and Null adapters
  - Redis connection configuration
  - Adapter availability checking
- `OmCache.KeyGenerator` - Customizable cache key generation
  - Default implementation with smart key handling
  - Behaviour for custom implementations
- `OmCache.Telemetry` - Basic telemetry integration
  - Logger attachment for cache operations
  - Nebulex event forwarding
- Comprehensive README with examples and best practices
