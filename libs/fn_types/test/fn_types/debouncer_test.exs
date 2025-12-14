defmodule FnTypes.DebouncerTest do
  use ExUnit.Case, async: true

  alias FnTypes.Debouncer

  # ============================================
  # Start/Stop Tests
  # ============================================

  describe "start_link/1" do
    test "starts a debouncer process" do
      assert {:ok, pid} = Debouncer.start_link()
      assert Process.alive?(pid)
    end

    test "starts with name" do
      name = :"debouncer_#{:erlang.unique_integer()}"
      assert {:ok, _pid} = Debouncer.start_link(name: name)
      assert Process.whereis(name) != nil
    end
  end

  # ============================================
  # Call Tests
  # ============================================

  describe "call/3" do
    test "executes function after delay" do
      {:ok, debouncer} = Debouncer.start_link()

      # Start timer to check execution time
      start = System.monotonic_time(:millisecond)

      result = Debouncer.call(debouncer, fn -> {:result, 42} end, 50)

      elapsed = System.monotonic_time(:millisecond) - start

      assert result == {:result, 42}
      assert elapsed >= 50
    end

    test "uses default delay of 100ms" do
      {:ok, debouncer} = Debouncer.start_link()

      start = System.monotonic_time(:millisecond)
      _result = Debouncer.call(debouncer, fn -> :ok end)
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 100
    end

    test "only executes the last call when called rapidly" do
      {:ok, debouncer} = Debouncer.start_link()

      # Use an agent to track which call executed
      {:ok, agent} = Agent.start_link(fn -> nil end)

      # Spawn tasks to make rapid calls - all but the last should be cancelled
      task1 = Task.async(fn ->
        try do
          Debouncer.call(debouncer, fn ->
            Agent.update(agent, fn _ -> :first end)
            :first
          end, 50)
        catch
          :exit, _ -> :cancelled
        end
      end)

      # Small delay to ensure first call registered
      Process.sleep(5)

      task2 = Task.async(fn ->
        try do
          Debouncer.call(debouncer, fn ->
            Agent.update(agent, fn _ -> :second end)
            :second
          end, 50)
        catch
          :exit, _ -> :cancelled
        end
      end)

      # Wait for tasks to complete
      result1 = Task.await(task1, 1000)
      result2 = Task.await(task2, 1000)

      # The first should be cancelled
      assert result1 == {:error, :cancelled}
      # The second should succeed
      assert result2 == :second

      # Agent should reflect the last call
      assert Agent.get(agent, & &1) == :second

      Agent.stop(agent)
    end
  end

  # ============================================
  # Cancel Tests
  # ============================================

  describe "cancel/1" do
    test "returns noop when nothing pending" do
      {:ok, debouncer} = Debouncer.start_link()

      assert :noop = Debouncer.cancel(debouncer)
    end

    test "cancels pending execution" do
      {:ok, debouncer} = Debouncer.start_link()

      # Start a debounced call in a task
      task = Task.async(fn ->
        Debouncer.call(debouncer, fn -> :should_not_run end, 500)
      end)

      # Give it a moment to register
      Process.sleep(10)

      # Cancel it
      assert :ok = Debouncer.cancel(debouncer)

      # The task should receive cancelled error
      result = Task.await(task, 1000)
      assert result == {:error, :cancelled}
    end
  end

  # ============================================
  # Concurrency Tests
  # ============================================

  describe "concurrency" do
    test "handles multiple sequential debounces correctly" do
      {:ok, debouncer} = Debouncer.start_link()

      # First debounced call
      result1 = Debouncer.call(debouncer, fn -> :first end, 20)
      assert result1 == :first

      # Second debounced call after first completes
      result2 = Debouncer.call(debouncer, fn -> :second end, 20)
      assert result2 == :second
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "handles function that returns nil" do
      {:ok, debouncer} = Debouncer.start_link()

      result = Debouncer.call(debouncer, fn -> nil end, 10)

      assert result == nil
    end

    test "handles function that returns error tuple" do
      {:ok, debouncer} = Debouncer.start_link()

      result = Debouncer.call(debouncer, fn -> {:error, :reason} end, 10)

      assert result == {:error, :reason}
    end

    test "works with very short delay" do
      {:ok, debouncer} = Debouncer.start_link()

      result = Debouncer.call(debouncer, fn -> :fast end, 1)

      assert result == :fast
    end
  end
end
