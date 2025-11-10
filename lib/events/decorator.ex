defmodule Events.Decorator do
  @moduledoc """
  Main entry point for using decorators in the Events application.

  This module provides a unified interface for applying decorators to functions
  using the `@decorate` attribute. It combines caching, telemetry, debugging,
  tracing, purity checking, testing helpers, and advanced composition patterns
  in a clean, composable way.

  ## Usage

      defmodule MyApp.Users do
        use Events.Decorator

        @decorate cacheable(cache: Cache, key: {User, id})
        @decorate telemetry_span([:my_app, :users, :get])
        @decorate log_if_slow(threshold: 1000)
        def get_user(id) do
          Repo.get(User, id)
        end
      end

  ## Features

  - **Caching**: Read-through, write-through, and cache eviction
  - **Telemetry & Logging**: Erlang telemetry, OpenTelemetry spans, structured logging, query logging, remote logging
  - **Performance**: Benchmarking, measurement, slow operation monitoring, memory tracking
  - **Debugging**: Interactive debugging with pry, inspect, and dbg integration
  - **Tracing**: Function call tracing, module dependency tracking
  - **Purity**: Function purity verification, determinism checking, idempotence testing
  - **Testing**: Fixture management, test data generation, mocking support
  - **Composition**: Combine multiple decorators seamlessly

  ## Decorator Categories

  ### Caching Decorators

  - `@decorate cacheable(opts)` - Cache function results
  - `@decorate cache_put(opts)` - Update cache with function results
  - `@decorate cache_evict(opts)` - Remove entries from cache

  ### Telemetry & Logging Decorators

  - `@decorate telemetry_span(event, opts)` - Emit telemetry events
  - `@decorate otel_span(name, opts)` - Create OpenTelemetry spans
  - `@decorate log_call(level, opts)` - Log function calls
  - `@decorate log_context(fields)` - Set Logger metadata
  - `@decorate log_if_slow(opts)` - Log slow operations
  - `@decorate log_query(opts)` - Log database queries with timing
  - `@decorate log_remote(opts)` - Send logs to remote service
  - `@decorate track_memory(opts)` - Track memory usage
  - `@decorate capture_errors(opts)` - Capture and report errors

  ### Performance Decorators

  - `@decorate benchmark(opts)` - Comprehensive benchmarking with statistics
  - `@decorate measure(opts)` - Simple execution time measurement

  ### Debugging Decorators (Dev/Test Only)

  - `@decorate debug(opts)` - Use Elixir's dbg/2 for detailed debugging
  - `@decorate inspect(opts)` - Inspect arguments and/or results
  - `@decorate pry(opts)` - Interactive breakpoints with IEx.pry
  - `@decorate trace_vars(opts)` - Trace variable changes

  ### Tracing Decorators (Dev/Test Only)

  - `@decorate trace_calls(opts)` - Trace all function calls during execution
  - `@decorate trace_modules(opts)` - Track which modules are called
  - `@decorate trace_dependencies(opts)` - Trace external library usage

  ### Purity Decorators

  - `@decorate pure(opts)` - Mark and verify function purity
  - `@decorate deterministic(opts)` - Verify deterministic behavior
  - `@decorate idempotent(opts)` - Verify idempotence
  - `@decorate memoizable(opts)` - Mark as safe to memoize

  ### Testing Decorators

  - `@decorate with_fixtures(opts)` - Automatic fixture loading
  - `@decorate sample_data(opts)` - Generate test data
  - `@decorate timeout_test(opts)` - Enforce test timeouts
  - `@decorate mock(opts)` - Mock module functions

  ### Advanced Decorators

  - `@decorate pipe_through(pipeline)` - Apply function pipeline
  - `@decorate around(wrapper)` - Around advice pattern
  - `@decorate compose(decorators)` - Compose multiple decorators

  ## Examples

      # Simple caching
      @decorate cacheable(cache: MyCache, key: id, ttl: 3600)
      def get_user(id) do
        Repo.get(User, id)
      end

      # Multiple decorators
      @decorate cacheable(cache: MyCache, key: {User, id})
      @decorate telemetry_span([:app, :get_user])
      @decorate log_if_slow(threshold: 1000)
      def get_user(id) do
        Repo.get(User, id)
      end

      # Write-through caching
      @decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
      @decorate telemetry_span([:app, :update_user])
      def update_user(user, attrs) do
        user
        |> User.changeset(attrs)
        |> Repo.update()
      end

      defp match_ok({:ok, result}), do: {true, result}
      defp match_ok(_), do: false

      # Cache invalidation
      @decorate cache_evict(cache: MyCache, keys: [{User, id}])
      def delete_user(id) do
        Repo.delete(User, id)
      end

      # Structured logging with context
      @decorate log_context([:user_id, :request_id])
      def handle_request(user_id, request_id, params) do
        # All logs in this function will include user_id and request_id
        Logger.info("Processing request")
        # ...
      end

  ## Configuration

  Decorators can be configured in your application config:

      config :events, Events.Decorator,
        telemetry_enabled: true,
        default_cache: Events.Cache,
        log_level: :info

  ## Best Practices

  1. **Order matters**: Decorators are applied from bottom to top
  2. **Keep it simple**: Use decorators for cross-cutting concerns
  3. **Pattern match**: Leverage pattern matching in match functions
  4. **Test thoroughly**: Each decorator should be tested independently
  5. **Document usage**: Add examples to your function docs

  ## Performance

  All decorators are applied at compile time, resulting in zero runtime overhead
  for the decorator mechanism itself. The only overhead is from the actual
  functionality (cache lookups, telemetry events, etc.).
  """

  @doc """
  Sets up decorator support for a module.

  When you `use Events.Decorator`, it:
  - Imports the decorator definition module
  - Enables the `@decorate` attribute
  - Provides access to all decorator utilities
  """
  defmacro __using__(_opts) do
    quote do
      use Events.Decorator.Define

      # Make AST utilities available for advanced use cases
      alias Events.Decorator.AST
      alias Events.Decorator.Context
    end
  end
end
