defmodule Events.Core.Cache.Config do
  @moduledoc """
  Cache configuration helpers for Nebulex adapters.

  Resolves cache adapter and builds configuration from environment variables.

  ## Environment Variables

  - `CACHE_ADAPTER` - Adapter type: "redis" (default), "local", "null"
  - `REDIS_HOST` - Redis host (default: "localhost")
  - `REDIS_PORT` - Redis port (default: 6379)

  ## Usage

      # In runtime.exs
      config :events, Events.Core.Cache, Events.Core.Cache.Config.build()

      # Or access individual parts
      Events.Core.Cache.Config.adapter()     # => NebulexRedisAdapter
      Events.Core.Cache.Config.redis_opts()  # => [host: "localhost", port: 6379]
  """

  alias FnTypes.Config, as: Cfg

  @type adapter :: NebulexRedisAdapter | Nebulex.Adapters.Local | Nebulex.Adapters.Nil

  @doc """
  Builds complete cache configuration.

  ## Examples

      Events.Core.Cache.Config.build()
      # => [adapter: NebulexRedisAdapter, conn_opts: [host: "localhost", port: 6379]]
  """
  @spec build() :: keyword()
  def build do
    adapter() |> build_for_adapter()
  end

  @doc """
  Gets the cache adapter module based on CACHE_ADAPTER env var.

  ## Supported Values

  - `"redis"` (default) - NebulexRedisAdapter
  - `"local"` - Nebulex.Adapters.Local (in-memory, single node)
  - `"null"`, `"none"`, `"nil"` - Nebulex.Adapters.Nil (no-op, for testing)

  ## Examples

      Events.Core.Cache.Config.adapter()
      # => NebulexRedisAdapter
  """
  @spec adapter() :: adapter()
  def adapter do
    Cfg.string("CACHE_ADAPTER", "redis")
    |> String.downcase()
    |> String.trim()
    |> parse_adapter()
  end

  @doc """
  Gets Redis connection options from environment.

  ## Examples

      Events.Core.Cache.Config.redis_opts()
      # => [host: "localhost", port: 6379]
  """
  @spec redis_opts() :: keyword()
  def redis_opts do
    [
      host: Cfg.string("REDIS_HOST", "localhost"),
      port: Cfg.integer("REDIS_PORT", 6379)
    ]
  end

  # ============================================
  # Private
  # ============================================

  defp parse_adapter(value) when value in ["null", "none", "nil"], do: Nebulex.Adapters.Nil
  defp parse_adapter("local"), do: Nebulex.Adapters.Local
  defp parse_adapter("redis"), do: NebulexRedisAdapter
  defp parse_adapter(""), do: NebulexRedisAdapter
  defp parse_adapter(_unknown), do: NebulexRedisAdapter

  defp build_for_adapter(Nebulex.Adapters.Local) do
    [
      adapter: Nebulex.Adapters.Local,
      gc_interval: :timer.hours(12),
      max_size: 1_000_000,
      allocated_memory: 2_000_000_000,
      gc_cleanup_min_timeout: :timer.seconds(10),
      gc_cleanup_max_timeout: :timer.minutes(10),
      stats: true
    ]
  end

  defp build_for_adapter(NebulexRedisAdapter) do
    [
      adapter: NebulexRedisAdapter,
      conn_opts: redis_opts()
    ]
  end

  defp build_for_adapter(Nebulex.Adapters.Nil) do
    [adapter: Nebulex.Adapters.Nil]
  end
end
