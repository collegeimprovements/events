defmodule Events.Decorator.Context do
  @moduledoc """
  Context struct containing metadata about a decorated function.

  This context is passed to decorator implementations and provides rich
  information about the function being decorated, including:

  - Function name, arity, and module
  - Function arguments (AST)
  - Guards (if any)
  - Additional metadata

  The context enables pattern matching in decorators and allows for
  sophisticated compile-time transformations.

  ## Fields

    * `:name` - Function name as atom
    * `:arity` - Function arity as integer
    * `:module` - Module where function is defined
    * `:args` - Function arguments as AST list
    * `:guards` - Function guards as AST (if any)
    * `:meta` - Additional metadata map

  ## Example

      %Context{
        name: :get_user,
        arity: 1,
        module: MyApp.Accounts,
        args: [{:id, [], Elixir}],
        guards: nil,
        meta: %{}
      }
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

  @doc """
  Creates a new context from function metadata.

  ## Examples

      iex> Context.new(name: :my_func, arity: 2, module: MyModule, args: [])
      %Context{name: :my_func, arity: 2, module: MyModule, args: [], guards: nil, meta: %{}}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Adds metadata to context.

  ## Examples

      iex> ctx = Context.new(name: :func, arity: 0, module: Mod, args: [])
      iex> Context.put_meta(ctx, :key, "value")
      %Context{name: :func, ..., meta: %{key: "value"}}
  """
  @spec put_meta(t(), atom(), term()) :: t()
  def put_meta(%__MODULE__{meta: meta} = context, key, value) when is_atom(key) do
    %{context | meta: Map.put(meta, key, value)}
  end

  @doc """
  Gets metadata from context.

  ## Examples

      iex> ctx = %Context{meta: %{key: "value"}}
      iex> Context.get_meta(ctx, :key)
      "value"
      iex> Context.get_meta(ctx, :missing, :default)
      :default
  """
  @spec get_meta(t(), atom(), term()) :: term()
  def get_meta(%__MODULE__{meta: meta}, key, default \\ nil) when is_atom(key) do
    Map.get(meta, key, default)
  end

  @doc """
  Returns a keyword list representation of the context for pattern matching.

  ## Examples

      iex> ctx = Context.new(name: :func, arity: 1, module: Mod, args: [{:x, [], nil}])
      iex> Context.to_keyword(ctx)
      [name: :func, arity: 1, module: Mod, args: [{:x, [], nil}], guards: nil, meta: %{}]
  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = context) do
    Map.from_struct(context) |> Enum.into([])
  end
end
