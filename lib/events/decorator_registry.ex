defmodule Events.DecoratorRegistry do
  @moduledoc """
  Unified registry for all decorators.
  Provides a single source of truth for decorator definitions and metadata.
  """

  @decorators %{
    # Caching decorators
    cacheable: %{
      module: Events.Decorators,
      arity: 1,
      category: :caching,
      description: "Read-through caching - caches results and returns cached values"
    },
    cache_put: %{
      module: Events.Decorators,
      arity: 1,
      category: :caching,
      description: "Write-through caching - always executes and updates cache"
    },
    cache_evict: %{
      module: Events.Decorators,
      arity: 1,
      category: :caching,
      description: "Cache invalidation - removes entries from cache"
    },

    # Telemetry decorators
    telemetry_span: %{
      module: Events.Decorators,
      arity: [1, 2],
      category: :telemetry,
      description: "Emit Erlang telemetry events"
    },
    log_call: %{
      module: Events.Decorators,
      arity: 1,
      category: :telemetry,
      description: "Log function calls"
    },
    log_if_slow: %{
      module: Events.Decorators,
      arity: 1,
      category: :telemetry,
      description: "Log slow operations"
    },
    log_context: %{
      module: Events.Decorators,
      arity: 1,
      category: :telemetry,
      description: "Set Logger metadata from function args"
    },

    # Performance decorators
    benchmark: %{
      module: Events.Decorators,
      arity: 1,
      category: :performance,
      description: "Benchmark function execution"
    },
    measure: %{
      module: Events.Decorators,
      arity: 1,
      category: :performance,
      description: "Measure execution time"
    },

    # Debugging decorators
    debug: %{
      module: Events.Decorators,
      arity: 1,
      category: :debugging,
      description: "Debug with dbg/2"
    },
    inspect: %{
      module: Events.Decorators,
      arity: 1,
      category: :debugging,
      description: "Inspect arguments and results"
    },
    pry: %{
      module: Events.Decorators,
      arity: 1,
      category: :debugging,
      description: "Interactive debugging with IEx.pry"
    },

    # Pipeline decorators
    pipe_through: %{
      module: Events.Decorators,
      arity: 1,
      category: :pipeline,
      description: "Apply function pipeline"
    },
    around: %{
      module: Events.Decorators,
      arity: 1,
      category: :pipeline,
      description: "Around advice pattern"
    },
    compose: %{
      module: Events.Decorators,
      arity: 1,
      category: :pipeline,
      description: "Compose multiple decorators"
    }
  }

  @doc "Get all registered decorators"
  def all, do: @decorators

  @doc "Get decorators by category"
  def by_category(category) do
    @decorators
    |> Enum.filter(fn {_name, meta} -> meta.category == category end)
    |> Enum.into(%{})
  end

  @doc "Get decorator metadata"
  def get(name) when is_atom(name) do
    Map.get(@decorators, name)
  end

  @doc "Check if decorator exists"
  def exists?(name) when is_atom(name) do
    Map.has_key?(@decorators, name)
  end

  @doc "List all categories"
  def categories do
    @decorators
    |> Enum.map(fn {_name, meta} -> meta.category end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Generate decorator definitions for use with Decorator.Define"
  def generate_definitions do
    @decorators
    |> Enum.flat_map(fn {name, meta} ->
      case meta.arity do
        arities when is_list(arities) ->
          Enum.map(arities, fn arity -> {name, arity} end)

        arity ->
          [{name, arity}]
      end
    end)
  end

  @doc "Generate delegation statements"
  def generate_delegations do
    @decorators
    |> Enum.flat_map(fn {name, meta} ->
      case meta.arity do
        [1, 2] ->
          [
            quote do
              defdelegate unquote(name)(opts, body, context),
                to: unquote(meta.module)
            end,
            quote do
              defdelegate unquote(name)(arg1, opts, body, context),
                to: unquote(meta.module)
            end
          ]

        _ ->
          [
            quote do
              defdelegate unquote(name)(opts, body, context),
                to: unquote(meta.module)
            end
          ]
      end
    end)
  end
end
