defmodule OmCache.StatsTest do
  use ExUnit.Case

  alias OmCache.Stats

  # Use a unique table name per test to avoid conflicts
  defp unique_cache_name, do: :"StatsTestCache_#{System.unique_integer([:positive])}"

  setup do
    cache_name = unique_cache_name()

    on_exit(fn ->
      try do
        Stats.detach(cache_name)
      rescue
        _ -> :ok
      end
    end)

    {:ok, cache: cache_name}
  end

  describe "attach/2 and detach/1" do
    test "creates ETS table", %{cache: cache} do
      Stats.attach(cache)
      table = :"#{cache}.Stats"
      assert :ets.whereis(table) != :undefined
    end

    test "detach cleans up", %{cache: cache} do
      Stats.attach(cache)
      Stats.detach(cache)
      table = :"#{cache}.Stats"
      assert :ets.whereis(table) == :undefined
    end
  end

  describe "get_stats/1" do
    test "returns error when not attached" do
      assert {:error, :not_attached} = Stats.get_stats(:nonexistent)
    end

    test "returns initial stats", %{cache: cache} do
      Stats.attach(cache)
      stats = Stats.get_stats(cache)

      assert stats.hits == 0
      assert stats.misses == 0
      assert stats.hit_ratio == 0.0
      assert stats.writes == 0
      assert stats.deletes == 0
      assert stats.errors == 0
      assert stats.avg_latency_ms == 0.0
      assert stats.error_breakdown == %{}
    end
  end

  describe "hit_ratio/1" do
    test "returns 0.0 with no operations", %{cache: cache} do
      Stats.attach(cache)
      assert Stats.hit_ratio(cache) == 0.0
    end

    test "returns error when not attached" do
      assert {:error, :not_attached} = Stats.hit_ratio(:nonexistent)
    end
  end

  describe "reset/1" do
    test "resets all counters", %{cache: cache} do
      Stats.attach(cache)

      # Manually increment a counter to verify reset
      table = :"#{cache}.Stats"
      :ets.update_counter(table, :hits, {2, 10})

      assert Stats.get_stats(cache).hits == 10

      Stats.reset(cache)
      assert Stats.get_stats(cache).hits == 0
    end

    test "returns error when not attached" do
      assert {:error, :not_attached} = Stats.reset(:nonexistent)
    end
  end

  describe "latency circular buffer" do
    test "records latencies without data loss", %{cache: cache} do
      Stats.attach(cache, latency_samples: 5)
      table = :"#{cache}.Stats"

      # Simulate recording latencies directly via the private-ish ETS operations
      for i <- 1..5 do
        index = :ets.update_counter(table, :latency_write_index, {2, 1, 4, 0})
        :ets.insert(table, {{:latency, index}, i * 10})
        :ets.update_counter(table, :latency_count, {2, 1}, {:latency_count, 0})
      end

      stats = Stats.get_stats(cache)
      assert stats.avg_latency_ms == 30.0
    end
  end
end
