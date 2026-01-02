defmodule Events.Support.ProtocolRegistry do
  @moduledoc """
  Registry for protocol implementations with introspection capabilities.

  Thin wrapper around `FnTypes.Protocols.Registry` with Events-specific defaults.

  See `FnTypes.Protocols.Registry` for full documentation.
  """

  defdelegate list_protocols(), to: FnTypes.Protocols.Registry
  defdelegate list_implementations(protocol), to: FnTypes.Protocols.Registry
  defdelegate get_implementation(protocol, for_type), to: FnTypes.Protocols.Registry
  defdelegate implemented?(protocol, for_type), to: FnTypes.Protocols.Registry
  defdelegate verify(protocol, for_type), to: FnTypes.Protocols.Registry
  defdelegate verify_protocol(protocol), to: FnTypes.Protocols.Registry
  defdelegate verify_all(), to: FnTypes.Protocols.Registry
  defdelegate summary(), to: FnTypes.Protocols.Registry
  defdelegate info(protocol), to: FnTypes.Protocols.Registry
  defdelegate docs(protocol), to: FnTypes.Protocols.Registry
  defdelegate register_protocol(protocol), to: FnTypes.Protocols.Registry
end
