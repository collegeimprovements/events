defmodule OmCacheTest do
  @moduledoc """
  Tests for OmCache - Unified caching layer built on Nebulex.

  OmCache provides flexible cache configuration supporting multiple backends
  (Redis, Local, Partitioned, Replicated) with automatic adapter selection.

  ## Use Cases

  - **Production**: Redis adapter for distributed caching
  - **Development**: Local adapter for single-node caching
  - **Testing**: Null adapter for no-op caching
  - **Distributed**: Partitioned/Replicated for cluster-wide caching

  ## Pattern: Environment-Based Configuration

      # config/runtime.exs
      config :om_cache, :adapter, System.get_env("CACHE_ADAPTER", "redis")

      # Automatic adapter selection:
      OmCache.Config.build()                          # Uses env or defaults to redis
      OmCache.Config.build(default_adapter: :local)   # Force local adapter
      OmCache.Config.build(default_adapter: :null)    # No-op for tests

  KeyGenerator handles cache key generation from function arguments.
  """

  use ExUnit.Case, async: true

  describe "OmCache.Config" do
    test "adapter/0 defaults to redis" do
      # When CACHE_ADAPTER is not set, defaults to redis
      assert OmCache.Config.adapter() == NebulexRedisAdapter
    end

    test "adapter/1 respects default_adapter option" do
      assert OmCache.Config.adapter(default_adapter: :local) == Nebulex.Adapters.Local
      assert OmCache.Config.adapter(default_adapter: :partitioned) == Nebulex.Adapters.Partitioned
      assert OmCache.Config.adapter(default_adapter: :replicated) == Nebulex.Adapters.Replicated
      assert OmCache.Config.adapter(default_adapter: :null) == Nebulex.Adapters.Nil
    end

    test "redis_opts/0 returns default redis options" do
      opts = OmCache.Config.redis_opts()
      assert opts[:host] == "localhost"
      assert opts[:port] == 6379
    end

    test "redis_opts/1 respects custom defaults when env not set" do
      # Use non-existent env vars to test defaults
      opts = OmCache.Config.redis_opts(
        redis_host_env: "NONEXISTENT_REDIS_HOST",
        redis_port_env: "NONEXISTENT_REDIS_PORT",
        default_host: "redis.local",
        default_port: 6380
      )
      assert opts[:host] == "redis.local"
      assert opts[:port] == 6380
    end

    test "redis_url/0 builds correct URL" do
      url = OmCache.Config.redis_url()
      assert url == "redis://localhost:6379"
    end

    test "build/0 returns complete config for redis adapter" do
      config = OmCache.Config.build()
      assert config[:adapter] == NebulexRedisAdapter
      assert config[:conn_opts][:host] == "localhost"
      assert config[:conn_opts][:port] == 6379
    end

    test "build/1 with local adapter returns local config" do
      config = OmCache.Config.build(default_adapter: :local)
      assert config[:adapter] == Nebulex.Adapters.Local
      assert config[:gc_interval] == :timer.hours(12)
      assert config[:max_size] == 1_000_000
      assert config[:stats] == true
    end

    test "build/1 with null adapter returns minimal config" do
      config = OmCache.Config.build(default_adapter: :null)
      assert config[:adapter] == Nebulex.Adapters.Nil
    end

    test "build/1 with partitioned adapter returns partitioned config" do
      config = OmCache.Config.build(default_adapter: :partitioned)
      assert config[:adapter] == Nebulex.Adapters.Partitioned
      assert config[:primary_storage_adapter] == Nebulex.Adapters.Local
      assert config[:stats] == true
    end

    test "build/1 with replicated adapter returns replicated config" do
      config = OmCache.Config.build(default_adapter: :replicated)
      assert config[:adapter] == Nebulex.Adapters.Replicated
      assert config[:primary_storage_adapter] == Nebulex.Adapters.Local
      assert config[:stats] == true
    end

    test "build/1 with custom partitioned_opts merges options" do
      config = OmCache.Config.build(
        default_adapter: :partitioned,
        partitioned_opts: [primary_storage_adapter: Nebulex.Adapters.Nil]
      )
      assert config[:adapter] == Nebulex.Adapters.Partitioned
      assert config[:primary_storage_adapter] == Nebulex.Adapters.Nil
    end

    test "build/1 with custom local_opts merges options" do
      config = OmCache.Config.build(default_adapter: :local, local_opts: [max_size: 500])
      assert config[:adapter] == Nebulex.Adapters.Local
      assert config[:max_size] == 500
    end
  end

  describe "OmCache.KeyGenerator" do
    test "generate/3 with empty args returns 0" do
      assert OmCache.KeyGenerator.generate(MyMod, :func, []) == 0
    end

    test "generate/3 with single arg returns the arg" do
      assert OmCache.KeyGenerator.generate(MyMod, :func, [123]) == 123
      assert OmCache.KeyGenerator.generate(MyMod, :func, ["key"]) == "key"
      assert OmCache.KeyGenerator.generate(MyMod, :func, [{User, 1}]) == {User, 1}
    end

    test "generate/3 with multiple args returns hash" do
      result = OmCache.KeyGenerator.generate(MyMod, :func, [1, 2, 3])
      assert is_integer(result)
      # Same args should produce same hash
      assert result == OmCache.KeyGenerator.generate(MyMod, :func, [1, 2, 3])
      # Different args should produce different hash
      refute result == OmCache.KeyGenerator.generate(MyMod, :func, [1, 2, 4])
    end
  end
end
