defmodule Events.Infra.KillSwitch.CacheTest do
  @moduledoc """
  Tests for Events.Infra.KillSwitch.Cache.

  Tests the cache wrapper with kill switch functionality,
  verifying graceful degradation when cache is disabled.
  """

  use Events.DataCase, async: false

  alias Events.Infra.KillSwitch
  alias Events.Infra.KillSwitch.Cache, as: KSCache

  setup do
    # Ensure cache is enabled by default for each test
    # KillSwitch is already started by the application supervisor
    KillSwitch.enable(:cache)

    on_exit(fn ->
      # Re-enable after test to avoid affecting other tests
      KillSwitch.enable(:cache)
    end)

    :ok
  end

  describe "enabled?/0" do
    test "returns true when cache is enabled" do
      KillSwitch.enable(:cache)
      assert KSCache.enabled?() == true
    end

    test "returns false when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")
      assert KSCache.enabled?() == false
    end
  end

  describe "check/0" do
    test "returns :enabled when cache service is enabled" do
      KillSwitch.enable(:cache)
      assert KSCache.check() == :enabled
    end

    test "returns {:disabled, reason} when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Redis unavailable")
      assert {:disabled, "Redis unavailable"} = KSCache.check()
    end
  end

  describe "status/0" do
    test "returns detailed status with enabled true" do
      KillSwitch.enable(:cache)

      status = KSCache.status()

      assert status.enabled == true
      assert status.reason == nil
      assert status.disabled_at == nil
    end

    test "returns detailed status with enabled false" do
      KillSwitch.disable(:cache, reason: "Maintenance")

      status = KSCache.status()

      assert status.enabled == false
      assert status.reason == "Maintenance"
      assert %DateTime{} = status.disabled_at
    end
  end

  describe "disable/1 and enable/0" do
    test "disable/1 disables the cache service" do
      assert KSCache.enabled?() == true

      KSCache.disable(reason: "Test")

      assert KSCache.enabled?() == false
    end

    test "enable/0 enables the cache service" do
      KSCache.disable(reason: "Test")
      assert KSCache.enabled?() == false

      KSCache.enable()

      assert KSCache.enabled?() == true
    end
  end

  describe "get/1 with kill switch" do
    test "returns cached value when cache is enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_test, :user, 1}
      Events.Core.Cache.put(key, %{id: 1, name: "Test"})

      result = KSCache.get(key)

      assert result == %{id: 1, name: "Test"}
    end

    test "returns nil when cache is disabled" do
      key = {:ks_test, :user, 2}
      Events.Core.Cache.put(key, %{id: 2, name: "Test"})

      KillSwitch.disable(:cache, reason: "Test disabled")

      result = KSCache.get(key)

      assert result == nil
    end
  end

  describe "put/3 with kill switch" do
    test "stores value when cache is enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_put, :test}
      result = KSCache.put(key, "value")

      assert result == :ok
      assert Events.Core.Cache.get(key) == "value"
    end

    test "returns :ok but does not store when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      key = {:ks_put_disabled, :test}
      result = KSCache.put(key, "value")

      assert result == :ok

      # Re-enable and verify nothing was stored
      KillSwitch.enable(:cache)
      assert Events.Core.Cache.get(key) == nil
    end

    test "accepts TTL option" do
      KillSwitch.enable(:cache)

      key = {:ks_put_ttl, :test}
      result = KSCache.put(key, "value", ttl: :timer.hours(1))

      assert result == :ok
    end
  end

  describe "delete/1 with kill switch" do
    test "deletes key when cache is enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_delete, :test}
      Events.Core.Cache.put(key, "value")
      assert Events.Core.Cache.get(key) == "value"

      result = KSCache.delete(key)

      assert result == :ok
      assert Events.Core.Cache.get(key) == nil
    end

    test "returns :ok but does not delete when cache is disabled" do
      KillSwitch.enable(:cache)

      key = {:ks_delete_disabled, :test}
      Events.Core.Cache.put(key, "value")

      KillSwitch.disable(:cache, reason: "Test disabled")

      result = KSCache.delete(key)
      assert result == :ok

      # Re-enable and verify value still exists
      KillSwitch.enable(:cache)
      assert Events.Core.Cache.get(key) == "value"
    end
  end

  describe "get_all/1 with kill switch" do
    test "returns values when cache is enabled" do
      KillSwitch.enable(:cache)

      Events.Core.Cache.put({:ks_all, 1}, "a")
      Events.Core.Cache.put({:ks_all, 2}, "b")

      result = KSCache.get_all([{:ks_all, 1}, {:ks_all, 2}])

      assert is_list(result) or is_map(result)
    end

    test "returns empty list when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      result = KSCache.get_all([{:ks_all, 1}, {:ks_all, 2}])

      assert result == []
    end
  end

  describe "has_key?/1 with kill switch" do
    test "returns true when key exists and cache is enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_has_key, :test}
      Events.Core.Cache.put(key, "value")

      assert KSCache.has_key?(key) == true
    end

    test "returns false when key does not exist" do
      KillSwitch.enable(:cache)

      assert KSCache.has_key?({:ks_nonexistent, :key}) == false
    end

    test "returns false when cache is disabled" do
      KillSwitch.enable(:cache)

      key = {:ks_has_key_disabled, :test}
      Events.Core.Cache.put(key, "value")

      KillSwitch.disable(:cache, reason: "Test disabled")

      assert KSCache.has_key?(key) == false
    end
  end

  describe "fetch/3 with kill switch" do
    test "returns cached value on hit when enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_fetch, :cached}
      Events.Core.Cache.put(key, "cached_value")

      call_count = :counters.new(1, [:atomics])

      result =
        KSCache.fetch(key, fn ->
          :counters.add(call_count, 1, 1)
          "computed_value"
        end)

      assert result == "cached_value"
      assert :counters.get(call_count, 1) == 0
    end

    test "computes and caches value on miss when enabled" do
      KillSwitch.enable(:cache)

      key = {:ks_fetch, :miss}

      result =
        KSCache.fetch(key, fn ->
          "computed_value"
        end)

      assert result == "computed_value"
      assert Events.Core.Cache.get(key) == "computed_value"
    end

    test "always computes value when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      key = {:ks_fetch_disabled, :test}
      call_count = :counters.new(1, [:atomics])

      # First call
      result1 =
        KSCache.fetch(key, fn ->
          :counters.add(call_count, 1, 1)
          "computed_value"
        end)

      # Second call
      result2 =
        KSCache.fetch(key, fn ->
          :counters.add(call_count, 1, 1)
          "computed_value"
        end)

      assert result1 == "computed_value"
      assert result2 == "computed_value"
      # Both calls executed the function
      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "delete_pattern/1 with kill switch" do
    test "returns :ok when cache is enabled" do
      KillSwitch.enable(:cache)

      result = KSCache.delete_pattern({:pattern, :_})

      assert result == :ok
    end

    test "returns :ok when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      result = KSCache.delete_pattern({:pattern, :_})

      assert result == :ok
    end
  end

  describe "with_cache/2" do
    test "executes function when cache is enabled" do
      KillSwitch.enable(:cache)

      result = KSCache.with_cache(fn -> {:ok, "executed"} end)

      assert result == {:ok, "executed"}
    end

    test "executes fallback when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      result =
        KSCache.with_cache(
          fn -> {:ok, "should not run"} end,
          fallback: fn -> {:ok, :fallback_executed} end
        )

      assert result == {:ok, :fallback_executed}
    end

    test "uses default fallback when cache is disabled" do
      KillSwitch.disable(:cache, reason: "Test disabled")

      result = KSCache.with_cache(fn -> {:ok, "should not run"} end)

      assert result == {:ok, :cache_disabled}
    end
  end
end
