defmodule Events.Context do
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
end
