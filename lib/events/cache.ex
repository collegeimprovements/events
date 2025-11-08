defmodule Events.Cache do
  @moduledoc """
  Main cache module for the Events application using Nebulex.

  This cache is used by the caching decorators to store and retrieve
  function results. It's configured with a local adapter suitable for
  development and can be extended for production with distributed backends.

  ## Usage

      # Direct cache operations
      Events.Cache.put({User, 123}, user_struct)
      Events.Cache.get({User, 123})
      Events.Cache.delete({User, 123})

      # With decorators
      @decorate cacheable(cache: Events.Cache, key: {User, id})
      def get_user(id) do
        Repo.get(User, id)
      end

  ## Configuration

  Configure the cache in `config/config.exs`:

      config :events, Events.Cache,
        gc_interval: :timer.hours(12),
        max_size: 1_000_000,
        allocated_memory: 2_000_000_000,
        gc_cleanup_min_timeout: :timer.seconds(10),
        gc_cleanup_max_timeout: :timer.minutes(10)

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

      Events.Cache.put(key, value, ttl: :timer.minutes(30))

  Or use the default TTL from decorator options:

      @decorate cacheable(cache: Events.Cache, key: id, ttl: :timer.hours(1))
      def get_user(id), do: Repo.get(User, id)
  """

  use Nebulex.Cache,
    otp_app: :events,
    adapter: Nebulex.Adapters.Local,
    default_key_generator: Events.Cache.KeyGenerator

  @doc """
  Returns the default key generator module.

  Used by caching decorators when no explicit key is provided.
  """
  def __default_key_generator__, do: Events.Cache.KeyGenerator
end
