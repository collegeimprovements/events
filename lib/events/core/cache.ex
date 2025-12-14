defmodule Events.Core.Cache do
  @moduledoc """
  Main cache module for the Events application using Nebulex.

  This cache is used by the caching decorators to store and retrieve
  function results. The adapter can be easily swapped using the CACHE_ADAPTER
  environment variable.

  ## Usage

      # Direct cache operations
      Events.Core.Cache.put({User, 123}, user_struct)
      Events.Core.Cache.get({User, 123})
      Events.Core.Cache.delete({User, 123})

      # With decorators
      @decorate cacheable(cache: Events.Core.Cache, key: {User, id})
      def get_user(id) do
        Repo.get(User, id)
      end

  ## Adapter Configuration

  Set the CACHE_ADAPTER environment variable to switch between adapters:

      # Redis cache (default, requires REDIS_HOST and REDIS_PORT)
      CACHE_ADAPTER=redis mix phx.server

      # Local in-memory cache
      CACHE_ADAPTER=local mix phx.server

      # Disable caching (no-op adapter)
      CACHE_ADAPTER=null mix phx.server

  ## Configuration

  Configure the cache in `config/config.exs` (for local adapter):

      config :events, Events.Core.Cache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10)

  For Redis adapter, configure in `config/runtime.exs`:

      config :events, Events.Core.Cache,
        conn_opts: [
          host: Cfg.string("REDIS_HOST", "localhost"),
          port: Cfg.integer("REDIS_PORT", 6379)
        ]

  ## Telemetry

  The cache emits telemetry events for all operations:

  - `[:events, :cache, :command, :start | :stop | :exception]`

  You can attach handlers to monitor cache performance:

      :telemetry.attach(
        "cache-stats",
        [:events, :cache, :command, :stop],
        &MyApp.Telemetry.handle_cache_event/4,
        nil
      )

  ## Key Design

  Use tuples for namespaced keys to avoid collisions:

      {User, id}                    # User by ID
      {User, :email, email}         # User by email
      {:session, session_id}        # Session data
      {:config, :app_settings}      # Configuration

  ## TTL (Time To Live)

  Set TTL when storing values:

      Events.Core.Cache.put(key, value, ttl: :timer.minutes(30))

  Or use the default TTL from decorator options:

      @decorate cacheable(cache: Events.Core.Cache, key: id, ttl: :timer.hours(1))
      def get_user(id), do: Repo.get(User, id)
  """

  # NOTE: The adapter is configured at runtime in config/runtime.exs based on CACHE_ADAPTER env var.
  # This compile-time adapter is only used as a fallback and should match the runtime default (redis).
  use Nebulex.Cache,
    otp_app: :events,
    adapter: NebulexRedisAdapter,
    default_key_generator: Events.Core.Cache.KeyGenerator
end
