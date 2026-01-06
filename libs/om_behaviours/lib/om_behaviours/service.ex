defmodule OmBehaviours.Service do
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
        @behaviour OmBehaviours.Service

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
  (e.g., maintains connections, has background processes, caches state).

  ## Parameters

  - `opts` - Configuration options for the service

  ## Returns

  A `Supervisor.child_spec/0` map with at least `:id` and `:start` keys.

  ## Examples

      defmodule MyApp.CacheService do
        @behaviour OmBehaviours.Service
        use GenServer

        @impl true
        def child_spec(opts) do
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, [opts]},
            restart: :permanent,
            shutdown: 5_000,
            type: :worker
          }
        end

        @impl true
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        @impl GenServer
        def init(opts) do
          cache_size = Keyword.get(opts, :max_size, 1000)
          {:ok, %{cache: %{}, max_size: cache_size}}
        end
      end

      # Add to supervision tree
      children = [
        {MyApp.CacheService, max_size: 5000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()

  @doc """
  Starts the service with given options.

  This is optional - only implement if the service needs initialization.
  Most stateless services won't need this callback.

  ## Parameters

  - `opts` - Configuration options for starting the service

  ## Returns

  - `{:ok, pid}` - Service started successfully
  - `{:error, reason}` - Service failed to start

  ## Examples

      defmodule MyApp.ConnectionPool do
        @behaviour OmBehaviours.Service
        use GenServer

        @impl true
        def start_link(opts) do
          pool_size = Keyword.get(opts, :pool_size, 10)
          GenServer.start_link(__MODULE__, pool_size, name: __MODULE__)
        end

        @impl GenServer
        def init(pool_size) do
          # Initialize connections
          connections = Enum.map(1..pool_size, fn _ ->
            {:ok, conn} = establish_connection()
            conn
          end)

          {:ok, %{connections: connections, available: connections}}
        end

        defp establish_connection do
          # Connection logic
          {:ok, %{conn: "connection"}}
        end
      end

      # Start the service
      {:ok, pid} = MyApp.ConnectionPool.start_link(pool_size: 20)
  """
  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, term()}

  @optional_callbacks child_spec: 1, start_link: 1

  @doc """
  Helper to check if a module implements the Service behaviour.

  ## Parameters

  - `module` - The module to check

  ## Returns

  `true` if the module implements `OmBehaviours.Service`, `false` otherwise.

  ## Examples

      defmodule MyApp.EmailService do
        @behaviour OmBehaviours.Service

        @impl true
        def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

        @impl true
        def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      iex> OmBehaviours.Service.implements?(MyApp.EmailService)
      true

      iex> OmBehaviours.Service.implements?(SomeOtherModule)
      false

  ## Real-World Usage

      # Ensure service contract is implemented
      defmodule MyApp.Application do
        use Application

        @services [MyApp.EmailService, MyApp.CacheService, MyApp.NotificationService]

        def start(_type, _args) do
          # Validate all services implement the behaviour
          Enum.each(@services, fn service ->
            unless OmBehaviours.Service.implements?(service) do
              raise "Service \#{inspect(service)} must implement OmBehaviours.Service"
            end
          end)

          children = Enum.map(@services, &{&1, []})
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    OmBehaviours.implements?(module, __MODULE__)
  end
end
