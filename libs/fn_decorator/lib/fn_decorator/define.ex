defmodule FnDecorator.Define do
  @moduledoc """
  Defines and registers all decorators.

  This module uses the `Decorator.Define` macro from the `decorator` library
  to register decorators that can be used with the `@decorate` attribute.

  ## Usage

      defmodule MyModule do
        use FnDecorator

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

  ### Types
  - `returns_result/1` - Enforce Result type
  - `returns_maybe/1` - Enforce Maybe type
  - `returns_bang/1` - Convert to bang function
  - `normalize_result/1` - Normalize errors
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
    # Additional decorators
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
    mock: 1,
    # Type decorators
    returns_result: 1,
    returns_maybe: 1,
    returns_bang: 1,
    returns_struct: 1,
    returns_list: 1,
    returns_union: 1,
    returns_pipeline: 1,
    normalize_result: 1

  # Caching decorators
  defdelegate cacheable(opts, body, context), to: FnDecorator.Caching
  defdelegate cache_put(opts, body, context), to: FnDecorator.Caching
  defdelegate cache_evict(opts, body, context), to: FnDecorator.Caching

  # Telemetry decorators
  defdelegate telemetry_span(opts, body, context), to: FnDecorator.Telemetry
  defdelegate telemetry_span(event, opts, body, context), to: FnDecorator.Telemetry
  defdelegate otel_span(opts, body, context), to: FnDecorator.Telemetry
  defdelegate otel_span(name, opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_call(opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_context(fields, body, context), to: FnDecorator.Telemetry
  defdelegate log_if_slow(opts, body, context), to: FnDecorator.Telemetry
  defdelegate track_memory(opts, body, context), to: FnDecorator.Telemetry
  defdelegate capture_errors(opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_query(opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_remote(opts, body, context), to: FnDecorator.Telemetry
  defdelegate benchmark(opts, body, context), to: FnDecorator.Telemetry
  defdelegate measure(opts, body, context), to: FnDecorator.Telemetry

  # Debugging decorators
  defdelegate debug(opts, body, context), to: FnDecorator.Debugging
  defdelegate inspect(opts, body, context), to: FnDecorator.Debugging
  defdelegate pry(opts, body, context), to: FnDecorator.Debugging
  defdelegate trace_vars(opts, body, context), to: FnDecorator.Debugging

  # Tracing decorators
  defdelegate trace_calls(opts, body, context), to: FnDecorator.Tracing
  defdelegate trace_modules(opts, body, context), to: FnDecorator.Tracing
  defdelegate trace_dependencies(opts, body, context), to: FnDecorator.Tracing

  # Purity decorators
  defdelegate pure(opts, body, context), to: FnDecorator.Purity
  defdelegate deterministic(opts, body, context), to: FnDecorator.Purity
  defdelegate idempotent(opts, body, context), to: FnDecorator.Purity
  defdelegate memoizable(opts, body, context), to: FnDecorator.Purity

  # Testing decorators
  defdelegate with_fixtures(opts, body, context), to: FnDecorator.Testing
  defdelegate sample_data(opts, body, context), to: FnDecorator.Testing
  defdelegate timeout_test(opts, body, context), to: FnDecorator.Testing
  defdelegate mock(opts, body, context), to: FnDecorator.Testing

  # Pipeline decorators
  defdelegate pipe_through(pipeline, body, context), to: FnDecorator.Pipeline
  defdelegate around(wrapper, body, context), to: FnDecorator.Pipeline
  defdelegate compose(decorators, body, context), to: FnDecorator.Pipeline

  # Type decorators
  defdelegate returns_result(opts, body, context), to: FnDecorator.Types
  defdelegate returns_maybe(opts, body, context), to: FnDecorator.Types
  defdelegate returns_bang(opts, body, context), to: FnDecorator.Types
  defdelegate returns_struct(opts, body, context), to: FnDecorator.Types
  defdelegate returns_list(opts, body, context), to: FnDecorator.Types
  defdelegate returns_union(opts, body, context), to: FnDecorator.Types
  defdelegate returns_pipeline(opts, body, context), to: FnDecorator.Types
  defdelegate normalize_result(opts, body, context), to: FnDecorator.Types
end
