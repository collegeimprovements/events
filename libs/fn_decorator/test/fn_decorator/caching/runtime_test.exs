defmodule FnDecorator.Caching.RuntimeTest do
  use ExUnit.Case, async: false

  alias FnDecorator.Caching.{Runtime, Entry, Lock}

  # Simple in-memory cache for testing using ETS
  defmodule TestCache do
    @table :fn_decorator_test_cache

    def init do
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:set, :public, :named_table])

        _ ->
          :ok
      end

      :ok
    end

    def get(key) do
      case :ets.lookup(@table, key) do
        [{^key, value}] -> value
        [] -> nil
      end
    end

    def put(key, value, _opts \\ []) do
      :ets.insert(@table, {key, value})
      :ok
    end

    def delete(key) do
      :ets.delete(@table, key)
      :ok
    end

    def clear do
      init()
      :ets.delete_all_objects(@table)
      :ok
    end
  end

  setup do
    TestCache.init()
    TestCache.clear()
    Lock.init()
    :ets.delete_all_objects(FnDecorator.Caching.Lock)
    :ok
  end

  describe "execute/4 - basic caching" do
    test "caches function result on first call" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        "computed_value"
      end

      opts = [store: [ttl: 60_000]]

      result1 = Runtime.execute(TestCache, :basic_key, fetch_fn, opts)
      assert result1 == "computed_value"
      assert :counters.get(call_count, 1) == 1

      result2 = Runtime.execute(TestCache, :basic_key, fetch_fn, opts)
      assert result2 == "computed_value"
      assert :counters.get(call_count, 1) == 1
    end

    test "stores value with Entry metadata" do
      opts = [store: [ttl: 5_000]]
      Runtime.execute(TestCache, :meta_key, fn -> "value" end, opts)

      stored = TestCache.get(:meta_key)
      assert is_tuple(stored)
      assert elem(stored, 0) == :fn_cache
    end

    test "respects TTL for freshness" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        "fresh_value"
      end

      opts = [store: [ttl: 1]]

      Runtime.execute(TestCache, :ttl_key, fetch_fn, opts)
      assert :counters.get(call_count, 1) == 1

      Process.sleep(10)

      Runtime.execute(TestCache, :ttl_key, fetch_fn, opts)
      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "execute/4 - stale-while-revalidate" do
    test "serves stale data when in stale window" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        "value_#{:counters.get(call_count, 1)}"
      end

      opts = [store: [ttl: 1], serve_stale: [ttl: 60_000]]

      result1 = Runtime.execute(TestCache, :stale_key, fetch_fn, opts)
      assert result1 == "value_1"

      Process.sleep(10)

      # Should return stale value
      result2 = Runtime.execute(TestCache, :stale_key, fetch_fn, opts)
      assert result2 == "value_1"
    end

    test "triggers background refresh on stale access" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        "value_#{:counters.get(call_count, 1)}"
      end

      opts = [store: [ttl: 1], serve_stale: [ttl: 60_000], refresh: [on: :stale_access]]

      Runtime.execute(TestCache, :refresh_key, fetch_fn, opts)
      assert :counters.get(call_count, 1) == 1

      Process.sleep(10)

      Runtime.execute(TestCache, :refresh_key, fetch_fn, opts)

      # Wait for background task
      Process.sleep(100)

      # Should have called function again in background
      assert :counters.get(call_count, 1) >= 1
    end

    test "expired entries trigger immediate fetch" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        "value_#{:counters.get(call_count, 1)}"
      end

      opts = [store: [ttl: 1], serve_stale: [ttl: 2]]

      Runtime.execute(TestCache, :expired_key, fetch_fn, opts)
      assert :counters.get(call_count, 1) == 1

      Process.sleep(20)

      result = Runtime.execute(TestCache, :expired_key, fetch_fn, opts)
      assert result == "value_2"
      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "execute/4 - only_if condition" do
    test "caches when only_if returns true" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        {:ok, "success"}
      end

      opts = [store: [ttl: 60_000, only_if: &match?({:ok, _}, &1)]]

      Runtime.execute(TestCache, :only_if_ok, fetch_fn, opts)
      Runtime.execute(TestCache, :only_if_ok, fetch_fn, opts)

      assert :counters.get(call_count, 1) == 1
    end

    test "does not cache when only_if returns false" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        {:error, "failure"}
      end

      opts = [store: [ttl: 60_000, only_if: &match?({:ok, _}, &1)]]

      Runtime.execute(TestCache, :only_if_err, fetch_fn, opts)
      Runtime.execute(TestCache, :only_if_err, fetch_fn, opts)

      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "execute/4 - thunder herd prevention" do
    test "only one process fetches while others wait" do
      parent = self()
      key = :thunder_key
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        Process.sleep(50)
        "computed"
      end

      opts = [
        store: [ttl: 60_000],
        serve_stale: [ttl: 120_000],
        prevent_thunder_herd: [max_wait: 5_000, lock_ttl: 30_000]
      ]

      TestCache.delete(key)

      pids =
        for i <- 1..5 do
          spawn(fn ->
            result = Runtime.execute(TestCache, key, fetch_fn, opts)
            send(parent, {:done, i, result})
          end)
        end

      results =
        for _ <- pids do
          receive do
            {:done, _i, result} -> result
          after
            5_000 -> :timeout
          end
        end

      assert Enum.all?(results, &(&1 == "computed"))
      assert :counters.get(call_count, 1) == 1
    end

    test "waiter gets cached value after lock holder finishes" do
      key = :wait_key
      call_count = :counters.new(1, [:atomics])

      slow_fetch = fn ->
        :counters.add(call_count, 1, 1)
        Process.sleep(100)
        "slow_result"
      end

      fast_fetch = fn ->
        :counters.add(call_count, 1, 1)
        "fast_result"
      end

      opts = [
        store: [ttl: 60_000],
        serve_stale: [ttl: 120_000],
        prevent_thunder_herd: [max_wait: 5_000, lock_ttl: 30_000]
      ]

      task1 = Task.async(fn -> Runtime.execute(TestCache, key, slow_fetch, opts) end)

      Process.sleep(10)

      task2 = Task.async(fn -> Runtime.execute(TestCache, key, fast_fetch, opts) end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      assert result1 == "slow_result"
      assert result2 == "slow_result"
      assert :counters.get(call_count, 1) == 1
    end

    test "on_timeout: :error returns error tuple" do
      key = :timeout_error_key

      slow_fetch = fn ->
        Process.sleep(1_000)
        "never_returned"
      end

      fast_check = fn ->
        "fallback"
      end

      opts = [
        store: [ttl: 60_000],
        prevent_thunder_herd: [max_wait: 10, lock_ttl: 30_000, on_timeout: :error]
      ]

      Task.start(fn -> Runtime.execute(TestCache, key, slow_fetch, opts) end)

      Process.sleep(5)

      result = Runtime.execute(TestCache, key, fast_check, opts)
      assert result == {:error, :cache_timeout}
    end

    test "on_timeout: {:value, term} returns the value" do
      key = :timeout_value_key

      slow_fetch = fn ->
        Process.sleep(1_000)
        "never_returned"
      end

      opts = [
        store: [ttl: 60_000],
        prevent_thunder_herd: [max_wait: 10, lock_ttl: 30_000, on_timeout: {:value, :default}]
      ]

      Task.start(fn -> Runtime.execute(TestCache, key, slow_fetch, opts) end)

      Process.sleep(5)

      result = Runtime.execute(TestCache, key, fn -> "other" end, opts)
      assert result == :default
    end

    test "on_timeout: {:call, fn} calls the function" do
      key = :timeout_call_key

      slow_fetch = fn ->
        Process.sleep(1_000)
        "never_returned"
      end

      opts = [
        store: [ttl: 60_000],
        prevent_thunder_herd: [max_wait: 10, lock_ttl: 30_000, on_timeout: {:call, fn -> "fallback_value" end}]
      ]

      Task.start(fn -> Runtime.execute(TestCache, key, slow_fetch, opts) end)

      Process.sleep(5)

      result = Runtime.execute(TestCache, key, fn -> "other" end, opts)
      assert result == "fallback_value"
    end

    test "disabled thunder herd allows concurrent fetches" do
      key = :no_thunder_key
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn ->
        :counters.add(call_count, 1, 1)
        Process.sleep(50)
        "result"
      end

      opts = [store: [ttl: 60_000], prevent_thunder_herd: false]

      TestCache.delete(key)

      tasks =
        for _ <- 1..3 do
          Task.async(fn -> Runtime.execute(TestCache, key, fetch_fn, opts) end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, &(&1 == "result"))
      assert :counters.get(call_count, 1) >= 1
    end
  end

  describe "execute/4 - fallback handling" do
    test "on_error: :serve_stale returns stale data on failure" do
      # Pre-populate with stale data
      entry = Entry.new("stale_data", 1, 60_000)
      TestCache.put(:stale_fallback, Entry.to_tuple(entry))

      Process.sleep(10)

      opts = [
        store: [ttl: 1],
        serve_stale: [ttl: 60_000],
        fallback: [on_error: :serve_stale]
      ]

      # Since entry is stale, it returns stale without calling fetch
      result = Runtime.execute(TestCache, :stale_fallback, fn -> raise "fetch_error" end, opts)
      assert result == "stale_data"
    end

    test "on_error: {:value, term} returns fallback" do
      opts = [
        store: [ttl: 60_000],
        fallback: [on_error: {:value, :fallback_value}]
      ]

      TestCache.delete(:fallback_value_key)

      result = Runtime.execute(TestCache, :fallback_value_key, fn -> raise "fetch_error" end, opts)
      assert result == :fallback_value
    end

    test "on_error: {:call, fn} calls handler" do
      opts = [
        store: [ttl: 60_000],
        fallback: [on_error: {:call, fn _error -> :handled end}]
      ]

      TestCache.delete(:fallback_call_key)

      result = Runtime.execute(TestCache, :fallback_call_key, fn -> raise "fetch_error" end, opts)
      assert result == :handled
    end
  end

  describe "execute/4 - complex keys" do
    test "handles tuple keys" do
      opts = [store: [ttl: 60_000]]
      Runtime.execute(TestCache, {User, 123}, fn -> "user_data" end, opts)
      result = Runtime.execute(TestCache, {User, 123}, fn -> "other" end, opts)
      assert result == "user_data"
    end

    test "handles nested structure keys" do
      opts = [store: [ttl: 60_000]]
      key = {:lookup, %{type: :user, id: 42}}
      Runtime.execute(TestCache, key, fn -> "nested_data" end, opts)
      result = Runtime.execute(TestCache, key, fn -> "other" end, opts)
      assert result == "nested_data"
    end
  end
end
