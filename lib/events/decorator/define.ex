defmodule Events.Decorator.Define do
  @moduledoc """
  Defines and registers all decorators for the Events application.

  This module uses the `Decorator.Define` macro from the `decorator` library
  to register decorators that can be used with the `@decorate` attribute.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate cacheable(cache: MyCache, key: id)
        def get_user(id) do
          # ...
        end
      end

  ## Available Decorators

  ### Caching
  - `cacheable/1` - Read-through caching
  - `cache_put/1` - Write-through caching
  - `cache_evict/1` - Cache invalidation

  ### Telemetry
  - `telemetry_span/1`, `telemetry_span/2` - Erlang telemetry events
  - `otel_span/1`, `otel_span/2` - OpenTelemetry spans
  - `log_call/0`, `log_call/1`, `log_call/2` - Function call logging
  - `log_context/1` - Set Logger metadata
  - `log_if_slow/1` - Performance monitoring
  - `track_memory/1` - Memory profiling
  - `capture_errors/1` - Error tracking

  ### Advanced
  - `pipe_through/1` - Pipeline composition
  - `around/1` - Around advice
  - `compose/1` - Decorator composition
  """

  use Decorator.Define,
    # Caching
    cacheable: 1,
    cache_put: 1,
    cache_evict: 1,
    # Telemetry
    telemetry_span: 1,
    telemetry_span: 2,
    log_call: 1,
    log_context: 1,
    log_if_slow: 1,
    # Performance
    benchmark: 1,
    measure: 1,
    # Debugging
    debug: 1,
    inspect: 1,
    pry: 1,
    # Pipeline
    pipe_through: 1,
    around: 1,
    compose: 1,
    # Additional decorators preserved for compatibility
    otel_span: 1,
    otel_span: 2,
    track_memory: 1,
    capture_errors: 1,
    log_query: 1,
    log_remote: 1,
    trace_vars: 1,
    trace_calls: 1,
    trace_modules: 1,
    trace_dependencies: 1,
    pure: 1,
    deterministic: 1,
    idempotent: 1,
    memoizable: 1,
    with_fixtures: 1,
    sample_data: 1,
    timeout_test: 1,
    mock: 1

  # Delegate to consolidated decorators module
  defdelegate cacheable(opts, body, context), to: Events.Decorators
  defdelegate cache_put(opts, body, context), to: Events.Decorators
  defdelegate cache_evict(opts, body, context), to: Events.Decorators

  defdelegate telemetry_span(opts, body, context), to: Events.Decorators
  defdelegate telemetry_span(event, opts, body, context), to: Events.Decorators
  defdelegate otel_span(opts, body, context), to: Events.Decorator.Telemetry
  defdelegate otel_span(name, opts, body, context), to: Events.Decorator.Telemetry
  defdelegate log_call(opts, body, context), to: Events.Decorators
  defdelegate log_context(fields, body, context), to: Events.Decorators
  defdelegate log_if_slow(opts, body, context), to: Events.Decorators
  defdelegate track_memory(opts, body, context), to: Events.Decorator.Telemetry
  defdelegate capture_errors(opts, body, context), to: Events.Decorator.Telemetry
  defdelegate log_query(opts, body, context), to: Events.Decorator.Telemetry
  defdelegate log_remote(opts, body, context), to: Events.Decorator.Telemetry
  defdelegate benchmark(opts, body, context), to: Events.Decorators
  defdelegate measure(opts, body, context), to: Events.Decorators

  defdelegate debug(opts, body, context), to: Events.Decorators
  defdelegate inspect(opts, body, context), to: Events.Decorators
  defdelegate pry(opts, body, context), to: Events.Decorators
  defdelegate trace_vars(opts, body, context), to: Events.Decorator.Debugging

  defdelegate trace_calls(opts, body, context), to: Events.Decorator.Tracing
  defdelegate trace_modules(opts, body, context), to: Events.Decorator.Tracing
  defdelegate trace_dependencies(opts, body, context), to: Events.Decorator.Tracing

  defdelegate pure(opts, body, context), to: Events.Decorator.Purity
  defdelegate deterministic(opts, body, context), to: Events.Decorator.Purity
  defdelegate idempotent(opts, body, context), to: Events.Decorator.Purity
  defdelegate memoizable(opts, body, context), to: Events.Decorator.Purity

  defdelegate with_fixtures(opts, body, context), to: Events.Decorator.Testing
  defdelegate sample_data(opts, body, context), to: Events.Decorator.Testing
  defdelegate timeout_test(opts, body, context), to: Events.Decorator.Testing
  defdelegate mock(opts, body, context), to: Events.Decorator.Testing

  defdelegate pipe_through(pipeline, body, context), to: Events.Decorators
  defdelegate around(wrapper, body, context), to: Events.Decorators
  defdelegate compose(decorators, body, context), to: Events.Decorators
end
