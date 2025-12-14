defmodule FnTypes.RetryTest do
  use ExUnit.Case, async: true

  alias FnTypes.Retry

  # ============================================
  # Execute Tests
  # ============================================

  describe "execute/2" do
    test "returns ok immediately when function succeeds" do
      result = Retry.execute(fn -> {:ok, 42} end)

      assert {:ok, 42} = result
    end

    test "retries on error and eventually succeeds when when predicate allows" do
      counter = :counters.new(1, [:atomics])

      result = Retry.execute(fn ->
        count = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if count < 2 do
          {:error, :transient}
        else
          {:ok, :success}
        end
      end, max_attempts: 5, when: fn _ -> true end, base_delay: 1)

      assert {:ok, :success} = result
    end

    test "fails after max attempts" do
      result = Retry.execute(
        fn -> {:error, :always_fails} end,
        max_attempts: 3,
        base_delay: 1,
        when: fn _ -> true end
      )

      assert {:error, {:max_retries, :always_fails}} = result
    end

    test "respects max_attempts option" do
      counter = :counters.new(1, [:atomics])

      Retry.execute(fn ->
        :counters.add(counter, 1, 1)
        {:error, :fail}
      end, max_attempts: 5, base_delay: 1, when: fn _ -> true end)

      assert :counters.get(counter, 1) == 5
    end

    test "calls on_retry callback on each retry" do
      retry_log = :ets.new(:retry_log, [:bag, :public])

      Retry.execute(fn ->
        {:error, :transient}
      end,
        max_attempts: 3,
        base_delay: 1,
        when: fn _ -> true end,
        on_retry: fn error, attempt, delay ->
          :ets.insert(retry_log, {attempt, error, delay})
        end
      )

      retries = :ets.tab2list(retry_log)
      :ets.delete(retry_log)

      # Should have 2 retries (first attempt + 2 retries = 3 total)
      assert length(retries) == 2
    end

    test "does not retry when when predicate returns false" do
      counter = :counters.new(1, [:atomics])

      result = Retry.execute(fn ->
        :counters.add(counter, 1, 1)
        {:error, :not_retryable}
      end,
        max_attempts: 5,
        base_delay: 1,
        when: fn _ -> false end
      )

      # Should only run once since predicate returns false
      assert :counters.get(counter, 1) == 1
      assert {:error, {:max_retries, :not_retryable}} = result
    end
  end

  # ============================================
  # Backoff Strategy Tests
  # ============================================

  describe "calculate_delay/3" do
    test "exponential backoff doubles delay" do
      delay1 = Retry.calculate_delay(1, :exponential, base: 100, jitter: 0.0)
      delay2 = Retry.calculate_delay(2, :exponential, base: 100, jitter: 0.0)
      delay3 = Retry.calculate_delay(3, :exponential, base: 100, jitter: 0.0)

      assert delay1 == 100
      assert delay2 == 200
      assert delay3 == 400
    end

    test "linear backoff increases linearly" do
      delay1 = Retry.calculate_delay(1, :linear, base: 100, jitter: 0.0)
      delay2 = Retry.calculate_delay(2, :linear, base: 100, jitter: 0.0)
      delay3 = Retry.calculate_delay(3, :linear, base: 100, jitter: 0.0)

      assert delay1 == 100
      assert delay2 == 200
      assert delay3 == 300
    end

    test "fixed backoff stays constant" do
      delay1 = Retry.calculate_delay(1, :fixed, base: 100)
      delay2 = Retry.calculate_delay(2, :fixed, base: 100)
      delay3 = Retry.calculate_delay(3, :fixed, base: 100)

      assert delay1 == 100
      assert delay2 == 100
      assert delay3 == 100
    end

    test "respects max delay cap" do
      delay = Retry.calculate_delay(10, :exponential, base: 1000, max: 5000, jitter: 0.0)

      assert delay <= 5000
    end

    test "adds jitter when specified" do
      # With jitter, delays should vary (run multiple times)
      delays = for _ <- 1..20 do
        Retry.calculate_delay(1, :exponential, base: 1000, jitter: 0.5)
      end

      # With 50% jitter, delays should vary between 500-1500
      unique_delays = Enum.uniq(delays)
      # With randomness, we should get at least a few unique values in 20 runs
      assert length(unique_delays) > 1
    end

    test "decorrelated jitter strategy works" do
      delay = Retry.calculate_delay(3, :decorrelated, base: 100, max: 10000)
      assert delay > 0
      assert delay <= 10000
    end

    test "full jitter strategy works" do
      delay = Retry.calculate_delay(3, :full_jitter, base: 100, max: 10000)
      assert delay >= 0
      assert delay <= 10000
    end

    test "equal jitter strategy works" do
      delay = Retry.calculate_delay(3, :equal_jitter, base: 100, max: 10000)
      assert delay > 0
      assert delay <= 10000
    end
  end

  # ============================================
  # With Backoff Tests
  # ============================================

  describe "with_backoff/3" do
    test "uses specified backoff strategy" do
      counter = :counters.new(1, [:atomics])

      Retry.with_backoff(
        fn ->
          count = :counters.get(counter, 1)
          :counters.add(counter, 1, 1)

          if count < 2, do: {:error, :retry}, else: {:ok, :done}
        end,
        :fixed,
        base: 1,
        max_attempts: 5,
        when: fn _ -> true end
      )

      assert :counters.get(counter, 1) == 3
    end
  end

  # ============================================
  # Recoverable Tests
  # ============================================

  describe "recoverable?/2" do
    test "returns false by default for plain errors" do
      # Without custom predicate and without Recoverable protocol impl
      refute Retry.recoverable?(:some_error)
    end

    test "uses custom when predicate" do
      assert Retry.recoverable?(:transient, when: fn _ -> true end)
      refute Retry.recoverable?(:permanent, when: fn _ -> false end)
    end
  end

  # ============================================
  # Custom Backoff Function Tests
  # ============================================

  describe "custom backoff function" do
    test "accepts custom backoff function" do
      custom_backoff = fn attempt, _opts -> attempt * 10 end

      delay1 = Retry.calculate_delay(1, custom_backoff, [])
      delay2 = Retry.calculate_delay(2, custom_backoff, [])
      delay3 = Retry.calculate_delay(3, custom_backoff, [])

      assert delay1 == 10
      assert delay2 == 20
      assert delay3 == 30
    end
  end

  # ============================================
  # Apply Jitter Tests
  # ============================================

  describe "apply_jitter/2" do
    test "returns original delay when jitter is 0" do
      assert Retry.apply_jitter(1000, 0.0) == 1000
    end

    test "applies jitter within expected range" do
      results = for _ <- 1..100, do: Retry.apply_jitter(1000, 0.25)

      # All results should be between 750 and 1250 (±25%)
      assert Enum.all?(results, fn r -> r >= 750 and r <= 1250 end)
    end
  end

  # ============================================
  # Parse Delay Tests
  # ============================================

  describe "parse_delay/1" do
    test "parses integer seconds to milliseconds" do
      assert Retry.parse_delay(5) == 5000
    end

    test "parses string seconds to milliseconds" do
      assert Retry.parse_delay("5") == 5000
    end

    test "parses tuple with milliseconds" do
      assert Retry.parse_delay({500, :milliseconds}) == 500
    end

    test "parses tuple with seconds" do
      assert Retry.parse_delay({5, :seconds}) == 5000
    end

    test "parses tuple with minutes" do
      assert Retry.parse_delay({2, :minutes}) == 120_000
    end

    test "parses tuple with hours" do
      assert Retry.parse_delay({1, :hours}) == 3_600_000
    end

    test "returns nil for invalid input" do
      assert Retry.parse_delay("invalid") == nil
      assert Retry.parse_delay(-5) == nil
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "handles immediate success" do
      result = Retry.execute(fn -> {:ok, :immediate} end)

      assert {:ok, :immediate} = result
    end

    test "handles nil return" do
      result = Retry.execute(fn -> {:ok, nil} end)

      assert {:ok, nil} = result
    end

    test "handles exception in function" do
      result = Retry.execute(
        fn -> raise "boom" end,
        max_attempts: 2,
        base_delay: 1,
        when: fn _ -> true end
      )

      assert {:error, {:max_retries, %RuntimeError{}}} = result
    end

    test "handles :ok atom result" do
      result = Retry.execute(fn -> :ok end)
      assert {:ok, :ok} = result
    end

    test "wraps non-tuple returns in ok" do
      result = Retry.execute(fn -> 42 end)
      assert {:ok, 42} = result
    end
  end
end
