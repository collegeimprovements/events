defmodule Events.Startup.Checker do
  @moduledoc """
  Thin wrapper around `Events.Observability.SystemHealth` for boot-time diagnostics.

  Keeps the historical API used by release tasks while delegating all of the
  heavy lifting to the centralized system health modules.
  """

  alias Events.Observability.SystemHealth

  @doc """
  Returns the current status for each critical service.

  Delegates to `Events.Observability.SystemHealth.services_status/0`.
  """
  @spec check_all() :: list(map())
  def check_all do
    SystemHealth.services_status()
  end

  @doc """
  Displays the formatted system health table.

  Accepts the same options as `Events.Observability.SystemHealth.display/1`.
  """
  @spec display_table(keyword()) :: :ok
  def display_table(opts \\ []) do
    SystemHealth.display(opts)
  end

  @doc """
  Runs the full suite of health checks and returns the aggregated data.

  Provided for callers that previously relied on the startup checker for
  environment, proxy, and migration details.
  """
  @spec check_full() :: map()
  def check_full do
    SystemHealth.check_all()
  end
end
