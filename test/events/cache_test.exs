defmodule Events.CacheTest do
  @moduledoc """
  Tests for Events.Cache (Nebulex-based cache).

  These tests verify the Nebulex cache operations work correctly.
  """

  use Events.DataCase, async: true

  alias Events.Cache

  describe "get/1" do
    test "returns cached value when key exists" do
      key = {:cache_test, :user, 123}
      value = %{id: 123, name: "Test User"}

      Cache.put(key, value)

      assert Cache.get(key) == value
    end

    test "returns nil when key does not exist" do
      key = {:cache_test, :nonexistent, :key}

      assert Cache.get(key) == nil
    end
  end

  describe "put/2 and put/3" do
    test "stores value with key and returns :ok" do
      key = {:cache_test, :session, "abc123"}
      value = %{user_id: 1, expires_at: DateTime.utc_now()}

      assert Cache.put(key, value) == :ok
      assert Cache.get(key) == value
    end

    test "stores value with TTL option" do
      key = {:cache_test, :temp, "expires-soon"}
      value = "temporary data"

      assert Cache.put(key, value, ttl: :timer.hours(1)) == :ok
      assert Cache.get(key) == value
    end

    test "overwrites existing value" do
      key = {:cache_test, :config, :app_settings}

      Cache.put(key, %{version: 1})
      assert Cache.get(key) == %{version: 1}

      Cache.put(key, %{version: 2})
      assert Cache.get(key) == %{version: 2}
    end
  end

  describe "delete/1" do
    test "removes key from cache" do
      key = {:cache_test, :user, 456}
      Cache.put(key, %{id: 456})

      assert Cache.get(key) != nil

      Cache.delete(key)

      assert Cache.get(key) == nil
    end

    test "returns :ok when deleting non-existent key" do
      key = {:cache_test, :never, :existed}

      # Should not raise, returns :ok
      result = Cache.delete(key)
      assert result == :ok
    end
  end

  describe "get_all/1" do
    test "returns map of values for multiple keys" do
      keys = [{:cache_test, :multi, 1}, {:cache_test, :multi, 2}, {:cache_test, :multi, 3}]

      Cache.put({:cache_test, :multi, 1}, %{id: 1})
      Cache.put({:cache_test, :multi, 2}, %{id: 2})
      Cache.put({:cache_test, :multi, 3}, %{id: 3})

      result = Cache.get_all(keys)

      assert is_map(result)
      assert map_size(result) == 3
    end

    test "returns empty map for non-existent keys" do
      keys = [{:cache_test, :missing, 1}, {:cache_test, :missing, 2}]

      result = Cache.get_all(keys)

      assert result == %{}
    end
  end

  describe "put_all/1 and put_all/2" do
    test "stores multiple key-value pairs" do
      entries = [
        {{:cache_test, :batch, 1}, "value1"},
        {{:cache_test, :batch, 2}, "value2"},
        {{:cache_test, :batch, 3}, "value3"}
      ]

      Cache.put_all(entries)

      assert Cache.get({:cache_test, :batch, 1}) == "value1"
      assert Cache.get({:cache_test, :batch, 2}) == "value2"
      assert Cache.get({:cache_test, :batch, 3}) == "value3"
    end
  end

  describe "delete_all/0" do
    test "clears all entries from cache" do
      Cache.put({:cache_test, :clear, 1}, "a")
      Cache.put({:cache_test, :clear, 2}, "b")

      Cache.delete_all()

      assert Cache.get({:cache_test, :clear, 1}) == nil
      assert Cache.get({:cache_test, :clear, 2}) == nil
    end
  end

  describe "count_all/0" do
    test "returns number of entries in cache" do
      # Clear first
      Cache.delete_all()

      Cache.put({:cache_test, :count, 1}, "a")
      Cache.put({:cache_test, :count, 2}, "b")

      count = Cache.count_all()
      assert count >= 2
    end
  end
end
