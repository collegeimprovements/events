defmodule Events.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # STEP 1: Validate critical configs BEFORE starting children
    # This ensures we fail fast if there are configuration errors
    validate_critical_configs()

    # STEP 2: Start supervision tree
    children =
      [
        EventsWeb.Telemetry,
        Events.Data.Repo,
        Events.Data.Cache,
        OmKillSwitch,
        {DNSCluster, query: Application.get_env(:events, :dns_cluster_query) || :ignore},
        Events.Services.PubSub,
        # Rate limiter using Hammer v7 (ETS or Redis backend)
        Events.Services.RateLimiter,
        # Task supervisor for async operations (error storage, telemetry, etc.)
        {Task.Supervisor, name: Events.TaskSupervisor},
        # Scheduler for background jobs and workflows (disabled by default in test)
        # Configure via: config :events, OmScheduler, enabled: true/false
        OmScheduler.Supervisor,
        # Start to serve requests, typically the last entry
        EventsWeb.Endpoint
      ]
      |> maybe_add_ttyd_session_manager()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Events.Supervisor]
    result = Supervisor.start_link(children, opts)

    # STEP 3: Validate all configs (including optional) and log warnings
    validate_all_configs()

    # STEP 4: Validate schemas against database after repo is started
    # Configured via :events, :schema_validation in config
    maybe_validate_schemas()

    result
  end

  # ============================================
  # Optional Services
  # ============================================

  # Add ttyd session manager for per-tab terminal sessions
  # Configure via: config :events, :ttyd, enabled: true, command: "bash", writable: true
  # Each browser tab at /ttyd gets its own terminal on a dynamic port (7700-7799)
  defp maybe_add_ttyd_session_manager(children) do
    config = Application.get_env(:events, :ttyd, [])
    enabled = Keyword.get(config, :enabled, false)

    if enabled and OmTtyd.available?() do
      children ++ [OmTtyd.SessionManager]
    else
      children
    end
  end

  # ============================================
  # Configuration Validation
  # ============================================

  defp validate_critical_configs do
    case Events.Startup.ConfigValidator.validate_critical() do
      {:ok, _results} ->
        :ok

      {:error, errors} ->
        require Logger
        Logger.error("Critical configuration errors detected!")

        Enum.each(errors, fn {service, reason} ->
          Logger.error("  #{service}: #{reason}")
        end)

        # Fail fast in production/test, continue in dev for better DX
        if Mix.env() != :dev do
          raise """
          Application startup aborted due to critical configuration errors.

          Fix the errors above and restart the application.
          """
        else
          Logger.warning("Continuing startup in dev mode despite errors...")
        end
    end
  end

  defp validate_all_configs do
    case Events.Startup.ConfigValidator.validate_all() do
      %{warnings: warnings, errors: errors} when warnings != [] or errors != [] ->
        require Logger

        unless Enum.empty?(warnings) do
          Logger.warning("Configuration warnings detected:")

          Enum.each(warnings, fn %{service: service, reason: reason} ->
            Logger.warning("  #{service}: #{reason}")
          end)
        end

        unless Enum.empty?(errors) do
          Logger.error("Non-critical configuration errors:")

          Enum.each(errors, fn %{service: service, reason: reason} ->
            Logger.error("  #{service}: #{reason}")
          end)
        end

      _ ->
        :ok
    end
  end

  # ============================================
  # Schema Validation
  # ============================================

  defp maybe_validate_schemas do
    config = Application.get_env(:events, :schema_validation, [])

    if Keyword.get(config, :on_startup, false) do
      # Wait for Repo to be fully registered before validation
      case wait_for_repo(50, 100) do
        :ok ->
          OmSchema.DatabaseValidator.validate_on_startup()

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
    case Ecto.Repo.Registry.lookup(Events.Data.Repo) do
      %{pid: pid} when is_pid(pid) -> :ok
      nil -> retry_wait_for_repo(attempts, interval)
    end
  rescue
    # Ecto 3.13+ throws RuntimeError when repo not started
    RuntimeError -> retry_wait_for_repo(attempts, interval)
  end

  defp retry_wait_for_repo(attempts, interval) do
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
