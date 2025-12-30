defmodule Events.Infra.ConfigValidator do
  @moduledoc """
  Validates service configurations at startup.

  Runs before services start to catch configuration errors early.
  Integrates with SystemHealth for display.

  ## Service Validation

  Each service has a validator function that returns:
  - `{:ok, metadata}` - Configuration is valid with metadata
  - `{:error, reason}` - Configuration is invalid with reason
  - `{:warning, reason, metadata}` - Configuration has warnings but is usable
  - `{:disabled, reason}` - Service is intentionally disabled (via KillSwitch)

  ## Usage

      # Validate all services
      ConfigValidator.validate_all()
      #=> %{ok: [...], warnings: [...], errors: [...], disabled: [...]}

      # Validate only critical services (fail fast)
      ConfigValidator.validate_critical()
      #=> {:ok, results} | {:error, errors}

      # Check specific service
      ConfigValidator.validate_service(:database)
      #=> {:ok, metadata} | {:error, reason}
  """

  use FnTypes.Config.Validator

  alias FnTypes.Config, as: Cfg
  alias FnTypes.Config.Validator
  alias Events.Infra.KillSwitch

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)

  # ============================================
  # Service Validator Definitions (DSL)
  # ============================================

  validators do
    service(:database,
      validator: &__MODULE__.validate_database/0,
      critical: true,
      description: "PostgreSQL connection"
    )

    service(:cache,
      validator: &__MODULE__.validate_cache/0,
      critical: false,
      description: "Cache adapter (Redis/Local)"
    )

    service(:s3,
      validator: &__MODULE__.validate_s3/0,
      critical: false,
      description: "S3/MinIO configuration"
    )

    service(:scheduler,
      validator: &__MODULE__.validate_scheduler/0,
      critical: false,
      description: "Background job scheduler"
    )

    service(:email,
      validator: &__MODULE__.validate_email/0,
      critical: false,
      description: "Email service (Swoosh)"
    )

    service(:stripe,
      validator: &__MODULE__.validate_stripe/0,
      critical: false,
      description: "Stripe payment gateway"
    )
  end

  # ============================================
  # Service Validators
  # ============================================

  @doc """
  Validates database configuration.

  Checks:
  - DATABASE_URL is set (production only)
  - Connection string is parseable
  - Pool size is reasonable
  """
  @spec validate_database() :: Validator.validation_result()
  def validate_database do
    Validator.with_checks(
      [
        fn -> check_database_url() end,
        fn -> check_pool_size() end
      ],
      %{}
    )
    |> case do
      {:ok, _} -> build_database_metadata()
      error -> error
    end
  end

  @doc """
  Validates cache configuration.

  Checks:
  - Cache adapter is configured
  - Adapter-specific settings are valid
  """
  @spec validate_cache() :: Validator.validation_result()
  def validate_cache do
    with {:ok, config} <- safe_build_cache_config(),
         {:ok, adapter_info} <- validate_cache_adapter(config) do
      {:ok, Map.merge(%{adapter: config[:adapter]}, adapter_info)}
    end
  end

  @doc """
  Validates S3 configuration.

  Only validates if S3 is enabled via KillSwitch.
  Checks:
  - AWS credentials are set
  - S3 bucket is configured
  - Region is specified
  """
  @spec validate_s3() :: Validator.validation_result()
  def validate_s3 do
    if not KillSwitch.enabled?(:s3) do
      {:disabled, "Service disabled via KillSwitch"}
    else
      validate_s3_config()
    end
  end

  @doc """
  Validates scheduler configuration.

  Checks:
  - Config is valid per NimbleOptions schema
  - Store backend is compatible
  - Peer module is available (if using database store)
  """
  @spec validate_scheduler() :: Validator.validation_result()
  def validate_scheduler do
    with {:ok, config} <- safe_validate_scheduler_config(),
         :ok <- validate_scheduler_store(config) do
      {:ok,
       %{
         enabled: config[:enabled],
         store: config[:store],
         peer: format_peer(config[:peer]),
         queues: Keyword.keys(config[:queues] || [])
       }}
    end
  end

  @doc """
  Validates email configuration.

  Checks:
  - Mailer adapter is configured
  - Production adapter has credentials (if prod)
  """
  @spec validate_email() :: Validator.validation_result()
  def validate_email do
    config = Application.get_env(@app_name, Events.Infra.Mailer, [])
    adapter = Keyword.get(config, :adapter)

    case adapter do
      nil ->
        {:error, "Mailer adapter not configured"}

      Swoosh.Adapters.Local ->
        {:ok, %{adapter: "Local (dev)", configured: true}}

      Swoosh.Adapters.Test ->
        {:ok, %{adapter: "Test", configured: true}}

      _ ->
        validate_production_mailer(adapter, config)
    end
  end

  @doc """
  Validates Stripe configuration.

  Optional service - only validates if API key is present.
  Checks:
  - API key format (test vs live)
  - API version is specified
  """
  @spec validate_stripe() :: Validator.validation_result()
  def validate_stripe do
    case Cfg.string(["STRIPE_API_KEY", "STRIPE_SECRET_KEY"]) do
      nil ->
        {:disabled, "API key not set (optional service)"}

      api_key ->
        with {:ok, config} <- safe_build_stripe_config() do
          mode = if String.starts_with?(api_key, "sk_test_"), do: "test", else: "live"

          {:ok,
           %{
             configured: true,
             mode: mode,
             api_version: config.api_version
           }}
        end
    end
  end

  # ============================================
  # Database Validation Helpers
  # ============================================

  defp check_database_url do
    case Cfg.string("DATABASE_URL") do
      nil ->
        if Mix.env() == :prod do
          {:error, "DATABASE_URL not set (required in production)"}
        else
          :ok
        end

      url ->
        parse_database_url(url)
    end
  end

  defp parse_database_url(url) do
    try do
      parsed = URI.parse(url)

      if parsed.host && parsed.path do
        :ok
      else
        {:error, "Invalid DATABASE_URL format"}
      end
    rescue
      _ -> {:error, "Failed to parse DATABASE_URL"}
    end
  end

  defp check_pool_size do
    pool_size = Cfg.integer("DB_POOL_SIZE", 10)

    cond do
      pool_size < 1 -> {:error, "DB_POOL_SIZE must be at least 1"}
      pool_size > 100 -> {:error, "DB_POOL_SIZE too large (max 100)"}
      true -> :ok
    end
  end

  defp build_database_metadata do
    url = Cfg.string("DATABASE_URL") || default_dev_url()
    parsed = URI.parse(url)
    pool_size = Cfg.integer("DB_POOL_SIZE", 10)

    {:ok,
     %{
       url: Validator.mask_url(url),
       host: parsed.host,
       database: parsed.path,
       pool_size: pool_size,
       ssl: Cfg.boolean("DB_SSL", false)
     }}
  end

  defp default_dev_url do
    case Mix.env() do
      :test ->
        partition = Cfg.string("MIX_TEST_PARTITION", "")
        "ecto://postgres:postgres@localhost/events_test#{partition}"

      :dev ->
        "ecto://postgres:postgres@localhost:5432/events_dev"
    end
  end

  # ============================================
  # Cache Validation Helpers
  # ============================================

  defp safe_build_cache_config do
    try do
      config = OmCache.Config.build()
      {:ok, config}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp validate_cache_adapter(config) do
    adapter = config[:adapter]

    case adapter do
      NebulexRedisAdapter ->
        redis_opts = config[:conn_opts] || []
        host = Keyword.get(redis_opts, :host, "localhost")
        port = Keyword.get(redis_opts, :port, 6379)
        {:ok, %{backend: "Redis", host: host, port: port}}

      Nebulex.Adapters.Local ->
        {:ok, %{backend: "Local (in-memory)"}}

      Nebulex.Adapters.Nil ->
        {:ok, %{backend: "Nil (no-op)"}}

      nil ->
        {:error, "Cache adapter not configured"}

      _ ->
        {:ok, %{backend: inspect(adapter)}}
    end
  end

  # ============================================
  # S3 Validation Helpers
  # ============================================

  defp validate_s3_config do
    with {:ok, config} <- safe_build_s3_config(),
         {:ok, bucket} <- validate_s3_bucket() do
      result = %{
        region: config.region,
        bucket: bucket,
        endpoint: config.endpoint
      }

      if is_nil(bucket) do
        {:warning, "S3 bucket not configured (optional service)", result}
      else
        {:ok, result}
      end
    end
  end

  defp safe_build_s3_config do
    try do
      config = OmS3.Config.from_env()
      {:ok, config}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp validate_s3_bucket do
    case Cfg.string(["S3_BUCKET", "AWS_S3_BUCKET"]) do
      nil -> {:ok, nil}
      bucket -> {:ok, bucket}
    end
  end

  # ============================================
  # Scheduler Validation Helpers
  # ============================================

  defp safe_validate_scheduler_config do
    try do
      config = OmScheduler.Config.get!()
      {:ok, config}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp validate_scheduler_store(config) do
    store = Keyword.get(config, :store)
    repo = Keyword.get(config, :repo)

    case {store, repo} do
      {:database, nil} -> {:error, "Scheduler store is :database but repo not configured"}
      _ -> :ok
    end
  end

  defp format_peer(nil), do: "None"
  defp format_peer(false), do: "Disabled"
  defp format_peer(peer) when is_atom(peer), do: inspect(peer)

  # ============================================
  # Email Validation Helpers
  # ============================================

  defp validate_production_mailer(adapter, config) do
    adapter_name =
      adapter
      |> Module.split()
      |> List.last()

    case {adapter_name, config} do
      {"Mailgun", config} ->
        validate_mailgun_config(config)

      {"Sendgrid", config} ->
        validate_sendgrid_config(config)

      {name, _} ->
        {:ok, %{adapter: name, configured: true, warning: "Config not validated"}}
    end
  end

  defp validate_mailgun_config(config) do
    api_key = Keyword.get(config, :api_key)
    domain = Keyword.get(config, :domain)

    cond do
      is_nil(api_key) -> {:error, "Mailgun API key not set"}
      is_nil(domain) -> {:error, "Mailgun domain not set"}
      true -> {:ok, %{adapter: "Mailgun", configured: true}}
    end
  end

  defp validate_sendgrid_config(config) do
    api_key = Keyword.get(config, :api_key)

    if is_nil(api_key) do
      {:error, "Sendgrid API key not set"}
    else
      {:ok, %{adapter: "Sendgrid", configured: true}}
    end
  end

  # ============================================
  # Stripe Validation Helpers
  # ============================================

  defp safe_build_stripe_config do
    try do
      config = Events.Api.Clients.Stripe.Config.from_env()
      {:ok, config}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
