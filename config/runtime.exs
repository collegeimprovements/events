import Config

# Runtime configuration loaded for all environments
# This file is executed after compilation and before the system starts
# All configuration here uses environment variables managed by mise/fnox

# Load config utilities (must use Code.require_file for config-time evaluation)
Code.require_file("config_helper.ex", __DIR__)

# Get current environment
env = config_env()

# ==============================================================================
# DATABASE CONFIGURATION
# ==============================================================================

# Database URL resolution
database_url =
  ConfigHelper.get_env("DATABASE_URL") ||
    case env do
      :test ->
        ConfigHelper.get_env("MIX_TEST_PARTITION", "")
        |> then(&"ecto://postgres:postgres@localhost/events_test#{&1}")

      :dev ->
        "ecto://postgres:postgres@localhost:5432/events_dev"

      :prod ->
        raise """
        environment variable DATABASE_URL is missing.
        Configure it in mise/fnox: mise set DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
        """
    end

# IPv6 support (optional)
maybe_ipv6 =
  ConfigHelper.get_env_boolean("ECTO_IPV6", false)
  |> then(&if &1, do: [:inet6], else: [])

# Base repo configuration shared across all environments
base_repo_config = [
  url: database_url,
  socket_options: maybe_ipv6,
  # PostgreSQL 18+ optimized settings
  prepare: :unnamed,
  # UTC enforcement for all timestamps
  parameters: [
    timezone: "UTC",
    application_name: "events_#{env}"
  ],
  # Connection pool settings
  queue_target: ConfigHelper.get_env_integer("DB_QUEUE_TARGET", 50),
  queue_interval: ConfigHelper.get_env_integer("DB_QUEUE_INTERVAL", 1000),
  # Telemetry
  telemetry_prefix: [:events, :repo]
]

# Environment-specific repo configuration
repo_config =
  base_repo_config
  |> then(fn base ->
    case env do
      :dev ->
        base ++
          [
            pool_size: ConfigHelper.get_env_integer("DB_POOL_SIZE", 10),
            log: ConfigHelper.get_env_atom("DB_LOG_LEVEL", "debug"),
            stacktrace: true,
            show_sensitive_data_on_connection_error: true
          ]

      :test ->
        base ++
          [
            pool: Ecto.Adapters.SQL.Sandbox,
            pool_size:
              System.schedulers_online()
              |> then(&(&1 * 2))
              |> Integer.to_string()
              |> then(&ConfigHelper.get_env_integer("DB_POOL_SIZE", &1)),
            log: false
          ]

      :prod ->
        base ++
          [
            pool_size: ConfigHelper.get_env_integer("DB_POOL_SIZE", 10),
            # Uncomment for multi-core systems with high load
            # pool_count: ConfigHelper.get_env_integer("DB_POOL_COUNT", 4),
            log: ConfigHelper.get_env_atom("DB_LOG_LEVEL", "warning"),
            ssl: ConfigHelper.get_env_boolean("DB_SSL")
          ]
    end
  end)

config :events, Events.Repo, repo_config

# ==============================================================================
# CACHE CONFIGURATION
# ==============================================================================

config :events, Events.Cache, ConfigHelper.get_cache_config()

# ==============================================================================
# PHOENIX ENDPOINT CONFIGURATION
# ==============================================================================

# Environment-specific endpoint configuration
endpoint_config =
  case env do
    :dev ->
      [
        http: [
          ip: {127, 0, 0, 1},
          port: ConfigHelper.get_env_integer("PORT", 4000)
        ],
        check_origin: false,
        code_reloader: true,
        debug_errors: true,
        secret_key_base:
          ConfigHelper.get_env(
            "SECRET_KEY_BASE",
            "vJtFNtGUA5c3eC18tawePzHZZr4Zd2pg7Popo59Mqml3MVtbfua54SkynyH3mL+G"
          ),
        watchers: [
          esbuild: {Esbuild, :install_and_run, [:events, ~w(--sourcemap=inline --watch)]},
          tailwind: {Tailwind, :install_and_run, [:events, ~w(--watch)]}
        ],
        live_reload: [
          web_console_logger: true,
          patterns: [
            ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
            ~r"priv/gettext/.*(po)$",
            ~r"lib/events_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
          ]
        ]
      ]

    :test ->
      [
        http: [ip: {127, 0, 0, 1}, port: 4002],
        secret_key_base:
          ConfigHelper.get_env(
            "SECRET_KEY_BASE",
            "YJMCebrCtSIMECylkrpmTGhQC0LKEfuQV/HHEJdiuCnKh838eu4ZVWZvKPOxQEcp"
          ),
        server: false
      ]

    :prod ->
      secret_key_base =
        ConfigHelper.get_env("SECRET_KEY_BASE") ||
          raise """
          environment variable SECRET_KEY_BASE is missing.
          Configure it in mise/fnox: mise set SECRET_KEY_BASE=$(mix phx.gen.secret)
          """

      host =
        ConfigHelper.get_env("PHX_HOST") ||
          raise "PHX_HOST environment variable is missing"

      [
        url: [host: host, port: 443, scheme: "https"],
        http: [
          ip: {0, 0, 0, 0, 0, 0, 0, 0},
          port: ConfigHelper.get_env_integer("PORT", 4000)
        ],
        secret_key_base: secret_key_base,
        server: ConfigHelper.get_env_boolean("PHX_SERVER", false)
      ]
  end

config :events, EventsWeb.Endpoint, endpoint_config

# ==============================================================================
# ENVIRONMENT-SPECIFIC CONFIGURATIONS
# ==============================================================================

case env do
  :dev ->
    # Enable dev routes for dashboard and mailbox
    config :events, dev_routes: true

    # Schema validation (validates schemas against DB on startup)
    # Logs warnings but doesn't fail in dev
    config :events, :schema_validation,
      enabled: true,
      on_startup: true,
      fail_on_error: false

    # Set a higher stacktrace during development
    config :phoenix, :stacktrace_depth, 20

    # Initialize plugs at runtime for faster development compilation
    config :phoenix, :plug_init_mode, :runtime

    # Phoenix LiveView development settings
    config :phoenix_live_view,
      debug_heex_annotations: true,
      debug_attributes: true,
      enable_expensive_runtime_checks: true

    # Disable swoosh api client in development
    config :swoosh, :api_client, false

  :test ->
    # Test mailer
    config :events, Events.Mailer, adapter: Swoosh.Adapters.Test

    # Schema validation (validates schemas against DB on startup)
    # Fails fast in tests if schemas don't match DB
    config :events, :schema_validation,
      enabled: true,
      on_startup: true,
      fail_on_error: true

    # Print only warnings and errors during test
    config :logger, level: :warning

    # Initialize plugs at runtime for faster test compilation
    config :phoenix, :plug_init_mode, :runtime

    # Enable expensive runtime checks in tests
    config :phoenix_live_view, enable_expensive_runtime_checks: true

    # Disable swoosh api client in test
    config :swoosh, :api_client, false

  :prod ->
    # DNS cluster configuration for multi-node deployment
    # Set DNS_CLUSTER_QUERY to your service discovery DNS name
    config :events, :dns_cluster_query, ConfigHelper.get_env("DNS_CLUSTER_QUERY")

    # Production mailer configuration
    # Configure based on your email service provider
    # Example for Mailgun (uncomment and configure):
    # config :events, Events.Mailer,
    #   adapter: Swoosh.Adapters.Mailgun,
    #   api_key: System.get_env("MAILGUN_API_KEY"),
    #   domain: System.get_env("MAILGUN_DOMAIN")

    # Swoosh API client for production
    # config :swoosh, :api_client, Swoosh.ApiClient.Req
end
