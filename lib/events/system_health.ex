defmodule Events.SystemHealth do
  @moduledoc """
  System health monitoring and status reporting.

  Provides comprehensive health checks for all application components including:
  - Services (Repo, Cache, Redis, PubSub, Endpoint, Telemetry)
  - Environment configuration
  - Database migrations
  - Proxy settings
  - Mise-managed tools

  ## Usage

      # Get all health checks
      SystemHealth.check_all()

      # Display formatted status table
      SystemHealth.display()

      # Get specific component status
      SystemHealth.services_status()
      SystemHealth.environment_info()
      SystemHealth.migration_status()

  ## Production Safety

  All checks are designed to be safe in production and Docker environments:
  - Graceful fallbacks for missing dependencies
  - No assumptions about file system paths
  - Docker-aware process detection
  - Safe error handling with timeouts
  """

  alias Events.SystemHealth.{
    Services,
    Environment,
    Migrations,
    Proxy,
    Mise,
    Infra,
    Display
  }

  @status_healthy :healthy
  @status_degraded :degraded
  @status_unhealthy :unhealthy

  @doc """
  Performs all health checks and returns comprehensive system status.

  Returns a map with all health information:
  - `:services` - Service health status
  - `:environment` - Environment configuration
  - `:migrations` - Database migration status
  - `:proxy` - Proxy configuration (if any)
  - `:mise` - Mise environment (if detected)
  - `:timestamp` - Check timestamp
  - `:duration_ms` - Time taken for checks
  """
  @spec check_all() :: map()
  def check_all do
    start_time = System.monotonic_time(:millisecond)

    result = %{
      services: Services.check_all(),
      environment: Environment.get_info(),
      migrations: Migrations.check_status(),
      proxy: Proxy.get_config(),
      mise: Mise.get_info(),
      infra: Infra.connections(),
      timestamp: DateTime.utc_now(),
      duration_ms: nil
    }

    end_time = System.monotonic_time(:millisecond)
    Map.put(result, :duration_ms, end_time - start_time)
  end

  @doc """
  Displays formatted system health status table.

  Options:
  - `:format` - Output format (`:table` (default), `:json`, `:compact`)
  - `:color` - Enable color output (default: `true`)
  """
  @spec display(keyword()) :: :ok
  def display(opts \\ []) do
    health = check_all()
    Display.render(health, opts)
  end

  @doc """
  Returns service health status only.
  """
  @spec services_status() :: list(map())
  def services_status do
    Services.check_all()
  end

  @doc """
  Returns environment information only.
  """
  @spec environment_info() :: map()
  def environment_info do
    Environment.get_info()
  end

  @doc """
  Returns migration status only.
  """
  @spec migration_status() :: map()
  def migration_status do
    Migrations.check_status()
  end

  @doc """
  Returns proxy configuration only.
  """
  @spec proxy_config() :: map()
  def proxy_config do
    Proxy.get_config()
  end

  @doc """
  Returns mise environment information only.
  """
  @spec mise_info() :: map()
  def mise_info do
    Mise.get_info()
  end

  @doc """
  Returns overall system health status.

  Returns:
  - `:healthy` - All critical services operational
  - `:degraded` - Some optional services down
  - `:unhealthy` - Critical services down
  """
  @spec overall_status() :: :healthy | :degraded | :unhealthy
  def overall_status do
    services = Services.check_all()

    critical_failed =
      Enum.any?(services, fn service ->
        service.critical and service.status != :ok
      end)

    optional_failed =
      Enum.any?(services, fn service ->
        not service.critical and service.status != :ok
      end)

    cond do
      critical_failed -> @status_unhealthy
      optional_failed -> @status_degraded
      true -> @status_healthy
    end
  end
end
