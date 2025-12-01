defmodule Events.Infra.Decorator.Introspection do
  @moduledoc """
  Runtime introspection for decorated modules.

  Enables querying decorator metadata at runtime. Useful for:
  - Documentation generation
  - Testing that decorators are applied correctly
  - Building admin UIs that show decorator configuration
  - Debugging decorator behavior

  ## Setup

  Modules using `Events.Infra.Decorator` automatically get introspection support
  via the `__decorators__/0` and `__decorators__/1` functions.

  ## Examples

      defmodule MyApp.Users do
        use Events.Infra.Decorator

        @decorate cacheable(cache: MyCache, key: id)
        def get_user(id), do: Repo.get(User, id)

        @decorate rate_limit(max: 10, window: :minute)
        @decorate audit_log(level: :info)
        def delete_user(id), do: Repo.delete(User, id)
      end

      # Query all decorators in the module
      MyApp.Users.__decorators__()
      # => %{
      #   {:get_user, 1} => [{:cacheable, [cache: MyCache, key: id]}],
      #   {:delete_user, 1} => [
      #     {:rate_limit, [max: 10, window: :minute]},
      #     {:audit_log, [level: :info]}
      #   ]
      # }

      # Query decorators for specific function
      MyApp.Users.__decorators__(:get_user, 1)
      # => [{:cacheable, [cache: MyCache, key: id]}]

      # Check if function has specific decorator
      Introspection.has_decorator?(MyApp.Users, :get_user, 1, :cacheable)
      # => true

  ## Implementation Note

  This module provides helper functions for querying decorator metadata.
  The actual `__decorators__/0` and `__decorators__/1` functions are
  generated in each decorated module by `Events.Infra.Decorator`.
  """

  @doc """
  Returns all decorator metadata for a module.

  Returns a map where keys are `{function_name, arity}` tuples and
  values are lists of `{decorator_name, opts}` tuples.

  ## Examples

      Introspection.decorators(MyApp.Users)
      # => %{
      #   {:get_user, 1} => [{:cacheable, [cache: MyCache, key: id]}],
      #   ...
      # }
  """
  @spec decorators(module()) :: %{{atom(), non_neg_integer()} => [{atom(), keyword()}]}
  def decorators(module) when is_atom(module) do
    if function_exported?(module, :__decorators__, 0) do
      module.__decorators__()
    else
      %{}
    end
  end

  @doc """
  Returns decorators for a specific function in a module.

  ## Examples

      Introspection.decorators(MyApp.Users, :get_user, 1)
      # => [{:cacheable, [cache: MyCache, key: id]}]

      Introspection.decorators(MyApp.Users, :undecorated_fn, 1)
      # => []
  """
  @spec decorators(module(), atom(), non_neg_integer()) :: [{atom(), keyword()}]
  def decorators(module, function, arity)
      when is_atom(module) and is_atom(function) and is_integer(arity) do
    if function_exported?(module, :__decorators__, 2) do
      module.__decorators__(function, arity)
    else
      []
    end
  end

  @doc """
  Checks if a function has a specific decorator applied.

  ## Examples

      Introspection.has_decorator?(MyApp.Users, :get_user, 1, :cacheable)
      # => true

      Introspection.has_decorator?(MyApp.Users, :get_user, 1, :rate_limit)
      # => false
  """
  @spec has_decorator?(module(), atom(), non_neg_integer(), atom()) :: boolean()
  def has_decorator?(module, function, arity, decorator_name)
      when is_atom(module) and is_atom(function) and is_integer(arity) and is_atom(decorator_name) do
    module
    |> decorators(function, arity)
    |> Enum.any?(fn {name, _opts} -> name == decorator_name end)
  end

  @doc """
  Gets the options for a specific decorator on a function.

  Returns `nil` if the decorator is not applied.

  ## Examples

      Introspection.get_decorator_opts(MyApp.Users, :get_user, 1, :cacheable)
      # => [cache: MyCache, key: id]

      Introspection.get_decorator_opts(MyApp.Users, :get_user, 1, :rate_limit)
      # => nil
  """
  @spec get_decorator_opts(module(), atom(), non_neg_integer(), atom()) :: keyword() | nil
  def get_decorator_opts(module, function, arity, decorator_name)
      when is_atom(module) and is_atom(function) and is_integer(arity) and is_atom(decorator_name) do
    module
    |> decorators(function, arity)
    |> Enum.find(fn {name, _opts} -> name == decorator_name end)
    |> case do
      {_name, opts} -> opts
      nil -> nil
    end
  end

  @doc """
  Returns all functions decorated with a specific decorator.

  ## Examples

      Introspection.functions_with_decorator(MyApp.Users, :cacheable)
      # => [{:get_user, 1}]
  """
  @spec functions_with_decorator(module(), atom()) :: [{atom(), non_neg_integer()}]
  def functions_with_decorator(module, decorator_name)
      when is_atom(module) and is_atom(decorator_name) do
    module
    |> decorators()
    |> Enum.filter(fn {_fn_key, decorator_list} ->
      Enum.any?(decorator_list, fn {name, _opts} -> name == decorator_name end)
    end)
    |> Enum.map(fn {fn_key, _decorators} -> fn_key end)
  end

  @doc """
  Returns a summary of decorators in a module.

  Useful for documentation and debugging.

  ## Examples

      Introspection.summary(MyApp.Users)
      # => %{
      #   module: MyApp.Users,
      #   decorated_functions: 5,
      #   total_decorators: 12,
      #   decorators_used: [:cacheable, :rate_limit, :audit_log],
      #   functions: [...]
      # }
  """
  @spec summary(module()) :: map()
  def summary(module) when is_atom(module) do
    all_decorators = decorators(module)

    decorator_names =
      all_decorators
      |> Enum.flat_map(fn {_fn, decorators} ->
        Enum.map(decorators, fn {name, _opts} -> name end)
      end)
      |> Enum.uniq()

    total_decorators =
      all_decorators
      |> Enum.map(fn {_fn, decorators} -> length(decorators) end)
      |> Enum.sum()

    functions =
      all_decorators
      |> Enum.map(fn {{name, arity}, decorators} ->
        %{
          name: name,
          arity: arity,
          decorators: Enum.map(decorators, fn {name, _opts} -> name end)
        }
      end)

    %{
      module: module,
      decorated_functions: map_size(all_decorators),
      total_decorators: total_decorators,
      decorators_used: Enum.sort(decorator_names),
      functions: functions
    }
  end

  @doc """
  Checks if introspection is supported for a module.

  Returns `true` if the module was compiled with `use Events.Infra.Decorator`.

  ## Examples

      Introspection.supported?(MyApp.Users)
      # => true

      Introspection.supported?(Enum)
      # => false
  """
  @spec supported?(module()) :: boolean()
  def supported?(module) when is_atom(module) do
    function_exported?(module, :__decorators__, 0)
  end
end
