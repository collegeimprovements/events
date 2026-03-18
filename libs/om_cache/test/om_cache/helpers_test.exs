defmodule OmCache.HelpersTest do
  use ExUnit.Case

  alias OmCache.{Helpers, Error}

  @cache OmCache.TestCache

  setup do
    @cache.delete_all()
    :ok
  end

  describe "fetch/3" do
    test "returns {:ok, value} when key exists" do
      @cache.put(:key, "value")
      assert {:ok, "value"} = Helpers.fetch(@cache, :key)
    end

    test "returns {:error, %Error{type: :key_not_found}} when key missing" do
      assert {:error, %Error{type: :key_not_found}} = Helpers.fetch(@cache, :missing)
    end

    test "returns {:ok, default} when key missing and default given" do
      assert {:ok, "default"} = Helpers.fetch(@cache, :missing, default: "default")
    end
  end

  describe "fetch!/3" do
    test "returns value when key exists" do
      @cache.put(:key, "value")
      assert "value" == Helpers.fetch!(@cache, :key)
    end

    test "raises OmCache.Error when key missing" do
      assert_raise OmCache.Error, fn ->
        Helpers.fetch!(@cache, :missing)
      end
    end
  end

  describe "put_safe/4" do
    test "puts value and returns {:ok, :ok}" do
      assert {:ok, :ok} = Helpers.put_safe(@cache, :key, "value")
      assert @cache.get(:key) == "value"
    end

    test "rejects nil key" do
      assert {:error, %Error{type: :invalid_key}} = Helpers.put_safe(@cache, nil, "value")
    end

    test "rejects negative TTL" do
      assert {:error, %Error{type: :invalid_ttl}} = Helpers.put_safe(@cache, :key, "val", ttl: -1)
    end

    test "rejects non-integer TTL" do
      assert {:error, %Error{type: :invalid_ttl}} = Helpers.put_safe(@cache, :key, "val", ttl: "bad")
    end

    test "accepts valid TTL" do
      assert {:ok, :ok} = Helpers.put_safe(@cache, :key, "value", ttl: 60_000)
    end

    test "skips our validation when validate_ttl: false (Nebulex may still reject)" do
      # Nebulex itself rejects negative TTLs, so we get an error from the adapter
      result = Helpers.put_safe(@cache, :key, "value", ttl: -1, validate_ttl: false)
      assert {:error, %Error{}} = result
    end
  end

  describe "delete_safe/3" do
    test "deletes key and returns {:ok, :ok}" do
      @cache.put(:key, "value")
      assert {:ok, :ok} = Helpers.delete_safe(@cache, :key)
      assert @cache.get(:key) == nil
    end

    test "rejects nil key" do
      assert {:error, %Error{type: :invalid_key}} = Helpers.delete_safe(@cache, nil)
    end
  end

  describe "get_or_fetch/4" do
    test "returns cached value on hit" do
      @cache.put(:key, "cached")
      assert {:ok, "cached"} = Helpers.get_or_fetch(@cache, :key, fn -> {:ok, "loaded"} end)
    end

    test "loads and caches on miss" do
      assert {:ok, "loaded"} = Helpers.get_or_fetch(@cache, :key, fn -> {:ok, "loaded"} end)
      assert @cache.get(:key) == "loaded"
    end

    test "does not cache when loader returns error" do
      assert {:error, :not_found} = Helpers.get_or_fetch(@cache, :key, fn -> {:error, :not_found} end)
      assert @cache.get(:key) == nil
    end

    test "does not cache when put_on_load: false" do
      assert {:ok, "loaded"} =
               Helpers.get_or_fetch(@cache, :key, fn -> {:ok, "loaded"} end, put_on_load: false)

      assert @cache.get(:key) == nil
    end
  end

  describe "fetch_batch/3" do
    test "returns hits and misses" do
      @cache.put(:a, 1)
      @cache.put(:b, 2)

      results = Helpers.fetch_batch(@cache, [:a, :b, :c])
      assert {:ok, 1} = results[:a]
      assert {:ok, 2} = results[:b]
      assert {:error, %Error{type: :key_not_found}} = results[:c]
    end
  end

  describe "put_batch/3" do
    test "puts multiple entries" do
      assert {:ok, :ok} = Helpers.put_batch(@cache, [a: 1, b: 2])
      assert @cache.get(:a) == 1
      assert @cache.get(:b) == 2
    end

    test "accepts map" do
      assert {:ok, :ok} = Helpers.put_batch(@cache, %{c: 3, d: 4})
      assert @cache.get(:c) == 3
    end
  end

  describe "exists?/3" do
    test "returns {:ok, true} when key exists" do
      @cache.put(:key, "value")
      assert {:ok, true} = Helpers.exists?(@cache, :key)
    end

    test "returns {:ok, false} when key missing" do
      assert {:ok, false} = Helpers.exists?(@cache, :missing)
    end
  end

  describe "ttl/3" do
    test "returns error for missing key" do
      assert {:error, %Error{}} = Helpers.ttl(@cache, :missing)
    end

    test "returns {:ok, ttl} for existing key with TTL" do
      @cache.put(:key, "value", ttl: 60_000)
      assert {:ok, ttl} = Helpers.ttl(@cache, :key)
      assert is_integer(ttl) or ttl == :infinity
    end
  end
end
