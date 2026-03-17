# Changelog

All notable changes to `fn_decorator` will be documented in this file.

## [Unreleased]

### Added

- **Decorator Composition Helpers** (`FnDecorator.Compose`)
  - `defpreset/2`, `defpreset/3` - Define reusable decorator bundles
  - `merge/1` - Merge multiple decorator lists
  - `when_env/2`, `unless_env/2` - Environment-specific decorators
  - `when_true/2` - Conditional decorator application
  - `with_metadata/2` - Attach metadata to decorators
  - `build/1` - Build decorator specs with environment awareness
  - `wrap/2` - Wrap decorators with before/after hooks
  - `define_bundle/2` - Create reusable decorator bundle modules
  - `validate!/1` - Validate decorator specifications
  - `describe/1` - Human-readable decorator summary

- **OpenTelemetry Context Propagation** (`FnDecorator.OpenTelemetry`)
  - `current_context/0`, `attach_context/1` - Context management
  - `async_with_context/1` - Task.async with context propagation
  - `async_stream_with_context/3` - Task.async_stream with context
  - `parallel_with_context/2` - Run functions in parallel with context
  - `with_span/3`, `with_linked_span/3` - Span creation utilities
  - `set_baggage/2`, `get_baggage/1`, `get_all_baggage/0` - Baggage management
  - `extract_from_headers/1`, `inject_into_headers/1` - HTTP header propagation
  - `set_attribute/2`, `set_attributes/1` - Span attribute helpers
  - `record_exception/2`, `add_event/2`, `set_status/2` - Span events
  - `call_with_context/3`, `cast_with_context/2` - GenServer context propagation
  - `to_carrier/0`, `from_carrier/1` - Manual context serialization

- **OpenTelemetry Decorators** (`FnDecorator.OpenTelemetry.Decorators`)
  - `@decorate propagate_context()` - Capture context for async propagation
  - `@decorate with_baggage(%{key: :arg})` - Set baggage from arguments
  - `@decorate otel_span_advanced(opts)` - Advanced span with attribute extraction

### Changed

- Updated `FnDecorator.Registry` to include new OpenTelemetry decorators
- Updated `FnDecorator.Define` to register new decorators

## [0.1.0] - Initial Release

- 40+ decorators across 9 categories
- Caching: `cacheable`, `cache_put`, `cache_evict`
- Telemetry: `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`
- Security: `role_required`, `rate_limit`, `audit_log`
- Debugging: `debug`, `inspect`, `pry`, `trace_vars`
- Tracing: `trace_calls`, `trace_modules`, `trace_dependencies`
- Purity: `pure`, `deterministic`, `idempotent`, `memoizable`
- Testing: `with_fixtures`, `sample_data`, `timeout_test`, `mock`
- Types: `returns_result`, `returns_maybe`, `returns_bang`, `normalize_result`
- Pipeline: `pipe_through`, `around`, `compose`
- Performance: `benchmark`, `measure`, `track_memory`
- Error handling: `capture_errors`
- Logging: `log_query`, `log_remote`
