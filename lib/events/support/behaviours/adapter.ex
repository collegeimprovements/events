defmodule Events.Support.Behaviours.Adapter do
  @moduledoc """
  Base behaviour for service adapter implementations.

  Thin wrapper around `OmBehaviours.Adapter` with Events-specific defaults.

  See `OmBehaviours.Adapter` for full documentation.
  """

  @callback adapter_name() :: atom()
  @callback adapter_config(opts :: keyword()) :: map()

  defdelegate resolve(adapter_name, base_module), to: OmBehaviours.Adapter
  defdelegate implements?(module), to: OmBehaviours.Adapter
end
