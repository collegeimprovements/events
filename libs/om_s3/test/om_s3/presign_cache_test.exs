defmodule OmS3.PresignCacheTest do
  use ExUnit.Case, async: true

  alias OmS3.PresignCache

  describe "key/2" do
    test "creates basic cache key" do
      assert PresignCache.key("s3://bucket/file.pdf") == {:om_s3_presign, "s3://bucket/file.pdf"}
    end

    test "creates cache key with context" do
      assert PresignCache.key("s3://bucket/file.pdf", user_id: 123) ==
               {:om_s3_presign, "s3://bucket/file.pdf", [user_id: 123]}
    end

    test "creates cache key with method context" do
      assert PresignCache.key("s3://bucket/file.pdf", method: :put) ==
               {:om_s3_presign, "s3://bucket/file.pdf", [method: :put]}
    end
  end

  describe "preset/1" do
    test "creates preset with required options" do
      preset = PresignCache.preset(cache: MyApp.Cache, key: {:presign, "uri"})

      assert is_list(preset)
      assert Keyword.has_key?(preset, :store)
      assert Keyword.has_key?(preset, :only_if)
    end

    test "calculates TTL based on expires_in minus buffer" do
      preset = PresignCache.preset(cache: MyApp.Cache, key: {:presign, "uri"}, expires_in: 3600)

      store_opts = Keyword.get(preset, :store)
      # 3600 - 60 (buffer) = 3540 seconds = 3_540_000 ms
      assert store_opts[:ttl] == 3_540_000
    end

    test "respects custom buffer" do
      preset =
        PresignCache.preset(
          cache: MyApp.Cache,
          key: {:presign, "uri"},
          expires_in: 3600,
          buffer: 120
        )

      store_opts = Keyword.get(preset, :store)
      # 3600 - 120 = 3480 seconds = 3_480_000 ms
      assert store_opts[:ttl] == 3_480_000
    end

    test "only_if function matches ok tuples" do
      preset = PresignCache.preset(cache: MyApp.Cache, key: {:presign, "uri"})
      only_if = Keyword.get(preset, :only_if)

      assert only_if.({:ok, "url"})
      refute only_if.({:error, :reason})
      refute only_if.(:ok)
    end
  end

  describe "GenServer cache" do
    setup do
      name = :"test_cache_#{System.unique_integer()}"
      {:ok, pid} = PresignCache.start_link(name: name)
      {:ok, cache: name, pid: pid}
    end

    test "starts successfully", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "returns cache statistics", %{cache: cache} do
      stats = PresignCache.stats(cache)

      assert Map.has_key?(stats, :entries)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
      assert Map.has_key?(stats, :hit_rate)
      assert stats.entries == 0
      assert stats.hit_rate == 0.0
    end

    test "clears resets stats", %{cache: cache} do
      # Clear
      :ok = PresignCache.clear(cache)

      stats = PresignCache.stats(cache)
      assert stats.entries == 0
      assert stats.hits == 0
      assert stats.misses == 0
    end

    test "invalidate is idempotent", %{cache: cache} do
      # Invalidating non-existent key should not error
      :ok = PresignCache.invalidate(cache, "s3://bucket/nonexistent.pdf")

      stats = PresignCache.stats(cache)
      assert stats.entries == 0
    end
  end
end
