defmodule Events.Services.Ttyd.Session do
  @moduledoc """
  A single ttyd terminal session.

  Thin wrapper around `OmTtyd.Session` with Events-specific defaults.

  See `OmTtyd.Session` for full documentation.
  """

  defdelegate start_link(opts), to: OmTtyd.Session
  defdelegate port(session_id, opts \\ []), to: OmTtyd.Session
  defdelegate info(session_id, opts \\ []), to: OmTtyd.Session
end
