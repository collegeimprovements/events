defmodule Events.Services.Ttyd.SessionManager do
  @moduledoc """
  Manages per-session ttyd terminal instances.

  Thin wrapper around `OmTtyd.SessionManager` with Events-specific defaults.

  See `OmTtyd.SessionManager` for full documentation.
  """

  @registry __MODULE__.Registry

  defdelegate start_link(opts \\ []), to: OmTtyd.SessionManager
  defdelegate start_session(owner_pid, opts \\ []), to: OmTtyd.SessionManager
  defdelegate get_session(session_id, opts \\ []), to: OmTtyd.SessionManager
  defdelegate stop_session(session_id, opts \\ []), to: OmTtyd.SessionManager
  defdelegate list_sessions(opts \\ []), to: OmTtyd.SessionManager
  defdelegate session_count(opts \\ []), to: OmTtyd.SessionManager
  defdelegate used_ports(opts \\ []), to: OmTtyd.SessionManager

  # Keep the registry name constant for backwards compatibility
  def registry_name, do: @registry
end
