defmodule OmKillSwitch do
  @moduledoc """
  Runtime service kill switch for graceful degradation.

  Provides a centralized way to enable/disable services at runtime,
  allowing applications to continue functioning with reduced capabilities
  when external services are unavailable.

  ## Configuration

  Set environment variables to disable services:

      # Disable a service
      MY_SERVICE_ENABLED=false

  Or configure in your application:

      config :om_kill_switch,
        services: [:s3, :cache, :email, :database],
        s3: true,
        cache: true,
        email: true,
        database: true

  ## Usage

  ### Check if service is enabled

      case OmKillSwitch.enabled?(:s3) do
        true -> S3.upload(bucket, key, content)
        false -> {:error, :service_disabled}
      end

  ### Execute with fallback

      OmKillSwitch.with_service(:cache, fn ->
        Cache.get(key)
      end, fallback: fn -> {:ok, nil} end)

  ### Execute or return error

      OmKillSwitch.execute(:s3, fn ->
        S3.upload(bucket, key, content)
      end)

  ## Pattern Matching API

      case OmKillSwitch.check(:s3) do
        :enabled -> S3.upload(bucket, key, content)
        {:disabled, reason} -> {:error, {:service_disabled, reason}}
      end

  ## Runtime Toggle

      # Disable service at runtime
      OmKillSwitch.disable(:s3, reason: "S3 outage detected")

      # Re-enable service
      OmKillSwitch.enable(:s3)

      # Check status
      OmKillSwitch.status(:s3)
      #=> %{enabled: false, reason: "S3 outage detected", disabled_at: ~U[...]}
  """

  use GenServer
  require Logger

  @type service :: atom()
  @type reason :: String.t()
  @type status :: %{
          enabled: boolean(),
          reason: reason() | nil,
          disabled_at: DateTime.t() | nil
        }

  @type opts :: [
          services: [service()],
          name: atom()
        ]

  ## Public API

  @doc """
  Checks if a service is enabled.

  ## Examples

      OmKillSwitch.enabled?(:s3)
      #=> true
  """
  @spec enabled?(service()) :: boolean()
  def enabled?(service) do
    case check(service) do
      :enabled -> true
      {:disabled, _reason} -> false
    end
  end

  @doc """
  Checks service status with pattern-matchable result.

  ## Examples

      case OmKillSwitch.check(:s3) do
        :enabled ->
          S3.upload(bucket, key, content)

        {:disabled, reason} ->
          Logger.warning("S3 disabled: \#{reason}")
          {:error, :service_disabled}
      end
  """
  @spec check(service()) :: :enabled | {:disabled, reason()}
  def check(service) do
    case get_service_state(service) do
      %{enabled: true} -> :enabled
      %{enabled: false, reason: reason} -> {:disabled, reason}
    end
  end

  @doc """
  Executes a function if service is enabled, returns error otherwise.

  ## Examples

      OmKillSwitch.execute(:s3, fn ->
        S3.upload(bucket, key, content)
      end)
      #=> :ok or {:error, {:service_disabled, reason}}
  """
  @spec execute(service(), (-> any())) :: any() | {:error, {:service_disabled, reason()}}
  def execute(service, func) when is_function(func, 0) do
    case check(service) do
      :enabled ->
        func.()

      {:disabled, reason} ->
        {:error, {:service_disabled, reason}}
    end
  end

  @doc """
  Executes a function with fallback if service is disabled.

  ## Options

  - `:fallback` - Function to execute if service is disabled (required)

  ## Examples

      OmKillSwitch.with_service(:cache,
        fn -> Cache.get(key) end,
        fallback: fn -> {:ok, nil} end
      )
  """
  @spec with_service(service(), (-> any()), keyword()) :: any()
  def with_service(service, func, opts \\ []) when is_function(func, 0) do
    fallback = Keyword.fetch!(opts, :fallback)

    case check(service) do
      :enabled ->
        func.()

      {:disabled, reason} ->
        Logger.debug("Service #{service} disabled: #{reason}, using fallback")
        fallback.()
    end
  end

  @doc """
  Gets detailed status for a service.

  ## Examples

      OmKillSwitch.status(:s3)
      #=> %{enabled: true, reason: nil, disabled_at: nil}
  """
  @spec status(service()) :: status()
  def status(service) do
    get_service_state(service)
  end

  @doc """
  Gets status for all registered services.
  """
  @spec status_all() :: %{service() => status()}
  def status_all do
    Map.new(services(), &{&1, status(&1)})
  end

  @doc """
  Returns list of registered services.
  """
  @spec services() :: [service()]
  def services do
    Application.get_env(:om_kill_switch, :services, [])
  end

  @doc """
  Disables a service at runtime.

  ## Options

  - `:reason` - Reason for disabling (default: "Manually disabled")

  ## Examples

      OmKillSwitch.disable(:s3, reason: "S3 outage detected")
      #=> :ok
  """
  @spec disable(service(), keyword()) :: :ok
  def disable(service, opts \\ []) do
    reason = Keyword.get(opts, :reason, "Manually disabled")
    GenServer.call(server_name(), {:disable, service, reason})
  end

  @doc """
  Enables a service at runtime.

  ## Examples

      OmKillSwitch.enable(:s3)
      #=> :ok
  """
  @spec enable(service()) :: :ok
  def enable(service) do
    GenServer.call(server_name(), {:enable, service})
  end

  ## GenServer Implementation

  @doc """
  Starts the kill switch GenServer.

  ## Options

  - `:services` - List of service atoms to manage
  - `:name` - Process name (default: OmKillSwitch)
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl GenServer
  def init(opts) do
    services = Keyword.get(opts, :services, services())
    state = initialize_services(services)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_state, service}, _from, state) do
    service_state = Map.get(state, service, default_state(service))
    {:reply, service_state, state}
  end

  @impl GenServer
  def handle_call({:disable, service, reason}, _from, state) do
    new_state = update_service_state(state, service, false, reason)
    Logger.warning("[OmKillSwitch] Service #{service} disabled: #{reason}")
    emit_telemetry(:disabled, service, reason)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:enable, service}, _from, state) do
    new_state = update_service_state(state, service, true, nil)
    Logger.info("[OmKillSwitch] Service #{service} enabled")
    emit_telemetry(:enabled, service, nil)
    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp server_name do
    Application.get_env(:om_kill_switch, :name, __MODULE__)
  end

  defp initialize_services(services) do
    Map.new(services, &{&1, initialize_service(&1)})
  end

  defp initialize_service(service) do
    enabled = read_service_config(service)

    build_status(enabled)
  end

  defp read_service_config(service) do
    env_var = "#{String.upcase(to_string(service))}_ENABLED"

    case System.get_env(env_var) do
      nil -> Application.get_env(:om_kill_switch, service, true)
      value when value in ["false", "0"] -> false
      _other -> true
    end
  end

  defp get_service_state(service) do
    case Process.whereis(server_name()) do
      nil ->
        # GenServer not started, use config defaults
        default_state(service)

      _pid ->
        GenServer.call(server_name(), {:get_state, service})
    end
  end

  defp default_state(service) do
    %{
      enabled: read_service_config(service),
      reason: nil,
      disabled_at: nil
    }
  end

  defp update_service_state(state, service, true, _reason) do
    Map.put(state, service, %{enabled: true, reason: nil, disabled_at: nil})
  end

  defp update_service_state(state, service, false, reason) do
    Map.put(state, service, %{enabled: false, reason: reason, disabled_at: DateTime.utc_now()})
  end

  defp emit_telemetry(event, service, reason) do
    :telemetry.execute(
      [:om_kill_switch, event],
      %{count: 1},
      %{service: service, reason: reason}
    )
  end

  defp build_status(true), do: %{enabled: true, reason: nil, disabled_at: nil}
  defp build_status(false), do: %{enabled: false, reason: "Disabled via configuration", disabled_at: DateTime.utc_now()}
end
