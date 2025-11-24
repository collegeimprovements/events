defmodule Events.CRUD.Plugin do
  @moduledoc """
  Plugin system for extending CRUD operations.

  Allows registration of custom operations, hooks, and extensions to the CRUD system.
  """

  @type t :: %{
          name: atom(),
          operations: [Events.CRUD.Types.operation_type()],
          hooks: keyword((term() -> term())),
          version: String.t()
        }

  @doc """
  Registers a plugin with the CRUD system.

  ## Examples

      defmodule MyCustomPlugin do
        @behaviour Events.CRUD.Plugin

        @impl true
        def plugin_info do
          %{
            name: :my_plugin,
            operations: [:custom_filter],
            hooks: [
              before_execute: &before_execute_hook/1,
              after_execute: &after_execute_hook/1
            ],
            version: "1.0.0"
          }
        end

        def before_execute_hook(token), do: token
        def after_execute_hook(result), do: result
      end

      Events.CRUD.Plugin.register(MyCustomPlugin)
  """
  @spec register(module()) :: :ok | {:error, String.t()}
  def register(plugin_module) do
    case validate_plugin(plugin_module) do
      :ok ->
        plugin = plugin_module.plugin_info()
        # Store plugin in registry (could use an Agent, ETS, or application env)
        plugins = Application.get_env(:events, :crud_plugins, [])
        Application.put_env(:events, :crud_plugins, [plugin | plugins])
        :ok

      error ->
        error
    end
  end

  @doc """
  Lists all registered plugins.
  """
  @spec list() :: [t()]
  def list do
    Application.get_env(:events, :crud_plugins, [])
  end

  @doc """
  Gets a plugin by name.
  """
  @spec get(atom()) :: t() | nil
  def get(name) do
    list()
    |> Enum.find(&(&1.name == name))
  end

  @doc """
  Checks if a plugin is registered.
  """
  @spec registered?(atom()) :: boolean()
  def registered?(name) do
    get(name) != nil
  end

  @doc """
  Executes hooks for a specific event.

  ## Examples

      # Execute before_execute hooks
      token = Events.CRUD.Plugin.execute_hooks(:before_execute, token)

      # Execute after_execute hooks
      result = Events.CRUD.Plugin.execute_hooks(:after_execute, result)
  """
  @spec execute_hooks(atom(), term()) :: term()
  def execute_hooks(event, data) do
    list()
    |> Enum.flat_map(& &1.hooks)
    |> Enum.filter(fn {hook_event, _} -> hook_event == event end)
    |> Enum.reduce(data, fn {_, hook_fun}, acc ->
      hook_fun.(acc)
    end)
  end

  @doc """
  Gets all operations provided by registered plugins.
  """
  @spec plugin_operations() :: [Events.CRUD.Types.operation_type()]
  def plugin_operations do
    list()
    |> Enum.flat_map(& &1.operations)
    |> Enum.uniq()
  end

  # Private functions

  defp validate_plugin(plugin_module) do
    cond do
      not Code.ensure_loaded?(plugin_module) ->
        {:error, "Plugin module #{plugin_module} not found"}

      not function_exported?(plugin_module, :plugin_info, 0) ->
        {:error, "Plugin module must export plugin_info/0"}

      true ->
        case plugin_module.plugin_info() do
          %{name: name, operations: ops, hooks: hooks, version: ver}
          when is_atom(name) and is_list(ops) and is_list(hooks) and is_binary(ver) ->
            :ok

          _ ->
            {:error, "Invalid plugin_info format"}
        end
    end
  end
end
