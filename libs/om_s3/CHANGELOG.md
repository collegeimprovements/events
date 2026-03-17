# Changelog

All notable changes to `om_s3` will be documented in this file.

## [Unreleased]

### Added

- **Streaming Support** (`OmS3.Stream`)
  - `download/3` - Stream large objects in chunks without loading into memory
  - `download_to_file/4` - Download directly to local file
  - `download_with_callback/4` - Process chunks with a callback function
  - `upload/4` - Upload from stream/enumerable using multipart
  - `upload_file/4` - Upload local file using streaming multipart

- **Batch Result Analysis** (`OmS3.BatchResult`)
  - `summarize/1` - Get comprehensive summary with counts and success rate
  - `all_succeeded?/1`, `any_failed?/1` - Quick status checks
  - `successes/1`, `failures/1` - Extract results by status
  - `failures_by_type/1` - Group failures by error type
  - `recoverable_failures/1`, `permanent_failures/1` - Filter by recoverability
  - `retry_failures/3` - Retry failed operations with custom function
  - `format/1` - Human-readable summary string
  - `raise_on_failure!/1` - Strict mode that raises on any failure

- **Telemetry Events** (`OmS3.Telemetry`)
  - Request events: `[:om_s3, :request, :start | :stop | :exception]`
  - Batch events: `[:om_s3, :batch, :start | :stop]`
  - Stream events: `[:om_s3, :stream, :start | :chunk | :stop]`
  - `span/4`, `batch_span/3` - Instrumentation helpers
  - `attach_default_logger/1` - Built-in logging handler

- **Presigned URL Caching** (`OmS3.PresignCache`)
  - GenServer-based cache with LRU eviction
  - `key/2` - Generate cache keys with optional context
  - `preset/1` - Create decorator-compatible caching presets
  - `get_or_generate/4` - Cache-through presigned URL generation
  - `invalidate/3`, `clear/1` - Cache management
  - `stats/1` - Cache hit/miss statistics

- **S3 Transfer Acceleration** (`OmS3.Config`)
  - `transfer_acceleration: true` option for accelerated endpoints
  - `path_style: true` option for path-style URLs
  - `endpoint_url/2` - Get the resolved endpoint URL
  - `transfer_acceleration?/1` - Check if acceleration is enabled

- **Duration Utilities** (`OmS3.Duration`)
  - `to_seconds/1` - Convert duration tuples to seconds
  - `to_ms/1` - Convert duration tuples to milliseconds
  - `format/1` - Human-readable duration strings

### Changed

- Refactored duration normalization to use shared `OmS3.Duration` module
- Removed duplicate `normalize_expiration` from `OmS3` and `OmS3.Request`

### Fixed

- N/A

## [0.1.0] - Initial Release

- Dual API: Direct and Pipeline styles
- Core operations: `get`, `put`, `delete`, `copy`, `head`, `exists?`, `list`
- Batch operations: `get_all`, `put_all`, `delete_all`, `copy_all`
- Presigned URLs: `presign`, `presign_get`, `presign_put`, `presign_all`
- Glob pattern support for batch operations
- File name normalization with timestamps/UUIDs
- S3 URI utilities
- Comprehensive error handling with FnTypes protocol implementations
- LocalStack/MinIO support via custom endpoints
- HTTP proxy support
