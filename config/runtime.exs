import Config

# Runtime configuration loaded for all environments
# This file is executed after compilation and before the system starts
# All configuration here uses environment variables managed by mise/fnox

# Get current environment
env = config_env()

# Database configuration for all environments
# All environments use mise/fnox for environment variable management
database_url =
  System.get_env("DATABASE_URL") ||
    case env do
      :test ->
        partition = System.get_env("MIX_TEST_PARTITION") || ""
        "ecto://postgres:postgres@localhost/events_test#{partition}"

      :dev ->
        "ecto://postgres:postgres@localhost/events_dev"

      :prod ->
        raise """
        environment variable DATABASE_URL is missing.
        Configure it in mise/fnox: mise set DATABASE_URL=ecto://USER:PASS@HOST/DATABASE
        """
    end

# IPv6 support (optional)
maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

# Base repo configuration with performance optimizations
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
  queue_target: String.to_integer(System.get_env("DB_QUEUE_TARGET") || "50"),
  queue_interval: String.to_integer(System.get_env("DB_QUEUE_INTERVAL") || "1000"),
  # Telemetry
  telemetry_prefix: [:events, :repo]
]

# Environment-specific repo configuration
repo_config =
  case env do
    :dev ->
      base_repo_config ++
        [
          pool_size: String.to_integer(System.get_env("DB_POOL_SIZE") || "10"),
          log: String.to_atom(System.get_env("DB_LOG_LEVEL") || "debug"),
          stacktrace: true,
          show_sensitive_data_on_connection_error: true
        ]

    :test ->
      base_repo_config ++
        [
          pool: Ecto.Adapters.SQL.Sandbox,
          pool_size: String.to_integer(System.get_env("DB_POOL_SIZE") || "#{System.schedulers_online() * 2}"),
          log: false
        ]

    :prod ->
      base_repo_config ++
        [
          pool_size: String.to_integer(System.get_env("DB_POOL_SIZE") || "10"),
          # Uncomment for multi-core systems with high load
          # pool_count: String.to_integer(System.get_env("DB_POOL_COUNT") || "4"),
          log: String.to_atom(System.get_env("DB_LOG_LEVEL") || "warning"),
          ssl: System.get_env("DB_SSL") in ~w(true 1)
        ]
  end

config :events, Events.Repo, repo_config

# Phoenix Endpoint configuration
if env == :dev do
  config :events, EventsWeb.Endpoint,
    http: [
      ip: {127, 0, 0, 1},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    check_origin: false,
    code_reloader: true,
    debug_errors: true,
    secret_key_base:
      System.get_env("SECRET_KEY_BASE") ||
        "vJtFNtGUA5c3eC18tawePzHZZr4Zd2pg7Popo59Mqml3MVtbfua54SkynyH3mL+G",
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

  # Enable dev routes for dashboard and mailbox
  config :events, dev_routes: true

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
end

if env == :test do
  config :events, EventsWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 4002],
    secret_key_base:
      System.get_env("SECRET_KEY_BASE") ||
        "YJMCebrCtSIMECylkrpmTGhQC0LKEfuQV/HHEJdiuCnKh838eu4ZVWZvKPOxQEcp",
    server: false

  # Test mailer
  config :events, Events.Mailer, adapter: Swoosh.Adapters.Test

  # Print only warnings and errors during test
  config :logger, level: :warning

  # Initialize plugs at runtime for faster test compilation
  config :phoenix, :plug_init_mode, :runtime

  # Enable expensive runtime checks in tests
  config :phoenix_live_view, enable_expensive_runtime_checks: true

  # Disable swoosh api client in test
  config :swoosh, :api_client, false
end

if env == :prod do
  # Enable server if PHX_SERVER is set
  if System.get_env("PHX_SERVER") in ~w(true 1) do
    config :events, EventsWeb.Endpoint, server: true
  end

  # Secret key base (required)
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Configure it in mise/fnox: mise set SECRET_KEY_BASE=$(mix phx.gen.secret)
      """

  # Host and port
  host = System.get_env("PHX_HOST") || raise "PHX_HOST environment variable is missing"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # DNS cluster configuration
  config :events, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :events, EventsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

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
