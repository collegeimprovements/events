defmodule OmCache.BatchTest do
  use ExUnit.Case

  alias OmCache.Batch

  @cache OmCache.TestCache

  setup do
    @cache.delete_all()
    :ok
  end

  describe "fetch_batch/4" do
    test "returns all cached values on full hit" do
      @cache.put({:user, 1}, "alice")
      @cache.put({:user, 2}, "bob")

      assert {:ok, results} =
               Batch.fetch_batch(@cache, [1, 2], fn _id -> {:ok, "loaded"} end,
                 key_fn: &{:user, &1}
               )

      assert results[1] == "alice"
      assert results[2] == "bob"
    end

    test "loads missing keys via loader" do
      @cache.put({:user, 1}, "alice")

      assert {:ok, results} =
               Batch.fetch_batch(@cache, [1, 2], fn id -> {:ok, "loaded_#{id}"} end,
                 key_fn: &{:user, &1}
               )

      assert results[1] == "alice"
      assert results[2] == "loaded_2"
      # Should also be cached now
      assert @cache.get({:user, 2}) == "loaded_2"
    end

    test "handles all misses" do
      assert {:ok, results} =
               Batch.fetch_batch(@cache, [1, 2], fn id -> {:ok, "loaded_#{id}"} end)

      assert results[1] == "loaded_1"
      assert results[2] == "loaded_2"
    end

    test "excludes loader errors from results" do
      assert {:ok, results} =
               Batch.fetch_batch(@cache, [1, 2], fn
                 1 -> {:ok, "success"}
                 2 -> {:error, :not_found}
               end)

      assert results[1] == "success"
      refute Map.has_key?(results, 2)
    end
  end

  describe "fetch_parallel/3" do
    test "partitions into hits and misses" do
      @cache.put(:a, 1)
      @cache.put(:b, 2)

      assert {:ok, %{hits: hits, misses: misses}} =
               Batch.fetch_parallel(@cache, [:a, :b, :c])

      assert hits[:a] == 1
      assert hits[:b] == 2
      assert :c in misses
    end
  end

  describe "put_batch/3" do
    test "puts map entries" do
      entries = %{a: 1, b: 2, c: 3}
      assert {:ok, :ok} = Batch.put_batch(@cache, entries)
      assert @cache.get(:a) == 1
      assert @cache.get(:b) == 2
      assert @cache.get(:c) == 3
    end

    test "puts list entries" do
      entries = [a: 1, b: 2]
      assert {:ok, :ok} = Batch.put_batch(@cache, entries)
      assert @cache.get(:a) == 1
    end
  end

  describe "warm_cache/4" do
    test "warms cache in batches" do
      ids = [1, 2, 3, 4, 5]

      assert {:ok, count} =
               Batch.warm_cache(@cache, ids, fn batch ->
                 entries = Map.new(batch, fn id -> {{:user, id}, "user_#{id}"} end)
                 {:ok, entries}
               end, batch_size: 2)

      assert count == 5
      assert @cache.get({:user, 1}) == "user_1"
      assert @cache.get({:user, 5}) == "user_5"
    end

    test "skips errors by default" do
      assert {:ok, 0} =
               Batch.warm_cache(@cache, [1], fn _batch ->
                 {:error, :db_down}
               end)
    end
  end

  describe "delete_batch/3" do
    test "deletes all specified keys" do
      @cache.put(:a, 1)
      @cache.put(:b, 2)
      @cache.put(:c, 3)

      assert {:ok, :ok} = Batch.delete_batch(@cache, [:a, :b])
      assert @cache.get(:a) == nil
      assert @cache.get(:b) == nil
      assert @cache.get(:c) == 3
    end
  end

  describe "pipeline/3" do
    test "executes operations sequentially" do
      @cache.put(:existing, "value")

      operations = [
        {:get, :existing},
        {:put, :new_key, "new_value"},
        {:delete, :existing}
      ]

      assert {:ok, results} = Batch.pipeline(@cache, operations)
      assert Enum.at(results, 0) == "value"
      assert @cache.get(:new_key) == "new_value"
      assert @cache.get(:existing) == nil
    end
  end
end
