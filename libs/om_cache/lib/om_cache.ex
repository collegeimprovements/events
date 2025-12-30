defmodule OmCache do
  @moduledoc """
  Nebulex cache wrapper with adapter selection, key generation, and graceful degradation.

  OmCache provides a unified interface for caching with:
  - **Adapter auto-selection**: Redis, local, or null based on environment
  - **Key generation**: Customizable key generation strategies
  - **Configuration helpers**: Build config from environment variables
  - **Telemetry integration**: Built-in telemetry events for monitoring

  ## Quick Start

  ### 1. Define Your Cache Module

      defmodule MyApp.Cache do
        use OmCache,
          otp_app: :my_app,
          default_adapter: :redis
      end

  ### 2. Configure in runtime.exs

      config :my_app, MyApp.Cache, OmCache.Config.build()

  ### 3. Use the Cache

      MyApp.Cache.put({User, 123}, user_struct)
      MyApp.Cache.get({User, 123})
      MyApp.Cache.delete({User, 123})

  ## Adapter Selection

  Set the `CACHE_ADAPTER` environment variable:

      # Redis cache (default)
      CACHE_ADAPTER=redis mix phx.server

      # Local in-memory cache (single node)
      CACHE_ADAPTER=local mix phx.server

      # Distributed cache across Erlang cluster (sharded)
      CACHE_ADAPTER=partitioned mix phx.server

      # Distributed cache across Erlang cluster (replicated)
      CACHE_ADAPTER=replicated mix phx.server

      # Disable caching (no-op)
      CACHE_ADAPTER=null mix phx.server

  ## Distributed Caching (without Redis)

  When Redis is unavailable, use `partitioned` or `replicated` adapters:

  - **Partitioned**: Shards data across Erlang cluster nodes using consistent hashing.
    Best for large datasets where each key lives on one node.
  - **Replicated**: Copies all data to every node. Best for read-heavy workloads
    with smaller datasets.

  ## Key Design

  Use tuples for namespaced keys:

      {User, id}                    # User by ID
      {User, :email, email}         # User by email
      {:session, session_id}        # Session data
      {:config, :app_settings}      # Configuration

  ## TTL (Time To Live)

      MyApp.Cache.put(key, value, ttl: :timer.minutes(30))

  ## Custom Key Generator

  Implement the `OmCache.KeyGenerator` behaviour:

      defmodule MyApp.CustomKeyGenerator do
        @behaviour OmCache.KeyGenerator

        @impl true
        def generate(mod, fun, args) do
          {mod, fun, :erlang.phash2(args)}
        end
      end

      # Configure
      config :my_app, MyApp.Cache,
        default_key_generator: MyApp.CustomKeyGenerator

  ## With Decorators

  Use with `FnDecorator.Caching`:

      @decorate cacheable(cache: MyApp.Cache, key: {User, id})
      def get_user(id), do: Repo.get(User, id)
  """

  @doc """
  Defines a cache module using Nebulex.

  ## Options

  - `:otp_app` - The OTP application name (required)
  - `:default_adapter` - Default adapter: `:redis`, `:local`, `:partitioned`, `:replicated`, or `:null` (default: `:redis`)
  - `:key_generator` - Custom key generator module (optional)

  ## Example

      defmodule MyApp.Cache do
        use OmCache,
          otp_app: :my_app,
          default_adapter: :redis
      end
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    default_adapter = Keyword.get(opts, :default_adapter, :redis)
    key_generator = Keyword.get(opts, :key_generator, OmCache.KeyGenerator)

    adapter_module =
      case default_adapter do
        :redis -> NebulexRedisAdapter
        :local -> Nebulex.Adapters.Local
        :partitioned -> Nebulex.Adapters.Partitioned
        :replicated -> Nebulex.Adapters.Replicated
        :null -> Nebulex.Adapters.Nil
        mod when is_atom(mod) -> mod
      end

    quote do
      use Nebulex.Cache,
        otp_app: unquote(otp_app),
        adapter: unquote(adapter_module),
        default_key_generator: unquote(key_generator)
    end
  end
end
