defmodule Events.Infra.KillSwitch do
  @moduledoc """
  Centralized kill switch system for external services.

  Provides graceful degradation when external services are unavailable.
  Services can be disabled via environment variables or runtime configuration,
  allowing the application to continue functioning with reduced capabilities.

  ## Supported Services

  - `:s3` - AWS S3 storage
  - `:cache` - Redis/Local cache
  - `:database` - PostgreSQL database
  - `:email` - Email service (Swoosh)

  ## Configuration

  Set environment variables to disable services:

      # Disable S3
      S3_ENABLED=false

      # Disable cache
      CACHE_ENABLED=false

      # Disable email
      EMAIL_ENABLED=false

  Or configure in runtime.exs:

      config :events, Events.Infra.KillSwitch,
        s3: true,
        cache: true,
        database: true,
        email: true

  ## Usage

  ### Check if service is enabled

      if KillSwitch.enabled?(:s3) do
        S3.upload(bucket, key, content)
      else
        {:error, :service_disabled}
      end

  ### Execute with fallback

      KillSwitch.with_service(:cache, fn ->
        Cache.get(key)
      end, fallback: fn -> {:ok, nil} end)

  ### Execute or return error

      KillSwitch.execute(:s3, fn ->
        S3.upload(bucket, key, content)
      end)

  ## Pattern Matching API

      case KillSwitch.check(:s3) do
        :enabled -> S3.upload(bucket, key, content)
        {:disabled, reason} -> {:error, {:service_disabled, reason}}
      end

  ## Runtime Toggle

      # Disable service at runtime
      KillSwitch.disable(:s3, reason: "S3 outage detected")

      # Re-enable service
      KillSwitch.enable(:s3)

      # Check status
      KillSwitch.status(:s3)
      #=> %{enabled: false, reason: "S3 outage detected", disabled_at: ~U[...]}

  ## Graceful Degradation Examples

      # S3: Fall back to database storage
      KillSwitch.with_service(:s3,
        fn -> S3.upload(bucket, key, content) end,
        fallback: fn -> DbStorage.save(key, content) end
      )

      # Cache: Proceed without caching
      KillSwitch.with_service(:cache,
        fn -> Cache.put(key, value) end,
        fallback: fn -> :ok end
      )

      # Email: Log instead of sending
      KillSwitch.with_service(:email,
        fn -> Mailer.deliver(email) end,
        fallback: fn ->
          Logger.info("Email not sent (service disabled): \#{inspect(email)}")
          :ok
        end
      )
  """

  use GenServer
  require Logger

  @type service :: :s3 | :cache | :database | :email
  @type reason :: String.t()
  @type status :: %{
          enabled: boolean(),
          reason: reason() | nil,
          disabled_at: DateTime.t() | nil
        }

  @services [:s3, :cache, :database, :email]

  ## Public API

  @doc """
  Checks if a service is enabled.

  ## Examples

      KillSwitch.enabled?(:s3)
      #=> true

      KillSwitch.enabled?(:cache)
      #=> false
  """
  @spec enabled?(service()) :: boolean()
  def enabled?(service) when service in @services do
    case check(service) do
      :enabled -> true
      {:disabled, _reason} -> false
    end
  end

  @doc """
  Checks service status with pattern-matchable result.

  ## Examples

      case KillSwitch.check(:s3) do
        :enabled ->
          S3.upload(bucket, key, content)

        {:disabled, reason} ->
          Logger.warning("S3 disabled: \#{reason}")
          {:error, :service_disabled}
      end
  """
  @spec check(service()) :: :enabled | {:disabled, reason()}
  def check(service) when service in @services do
    case get_service_state(service) do
      %{enabled: true} -> :enabled
      %{enabled: false, reason: reason} -> {:disabled, reason}
    end
  end

  @doc """
  Executes a function if service is enabled, returns error otherwise.

  ## Examples

      KillSwitch.execute(:s3, fn ->
        S3.upload(bucket, key, content)
      end)
      #=> :ok or {:error, {:service_disabled, reason}}
  """
  @spec execute(service(), (-> any())) :: any() | {:error, {:service_disabled, reason()}}
  def execute(service, func) when service in @services and is_function(func, 0) do
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

      KillSwitch.with_service(:cache,
        fn -> Cache.get(key) end,
        fallback: fn -> {:ok, nil} end
      )
  """
  @spec with_service(service(), (-> any()), keyword()) :: any()
  def with_service(service, func, opts \\ [])
      when service in @services and is_function(func, 0) do
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

      KillSwitch.status(:s3)
      #=> %{enabled: true, reason: nil, disabled_at: nil}

      KillSwitch.status(:cache)
      #=> %{enabled: false, reason: "Redis connection failed", disabled_at: ~U[2024-01-15 10:30:00Z]}
  """
  @spec status(service()) :: status()
  def status(service) when service in @services do
    get_service_state(service)
  end

  @doc """
  Gets status for all services.

  ## Examples

      KillSwitch.status_all()
      #=> %{
      #     s3: %{enabled: true, reason: nil, disabled_at: nil},
      #     cache: %{enabled: false, reason: "Redis down", disabled_at: ~U[...]},
      #     ...
      #   }
  """
  @spec status_all() :: %{service() => status()}
  def status_all do
    @services
    |> Enum.map(&{&1, status(&1)})
    |> Map.new()
  end

  @doc """
  Disables a service at runtime.

  ## Options

  - `:reason` - Reason for disabling (optional, default: "Manually disabled")

  ## Examples

      KillSwitch.disable(:s3, reason: "S3 outage detected")
      #=> :ok
  """
  @spec disable(service(), keyword()) :: :ok
  def disable(service, opts \\ []) when service in @services do
    reason = Keyword.get(opts, :reason, "Manually disabled")
    GenServer.call(__MODULE__, {:disable, service, reason})
  end

  @doc """
  Enables a service at runtime.

  ## Examples

      KillSwitch.enable(:s3)
      #=> :ok
  """
  @spec enable(service()) :: :ok
  def enable(service) when service in @services do
    GenServer.call(__MODULE__, {:enable, service})
  end

  ## GenServer Implementation

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    state = initialize_services()
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_state, service}, _from, state) do
    service_state = Map.get(state, service)
    {:reply, service_state, state}
  end

  @impl GenServer
  def handle_call({:disable, service, reason}, _from, state) do
    new_state = update_service_state(state, service, false, reason)

    Logger.warning("Service #{service} disabled: #{reason}")

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:enable, service}, _from, state) do
    new_state = update_service_state(state, service, true, nil)

    Logger.info("Service #{service} enabled")

    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp initialize_services do
    @services
    |> Enum.map(&{&1, initialize_service(&1)})
    |> Map.new()
  end

  defp initialize_service(service) do
    enabled = read_service_config(service)

    %{
      enabled: enabled,
      reason: if(enabled, do: nil, else: "Disabled via configuration"),
      disabled_at: if(enabled, do: nil, else: DateTime.utc_now())
    }
  end

  defp read_service_config(:s3) do
    case System.get_env("S3_ENABLED") do
      nil -> get_app_config(:s3, true)
      value -> parse_boolean(value)
    end
  end

  defp read_service_config(:cache) do
    case System.get_env("CACHE_ENABLED") do
      nil -> get_app_config(:cache, true)
      value -> parse_boolean(value)
    end
  end

  defp read_service_config(:database) do
    case System.get_env("DATABASE_ENABLED") do
      nil -> get_app_config(:database, true)
      value -> parse_boolean(value)
    end
  end

  defp read_service_config(:email) do
    case System.get_env("EMAIL_ENABLED") do
      nil -> get_app_config(:email, true)
      value -> parse_boolean(value)
    end
  end

  defp get_app_config(service, default) do
    Application.get_env(:events, __MODULE__, [])
    |> Keyword.get(service, default)
  end

  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(value) when value in ["1", "true", "yes"], do: true
  defp parse_boolean(value) when value in ["0", "false", "no"], do: false
  defp parse_boolean(_value), do: false

  defp get_service_state(service) do
    case Process.whereis(__MODULE__) do
      nil ->
        # GenServer not started, use config defaults
        %{
          enabled: read_service_config(service),
          reason: nil,
          disabled_at: nil
        }

      _pid ->
        GenServer.call(__MODULE__, {:get_state, service})
    end
  end

  defp update_service_state(state, service, enabled, reason) do
    Map.update!(state, service, fn current ->
      case enabled do
        true ->
          %{current | enabled: true, reason: nil, disabled_at: nil}

        false ->
          %{current | enabled: false, reason: reason, disabled_at: DateTime.utc_now()}
      end
    end)
  end
end
