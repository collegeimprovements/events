defmodule FnTypes.ThrottlerTest do
  use ExUnit.Case, async: true

  alias FnTypes.Throttler

  # ============================================
  # Start/Stop Tests
  # ============================================

  describe "start_link/1" do
    test "starts a throttler process" do
      assert {:ok, pid} = Throttler.start_link()
      assert Process.alive?(pid)
    end

    test "starts with custom interval" do
      assert {:ok, pid} = Throttler.start_link(interval: 500)
      assert Process.alive?(pid)
    end

    test "starts with name" do
      name = :"throttler_#{:erlang.unique_integer()}"
      assert {:ok, _pid} = Throttler.start_link(name: name)
      assert Process.whereis(name) != nil
    end
  end

  # ============================================
  # Call Tests
  # ============================================

  describe "call/2" do
    test "executes function immediately on first call" do
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      result = Throttler.call(throttler, fn -> {:computed, 42} end)

      assert {:ok, {:computed, 42}} = result
    end

    test "returns throttled when called too quickly" do
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      # First call succeeds
      assert {:ok, _} = Throttler.call(throttler, fn -> :first end)

      # Second call immediately after is throttled
      assert {:error, :throttled} = Throttler.call(throttler, fn -> :second end)
    end

    test "allows call after interval passes" do
      {:ok, throttler} = Throttler.start_link(interval: 10)

      # First call
      assert {:ok, :first} = Throttler.call(throttler, fn -> :first end)

      # Wait for interval
      Process.sleep(15)

      # Now should succeed
      assert {:ok, :second} = Throttler.call(throttler, fn -> :second end)
    end

    test "tracks execution count properly with throttling" do
      {:ok, throttler} = Throttler.start_link(interval: 50)
      counter = :counters.new(1, [:atomics])

      # Make several calls with small gaps - some should be throttled
      for _ <- 1..5 do
        case Throttler.call(throttler, fn ->
          :counters.add(counter, 1, 1)
          :ok
        end) do
          {:ok, _} -> :executed
          {:error, :throttled} -> :throttled
        end
        Process.sleep(10)  # Less than interval
      end

      # Should have executed only the first call (or at most 2 if timing is variable)
      count = :counters.get(counter, 1)
      assert count >= 1
      assert count < 5
    end
  end

  # ============================================
  # Reset Tests
  # ============================================

  describe "reset/1" do
    test "allows immediate execution after reset" do
      {:ok, throttler} = Throttler.start_link(interval: 10000)

      # First call
      assert {:ok, _} = Throttler.call(throttler, fn -> :first end)

      # Would normally be throttled
      assert {:error, :throttled} = Throttler.call(throttler, fn -> :second end)

      # Reset
      assert :ok = Throttler.reset(throttler)

      # Now should execute immediately
      assert {:ok, :third} = Throttler.call(throttler, fn -> :third end)
    end

    test "reset returns ok" do
      {:ok, throttler} = Throttler.start_link()

      assert :ok = Throttler.reset(throttler)
    end
  end

  # ============================================
  # Remaining Tests
  # ============================================

  describe "remaining/1" do
    test "returns 0 before first call" do
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      # Before any calls, remaining should be 0 (ready to execute)
      assert Throttler.remaining(throttler) == 0
    end

    test "returns positive value after call" do
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      # Make a call
      Throttler.call(throttler, fn -> :work end)

      # Remaining should be positive (close to 1000ms)
      remaining = Throttler.remaining(throttler)
      assert remaining > 0
      assert remaining <= 1000
    end

    test "returns 0 after interval passes" do
      {:ok, throttler} = Throttler.start_link(interval: 10)

      # Make a call
      Throttler.call(throttler, fn -> :work end)

      # Wait for interval to pass
      Process.sleep(15)

      # Remaining should be 0
      assert Throttler.remaining(throttler) == 0
    end

    test "returns 0 after reset" do
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      # Make a call
      Throttler.call(throttler, fn -> :work end)

      # Remaining should be positive
      assert Throttler.remaining(throttler) > 0

      # Reset
      Throttler.reset(throttler)

      # After reset, remaining should be 0
      assert Throttler.remaining(throttler) == 0
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "handles function that returns nil" do
      {:ok, throttler} = Throttler.start_link()

      result = Throttler.call(throttler, fn -> nil end)

      assert {:ok, nil} = result
    end

    test "handles function that returns error tuple" do
      {:ok, throttler} = Throttler.start_link()

      result = Throttler.call(throttler, fn -> {:error, :reason} end)

      assert {:ok, {:error, :reason}} = result
    end

    test "works with very short interval" do
      {:ok, throttler} = Throttler.start_link(interval: 1)

      # All calls should eventually succeed with short interval and delays
      results = for _ <- 1..5 do
        result = Throttler.call(throttler, fn -> :ok end)
        Process.sleep(2)  # Wait longer than interval
        result
      end

      ok_count = Enum.count(results, &match?({:ok, _}, &1))
      assert ok_count == 5
    end

    test "multiple throttlers are independent" do
      {:ok, t1} = Throttler.start_link(interval: 1000)
      {:ok, t2} = Throttler.start_link(interval: 1000)

      # Both first calls should succeed
      assert {:ok, _} = Throttler.call(t1, fn -> :t1 end)
      assert {:ok, _} = Throttler.call(t2, fn -> :t2 end)

      # Both second calls should be throttled
      assert {:error, :throttled} = Throttler.call(t1, fn -> :t1_again end)
      assert {:error, :throttled} = Throttler.call(t2, fn -> :t2_again end)
    end
  end
end
