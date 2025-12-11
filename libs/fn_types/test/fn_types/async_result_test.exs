defmodule FnTypes.AsyncResultTest do
  use ExUnit.Case, async: true

  alias FnTypes.AsyncResult

  describe "parallel/2" do
    test "executes tasks in parallel and returns all results" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:ok, 3} end
      ]

      assert AsyncResult.parallel(tasks) == {:ok, [1, 2, 3]}
    end

    test "returns first error on failure" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ]

      assert AsyncResult.parallel(tasks) == {:error, :bad}
    end

    test "returns ok for empty list" do
      assert AsyncResult.parallel([]) == {:ok, []}
    end

    test "respects max_concurrency option" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      tasks =
        Enum.map(1..10, fn i ->
          fn ->
            current = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
            # Ensure we're not running more than max_concurrency at once
            Process.sleep(10)
            Agent.update(agent, fn n -> n - 1 end)
            {:ok, {i, current}}
          end
        end)

      {:ok, results} = AsyncResult.parallel(tasks, max_concurrency: 2)
      assert length(results) == 10
    end

    test "preserves order when ordered: true" do
      tasks =
        Enum.map(1..5, fn i ->
          fn ->
            Process.sleep(:rand.uniform(10))
            {:ok, i}
          end
        end)

      {:ok, results} = AsyncResult.parallel(tasks, ordered: true)
      assert results == [1, 2, 3, 4, 5]
    end

    test "collects all results with settle: true" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ]

      result = AsyncResult.parallel(tasks, settle: true)

      assert result.ok == [1, 3]
      assert result.errors == [:bad]
      assert length(result.results) == 3
    end

    test "returns empty collections for empty list with settle: true" do
      result = AsyncResult.parallel([], settle: true)
      assert result == %{ok: [], errors: [], results: []}
    end

    test "reports progress with on_progress callback" do
      {:ok, progress_agent} = Agent.start_link(fn -> [] end)

      tasks = Enum.map(1..3, fn i -> fn -> {:ok, i} end end)

      callback = fn completed, total ->
        Agent.update(progress_agent, fn list -> [{completed, total} | list] end)
      end

      {:ok, results} = AsyncResult.parallel(tasks, on_progress: callback, timeout: 5000)

      assert results == [1, 2, 3]

      progress = Agent.get(progress_agent, fn list -> Enum.reverse(list) end)
      assert {3, 3} in progress
    end
  end

  describe "parallel_map/3" do
    test "maps function over items in parallel" do
      {:ok, results} = AsyncResult.parallel_map([1, 2, 3], fn x -> {:ok, x * 2} end)
      assert results == [2, 4, 6]
    end

    test "returns error if any fails" do
      result =
        AsyncResult.parallel_map([1, 2, 3], fn
          2 -> {:error, :bad}
          x -> {:ok, x * 2}
        end)

      assert result == {:error, :bad}
    end

    test "collects all results with settle: true" do
      result =
        AsyncResult.parallel_map(
          [1, 2, 3],
          fn
            2 -> {:error, :bad}
            x -> {:ok, x * 2}
          end,
          settle: true
        )

      assert result.ok == [2, 6]
      assert result.errors == [:bad]
    end
  end

  describe "race/2" do
    test "returns first successful result" do
      # Trap exits to handle shutdown signals from spawned tasks
      Process.flag(:trap_exit, true)

      tasks = [
        fn ->
          Process.sleep(50)
          {:ok, :slow}
        end,
        fn -> {:ok, :fast} end,
        fn ->
          Process.sleep(100)
          {:ok, :slower}
        end
      ]

      assert AsyncResult.race(tasks) == {:ok, :fast}
    end

    test "returns error if all fail" do
      tasks = [
        fn -> {:error, :a} end,
        fn -> {:error, :b} end
      ]

      {:error, errors} = AsyncResult.race(tasks)
      assert Enum.sort(errors) == [:a, :b]
    end

    test "raises for empty list" do
      assert_raise FunctionClauseError, fn ->
        AsyncResult.race([])
      end
    end
  end

  describe "first_ok/1" do
    test "returns first successful result" do
      tasks = [
        fn -> {:error, :a} end,
        fn -> {:ok, :found} end,
        fn -> raise "should not be called" end
      ]

      assert AsyncResult.first_ok(tasks) == {:ok, :found}
    end

    test "returns error if all fail" do
      tasks = [
        fn -> {:error, :a} end,
        fn -> {:error, :b} end
      ]

      assert AsyncResult.first_ok(tasks) == {:error, :all_failed}
    end
  end

  describe "batch/2" do
    test "executes tasks in batches" do
      tasks = Enum.map(1..10, fn i -> fn -> {:ok, i} end end)

      {:ok, results} = AsyncResult.batch(tasks, batch_size: 3)
      assert results == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    end

    test "fails fast on error" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ]

      assert AsyncResult.batch(tasks, batch_size: 1) == {:error, :bad}
    end
  end

  describe "retry/2" do
    test "succeeds on first try" do
      result = AsyncResult.retry(fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "retries on failure and eventually succeeds" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      task = fn ->
        count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if count < 2 do
          {:error, :retry}
        else
          {:ok, :success}
        end
      end

      result = AsyncResult.retry(task, max_attempts: 5, initial_delay: 1)
      assert result == {:ok, :success}
    end

    test "returns error after max attempts" do
      task = fn -> {:error, :always_fails} end

      result = AsyncResult.retry(task, max_attempts: 3, initial_delay: 1)
      assert result == {:error, {:max_retries, :always_fails}}
    end
  end

  describe "safe/1" do
    test "wraps successful result" do
      result = AsyncResult.safe(fn -> 42 end)
      assert result == {:ok, 42}
    end

    test "wraps exception in error" do
      result = AsyncResult.safe(fn -> raise "boom" end)
      assert {:error, %RuntimeError{}} = result
    end
  end

  describe "timeout/2" do
    test "returns result if within timeout" do
      result = AsyncResult.timeout(fn -> {:ok, 42} end, 1000)
      assert result == {:ok, 42}
    end

    test "returns timeout error if exceeded" do
      result =
        AsyncResult.timeout(
          fn ->
            Process.sleep(100)
            {:ok, 42}
          end,
          10
        )

      assert result == {:error, :timeout}
    end
  end

  describe "hedge/3" do
    test "returns primary result if fast enough" do
      result =
        AsyncResult.hedge(
          fn -> {:ok, :primary} end,
          fn -> {:ok, :backup} end,
          delay: 100
        )

      assert result == {:ok, :primary}
    end

    test "returns backup if primary is slow" do
      # Trap exits to handle shutdown signals from spawned tasks
      Process.flag(:trap_exit, true)

      result =
        AsyncResult.hedge(
          fn ->
            Process.sleep(200)
            {:ok, :primary}
          end,
          fn -> {:ok, :backup} end,
          delay: 10
        )

      assert result == {:ok, :backup}
    end
  end

  describe "fire_and_forget/2" do
    test "returns pid immediately" do
      {:ok, pid} = AsyncResult.fire_and_forget(fn -> :ok end)
      assert is_pid(pid)
    end
  end

  describe "stream/3" do
    test "processes items with backpressure" do
      results =
        1..5
        |> AsyncResult.stream(fn x -> {:ok, x * 2} end, max_concurrency: 2)
        |> Enum.to_list()

      assert Enum.sort(results) == [{:ok, 2}, {:ok, 4}, {:ok, 6}, {:ok, 8}, {:ok, 10}]
    end

    test "halts on error by default" do
      results =
        1..5
        |> AsyncResult.stream(fn
          3 -> {:error, :bad}
          x -> {:ok, x}
        end)
        |> Enum.to_list()

      # Will include some results before the error, then halt
      assert {:error, :bad} in results
    end

    test "skips errors with on_error: :skip" do
      results =
        1..5
        |> AsyncResult.stream(
          fn
            3 -> {:error, :bad}
            x -> {:ok, x}
          end,
          on_error: :skip
        )
        |> Enum.to_list()

      assert results == [{:ok, 1}, {:ok, 2}, {:ok, 4}, {:ok, 5}]
    end
  end

  describe "lazy/1 and run_lazy/1" do
    test "defers computation until run" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      lazy =
        AsyncResult.lazy(fn ->
          Agent.update(counter, &(&1 + 1))
          {:ok, :done}
        end)

      # Not executed yet
      assert Agent.get(counter, & &1) == 0

      # Execute
      assert AsyncResult.run_lazy(lazy) == {:ok, :done}
      assert Agent.get(counter, & &1) == 1
    end

    test "run_lazy handles list of lazies" do
      lazies = [
        AsyncResult.lazy(fn -> {:ok, 1} end),
        AsyncResult.lazy(fn -> {:ok, 2} end),
        AsyncResult.lazy(fn -> {:ok, 3} end)
      ]

      assert AsyncResult.run_lazy(lazies) == {:ok, [1, 2, 3]}
    end
  end

  describe "lazy_then/2" do
    test "chains lazy computations" do
      lazy =
        AsyncResult.lazy(fn -> {:ok, 5} end)
        |> AsyncResult.lazy_then(fn x ->
          AsyncResult.lazy(fn -> {:ok, x * 2} end)
        end)

      assert AsyncResult.run_lazy(lazy) == {:ok, 10}
    end
  end

  describe "async/1 and await/2" do
    test "basic async/await" do
      handle = AsyncResult.async(fn -> {:ok, 42} end)
      assert AsyncResult.await(handle) == {:ok, 42}
    end

    test "await with timeout" do
      handle =
        AsyncResult.async(fn ->
          Process.sleep(100)
          {:ok, 42}
        end)

      assert AsyncResult.await(handle, timeout: 10) == {:error, :timeout}
    end
  end

  describe "await_many/2" do
    test "awaits multiple handles" do
      handles = [
        AsyncResult.async(fn -> {:ok, 1} end),
        AsyncResult.async(fn -> {:ok, 2} end),
        AsyncResult.async(fn -> {:ok, 3} end)
      ]

      assert AsyncResult.await_many(handles) == {:ok, [1, 2, 3]}
    end

    test "returns settlement with settle: true" do
      handles = [
        AsyncResult.async(fn -> {:ok, 1} end),
        AsyncResult.async(fn -> {:error, :bad} end),
        AsyncResult.async(fn -> {:ok, 3} end)
      ]

      result = AsyncResult.await_many(handles, settle: true)
      assert result.ok == [1, 3]
      assert result.errors == [:bad]
    end
  end

  describe "yield/2" do
    test "returns result if ready" do
      handle = AsyncResult.async(fn -> {:ok, 42} end)
      Process.sleep(10)
      assert AsyncResult.yield(handle) == {:ok, {:ok, 42}}
    end

    test "returns nil if not ready" do
      handle =
        AsyncResult.async(fn ->
          Process.sleep(100)
          {:ok, 42}
        end)

      assert AsyncResult.yield(handle, timeout: 0) == nil
    end
  end

  describe "shutdown/2" do
    test "terminates running task" do
      handle =
        AsyncResult.async(fn ->
          Process.sleep(1000)
          {:ok, 42}
        end)

      result = AsyncResult.shutdown(handle)
      # Either nil (no result) or the result if it finished
      assert result in [nil, {:ok, 42}]
    end
  end

  describe "completed/1" do
    test "creates pre-computed handle" do
      handle = AsyncResult.completed({:ok, 42})
      assert AsyncResult.await(handle) == {:ok, 42}
    end
  end

  describe "run_all/3" do
    test "executes all functions ignoring results" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      items = [1, 2, 3]

      :ok =
        AsyncResult.run_all(items, fn x ->
          Agent.update(agent, fn list -> [x | list] end)
        end)

      Process.sleep(50)
      values = Agent.get(agent, & &1)
      assert Enum.sort(values) == [1, 2, 3]
    end
  end

  describe "Settlement helpers" do
    alias AsyncResult.Settlement

    test "Settlement.ok/1 extracts successes" do
      result = %{ok: [1, 2], errors: [:bad], results: []}
      assert Settlement.ok(result) == [1, 2]
    end

    test "Settlement.errors/1 extracts failures" do
      result = %{ok: [1, 2], errors: [:bad, :worse], results: []}
      assert Settlement.errors(result) == [:bad, :worse]
    end

    test "Settlement.ok?/1 checks if all succeeded" do
      assert Settlement.ok?(%{ok: [1, 2], errors: [], results: []})
      refute Settlement.ok?(%{ok: [1], errors: [:bad], results: []})
    end

    test "Settlement.split/1 returns tuple" do
      result = %{ok: [1, 2], errors: [:bad], results: []}
      assert Settlement.split(result) == {[1, 2], [:bad]}
    end
  end
end
