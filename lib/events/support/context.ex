defmodule Events.Support.Context do
  @moduledoc """
  Context for decorated functions.

  This module delegates to `FnDecorator.Support.Context` but uses
  `:events` as the default telemetry prefix.
  """

  defstruct [:name, :arity, :module, :args, :guards, meta: %{}]

  @type t :: %__MODULE__{
          name: atom(),
          arity: non_neg_integer(),
          module: module(),
          args: [Macro.t()],
          guards: Macro.t() | nil,
          meta: map()
        }

  @doc "Creates new context from options"
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  defdelegate put_meta(context, key, value), to: FnDecorator.Support.Context
  defdelegate get_meta(context, key, default \\ nil), to: FnDecorator.Support.Context
  defdelegate full_name(context), to: FnDecorator.Support.Context
  defdelegate short_module(context), to: FnDecorator.Support.Context
  defdelegate telemetry_module(context), to: FnDecorator.Support.Context
  defdelegate span_name(context), to: FnDecorator.Support.Context
  defdelegate arg_names(context), to: FnDecorator.Support.Context
  defdelegate base_metadata(context, opts \\ []), to: FnDecorator.Support.Context

  @doc """
  Builds default telemetry event name with :events prefix.

  ## Examples

      iex> context = %Events.Support.Context{module: MyApp.UserService, name: :create, arity: 1}
      iex> Events.Support.Context.telemetry_event(context)
      [:events, :user_service, :create]
  """
  def telemetry_event(%__MODULE__{name: name} = context, prefix \\ [:events]) do
    prefix ++ [telemetry_module(context), name]
  end
end
