defmodule FnTypes.TimingTest do
  use ExUnit.Case, async: true

  alias FnTypes.Timing
  alias FnTypes.Timing.Duration

  describe "Duration.from_native/1" do
    test "creates duration with all units" do
      # Get a reference for 1 second in native units
      one_second_native = System.convert_time_unit(1, :second, :native)
      duration = Duration.from_native(one_second_native)

      assert duration.native == one_second_native
      assert duration.seconds == 1.0
      assert duration.ms == 1000
      assert duration.us == 1_000_000
      assert duration.ns == 1_000_000_000
    end

    test "handles zero" do
      duration = Duration.from_native(0)

      assert duration.native == 0
      assert duration.ms == 0
      assert duration.seconds == 0.0
    end
  end

  describe "Duration.from_ms/1" do
    test "creates duration from milliseconds" do
      duration = Duration.from_ms(100)

      assert duration.ms == 100
      assert duration.us >= 100_000
      assert duration.seconds >= 0.099 and duration.seconds <= 0.101
    end

    test "handles zero" do
      duration = Duration.from_ms(0)
      assert duration.ms == 0
    end
  end

  describe "Duration.from_seconds/1" do
    test "creates duration from seconds" do
      duration = Duration.from_seconds(1.5)

      assert duration.seconds >= 1.49 and duration.seconds <= 1.51
      assert duration.ms == 1500
    end

    test "handles float seconds" do
      duration = Duration.from_seconds(0.001)
      assert duration.ms == 1
    end
  end

  describe "Duration.add/2" do
    test "adds two durations" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(50)
      result = Duration.add(d1, d2)

      assert result.ms == 150
    end
  end

  describe "Duration.subtract/2" do
    test "subtracts durations" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(30)
      result = Duration.subtract(d1, d2)

      assert result.ms == 70
    end

    test "returns zero when result would be negative" do
      d1 = Duration.from_ms(30)
      d2 = Duration.from_ms(100)
      result = Duration.subtract(d1, d2)

      assert result.ms == 0
    end
  end

  describe "Duration.compare/2" do
    test "compares less than" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(200)

      assert Duration.compare(d1, d2) == :lt
    end

    test "compares greater than" do
      d1 = Duration.from_ms(200)
      d2 = Duration.from_ms(100)

      assert Duration.compare(d1, d2) == :gt
    end

    test "compares equal" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(100)

      assert Duration.compare(d1, d2) == :eq
    end
  end

  describe "measure/1" do
    test "measures execution time" do
      {result, duration} = Timing.measure(fn ->
        Process.sleep(10)
        :done
      end)

      assert result == :done
      assert duration.ms >= 10
      assert duration.native > 0
    end

    test "returns result correctly" do
      {result, _duration} = Timing.measure(fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "measures fast operations" do
      {result, duration} = Timing.measure(fn -> 1 + 1 end)

      assert result == 2
      assert duration.native > 0
      assert duration.us >= 0
    end
  end

  describe "measure!/1" do
    test "returns result and milliseconds" do
      {result, ms} = Timing.measure!(fn ->
        Process.sleep(5)
        :done
      end)

      assert result == :done
      assert is_integer(ms)
      assert ms >= 5
    end
  end

  describe "measure_safe/1" do
    test "returns ok tuple on success" do
      case Timing.measure_safe(fn -> {:ok, 42} end) do
        {:ok, result, duration} ->
          assert result == {:ok, 42}
          assert %Duration{} = duration

        _ ->
          flunk("Expected :ok tuple")
      end
    end

    test "captures raised exceptions" do
      case Timing.measure_safe(fn -> raise "test error" end) do
        {:error, :error, %RuntimeError{message: "test error"}, stacktrace, duration} ->
          assert is_list(stacktrace)
          assert %Duration{} = duration
          assert duration.native > 0

        other ->
          flunk("Expected error tuple, got: #{inspect(other)}")
      end
    end

    test "captures thrown values" do
      case Timing.measure_safe(fn -> throw(:oops) end) do
        {:error, :throw, :oops, stacktrace, duration} ->
          assert is_list(stacktrace)
          assert %Duration{} = duration

        other ->
          flunk("Expected throw tuple, got: #{inspect(other)}")
      end
    end

    test "captures exits" do
      case Timing.measure_safe(fn -> exit(:normal) end) do
        {:error, :exit, :normal, stacktrace, duration} ->
          assert is_list(stacktrace)
          assert %Duration{} = duration

        other ->
          flunk("Expected exit tuple, got: #{inspect(other)}")
      end
    end

    test "measures duration even on error" do
      case Timing.measure_safe(fn ->
             Process.sleep(5)
             raise "delayed error"
           end) do
        {:error, :error, _exception, _stacktrace, duration} ->
          assert duration.ms >= 5

        _ ->
          flunk("Expected error")
      end
    end
  end

  describe "timed/2" do
    test "calls callback with duration" do
      test_pid = self()

      result = Timing.timed(fn -> :result end, fn duration ->
        send(test_pid, {:duration, duration})
      end)

      assert result == :result
      assert_receive {:duration, %Duration{}}
    end
  end

  describe "timed_if_slow/3" do
    test "calls callback when exceeds threshold" do
      test_pid = self()

      Timing.timed_if_slow(
        fn ->
          Process.sleep(20)
          :done
        end,
        10,
        fn duration ->
          send(test_pid, {:slow, duration})
        end
      )

      assert_receive {:slow, %Duration{}}
    end

    test "does not call callback when under threshold" do
      test_pid = self()

      Timing.timed_if_slow(
        fn -> :fast end,
        1000,
        fn _duration ->
          send(test_pid, :slow)
        end
      )

      refute_receive :slow, 50
    end
  end

  describe "duration_since/1" do
    test "calculates duration from start time" do
      start = System.monotonic_time()
      Process.sleep(10)
      duration = Timing.duration_since(start)

      assert duration.ms >= 10
    end
  end

  describe "slow?/2" do
    test "returns true when duration exceeds integer threshold" do
      duration = Duration.from_ms(150)

      assert Timing.slow?(duration, 100) == true
      assert Timing.slow?(duration, 200) == false
    end

    test "returns true when duration exceeds duration threshold" do
      duration = Duration.from_ms(150)
      threshold = Duration.from_ms(100)

      assert Timing.slow?(duration, threshold) == true
    end
  end

  describe "within?/2" do
    test "returns true when duration is within threshold" do
      duration = Duration.from_ms(50)

      assert Timing.within?(duration, 100) == true
      assert Timing.within?(duration, 30) == false
    end
  end

  describe "format/1" do
    test "formats nanoseconds" do
      duration = Duration.from_native(100)
      # For very small durations
      formatted = Timing.format(duration)
      assert String.ends_with?(formatted, "ns") or String.ends_with?(formatted, "μs")
    end

    test "formats milliseconds" do
      duration = Duration.from_ms(150)
      assert Timing.format(duration) == "150ms"
    end

    test "formats seconds" do
      duration = Duration.from_seconds(2.5)
      assert Timing.format(duration) == "2.5s"
    end

    test "formats minutes" do
      duration = Duration.from_seconds(90)
      assert Timing.format(duration) == "1m 30s"
    end

    test "respects unit option" do
      duration = Duration.from_ms(1500)

      assert Timing.format(duration, unit: :ms) == "1500ms"
      assert Timing.format(duration, unit: :seconds) == "1.5s"
    end

    test "respects precision option" do
      duration = Duration.from_seconds(1.234)

      assert Timing.format(duration, precision: 2) == "1.23s"
      assert Timing.format(duration, precision: 0) == "1.0s"
    end
  end

  describe "benchmark/2" do
    test "returns statistics" do
      stats = Timing.benchmark(fn -> Process.sleep(1) end, iterations: 10, warmup: 2)

      assert stats.count == 10
      assert %Duration{} = stats.total
      assert %Duration{} = stats.mean
      assert %Duration{} = stats.min
      assert %Duration{} = stats.max
      assert %Duration{} = stats.p50
      assert %Duration{} = stats.p90
      assert %Duration{} = stats.p95
      assert %Duration{} = stats.p99
      assert is_float(stats.stddev_ms)
    end

    test "min <= mean <= max" do
      stats = Timing.benchmark(fn -> :rand.uniform(10) end, iterations: 50)

      assert Duration.compare(stats.min, stats.mean) in [:lt, :eq]
      assert Duration.compare(stats.mean, stats.max) in [:lt, :eq]
    end

    test "percentiles are ordered" do
      stats = Timing.benchmark(fn -> Process.sleep(1) end, iterations: 20)

      assert Duration.compare(stats.p50, stats.p90) in [:lt, :eq]
      assert Duration.compare(stats.p90, stats.p95) in [:lt, :eq]
      assert Duration.compare(stats.p95, stats.p99) in [:lt, :eq]
    end
  end

  describe "stats/1" do
    test "calculates statistics from duration list" do
      durations = [
        Duration.from_ms(10),
        Duration.from_ms(20),
        Duration.from_ms(30),
        Duration.from_ms(40),
        Duration.from_ms(50)
      ]

      stats = Timing.stats(durations)

      assert stats.count == 5
      assert stats.min.ms == 10
      assert stats.max.ms == 50
      assert stats.mean.ms == 30
    end
  end

  describe "min/2 and max/2" do
    test "returns minimum duration" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(200)

      assert Timing.min(d1, d2).ms == 100
      assert Timing.min(d2, d1).ms == 100
    end

    test "returns maximum duration" do
      d1 = Duration.from_ms(100)
      d2 = Duration.from_ms(200)

      assert Timing.max(d1, d2).ms == 200
      assert Timing.max(d2, d1).ms == 200
    end
  end

  describe "sum/1" do
    test "sums durations" do
      durations = [
        Duration.from_ms(10),
        Duration.from_ms(20),
        Duration.from_ms(30)
      ]

      result = Timing.sum(durations)
      assert result.ms == 60
    end

    test "returns zero for empty list" do
      assert Timing.sum([]).ms == 0
    end
  end

  describe "average/1" do
    test "averages durations" do
      durations = [
        Duration.from_ms(10),
        Duration.from_ms(20),
        Duration.from_ms(30)
      ]

      result = Timing.average(durations)
      assert result.ms == 20
    end

    test "returns zero for empty list" do
      assert Timing.average([]).ms == 0
    end
  end

  describe "predicates" do
    test "duration?/1" do
      assert Timing.duration?(Duration.from_ms(100)) == true
      assert Timing.duration?(%{ms: 100}) == false
      assert Timing.duration?(100) == false
    end

    test "zero?/1" do
      assert Timing.zero?(Duration.zero()) == true
      assert Timing.zero?(Duration.from_ms(0)) == true
      assert Timing.zero?(Duration.from_ms(1)) == false
    end

    test "positive?/1" do
      assert Timing.positive?(Duration.from_ms(1)) == true
      assert Timing.positive?(Duration.from_ms(0)) == false
      assert Timing.positive?(Duration.zero()) == false
    end
  end

  describe "duration/1 tuple conversion" do
    test "converts milliseconds" do
      duration = Timing.duration({100, :milliseconds})
      assert duration.ms == 100
    end

    test "converts seconds" do
      duration = Timing.duration({2, :seconds})
      assert duration.ms == 2000
      assert duration.seconds == 2.0
    end

    test "converts minutes" do
      duration = Timing.duration({1, :minutes})
      assert duration.seconds == 60.0
    end

    test "converts hours" do
      duration = Timing.duration({1, :hours})
      assert duration.seconds == 3600.0
    end

    test "converts microseconds" do
      duration = Timing.duration({1000, :microseconds})
      assert duration.us == 1000
      assert duration.ms == 1
    end
  end

  describe "to_map/1" do
    test "converts duration to map" do
      duration = Duration.from_ms(100)
      map = Timing.to_map(duration)

      assert is_map(map)
      assert map.ms == 100
      assert Map.has_key?(map, :native)
      assert Map.has_key?(map, :ns)
      assert Map.has_key?(map, :us)
      assert Map.has_key?(map, :seconds)
    end
  end
end
