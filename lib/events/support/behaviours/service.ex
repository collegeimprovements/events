defmodule Events.Support.Behaviours.Service do
  @moduledoc """
  Base behaviour for all service modules.

  Thin wrapper around `OmBehaviours.Service` with Events-specific defaults.

  See `OmBehaviours.Service` for full documentation.
  """

  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()
  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}

  @optional_callbacks child_spec: 1, start_link: 1

  defdelegate implements?(module), to: OmBehaviours.Service
end
