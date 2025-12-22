defmodule Events.Infra.KillSwitch do
  @moduledoc """
  Centralized kill switch system for external services.

  This module delegates to `OmKillSwitch` for core functionality.
  See `OmKillSwitch` for full documentation.

  ## Supported Services

  - `:s3` - AWS S3 storage
  - `:cache` - Redis/Local cache
  - `:database` - PostgreSQL database
  - `:email` - Email service (Swoosh)

  ## Quick Start

      if KillSwitch.enabled?(:s3) do
        S3.upload(bucket, key, content)
      else
        {:error, :service_disabled}
      end
  """

  @type service :: :s3 | :cache | :database | :email
  @type reason :: String.t()
  @type status :: OmKillSwitch.status()

  @services [:s3, :cache, :database, :email]

  # Delegate to OmKillSwitch with service validation
  defdelegate start_link(opts \\ []), to: OmKillSwitch
  defdelegate child_spec(opts), to: OmKillSwitch

  @doc "Checks if a service is enabled."
  @spec enabled?(service()) :: boolean()
  def enabled?(service) when service in @services do
    OmKillSwitch.enabled?(service)
  end

  @doc "Checks service status with pattern-matchable result."
  @spec check(service()) :: :enabled | {:disabled, reason()}
  def check(service) when service in @services do
    OmKillSwitch.check(service)
  end

  @doc "Executes a function if service is enabled, returns error otherwise."
  @spec execute(service(), (-> any())) :: any() | {:error, {:service_disabled, reason()}}
  def execute(service, func) when service in @services and is_function(func, 0) do
    OmKillSwitch.execute(service, func)
  end

  @doc "Executes a function with fallback if service is disabled."
  @spec with_service(service(), (-> any()), keyword()) :: any()
  def with_service(service, func, opts \\ [])
      when service in @services and is_function(func, 0) do
    OmKillSwitch.with_service(service, func, opts)
  end

  @doc "Gets detailed status for a service."
  @spec status(service()) :: status()
  def status(service) when service in @services do
    OmKillSwitch.status(service)
  end

  @doc "Gets status for all services."
  @spec status_all() :: %{service() => status()}
  def status_all do
    @services
    |> Enum.map(&{&1, status(&1)})
    |> Map.new()
  end

  @doc "Disables a service at runtime."
  @spec disable(service(), keyword()) :: :ok
  def disable(service, opts \\ []) when service in @services do
    OmKillSwitch.disable(service, opts)
  end

  @doc "Enables a service at runtime."
  @spec enable(service()) :: :ok
  def enable(service) when service in @services do
    OmKillSwitch.enable(service)
  end
end
