defmodule Events.Types.AsyncResultTest do
  use ExUnit.Case, async: true

  alias Events.Types.AsyncResult

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
  end

  describe "parallel_settle/2" do
    test "collects all results including failures" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ]

      result = AsyncResult.parallel_settle(tasks)

      assert result.ok == [1, 3]
      assert result.errors == [:bad]
      assert length(result.results) == 3
    end

    test "returns empty collections for empty list" do
      result = AsyncResult.parallel_settle([])
      assert result == %{ok: [], errors: [], results: []}
    end
  end

  describe "race/2" do
    test "returns first successful result" do
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

    test "returns error for empty list" do
      assert AsyncResult.race([]) == {:error, :no_tasks}
    end
  end

  describe "race_with_fallback/3" do
    test "returns primary success without calling fallback" do
      result =
        AsyncResult.race_with_fallback(
          [fn -> {:ok, :primary} end],
          fn -> raise "should not be called" end
        )

      assert result == {:ok, :primary}
    end

    test "calls fallback when all primary fail" do
      result =
        AsyncResult.race_with_fallback(
          [fn -> {:error, :a} end, fn -> {:error, :b} end],
          fn -> {:ok, :fallback} end
        )

      assert result == {:ok, :fallback}
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

  describe "until_error/1" do
    test "returns all successful values until error" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 4} end
      ]

      assert AsyncResult.until_error(tasks) == {:error, {:at_index, 2, :bad, [1, 2]}}
    end

    test "returns all values if no error" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end
      ]

      assert AsyncResult.until_error(tasks) == {:ok, [1, 2]}
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
      assert result == {:error, {:max_retries_exceeded, :always_fails}}
    end
  end

  describe "combine/3" do
    test "combines two parallel tasks" do
      result =
        AsyncResult.combine(
          fn -> {:ok, 1} end,
          fn -> {:ok, 2} end
        )

      assert result == {:ok, {1, 2}}
    end

    test "returns first error" do
      result =
        AsyncResult.combine(
          fn -> {:error, :a} end,
          fn -> {:ok, 2} end
        )

      assert result == {:error, :a}
    end
  end

  describe "combine_with/4" do
    test "combines with function" do
      result =
        AsyncResult.combine_with(
          fn -> {:ok, 2} end,
          fn -> {:ok, 3} end,
          &(&1 + &2)
        )

      assert result == {:ok, 5}
    end
  end

  describe "combine_all/4" do
    test "combines all with reducer" do
      tasks = [
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:ok, 3} end
      ]

      result = AsyncResult.combine_all(tasks, fn acc, val -> acc + val end, 0)
      assert result == {:ok, 6}
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

  describe "with_timeout/2" do
    test "returns result if within timeout" do
      result = AsyncResult.with_timeout(fn -> {:ok, 42} end, 1000)
      assert result == {:ok, 42}
    end

    test "returns timeout error if exceeded" do
      result =
        AsyncResult.with_timeout(
          fn ->
            Process.sleep(100)
            {:ok, 42}
          end,
          10
        )

      assert result == {:error, :timeout}
    end
  end

  describe "map/2" do
    test "maps over successful result" do
      result =
        AsyncResult.parallel([fn -> {:ok, 1} end, fn -> {:ok, 2} end])
        |> AsyncResult.map(&Enum.sum/1)

      assert result == {:ok, 3}
    end

    test "returns error unchanged" do
      result =
        {:error, :bad}
        |> AsyncResult.map(&Enum.sum/1)

      assert result == {:error, :bad}
    end
  end

  describe "and_then/2" do
    test "chains operations" do
      result =
        AsyncResult.parallel([fn -> {:ok, 1} end])
        |> AsyncResult.and_then(fn [x] -> {:ok, x * 2} end)

      assert result == {:ok, 2}
    end
  end

  describe "with_context/2" do
    test "adds context to errors" do
      task = AsyncResult.with_context(fn -> {:error, :not_found} end, user_id: 123)
      result = task.()

      assert result == {:error, %{reason: :not_found, context: %{user_id: 123}}}
    end

    test "passes through success" do
      task = AsyncResult.with_context(fn -> {:ok, 42} end, user_id: 123)
      result = task.()

      assert result == {:ok, 42}
    end
  end

  describe "parallel_with_context/2" do
    test "executes tasks with context attached" do
      tasks = [
        {fn -> {:ok, 1} end, id: 1},
        {fn -> {:ok, 2} end, id: 2}
      ]

      {:ok, results} = AsyncResult.parallel_with_context(tasks)
      assert results == [1, 2]
    end
  end

  describe "parallel_with_progress/3" do
    test "reports progress" do
      {:ok, progress_agent} = Agent.start_link(fn -> [] end)

      tasks = Enum.map(1..3, fn i -> fn -> {:ok, i} end end)

      callback = fn completed, total ->
        Agent.update(progress_agent, fn list -> [{completed, total} | list] end)
      end

      {:ok, results} = AsyncResult.parallel_with_progress(tasks, callback, timeout: 5000)

      assert results == [1, 2, 3]

      progress = Agent.get(progress_agent, fn list -> Enum.reverse(list) end)
      assert {3, 3} in progress
    end
  end
end
