defmodule Events.Data.Cache do
  @moduledoc """
  Main cache module for the Events application.

  Wraps OmCache with Events-specific defaults. See `OmCache` for full documentation.

  ## Usage

      # Direct cache operations
      Events.Data.Cache.put({User, 123}, user_struct)
      Events.Data.Cache.get({User, 123})
      Events.Data.Cache.delete({User, 123})

      # With decorators
      @decorate cacheable(cache: Events.Data.Cache, key: {User, id})
      def get_user(id) do
        Repo.get(User, id)
      end

  ## Adapter Configuration

  Set the CACHE_ADAPTER environment variable to switch between adapters:

      CACHE_ADAPTER=redis mix phx.server   # Redis (default)
      CACHE_ADAPTER=local mix phx.server   # Local in-memory
      CACHE_ADAPTER=null mix phx.server    # No-op

  ## Configuration

  Configured in `config/runtime.exs`:

      config :events, Events.Data.Cache, OmCache.Config.build()
  """

  # Uses OmCache with Events-specific defaults:
  # - otp_app: :events (loads config from :events app)
  # - default_adapter: :redis (falls back to Redis)
  # - key_generator: OmCache.KeyGenerator (standard key generation)
  use OmCache,
    otp_app: :events,
    default_adapter: :redis,
    key_generator: OmCache.KeyGenerator
end
