defmodule OmBehaviours do
  @moduledoc """
  Common behaviour patterns for Elixir applications.

  Provides base behaviours for:
  - **Adapter** - Swappable backend implementations
  - **Service** - Supervised service modules
  - **Builder** - Fluent builder patterns
  - **Worker** - Background job execution
  - **Plugin** - Extension point plugins
  - **HealthCheck** - System health reporting
  """

  @doc """
  Checks if a module implements a specific behaviour.

  ## Examples

      OmBehaviours.implements?(MyAdapter, OmBehaviours.Adapter)
      #=> true
  """
  @spec implements?(module(), module()) :: boolean()
  def implements?(module, behaviour) when is_atom(module) and is_atom(behaviour) do
    module
    |> module_behaviours()
    |> Enum.member?(behaviour)
  rescue
    UndefinedFunctionError -> false
  end

  def implements?(_module, _behaviour), do: false

  defp module_behaviours(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
