defmodule OmCache.Config do
  @moduledoc """
  Cache configuration helpers for Nebulex adapters.

  Resolves cache adapter and builds configuration from environment variables.

  ## Environment Variables

  - `CACHE_ADAPTER` - Adapter type: "redis" (default), "local", "partitioned", "replicated", "null"
  - `REDIS_HOST` - Redis host (default: "localhost")
  - `REDIS_PORT` - Redis port (default: 6379)

  ## Adapters

  | Value | Module | Use Case |
  |-------|--------|----------|
  | `"redis"` | `NebulexRedisAdapter` | Production with Redis |
  | `"local"` | `Nebulex.Adapters.Local` | Single node, development |
  | `"partitioned"` | `Nebulex.Adapters.Partitioned` | Distributed across Erlang cluster (sharded) |
  | `"replicated"` | `Nebulex.Adapters.Replicated` | Distributed across Erlang cluster (full copy) |
  | `"null"` | `Nebulex.Adapters.Nil` | Testing, no-op |

  ## Usage

      # In runtime.exs
      config :my_app, MyApp.Cache, OmCache.Config.build()

      # Or access individual parts
      OmCache.Config.adapter()     # => NebulexRedisAdapter
      OmCache.Config.redis_opts()  # => [host: "localhost", port: 6379]

  ## Custom Configuration

      # Override defaults
      OmCache.Config.build(
        adapter_env: "MY_CACHE_ADAPTER",
        redis_host_env: "MY_REDIS_HOST",
        redis_port_env: "MY_REDIS_PORT",
        default_adapter: :local
      )
  """

  alias FnTypes.Config, as: Cfg

  @type adapter ::
          NebulexRedisAdapter
          | Nebulex.Adapters.Local
          | Nebulex.Adapters.Partitioned
          | Nebulex.Adapters.Replicated
          | Nebulex.Adapters.Nil

  @doc """
  Builds complete cache configuration.

  ## Options

  - `:adapter_env` - Environment variable for adapter (default: "CACHE_ADAPTER")
  - `:redis_host_env` - Environment variable for Redis host (default: "REDIS_HOST")
  - `:redis_port_env` - Environment variable for Redis port (default: "REDIS_PORT")
  - `:default_adapter` - Default adapter when env not set (default: :redis)
  - `:local_opts` - Custom options for local adapter
  - `:redis_opts` - Custom options for Redis adapter

  ## Examples

      OmCache.Config.build()
      # => [adapter: NebulexRedisAdapter, conn_opts: [host: "localhost", port: 6379]]

      OmCache.Config.build(default_adapter: :local)
      # => [adapter: Nebulex.Adapters.Local, gc_interval: ..., ...]
  """
  @spec build(keyword()) :: keyword()
  def build(opts \\ []) do
    adapter(opts) |> build_for_adapter(opts)
  end

  @doc """
  Gets the cache adapter module based on environment variable.

  ## Options

  - `:adapter_env` - Environment variable name (default: "CACHE_ADAPTER")
  - `:default_adapter` - Default when not set: :redis, :local, :partitioned, :replicated, :null (default: :redis)

  ## Supported Values

  - `"redis"` (default) - NebulexRedisAdapter
  - `"local"` - Nebulex.Adapters.Local (in-memory, single node)
  - `"partitioned"` - Nebulex.Adapters.Partitioned (distributed, sharded across Erlang cluster)
  - `"replicated"` - Nebulex.Adapters.Replicated (distributed, replicated across Erlang cluster)
  - `"null"`, `"none"`, `"nil"` - Nebulex.Adapters.Nil (no-op, for testing)

  ## Examples

      OmCache.Config.adapter()
      # => NebulexRedisAdapter
  """
  @spec adapter(keyword()) :: adapter()
  def adapter(opts \\ []) do
    env_var = Keyword.get(opts, :adapter_env, "CACHE_ADAPTER")
    default = Keyword.get(opts, :default_adapter, :redis)

    default_str =
      case default do
        :redis -> "redis"
        :local -> "local"
        :partitioned -> "partitioned"
        :replicated -> "replicated"
        :null -> "null"
        _ -> "redis"
      end

    Cfg.string(env_var, default_str)
    |> String.downcase()
    |> String.trim()
    |> parse_adapter()
  end

  @doc """
  Gets Redis connection options from environment.

  ## Options

  - `:redis_host_env` - Environment variable for host (default: "REDIS_HOST")
  - `:redis_port_env` - Environment variable for port (default: "REDIS_PORT")
  - `:default_host` - Default host (default: "localhost")
  - `:default_port` - Default port (default: 6379)

  ## Examples

      OmCache.Config.redis_opts()
      # => [host: "localhost", port: 6379]
  """
  @spec redis_opts(keyword()) :: keyword()
  def redis_opts(opts \\ []) do
    host_env = Keyword.get(opts, :redis_host_env, "REDIS_HOST")
    port_env = Keyword.get(opts, :redis_port_env, "REDIS_PORT")
    default_host = Keyword.get(opts, :default_host, "localhost")
    default_port = Keyword.get(opts, :default_port, 6379)

    [
      host: Cfg.string(host_env, default_host),
      port: Cfg.integer(port_env, default_port)
    ]
  end

  @doc """
  Gets Redis URL from environment.

  ## Examples

      OmCache.Config.redis_url()
      # => "redis://localhost:6379"
  """
  @spec redis_url(keyword()) :: String.t()
  def redis_url(opts \\ []) do
    redis = redis_opts(opts)
    "redis://#{redis[:host]}:#{redis[:port]}"
  end

  @doc """
  Checks if Redis is available by attempting a connection.

  ## Options

  - `:timeout` - Connection timeout in ms (default: 5000)
  - Plus all redis_opts options

  ## Examples

      OmCache.Config.redis_available?()
      # => true
  """
  @spec redis_available?(keyword()) :: boolean()
  def redis_available?(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    redis = redis_opts(opts)

    case Redix.start_link(host: redis[:host], port: redis[:port], timeout: timeout) do
      {:ok, conn} ->
        result =
          case Redix.command(conn, ["PING"]) do
            {:ok, "PONG"} -> true
            _ -> false
          end

        Redix.stop(conn)
        result

      {:error, _reason} ->
        false
    end
  end

  # ============================================
  # Private
  # ============================================

  defp parse_adapter(value) when value in ["null", "none", "nil"], do: Nebulex.Adapters.Nil
  defp parse_adapter("local"), do: Nebulex.Adapters.Local
  defp parse_adapter("partitioned"), do: Nebulex.Adapters.Partitioned
  defp parse_adapter("replicated"), do: Nebulex.Adapters.Replicated
  defp parse_adapter("redis"), do: NebulexRedisAdapter
  defp parse_adapter(""), do: NebulexRedisAdapter
  defp parse_adapter(_unknown), do: NebulexRedisAdapter

  defp build_for_adapter(Nebulex.Adapters.Local, opts) do
    local_defaults = [
      adapter: Nebulex.Adapters.Local,
      gc_interval: :timer.hours(12),
      max_size: 1_000_000,
      allocated_memory: 2_000_000_000,
      gc_cleanup_min_timeout: :timer.seconds(10),
      gc_cleanup_max_timeout: :timer.minutes(10),
      stats: true
    ]

    custom = Keyword.get(opts, :local_opts, [])
    Keyword.merge(local_defaults, custom)
  end

  defp build_for_adapter(NebulexRedisAdapter, opts) do
    redis_defaults = [
      adapter: NebulexRedisAdapter,
      conn_opts: redis_opts(opts)
    ]

    custom = Keyword.get(opts, :redis_opts, [])
    Keyword.merge(redis_defaults, custom)
  end

  defp build_for_adapter(Nebulex.Adapters.Partitioned, opts) do
    partitioned_defaults = [
      adapter: Nebulex.Adapters.Partitioned,
      primary_storage_adapter: Nebulex.Adapters.Local,
      stats: true
    ]

    custom = Keyword.get(opts, :partitioned_opts, [])
    Keyword.merge(partitioned_defaults, custom)
  end

  defp build_for_adapter(Nebulex.Adapters.Replicated, opts) do
    replicated_defaults = [
      adapter: Nebulex.Adapters.Replicated,
      primary_storage_adapter: Nebulex.Adapters.Local,
      stats: true
    ]

    custom = Keyword.get(opts, :replicated_opts, [])
    Keyword.merge(replicated_defaults, custom)
  end

  defp build_for_adapter(Nebulex.Adapters.Nil, _opts) do
    [adapter: Nebulex.Adapters.Nil]
  end
end
