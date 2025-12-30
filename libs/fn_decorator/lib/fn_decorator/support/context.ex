defmodule FnDecorator.Support.Context do
  @moduledoc """
  Context for decorated functions.
  Contains metadata about the function being decorated.
  """

  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          module: module(),
          args: [Macro.t()],
          guards: Macro.t() | nil,
          meta: map()
        }

  defstruct [:name, :arity, :module, :args, :guards, meta: %{}]

  @doc "Creates new context from options"
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @doc "Adds metadata to context"
  def put_meta(%__MODULE__{meta: meta} = context, key, value) do
    %{context | meta: Map.put(meta, key, value)}
  end

  @doc "Gets metadata from context"
  def get_meta(%__MODULE__{meta: meta}, key, default \\ nil) do
    Map.get(meta, key, default)
  end

  @doc """
  Returns fully qualified function name.

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.User, name: :create, arity: 2}
      iex> FnDecorator.Support.Context.full_name(context)
      "MyApp.User.create/2"
  """
  def full_name(%__MODULE__{module: module, name: name, arity: arity}) do
    "#{module}.#{name}/#{arity}"
  end

  @doc """
  Returns short module name (last segment).

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.Services.UserService, name: :create, arity: 1}
      iex> FnDecorator.Support.Context.short_module(context)
      "UserService"
  """
  def short_module(%__MODULE__{module: module}) do
    module |> Module.split() |> List.last()
  end

  @doc """
  Returns underscored module name suitable for telemetry events.

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.UserService, name: :create, arity: 1}
      iex> FnDecorator.Support.Context.telemetry_module(context)
      :user_service
  """
  def telemetry_module(%__MODULE__{module: module}) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  @doc """
  Builds default telemetry event name.

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.UserService, name: :create, arity: 1}
      iex> FnDecorator.Support.Context.telemetry_event(context)
      [:fn_decorator, :user_service, :create]

      iex> FnDecorator.Support.Context.telemetry_event(context, [:myapp])
      [:myapp, :user_service, :create]
  """
  def telemetry_event(%__MODULE__{name: name} = context, prefix \\ [:fn_decorator]) do
    prefix ++ [telemetry_module(context), name]
  end

  @doc """
  Builds span name for OpenTelemetry.

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.UserService, name: :create, arity: 1}
      iex> FnDecorator.Support.Context.span_name(context)
      "user_service.create"
  """
  def span_name(%__MODULE__{name: name} = context) do
    module_name = context |> telemetry_module() |> Atom.to_string()
    "#{module_name}.#{name}"
  end

  @doc """
  Extracts argument names from context.

  Returns list of atoms representing argument names, with `:_unknown` for
  arguments that can't be identified.

  ## Examples

      iex> context = %FnDecorator.Support.Context{args: [{:user_id, [], nil}, {:name, [], nil}]}
      iex> FnDecorator.Support.Context.arg_names(context)
      [:user_id, :name]
  """
  def arg_names(%__MODULE__{args: args}) do
    Enum.map(args, fn
      {name, _, _} when is_atom(name) -> name
      _ -> :_unknown
    end)
  end

  @doc """
  Returns base metadata map from context.

  Useful for telemetry, logging, and audit trails.

  ## Examples

      iex> context = %FnDecorator.Support.Context{module: MyApp.User, name: :create, arity: 2}
      iex> FnDecorator.Support.Context.base_metadata(context)
      %{module: MyApp.User, function: :create, arity: 2}

      iex> FnDecorator.Support.Context.base_metadata(context, timestamp: true, node: true)
      %{module: MyApp.User, function: :create, arity: 2, timestamp: ~U[...], node: :nonode@nohost}
  """
  def base_metadata(%__MODULE__{} = context, opts \\ []) do
    %{
      module: context.module,
      function: context.name,
      arity: context.arity
    }
    |> maybe_add_timestamp(opts[:timestamp])
    |> maybe_add_node(opts[:node])
    |> maybe_merge_extra(opts[:extra])
  end

  defp maybe_add_timestamp(map, true), do: Map.put(map, :timestamp, DateTime.utc_now())
  defp maybe_add_timestamp(map, _), do: map

  defp maybe_add_node(map, true), do: Map.put(map, :node, node())
  defp maybe_add_node(map, _), do: map

  defp maybe_merge_extra(map, extra) when is_map(extra), do: Map.merge(map, extra)
  defp maybe_merge_extra(map, _), do: map
end
