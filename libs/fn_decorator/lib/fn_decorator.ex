defmodule FnDecorator do
  @moduledoc """
  Main entry point for using decorators.

  This module provides a unified interface for applying decorators to functions
  using the `@decorate` attribute. It combines caching, telemetry, debugging,
  tracing, purity checking, testing helpers, and advanced composition patterns
  in a clean, composable way.

  ## Usage

      defmodule MyApp.Users do
        use FnDecorator

        @decorate cacheable(cache: Cache, key: {User, id})
        @decorate telemetry_span([:my_app, :users, :get])
        @decorate log_if_slow(threshold: 1000)
        def get_user(id) do
          Repo.get(User, id)
        end
      end

  ## Features

  - **Caching**: Read-through, write-through, and cache eviction
  - **Telemetry & Logging**: Erlang telemetry, OpenTelemetry spans, structured logging
  - **Performance**: Benchmarking, measurement, slow operation monitoring
  - **Debugging**: Interactive debugging with pry, inspect, and dbg integration
  - **Tracing**: Function call tracing, module dependency tracking
  - **Purity**: Function purity verification, determinism checking
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

  ### Type Decorators

  - `@decorate returns_result(opts)` - Enforce Result type returns
  - `@decorate returns_maybe(opts)` - Enforce Maybe type returns
  - `@decorate returns_bang(opts)` - Convert to bang (raising) function
  - `@decorate normalize_result(opts)` - Normalize errors to Error struct

  ## Configuration

  Decorators can be configured in your application config:

      config :fn_decorator,
        telemetry_enabled: true,
        log_level: :info

  ## Best Practices

  1. **Order matters**: Decorators are applied from bottom to top
  2. **Keep it simple**: Use decorators for cross-cutting concerns
  3. **Pattern match**: Leverage pattern matching in match functions
  4. **Test thoroughly**: Each decorator should be tested independently

  ## Performance

  All decorators are applied at compile time, resulting in zero runtime overhead
  for the decorator mechanism itself. The only overhead is from the actual
  functionality (cache lookups, telemetry events, etc.).
  """

  @doc """
  Sets up decorator support for a module.

  When you `use FnDecorator`, it:
  - Imports the decorator definition module
  - Enables the `@decorate` attribute
  - Provides access to all decorator utilities
  """
  defmacro __using__(_opts) do
    quote do
      use FnDecorator.Define

      # Make utilities available for advanced use cases
      alias FnDecorator.Support.AST
      alias FnDecorator.Support.Context
    end
  end
end
