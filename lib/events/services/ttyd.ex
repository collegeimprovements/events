defmodule Events.Services.Ttyd do
  @moduledoc """
  Web-based terminal sharing service.

  Thin wrapper around `OmTtyd` with Events-specific defaults.

  See `OmTtyd` for full documentation.
  """

  # Client API
  defdelegate start(command, opts \\ []), to: OmTtyd
  defdelegate start_link(command, opts \\ []), to: OmTtyd
  defdelegate stop(server, timeout \\ 5000), to: OmTtyd
  defdelegate url(server), to: OmTtyd
  defdelegate port(server), to: OmTtyd
  defdelegate info(server), to: OmTtyd
  defdelegate alive?(server), to: OmTtyd

  # Utility
  defdelegate available?(), to: OmTtyd
  defdelegate version(), to: OmTtyd
  defdelegate version!(), to: OmTtyd
end
