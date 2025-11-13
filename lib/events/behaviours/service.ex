defmodule Events.Behaviours.Service do
  @moduledoc """
  Base behaviour for all service modules.

  Services represent core business capabilities with clear boundaries and well-defined behaviours.
  Each service should define its own behaviour that extends this base behaviour.

  ## Design Principles

  - **Single Responsibility**: Each service does one thing well
  - **Behaviour-Based**: Define behaviours, implement via adapters
  - **Configuration Explicit**: Pass configuration as structs, not global config
  - **Error Normalization**: Return standard error tuples, normalize externally
  - **Composable**: Services should be easily composable with decorators

  ## Example

      defmodule MyApp.Services.Notifications do
        @behaviour Events.Behaviours.Service

        @impl true
        def child_spec(opts) do
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, [opts]}
          }
        end

        @impl true
        def start_link(opts) do
          # Initialize service
        end
      end
  """

  @doc """
  Returns a child specification for supervised services.

  This is optional - only implement if the service needs to run under supervision
  (e.g., maintains connections, has background processes).
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  @doc """
  Starts the service with given options.

  This is optional - only implement if the service needs initialization.
  Most stateless services won't need this.
  """
  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}

  @optional_callbacks child_spec: 1, start_link: 1

  @doc """
  Helper to check if a module implements the Service behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    :attributes
    |> module.__info__()
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(__MODULE__)
  end
end
