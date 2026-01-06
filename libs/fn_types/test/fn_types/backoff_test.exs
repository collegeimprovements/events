defmodule FnTypes.BackoffTest do
  use ExUnit.Case, async: true

  alias FnTypes.Backoff

  doctest Backoff

  describe "exponential/1" do
    test "creates exponential backoff with defaults" do
      backoff = Backoff.exponential()

      assert backoff.strategy == :exponential
      assert backoff.initial_delay == 100
      assert backoff.max_delay == 30_000
      assert backoff.jitter_factor == 0.25
      assert backoff.multiplier == 2
    end

    test "accepts custom options" do
      backoff = Backoff.exponential(initial: 500, max: 60_000, jitter: 0.1, multiplier: 1.5)

      assert backoff.initial_delay == 500
      assert backoff.max_delay == 60_000
      assert backoff.jitter_factor == 0.1
      assert backoff.multiplier == 1.5
    end
  end

  describe "linear/1" do
    test "creates linear backoff with defaults" do
      backoff = Backoff.linear()

      assert backoff.strategy == :linear
      assert backoff.initial_delay == 100
      assert backoff.max_delay == 30_000
      assert backoff.jitter_factor == 0.0
    end

    test "accepts custom options" do
      backoff = Backoff.linear(initial: 200, max: 10_000)

      assert backoff.initial_delay == 200
      assert backoff.max_delay == 10_000
    end
  end

  describe "constant/1" do
    test "creates constant backoff" do
      backoff = Backoff.constant(2000)

      assert backoff.strategy == :constant
      assert backoff.initial_delay == 2000
      assert backoff.max_delay == 2000
      assert backoff.jitter_factor == 0.0
    end
  end

  describe "decorrelated/1" do
    test "creates decorrelated jitter backoff with defaults" do
      backoff = Backoff.decorrelated()

      assert backoff.strategy == :decorrelated
      assert backoff.initial_delay == 100
      assert backoff.max_delay == 30_000
    end

    test "accepts custom options" do
      backoff = Backoff.decorrelated(base: 200, max: 15_000)

      assert backoff.initial_delay == 200
      assert backoff.max_delay == 15_000
    end
  end

  describe "full_jitter/1" do
    test "creates full jitter backoff" do
      backoff = Backoff.full_jitter(base: 1000)

      assert backoff.strategy == :full_jitter
      assert backoff.initial_delay == 1000
      assert backoff.jitter_factor == 1.0
    end
  end

  describe "equal_jitter/1" do
    test "creates equal jitter backoff" do
      backoff = Backoff.equal_jitter(base: 500)

      assert backoff.strategy == :equal_jitter
      assert backoff.initial_delay == 500
      assert backoff.jitter_factor == 0.5
    end
  end

  describe "delay/2 - exponential strategy" do
    test "calculates exponential backoff: base * 2^(attempt-1)" do
      backoff = Backoff.exponential(initial: 100, jitter: 0.0)

      assert {:ok, 100} = Backoff.delay(backoff, attempt: 1)
      assert {:ok, 200} = Backoff.delay(backoff, attempt: 2)
      assert {:ok, 400} = Backoff.delay(backoff, attempt: 3)
      assert {:ok, 800} = Backoff.delay(backoff, attempt: 4)
    end

    test "respects max_delay cap" do
      backoff = Backoff.exponential(initial: 100, max: 500, jitter: 0.0)

      assert {:ok, 100} = Backoff.delay(backoff, attempt: 1)
      assert {:ok, 200} = Backoff.delay(backoff, attempt: 2)
      assert {:ok, 400} = Backoff.delay(backoff, attempt: 3)
      assert {:ok, 500} = Backoff.delay(backoff, attempt: 4)  # Capped
      assert {:ok, 500} = Backoff.delay(backoff, attempt: 5)  # Still capped
    end

    test "applies jitter when configured" do
      backoff = Backoff.exponential(initial: 1000, jitter: 0.25)

      # With 25% jitter on 1000ms base, delay should be in range [750, 1250]
      {:ok, delay} = Backoff.delay(backoff, attempt: 1)
      assert delay >= 750
      assert delay <= 1250
    end

    test "supports custom multiplier" do
      # 1.5x growth instead of 2x
      backoff = Backoff.exponential(initial: 100, multiplier: 1.5, jitter: 0.0)

      assert {:ok, 100} = Backoff.delay(backoff, attempt: 1)  # 100 * 1.5^0
      assert {:ok, 150} = Backoff.delay(backoff, attempt: 2)  # 100 * 1.5^1
      assert {:ok, 225} = Backoff.delay(backoff, attempt: 3)  # 100 * 1.5^2
    end
  end

  describe "delay/2 - linear strategy" do
    test "calculates linear backoff: base * attempt" do
      backoff = Backoff.linear(initial: 100)

      assert {:ok, 100} = Backoff.delay(backoff, attempt: 1)   # 100 * 1
      assert {:ok, 200} = Backoff.delay(backoff, attempt: 2)   # 100 * 2
      assert {:ok, 300} = Backoff.delay(backoff, attempt: 3)   # 100 * 3
      assert {:ok, 1000} = Backoff.delay(backoff, attempt: 10) # 100 * 10
    end

    test "respects max_delay cap" do
      backoff = Backoff.linear(initial: 100, max: 500)

      assert {:ok, 100} = Backoff.delay(backoff, attempt: 1)
      assert {:ok, 200} = Backoff.delay(backoff, attempt: 2)
      assert {:ok, 500} = Backoff.delay(backoff, attempt: 6)  # Capped at 500
      assert {:ok, 500} = Backoff.delay(backoff, attempt: 10) # Still capped
    end
  end

  describe "delay/2 - constant strategy" do
    test "always returns the same delay" do
      backoff = Backoff.constant(2000)

      assert {:ok, 2000} = Backoff.delay(backoff, attempt: 1)
      assert {:ok, 2000} = Backoff.delay(backoff, attempt: 2)
      assert {:ok, 2000} = Backoff.delay(backoff, attempt: 99)
    end
  end

  describe "delay/2 - decorrelated strategy" do
    test "calculates delay with decorrelated jitter" do
      backoff = Backoff.decorrelated(base: 100, max: 10_000)

      # First attempt uses base
      {:ok, delay1} = Backoff.delay(backoff, attempt: 1)
      assert delay1 >= 100

      # Subsequent attempts use previous delay
      {:ok, delay2} = Backoff.delay(backoff, attempt: 2, previous_delay: delay1)
      # Should be between base and min(previous * 3, max)
      expected_max = min(delay1 * 3, 10_000)
      assert delay2 >= 100
      assert delay2 <= expected_max
    end

    test "respects max_delay cap" do
      backoff = Backoff.decorrelated(base: 100, max: 500)

      {:ok, delay} = Backoff.delay(backoff, attempt: 10, previous_delay: 1000)
      assert delay <= 500
    end

    test "handles edge case when previous * 3 < base" do
      backoff = Backoff.decorrelated(base: 1000, max: 10_000)

      # If previous is very small, should still use base as minimum
      {:ok, delay} = Backoff.delay(backoff, attempt: 2, previous_delay: 10)
      assert delay >= 1000
    end
  end

  describe "delay/2 - full_jitter strategy" do
    test "returns random delay between 0 and exponential cap" do
      backoff = Backoff.full_jitter(base: 1000)

      # Attempt 1: 0 to 2000 (1000 * 2^1)
      {:ok, delay1} = Backoff.delay(backoff, attempt: 1)
      assert delay1 >= 0
      assert delay1 <= 2000

      # Attempt 3: 0 to 8000 (1000 * 2^3)
      {:ok, delay3} = Backoff.delay(backoff, attempt: 3)
      assert delay3 >= 0
      assert delay3 <= 8000
    end

    test "respects max_delay cap" do
      backoff = Backoff.full_jitter(base: 1000, max: 5000)

      {:ok, delay} = Backoff.delay(backoff, attempt: 10)
      assert delay <= 5000
    end
  end

  describe "delay/2 - equal_jitter strategy" do
    test "returns half exponential + half random" do
      backoff = Backoff.equal_jitter(base: 1000)

      # Attempt 3: exp = 1000 * 2^2 = 4000
      # Expected range: 2000-4000 (half + random half)
      {:ok, delay} = Backoff.delay(backoff, attempt: 3)
      assert delay >= 2000
      assert delay <= 4000
    end

    test "respects max_delay cap" do
      backoff = Backoff.equal_jitter(base: 1000, max: 3000)

      {:ok, delay} = Backoff.delay(backoff, attempt: 10)
      assert delay <= 3000
    end
  end

  describe "delay/2 - custom function" do
    test "supports custom backoff function" do
      custom_backoff = %Backoff{
        strategy: fn attempt, _opts ->
          # Logarithmic growth
          round(100 * :math.log(attempt + 1))
        end,
        initial_delay: 100,
        max_delay: 1000
      }

      {:ok, delay1} = Backoff.delay(custom_backoff, attempt: 1)
      {:ok, delay2} = Backoff.delay(custom_backoff, attempt: 2)
      {:ok, delay10} = Backoff.delay(custom_backoff, attempt: 10)

      # Logarithmic growth is slower than exponential
      assert delay1 < delay2
      assert delay2 < delay10
      assert delay10 <= 1000  # Still respects max
    end
  end

  describe "apply_jitter/2" do
    test "returns delay unchanged when jitter is 0" do
      assert 1000.0 == Backoff.apply_jitter(1000, 0.0)
      assert 5000.0 == Backoff.apply_jitter(5000, 0.0)
    end

    test "applies 25% jitter" do
      # Run multiple times to verify jitter is within expected range
      results =
        for _ <- 1..100 do
          Backoff.apply_jitter(1000, 0.25)
        end

      # All values should be in [750, 1250] range
      assert Enum.all?(results, fn delay -> delay >= 750 and delay <= 1250 end)

      # Should have good distribution (not all the same)
      unique_count = results |> Enum.uniq() |> length()
      assert unique_count > 50  # Should have many unique values
    end

    test "applies 50% jitter" do
      results =
        for _ <- 1..100 do
          Backoff.apply_jitter(1000, 0.5)
        end

      # All values should be in [500, 1500] range
      assert Enum.all?(results, fn delay -> delay >= 500 and delay <= 1500 end)
    end

    test "never returns negative delays" do
      results =
        for _ <- 1..100 do
          Backoff.apply_jitter(10, 1.0)  # Extreme case
        end

      assert Enum.all?(results, fn delay -> delay >= 0 end)
    end
  end

  describe "parse_delay/1" do
    test "parses integer seconds" do
      assert 5000 == Backoff.parse_delay(5)
      assert 0 == Backoff.parse_delay(0)
      assert 60_000 == Backoff.parse_delay(60)
    end

    test "parses string seconds" do
      assert 5000 == Backoff.parse_delay("5")
      assert 0 == Backoff.parse_delay("0")
      assert 120_000 == Backoff.parse_delay("120")
    end

    test "parses tuple formats" do
      assert 500 == Backoff.parse_delay({500, :milliseconds})
      assert 5000 == Backoff.parse_delay({5, :seconds})
      assert 60_000 == Backoff.parse_delay({1, :minutes})
      assert 3_600_000 == Backoff.parse_delay({1, :hours})
    end

    test "returns nil for invalid input" do
      assert nil == Backoff.parse_delay("invalid")
      assert nil == Backoff.parse_delay("5.5x")
      assert nil == Backoff.parse_delay(-5)
      assert nil == Backoff.parse_delay({-1, :seconds})
      assert nil == Backoff.parse_delay(%{})
    end
  end

  describe "integration scenarios" do
    test "realistic API retry scenario" do
      # Start with 100ms, exponential backoff, max 30s
      backoff = Backoff.exponential(initial: 100, max: 30_000, jitter: 0.25)

      {:ok, delay1} = Backoff.delay(backoff, attempt: 1)
      {:ok, delay2} = Backoff.delay(backoff, attempt: 2)
      {:ok, delay3} = Backoff.delay(backoff, attempt: 3)
      {:ok, delay4} = Backoff.delay(backoff, attempt: 4)
      {:ok, delay5} = Backoff.delay(backoff, attempt: 5)

      # Each delay should generally be ~2x the previous (with jitter variance)
      assert delay1 < delay2
      assert delay2 < delay3
      assert delay3 < delay4
      assert delay4 < delay5

      # None should exceed max
      assert delay5 <= 30_000
    end

    test "distributed system decorrelated jitter" do
      backoff = Backoff.decorrelated(base: 100, max: 10_000)

      # Simulate multiple retry attempts tracking previous delay
      {:ok, delay1} = Backoff.delay(backoff, attempt: 1)
      {:ok, delay2} = Backoff.delay(backoff, attempt: 2, previous_delay: delay1)
      {:ok, delay3} = Backoff.delay(backoff, attempt: 3, previous_delay: delay2)

      # All delays should be reasonable
      assert delay1 >= 100
      assert delay2 >= 100
      assert delay3 >= 100
      assert delay3 <= 10_000
    end

    test "gentle linear backoff for internal services" do
      # Use linear backoff for predictable, gradual increase
      backoff = Backoff.linear(initial: 200, max: 5000)

      {:ok, 200} = Backoff.delay(backoff, attempt: 1)
      {:ok, 400} = Backoff.delay(backoff, attempt: 2)
      {:ok, 600} = Backoff.delay(backoff, attempt: 3)
      {:ok, 800} = Backoff.delay(backoff, attempt: 4)
    end

    test "constant backoff for fixed polling interval" do
      backoff = Backoff.constant(1000)

      # Always poll every 1 second
      {:ok, 1000} = Backoff.delay(backoff, attempt: 1)
      {:ok, 1000} = Backoff.delay(backoff, attempt: 10)
      {:ok, 1000} = Backoff.delay(backoff, attempt: 100)
    end
  end

  describe "comparison with existing implementations" do
    test "matches FnTypes.Retry exponential behavior" do
      backoff = Backoff.exponential(initial: 100, max: 5000, jitter: 0.25)

      # FnTypes.Retry uses: base * 2^(attempt-1)
      # Our exponential should produce the same base delays
      {:ok, delay1} = Backoff.delay(backoff, attempt: 1)
      {:ok, delay2} = Backoff.delay(backoff, attempt: 2)
      {:ok, delay3} = Backoff.delay(backoff, attempt: 3)

      # With jitter, we can't assert exact values, but we can verify ranges
      # Attempt 1: ~100ms (75-125 with 25% jitter)
      assert delay1 >= 75 and delay1 <= 125

      # Attempt 2: ~200ms (150-250 with 25% jitter)
      assert delay2 >= 150 and delay2 <= 250

      # Attempt 3: ~400ms (300-500 with 25% jitter)
      assert delay3 >= 300 and delay3 <= 500
    end

    test "matches Effect.Retry decorrelated behavior" do
      backoff = Backoff.decorrelated(base: 100, max: 30_000)

      {:ok, delay} = Backoff.delay(backoff, attempt: 2, previous_delay: 300)

      # Effect.Retry uses: base + rand() * (upper - base) where upper = base * 3^(attempt-1)
      # For attempt 2: upper = 100 * 3^1 = 300, so delay should be in [100, 300]
      # But we use previous * 3, so: [100, 900]
      assert delay >= 100
      assert delay <= 900
    end
  end
end
