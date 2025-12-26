import Config

# General application configuration
config :events,
  ecto_repos: [Events.Core.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Repo configuration with UUIDv7 and UTC timestamp defaults
# PostgreSQL 18+ has native uuidv7() function - no extensions needed
config :events, Events.Core.Repo,
  migration_primary_key: [type: :uuid, default: {:fragment, "uuidv7()"}],
  migration_foreign_key: [type: :uuid],
  migration_timestamps: [
    type: :utc_datetime_usec,
    null: false,
    default: {:fragment, "CURRENT_TIMESTAMP"}
  ]

# ─────────────────────────────────────────────────────────────
# OmSchema library configuration
# ─────────────────────────────────────────────────────────────
config :om_schema,
  default_repo: Events.Core.Repo,
  app_name: :events,
  telemetry_prefix: [:events, :schema]

# ─────────────────────────────────────────────────────────────
# OmQuery library configuration
# ─────────────────────────────────────────────────────────────
config :om_query,
  default_repo: Events.Core.Repo,
  telemetry_prefix: [:events, :query]

# ─────────────────────────────────────────────────────────────
# OmCrud library configuration
# ─────────────────────────────────────────────────────────────
config :om_crud,
  default_repo: Events.Core.Repo,
  telemetry_prefix: [:events, :crud]

# ─────────────────────────────────────────────────────────────
# FnTypes library configuration
# ─────────────────────────────────────────────────────────────
config :fn_types,
  telemetry_prefix: [:events]

# ─────────────────────────────────────────────────────────────
# FnDecorator library configuration
# ─────────────────────────────────────────────────────────────
config :fn_decorator, FnDecorator.Telemetry,
  repo: Events.Core.Repo,
  telemetry_prefix: [:events]

# ─────────────────────────────────────────────────────────────
# OmScheduler library configuration
# ─────────────────────────────────────────────────────────────
config :om_scheduler,
  app_name: :events,
  repo: Events.Core.Repo,
  telemetry_prefix: [:events, :scheduler]

# Phoenix endpoint configuration
config :events, EventsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EventsWeb.ErrorHTML, json: EventsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Events.Infra.PubSub.Server,
  live_view: [signing_salt: "bADKq9rD"]

# Mailer configuration
config :events, Events.Infra.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  events: [
    args:
      ~w(./js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()] |> Enum.join(":")
    }
  ]

# Configure tailwind
config :tailwind,
  version: "4.1.7",
  events: [
    args:
      ~w(--input) ++
        [Path.expand("../assets/css/app.css", __DIR__)] ++
        ~w(--output) ++
        [Path.expand("../priv/static/assets/css/app.css", __DIR__)],
    cd: Path.expand("..", __DIR__)
  ]

# Cache configuration
# NOTE: The adapter is configured at runtime via the CACHE_ADAPTER environment variable
# in config/runtime.exs. Default is "redis". Set CACHE_ADAPTER to "local", "redis", or "null".
# See lib/events/cache.ex for more details.
# Adapter-specific configuration is set in runtime.exs based on the selected adapter.

# Hammer rate limiter configuration
# NOTE: Backend is configured at runtime in config/runtime.exs

# Logger configuration
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Compile-time options (Phoenix reads these during compilation)
if config_env() == :dev do
  config :events, dev_routes: true
  config :events, EventsWeb.Endpoint, code_reloader: true, debug_errors: true
end

# Scheduler configuration (defaults for development)
# Production settings should be configured in runtime.exs
config :events, Events.Infra.Scheduler,
  enabled: true,
  store: :memory,
  peer: Events.Infra.Scheduler.Peer.Global,
  queues: [default: 5],
  plugins: []

# NOTE: runtime.exs is automatically loaded at application startup
# Do NOT use import_config "runtime.exs" - that would run it at compile time
