defmodule FnTypes.LazyTest do
  @moduledoc """
  Tests for FnTypes.Lazy - deferred computation and streaming.
  """
  use ExUnit.Case, async: true

  alias FnTypes.Lazy

  # ============================================
  # Deferred Computation
  # ============================================

  describe "defer/2" do
    test "creates a deferred computation that doesn't execute immediately" do
      test_pid = self()

      lazy = Lazy.defer(fn ->
        send(test_pid, :executed)
        {:ok, 42}
      end)

      refute_received :executed
      assert {:ok, 42} = Lazy.run(lazy)
      assert_received :executed
    end

    test "executes computation each time when not memoized" do
      counter = :counters.new(1, [:atomics])

      lazy = Lazy.defer(fn ->
        :counters.add(counter, 1, 1)
        {:ok, :counters.get(counter, 1)}
      end)

      assert {:ok, 1} = Lazy.run(lazy)
      assert {:ok, 2} = Lazy.run(lazy)
      assert {:ok, 3} = Lazy.run(lazy)
    end
  end

  describe "pure/1" do
    test "wraps a value in a lazy ok" do
      lazy = Lazy.pure(42)
      assert {:ok, 42} = Lazy.run(lazy)
    end

    test "works with complex values" do
      lazy = Lazy.pure(%{name: "test", items: [1, 2, 3]})
      assert {:ok, %{name: "test", items: [1, 2, 3]}} = Lazy.run(lazy)
    end
  end

  describe "error/1" do
    test "creates a lazy error" do
      lazy = Lazy.error(:not_found)
      assert {:error, :not_found} = Lazy.run(lazy)
    end

    test "works with complex error reasons" do
      lazy = Lazy.error({:validation, [:email, :name]})
      assert {:error, {:validation, [:email, :name]}} = Lazy.run(lazy)
    end
  end

  describe "run/1" do
    test "executes the deferred computation" do
      lazy = Lazy.defer(fn -> {:ok, "result"} end)
      assert {:ok, "result"} = Lazy.run(lazy)
    end

    test "returns error tuples" do
      lazy = Lazy.defer(fn -> {:error, :failed} end)
      assert {:error, :failed} = Lazy.run(lazy)
    end
  end

  describe "run!/1" do
    test "returns value on success" do
      assert 42 = Lazy.run!(Lazy.pure(42))
    end

    test "raises on error" do
      lazy = Lazy.error(:failed)

      assert_raise RuntimeError, ~r/Lazy computation failed/, fn ->
        Lazy.run!(lazy)
      end
    end
  end

  # ============================================
  # Transformation
  # ============================================

  describe "map/2" do
    test "transforms the value" do
      result =
        Lazy.pure(5)
        |> Lazy.map(&(&1 * 2))
        |> Lazy.run()

      assert {:ok, 10} = result
    end

    test "chains multiple maps" do
      result =
        Lazy.pure(2)
        |> Lazy.map(&(&1 + 1))
        |> Lazy.map(&(&1 * 3))
        |> Lazy.map(&Integer.to_string/1)
        |> Lazy.run()

      assert {:ok, "9"} = result
    end

    test "skips map on error" do
      result =
        Lazy.error(:not_found)
        |> Lazy.map(fn _ -> raise "should not be called" end)
        |> Lazy.run()

      assert {:error, :not_found} = result
    end

    test "defers execution until run" do
      test_pid = self()

      lazy =
        Lazy.pure(1)
        |> Lazy.map(fn n ->
          send(test_pid, {:mapped, n})
          n + 1
        end)

      refute_received {:mapped, _}
      Lazy.run(lazy)
      assert_received {:mapped, 1}
    end
  end

  describe "and_then/2" do
    test "chains lazy computations" do
      result =
        Lazy.pure(5)
        |> Lazy.and_then(fn n ->
          Lazy.defer(fn -> {:ok, n * 2} end)
        end)
        |> Lazy.run()

      assert {:ok, 10} = result
    end

    test "short-circuits on error" do
      result =
        Lazy.error(:first_error)
        |> Lazy.and_then(fn _ ->
          Lazy.pure("should not reach")
        end)
        |> Lazy.run()

      assert {:error, :first_error} = result
    end

    test "propagates errors from chained lazy" do
      result =
        Lazy.pure(5)
        |> Lazy.and_then(fn _ ->
          Lazy.error(:chained_error)
        end)
        |> Lazy.run()

      assert {:error, :chained_error} = result
    end
  end

  describe "and_then_result/2" do
    test "chains with result-returning function" do
      result =
        Lazy.pure(5)
        |> Lazy.and_then_result(fn n -> {:ok, n * 2} end)
        |> Lazy.run()

      assert {:ok, 10} = result
    end

    test "propagates errors" do
      result =
        Lazy.pure(5)
        |> Lazy.and_then_result(fn _ -> {:error, :failed} end)
        |> Lazy.run()

      assert {:error, :failed} = result
    end
  end

  describe "or_else/2" do
    test "handles errors with recovery" do
      result =
        Lazy.error(:not_found)
        |> Lazy.or_else(fn _reason -> Lazy.pure(:default) end)
        |> Lazy.run()

      assert {:ok, :default} = result
    end

    test "passes through success" do
      result =
        Lazy.pure(:original)
        |> Lazy.or_else(fn _ -> Lazy.pure(:fallback) end)
        |> Lazy.run()

      assert {:ok, :original} = result
    end

    test "can recover with different value based on error" do
      result =
        Lazy.error(:not_found)
        |> Lazy.or_else(fn
          :not_found -> Lazy.pure(:default_user)
          :forbidden -> Lazy.pure(:guest_user)
          other -> Lazy.error(other)
        end)
        |> Lazy.run()

      assert {:ok, :default_user} = result
    end
  end

  # ============================================
  # Streaming
  # ============================================

  describe "stream/3" do
    test "creates stream from enumerable" do
      results =
        [1, 2, 3]
        |> Lazy.stream(fn n -> {:ok, n * 2} end)
        |> Enum.to_list()

      assert [{:ok, 2}, {:ok, 4}, {:ok, 6}] = results
    end

    test "halts on error by default" do
      results =
        [1, 2, 3, 4, 5]
        |> Lazy.stream(fn
          3 -> {:error, :three_is_bad}
          n -> {:ok, n}
        end)
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 2}] = results
    end

    test "skips errors with on_error: :skip" do
      results =
        [1, 2, 3, 4, 5]
        |> Lazy.stream(
          fn
            n when rem(n, 2) == 0 -> {:error, :even}
            n -> {:ok, n}
          end,
          on_error: :skip
        )
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 3}, {:ok, 5}] = results
    end

    test "collects errors with on_error: :collect" do
      results =
        [1, 2, 3, 4, 5]
        |> Lazy.stream(
          fn
            n when rem(n, 2) == 0 -> {:error, {:even, n}}
            n -> {:ok, n}
          end,
          on_error: :collect
        )
        |> Enum.to_list()

      assert [
               {:ok, 1},
               {:error, {:even, 2}},
               {:ok, 3},
               {:error, {:even, 4}},
               {:ok, 5}
             ] = results
    end

    test "respects max_errors limit" do
      results =
        [1, 2, 3, 4, 5, 6, 7]
        |> Lazy.stream(
          fn
            n when rem(n, 2) == 0 -> {:error, :even}
            n -> {:ok, n}
          end,
          on_error: :skip,
          max_errors: 2
        )
        |> Enum.to_list()

      # Stops after 2 errors (at n=4)
      assert [{:ok, 1}, {:ok, 3}] = results
    end
  end

  describe "stream_map/2" do
    test "maps over stream values" do
      results =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_map(fn n -> {:ok, n * 10} end)
        |> Enum.to_list()

      assert [{:ok, 10}, {:ok, 20}, {:ok, 30}] = results
    end

    test "passes through errors" do
      results =
        [{:ok, 1}, {:error, :failed}, {:ok, 3}]
        |> Lazy.stream_map(fn n -> {:ok, n * 10} end)
        |> Enum.to_list()

      assert [{:ok, 10}, {:error, :failed}, {:ok, 30}] = results
    end
  end

  describe "stream_filter/2" do
    test "filters stream with predicate" do
      results =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:ok, 4}]
        |> Lazy.stream_filter(fn n -> {:ok, rem(n, 2) == 0} end)
        |> Enum.to_list()

      assert [{:ok, 2}, {:ok, 4}] = results
    end

    test "propagates predicate errors" do
      results =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_filter(fn
          2 -> {:error, :two_is_bad}
          n -> {:ok, n > 1}
        end)
        |> Enum.to_list()

      assert [{:error, :two_is_bad}, {:ok, 3}] = results
    end
  end

  describe "stream_take/2" do
    test "takes first N successful results" do
      results =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:ok, 4}, {:ok, 5}]
        |> Lazy.stream_take(3)
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 2}, {:ok, 3}] = results
    end

    test "doesn't count errors toward limit" do
      results =
        [{:ok, 1}, {:error, :e1}, {:ok, 2}, {:error, :e2}, {:ok, 3}, {:ok, 4}]
        |> Lazy.stream_take(3)
        |> Enum.to_list()

      assert [{:ok, 1}, {:error, :e1}, {:ok, 2}, {:error, :e2}, {:ok, 3}] = results
    end

    test "handles taking 0" do
      results =
        [{:ok, 1}, {:ok, 2}]
        |> Lazy.stream_take(0)
        |> Enum.to_list()

      assert [] = results
    end
  end

  describe "stream_collect/2" do
    test "collects successful results (fail-fast)" do
      result =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_collect()

      assert {:ok, [1, 2, 3]} = result
    end

    test "fails fast on error" do
      result =
        [{:ok, 1}, {:error, :failed}, {:ok, 3}]
        |> Lazy.stream_collect()

      assert {:error, :failed} = result
    end

    test "settles all results with settle: true" do
      result =
        [{:ok, 1}, {:error, :e1}, {:ok, 2}, {:error, :e2}]
        |> Lazy.stream_collect(settle: true)

      assert %{ok: [1, 2], errors: [:e1, :e2]} = result
    end
  end

  describe "stream_reduce/3" do
    test "reduces stream with accumulator" do
      result =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_reduce(0, fn value, acc -> {:ok, acc + value} end)

      assert {:ok, 6} = result
    end

    test "stops on stream error" do
      result =
        [{:ok, 1}, {:error, :failed}, {:ok, 3}]
        |> Lazy.stream_reduce(0, fn value, acc -> {:ok, acc + value} end)

      assert {:error, :failed} = result
    end

    test "stops on reducer error" do
      result =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_reduce(0, fn
          2, _acc -> {:error, :two_is_bad}
          value, acc -> {:ok, acc + value}
        end)

      assert {:error, :two_is_bad} = result
    end
  end

  # ============================================
  # Pagination
  # ============================================

  describe "paginate/3" do
    test "paginates through pages" do
      # Simulate 3 pages of data
      pages = %{
        nil => %{items: [1, 2], next_cursor: :page2},
        :page2 => %{items: [3, 4], next_cursor: :page3},
        :page3 => %{items: [5], next_cursor: nil}
      }

      results =
        Lazy.paginate(
          fn cursor -> {:ok, pages[cursor]} end,
          fn page -> page.next_cursor end
        )
        |> Enum.to_list()

      assert [
               {:ok, 1},
               {:ok, 2},
               {:ok, 3},
               {:ok, 4},
               {:ok, 5}
             ] = results
    end

    test "handles fetch error" do
      results =
        Lazy.paginate(
          fn
            nil -> {:ok, %{items: [1, 2], next_cursor: :page2}}
            :page2 -> {:error, :api_error}
          end,
          fn page -> page.next_cursor end
        )
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 2}, {:error, :api_error}] = results
    end

    test "supports custom item extraction" do
      pages = %{
        nil => %{data: %{records: [1, 2]}, meta: %{next: :page2}},
        :page2 => %{data: %{records: [3]}, meta: %{next: nil}}
      }

      results =
        Lazy.paginate(
          fn cursor -> {:ok, pages[cursor]} end,
          fn page -> page.meta.next end,
          get_items: fn page -> page.data.records end
        )
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 2}, {:ok, 3}] = results
    end

    test "supports initial cursor" do
      pages = %{
        :start => %{items: [1, 2], next_cursor: nil}
      }

      results =
        Lazy.paginate(
          fn cursor -> {:ok, pages[cursor]} end,
          fn page -> page.next_cursor end,
          initial_cursor: :start
        )
        |> Enum.to_list()

      assert [{:ok, 1}, {:ok, 2}] = results
    end
  end

  # ============================================
  # Batch Processing
  # ============================================

  describe "stream_batch/3" do
    test "processes in batches" do
      results =
        [{:ok, 1}, {:ok, 2}, {:ok, 3}, {:ok, 4}, {:ok, 5}]
        |> Lazy.stream_batch(2, fn batch ->
          {:ok, Enum.sum(batch)}
        end)
        |> Enum.to_list()

      assert [{:ok, 3}, {:ok, 7}, {:ok, 5}] = results
    end

    test "skips errors in batch" do
      results =
        [{:ok, 1}, {:error, :e}, {:ok, 2}, {:ok, 3}]
        |> Lazy.stream_batch(2, fn batch ->
          {:ok, batch}
        end)
        |> Enum.to_list()

      # First batch: [1] (error skipped), Second batch: [2, 3]
      assert [{:ok, [1]}, {:ok, [2, 3]}] = results
    end
  end

  # ============================================
  # Utility
  # ============================================

  describe "zip/2" do
    test "combines two lazy values" do
      result =
        Lazy.zip(Lazy.pure(1), Lazy.pure(2))
        |> Lazy.run()

      assert {:ok, {1, 2}} = result
    end

    test "fails if first fails" do
      result =
        Lazy.zip(Lazy.error(:first), Lazy.pure(2))
        |> Lazy.run()

      assert {:error, :first} = result
    end

    test "fails if second fails" do
      result =
        Lazy.zip(Lazy.pure(1), Lazy.error(:second))
        |> Lazy.run()

      assert {:error, :second} = result
    end
  end

  describe "zip_with/3" do
    test "combines with function" do
      result =
        Lazy.zip_with(Lazy.pure(2), Lazy.pure(3), &*/2)
        |> Lazy.run()

      assert {:ok, 6} = result
    end

    test "works with complex functions" do
      result =
        Lazy.zip_with(
          Lazy.pure(%{a: 1}),
          Lazy.pure(%{b: 2}),
          &Map.merge/2
        )
        |> Lazy.run()

      assert {:ok, %{a: 1, b: 2}} = result
    end
  end

  describe "sequence/1" do
    test "sequences list of lazy values" do
      result =
        [Lazy.pure(1), Lazy.pure(2), Lazy.pure(3)]
        |> Lazy.sequence()
        |> Lazy.run()

      assert {:ok, [1, 2, 3]} = result
    end

    test "fails on first error" do
      result =
        [Lazy.pure(1), Lazy.error(:second), Lazy.pure(3)]
        |> Lazy.sequence()
        |> Lazy.run()

      assert {:error, :second} = result
    end

    test "handles empty list" do
      result =
        []
        |> Lazy.sequence()
        |> Lazy.run()

      assert {:ok, []} = result
    end
  end

  describe "to_stream/1" do
    test "converts lazy to single-element stream" do
      results =
        Lazy.pure(42)
        |> Lazy.to_stream()
        |> Enum.to_list()

      assert [{:ok, 42}] = results
    end

    test "works with error" do
      results =
        Lazy.error(:failed)
        |> Lazy.to_stream()
        |> Enum.to_list()

      assert [{:error, :failed}] = results
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "integration: lazy pipeline" do
    test "complex lazy pipeline" do
      result =
        Lazy.pure(10)
        |> Lazy.map(&(&1 * 2))
        |> Lazy.and_then(fn n ->
          if n > 15 do
            Lazy.pure(n)
          else
            Lazy.error(:too_small)
          end
        end)
        |> Lazy.map(&Integer.to_string/1)
        |> Lazy.run()

      assert {:ok, "20"} = result
    end

    test "stream with collect pipeline" do
      result =
        1..10
        |> Lazy.stream(fn n -> {:ok, n} end)
        |> Lazy.stream_filter(fn n -> {:ok, rem(n, 2) == 0} end)
        |> Lazy.stream_map(fn n -> {:ok, n * 10} end)
        |> Lazy.stream_take(3)
        |> Lazy.stream_collect()

      assert {:ok, [20, 40, 60]} = result
    end
  end
end
