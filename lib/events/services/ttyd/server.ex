defmodule Events.Services.Ttyd.Server do
  @moduledoc """
  Supervised ttyd terminal server.

  Thin wrapper around `OmTtyd.Server` with Events-specific defaults.

  See `OmTtyd.Server` for full documentation.
  """

  defdelegate start_link(opts \\ []), to: OmTtyd.Server
  defdelegate url(server \\ __MODULE__), to: OmTtyd.Server
  defdelegate port(server \\ __MODULE__), to: OmTtyd.Server
  defdelegate info(server \\ __MODULE__), to: OmTtyd.Server
  defdelegate alive?(server \\ __MODULE__), to: OmTtyd.Server
  defdelegate child_spec(opts), to: OmTtyd.Server
end
