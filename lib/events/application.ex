defmodule Events.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EventsWeb.Telemetry,
      Events.Repo,
      Events.Cache,
      Events.KillSwitch,
      {DNSCluster, query: Application.get_env(:events, :dns_cluster_query) || :ignore},
      Events.PubSub,
      # Start a worker by calling: Events.Worker.start_link(arg)
      # {Events.Worker, arg},
      # Start to serve requests, typically the last entry
      EventsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Events.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Validate schemas against database after repo is started
    # Configured via :events, :schema_validation in config
    maybe_validate_schemas()

    result
  end

  defp maybe_validate_schemas do
    config = Application.get_env(:events, :schema_validation, [])

    if Keyword.get(config, :on_startup, false) do
      # Wait for Repo to be fully registered before validation
      case wait_for_repo(50, 100) do
        :ok ->
          Events.Schema.DatabaseValidator.validate_on_startup()

        :timeout ->
          require Logger
          Logger.warning("Schema validation skipped: Repo not available")
          :ok
      end
    else
      :ok
    end
  end

  # Wait for the Repo to be registered with Ecto.Repo.Registry
  defp wait_for_repo(0, _interval), do: :timeout

  defp wait_for_repo(attempts, interval) do
    case Ecto.Repo.Registry.lookup(Events.Repo) do
      {_adapter_meta, _pid} ->
        :ok

      nil ->
        Process.sleep(interval)
        wait_for_repo(attempts - 1, interval)
    end
  rescue
    _ ->
      Process.sleep(interval)
      wait_for_repo(attempts - 1, interval)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EventsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
