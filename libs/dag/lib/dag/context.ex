defmodule Dag.Context do
  @moduledoc """
  Scoped runtime context for workflow execution.

  Provides three levels of context resolution (highest to lowest priority):
  1. **Scoped** - Per-component values
  2. **Global** - Available to all components
  3. **Defaults** - Fallback values

  ## Examples

      context =
        Dag.Context.new()
        |> Dag.Context.put_global(:api_url, "https://api.example.com")
        |> Dag.Context.put_scoped(:call_api, :api_key, "sk-...")
        |> Dag.Context.put_default(:timeout, 5000)

      Dag.Context.resolve(context, :call_api, :api_key)  #=> "sk-..."
      Dag.Context.resolve(context, :call_api, :api_url)  #=> "https://api.example.com"
      Dag.Context.resolve(context, :other, :timeout)      #=> 5000

  ## Runic-style bulk context

      Dag.Context.from_map(%{
        _global: %{workspace_id: "ws1"},
        call_llm: %{api_key: "sk-...", model: "claude-4"},
        fetch_data: %{timeout: 30_000}
      })
  """

  @type t :: %__MODULE__{
          global: map(),
          scoped: %{Dag.node_id() => map()},
          defaults: map()
        }

  defstruct global: %{}, scoped: %{}, defaults: %{}

  @doc "Creates a new context."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      global: Keyword.get(opts, :global, %{}),
      scoped: Keyword.get(opts, :scoped, %{}),
      defaults: Keyword.get(opts, :defaults, %{})
    }
  end

  @doc """
  Creates a context from a map with optional `:_global` key.

  ## Examples

      Dag.Context.from_map(%{
        _global: %{api_url: "https://..."},
        step_a: %{key: "value"}
      })
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    {global, scoped} = Map.pop(map, :_global, %{})
    %__MODULE__{global: global, scoped: scoped}
  end

  @doc "Sets a global context value."
  @spec put_global(t(), atom(), term()) :: t()
  def put_global(%__MODULE__{} = ctx, key, value) do
    %{ctx | global: Map.put(ctx.global, key, value)}
  end

  @doc "Sets a scoped context value for a specific component."
  @spec put_scoped(t(), Dag.node_id(), atom(), term()) :: t()
  def put_scoped(%__MODULE__{} = ctx, component_id, key, value) do
    scoped =
      Map.update(ctx.scoped, component_id, %{key => value}, &Map.put(&1, key, value))

    %{ctx | scoped: scoped}
  end

  @doc "Sets a default value."
  @spec put_default(t(), atom(), term()) :: t()
  def put_default(%__MODULE__{} = ctx, key, value) do
    %{ctx | defaults: Map.put(ctx.defaults, key, value)}
  end

  @doc """
  Resolves a value for a component. Checks scoped -> global -> defaults.
  Returns `default` if not found at any level.
  """
  @spec resolve(t(), Dag.node_id(), atom(), term()) :: term()
  def resolve(%__MODULE__{} = ctx, component_id, key, default \\ nil) do
    with :error <- fetch_scoped(ctx, component_id, key),
         :error <- Map.fetch(ctx.global, key),
         :error <- Map.fetch(ctx.defaults, key) do
      default
    else
      {:ok, value} -> value
    end
  end

  @doc "Returns the full resolved context map for a component."
  @spec resolve_all(t(), Dag.node_id()) :: map()
  def resolve_all(%__MODULE__{} = ctx, component_id) do
    ctx.defaults
    |> Map.merge(ctx.global)
    |> Map.merge(Map.get(ctx.scoped, component_id, %{}))
  end

  @doc "Merges two contexts. ctx2 takes precedence."
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = ctx1, %__MODULE__{} = ctx2) do
    %__MODULE__{
      global: Map.merge(ctx1.global, ctx2.global),
      scoped:
        Map.merge(ctx1.scoped, ctx2.scoped, fn _k, s1, s2 ->
          Map.merge(s1, s2)
        end),
      defaults: Map.merge(ctx1.defaults, ctx2.defaults)
    }
  end

  defp fetch_scoped(%__MODULE__{scoped: scoped}, component_id, key) do
    case Map.fetch(scoped, component_id) do
      {:ok, scope_map} -> Map.fetch(scope_map, key)
      :error -> :error
    end
  end
end
