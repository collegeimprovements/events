defmodule Events.Support.Behaviours.Builder do
  @moduledoc """
  Base behaviour for builder modules.

  Thin wrapper around `OmBehaviours.Builder` with Events-specific defaults.

  See `OmBehaviours.Builder` for full documentation.
  """

  @callback new(data :: term(), opts :: keyword()) :: struct()
  @callback compose(builder :: struct(), operation :: term()) :: struct()
  @callback build(builder :: struct()) :: term()

  defdelegate implements?(module), to: OmBehaviours.Builder

  defmacro __using__(opts) do
    quote do
      use OmBehaviours.Builder, unquote(opts)
    end
  end

  defmacro defcompose(call, do: block) do
    quote do
      OmBehaviours.Builder.defcompose(unquote(call), do: unquote(block))
    end
  end
end
