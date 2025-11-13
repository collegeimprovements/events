defmodule Events.Decorators.Decorator do
  @moduledoc """
  Main decorator module providing a unified interface for all decorators.

  This module consolidates access to all decorator categories in a clean,
  organized way. Each decorator category is in its own module for better
  organization and maintainability.

  ## Available Decorator Categories

  - **Cache** - Caching decorators (cacheable, cache_put, cache_evict)
  - **Telemetry** - Observability (telemetry_span, log_call, log_if_slow)
  - **Performance** - Performance measurement (benchmark, measure, profile)
  - **Debug** - Debugging tools (debug, inspect, pry, trace)
  - **Validation** - Input/output validation (validate_args, ensure)
  - **Purity** - Function purity (pure, deterministic, idempotent)
  - **Testing** - Test support (fixtures, mocks, property tests)

  ## Usage

  Add `use Events.Decorator` to your module to enable all decorators:

      defmodule MyModule do
        use Events.Decorator

        # Caching
        @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
        def get_user(id), do: Repo.get(User, id)

        # Telemetry
        @decorate telemetry_span([:my_app, :process])
        @decorate log_if_slow(threshold: 1000)
        def process_data(data), do: # ...

        # Validation
        @decorate validate_args(schema: %{id: :integer})
        def find_by_id(id), do: # ...

        # Multiple decorators compose
        @decorate cacheable(cache: Cache, key: key)
        @decorate telemetry_span([:app, :calculate])
        @decorate pure()
        def calculate(x, y), do: x + y
      end

  ## Decorator Composition

  Decorators are applied from bottom to top (closest to function first):

      @decorate log_call()        # 3. Logs the cached result
      @decorate cacheable(...)    # 2. Checks cache
      @decorate validate_args(...) # 1. Validates args first
      def my_function(args), do: # ...

  ## Environment-Specific Decorators

  Some decorators are intended for development/test only:
  - Debug decorators (debug, pry, inspect)
  - Tracing decorators (trace_calls, trace_modules)
  - Testing decorators (mock, with_fixtures)

  These can be conditionally compiled:

      if Mix.env() in [:dev, :test] do
        @decorate debug()
        @decorate trace_calls()
      end
      def complex_function(x), do: # ...

  ## Configuration

  Configure decorators in your application config:

      config :events, Events.Decorators,
        default_cache: MyApp.Cache,
        telemetry_prefix: [:my_app],
        log_level: :info

  ## Best Practices

  1. **Use specific imports** - Import only what you need
  2. **Order matters** - Consider decorator execution order
  3. **Keep it simple** - Don't over-decorate
  4. **Document decorated functions** - Explain decorator usage
  5. **Test decorated and undecorated** - Test both paths
  6. **Profile in production** - Monitor decorator overhead
  """

  defmacro __using__(opts \\ []) do
    imports = Keyword.get(opts, :only, :all)

    modules = case imports do
      :all -> [
        Events.Decorators.Cache,
        Events.Decorators.Telemetry,
        Events.Decorators.Performance,
        Events.Decorators.Debug,
        Events.Decorators.Validation,
        Events.Decorators.Purity,
        Events.Decorators.Testing
      ]

      list when is_list(list) ->
        Enum.map(list, fn
          :cache -> Events.Decorators.Cache
          :telemetry -> Events.Decorators.Telemetry
          :performance -> Events.Decorators.Performance
          :debug -> Events.Decorators.Debug
          :validation -> Events.Decorators.Validation
          :purity -> Events.Decorators.Purity
          :testing -> Events.Decorators.Testing
          module when is_atom(module) -> module
        end)

      module when is_atom(module) -> [module]
    end

    quote do
      use Decorator.Define

      # Import all decorator modules
      unquote(
        for module <- modules do
          quote do
            import unquote(module)
          end
        end
      )

      # Import the implementation module that has the actual decorator logic
      # This assumes the existing decorator implementations are available
      import Events.Decorators
    end
  end

  @doc """
  Lists all available decorators.
  """
  def list_decorators do
    %{
      cache: [
        :cacheable,
        :cache_put,
        :cache_evict,
        :cache_stats
      ],
      telemetry: [
        :telemetry_span,
        :otel_span,
        :log_call,
        :log_context,
        :log_if_slow,
        :log_query,
        :log_remote,
        :track_memory,
        :capture_errors
      ],
      performance: [
        :benchmark,
        :measure,
        :profile,
        :rate_limit,
        :timeout
      ],
      debug: [
        :debug,
        :inspect,
        :pry,
        :trace_vars,
        :trace_calls,
        :trace_modules,
        :trace_dependencies
      ],
      validation: [
        :validate_args,
        :validate_result,
        :ensure,
        :contract,
        :typed
      ],
      purity: [
        :pure,
        :deterministic,
        :idempotent,
        :memoizable,
        :referentially_transparent
      ],
      testing: [
        :with_fixtures,
        :sample_data,
        :timeout_test,
        :mock,
        :property,
        :snapshot
      ]
    }
  end

  @doc """
  Gets decorator documentation.
  """
  def decorator_docs(decorator) do
    docs = %{
      cacheable: "Read-through cache - checks cache, executes on miss, caches result",
      cache_put: "Write-through cache - updates cache with function result",
      cache_evict: "Cache eviction - removes entries from cache",
      telemetry_span: "Emits telemetry events for function execution",
      log_call: "Logs function calls with arguments and results",
      log_if_slow: "Logs warning if execution exceeds threshold",
      benchmark: "Comprehensive benchmarking with statistics",
      measure: "Simple execution time measurement",
      debug: "Debug with Elixir's dbg/2",
      inspect: "Inspect function arguments and results",
      pure: "Marks function as pure (no side effects)",
      deterministic: "Same input always produces same output",
      validate_args: "Validates function arguments against schema",
      with_fixtures: "Automatically loads test fixtures"
    }

    Map.get(docs, decorator, "No documentation available for #{decorator}")
  end
end