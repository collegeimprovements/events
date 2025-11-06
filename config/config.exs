import Config

# General application configuration
config :events,
  ecto_repos: [Events.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Repo configuration with UUIDv7 and UTC timestamp defaults
# PostgreSQL 18+ has native uuidv7() function - no extensions needed
config :events, Events.Repo,
  migration_primary_key: [type: :uuid, default: {:fragment, "uuidv7()"}],
  migration_foreign_key: [type: :uuid],
  migration_timestamps: [
    type: :utc_datetime_usec,
    null: false,
    default: {:fragment, "CURRENT_TIMESTAMP"}
  ]

# Phoenix endpoint configuration
config :events, EventsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EventsWeb.ErrorHTML, json: EventsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Events.PubSub,
  live_view: [signing_salt: "bADKq9rD"]

# Mailer configuration
config :events, Events.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  events: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind
config :tailwind,
  version: "4.1.7",
  events: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Logger configuration
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Load runtime configuration
# This will load environment-specific settings from runtime.exs
import_config "runtime.exs"
