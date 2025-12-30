defmodule FnTypes.Timing do
  @moduledoc """
  Execution timing and duration utilities.

  Provides consistent, comprehensive timing measurement with multiple output
  formats, exception handling, and utility functions for working with durations.

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `measure/1` | Measure execution, get `{result, duration}` |
  | `measure!/1` | Measure execution, get `{result, ms}` (simple) |
  | `measure_safe/1` | Measure with exception capture |
  | `timed/2` | Execute with callback receiving duration |
  | `benchmark/2` | Run N iterations, get statistics |
  | `slow?/2` | Check if duration exceeds threshold |
  | `format/1` | Human-readable duration string |

  ## Basic Usage

      alias FnTypes.Timing

      # Simple measurement
      {result, duration} = Timing.measure(fn -> expensive_operation() end)
      Logger.info("Completed in \#{duration.ms}ms")

      # Even simpler - just get milliseconds
      {result, ms} = Timing.measure!(fn -> operation() end)

      # With exception handling
      case Timing.measure_safe(fn -> risky_operation() end) do
        {:ok, result, duration} ->
          Logger.info("Success in \#{duration.ms}ms")
        {:error, kind, reason, stacktrace, duration} ->
          Logger.error("Failed after \#{duration.ms}ms")
      end

  ## Duration Struct

  The `duration` returned by `measure/1` contains multiple units:

      %FnTypes.Timing.Duration{
        native: 1234567,      # Native time units (for telemetry)
        ns: 1234567000,       # Nanoseconds
        us: 1234567,          # Microseconds
        ms: 1234,             # Milliseconds
        seconds: 1.234        # Seconds (float)
      }

  ## Telemetry Integration

      # Emit telemetry with timing
      {result, duration} = Timing.measure(fn -> fetch_user(id) end)
      :telemetry.execute([:app, :user, :fetch], %{duration: duration.native}, %{id: id})

  ## Benchmarking

      # Run 1000 iterations and get statistics
      stats = Timing.benchmark(fn -> operation() end, iterations: 1000)
      IO.puts("Mean: \#{stats.mean.ms}ms, P99: \#{stats.p99.ms}ms")

  ## Threshold Checking

      {result, duration} = Timing.measure(fn -> query() end)
      if Timing.slow?(duration, 100) do
        Logger.warning("Slow query: \#{duration.ms}ms")
      end
  """

  # ============================================
  # Types
  # ============================================

  defmodule Duration do
    @moduledoc """
    Represents a measured duration in multiple time units.

    All fields are derived from the same measurement, just in different units
    for convenience. Use whichever unit is appropriate for your context:

    - `:native` - For telemetry (pass directly to `:telemetry.execute/3`)
    - `:ns` - Nanoseconds (high precision timing)
    - `:us` - Microseconds (database queries, fast operations)
    - `:ms` - Milliseconds (HTTP requests, most common)
    - `:seconds` - Float seconds (human display, long operations)

    ## Examples

        duration.ms       #=> 150
        duration.seconds  #=> 0.15
        duration.native   #=> 12345678 (for telemetry)
    """

    @enforce_keys [:native]
    defstruct [:native, :ns, :us, :ms, :seconds]

    @type t :: %__MODULE__{
            native: integer(),
            ns: non_neg_integer(),
            us: non_neg_integer(),
            ms: non_neg_integer(),
            seconds: float()
          }

    @doc """
    Creates a Duration from native time units.

    You typically don't call this directly - use `FnTypes.Timing.measure/1` instead.
    """
    @spec from_native(integer()) :: t()
    def from_native(native) when is_integer(native) do
      %__MODULE__{
        native: native,
        ns: System.convert_time_unit(native, :native, :nanosecond),
        us: System.convert_time_unit(native, :native, :microsecond),
        ms: System.convert_time_unit(native, :native, :millisecond),
        seconds: native / System.convert_time_unit(1, :second, :native)
      }
    end

    @doc """
    Creates a Duration from milliseconds.

    Useful for creating durations from config values or thresholds.

    ## Examples

        threshold = Duration.from_ms(100)
        Timing.slow?(actual_duration, threshold)
    """
    @spec from_ms(non_neg_integer()) :: t()
    def from_ms(ms) when is_integer(ms) and ms >= 0 do
      native = System.convert_time_unit(ms, :millisecond, :native)
      from_native(native)
    end

    @doc """
    Creates a Duration from microseconds.
    """
    @spec from_us(non_neg_integer()) :: t()
    def from_us(us) when is_integer(us) and us >= 0 do
      native = System.convert_time_unit(us, :microsecond, :native)
      from_native(native)
    end

    @doc """
    Creates a Duration from seconds (can be float).
    """
    @spec from_seconds(number()) :: t()
    def from_seconds(seconds) when is_number(seconds) and seconds >= 0 do
      native = round(seconds * System.convert_time_unit(1, :second, :native))
      from_native(native)
    end

    @doc """
    Adds two durations together.

    ## Examples

        total = Duration.add(duration1, duration2)
    """
    @spec add(t(), t()) :: t()
    def add(%__MODULE__{native: a}, %__MODULE__{native: b}) do
      from_native(a + b)
    end

    @doc """
    Subtracts second duration from first.

    Returns zero duration if result would be negative.
    """
    @spec subtract(t(), t()) :: t()
    def subtract(%__MODULE__{native: a}, %__MODULE__{native: b}) do
      from_native(max(0, a - b))
    end

    @doc """
    Compares two durations.

    Returns `:lt`, `:eq`, or `:gt`.
    """
    @spec compare(t(), t()) :: :lt | :eq | :gt
    def compare(%__MODULE__{native: a}, %__MODULE__{native: b}) do
      cond do
        a < b -> :lt
        a > b -> :gt
        true -> :eq
      end
    end

    @doc """
    Returns the zero duration.
    """
    @spec zero() :: t()
    def zero, do: from_native(0)
  end

  @type duration :: Duration.t()

  @type measure_result(a) :: {a, duration()}

  @type safe_result(a) ::
          {:ok, a, duration()}
          | {:error, :error | :exit | :throw, term(), list(), duration()}

  @type stats :: %{
          count: pos_integer(),
          total: duration(),
          mean: duration(),
          min: duration(),
          max: duration(),
          p50: duration(),
          p90: duration(),
          p95: duration(),
          p99: duration(),
          stddev_ms: float()
        }

  # ============================================
  # Core Measurement Functions
  # ============================================

  @doc """
  Measures execution time of a function.

  Returns `{result, duration}` where duration contains multiple time units.

  ## Examples

      {result, duration} = Timing.measure(fn -> fetch_user(id) end)

      Logger.info("Fetched user in \#{duration.ms}ms")
      :telemetry.execute([:app, :user, :fetch], %{duration: duration.native}, %{})

  ## With Pattern Matching

      {{:ok, user}, duration} = Timing.measure(fn -> Repo.fetch(User, id) end)
  """
  @spec measure((-> result)) :: measure_result(result) when result: term()
  def measure(fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    duration = Duration.from_native(System.monotonic_time() - start)
    {result, duration}
  end

  @doc """
  Simplified measurement returning just milliseconds.

  Use when you only need milliseconds and don't want the full Duration struct.

  ## Examples

      {result, ms} = Timing.measure!(fn -> operation() end)
      Logger.info("Completed in \#{ms}ms")
  """
  @spec measure!((-> result)) :: {result, non_neg_integer()} when result: term()
  def measure!(fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    ms = System.convert_time_unit(System.monotonic_time() - start, :native, :millisecond)
    {result, ms}
  end

  @doc """
  Measures execution with exception capture.

  Always returns the duration, even when the function raises or throws.

  ## Returns

  - `{:ok, result, duration}` - Function completed successfully
  - `{:error, kind, reason, stacktrace, duration}` - Function raised/threw/exited

  ## Examples

      case Timing.measure_safe(fn -> risky_operation() end) do
        {:ok, result, duration} ->
          Logger.info("Success in \#{duration.ms}ms")
          {:ok, result}

        {:error, :error, exception, stacktrace, duration} ->
          Logger.error("Failed after \#{duration.ms}ms: \#{Exception.message(exception)}")
          {:error, exception}

        {:error, :exit, reason, _stacktrace, duration} ->
          Logger.error("Process exited after \#{duration.ms}ms")
          {:error, {:exit, reason}}

        {:error, :throw, value, _stacktrace, duration} ->
          Logger.warning("Threw value after \#{duration.ms}ms")
          {:error, {:throw, value}}
      end

  ## Re-raising After Measurement

      case Timing.measure_safe(fn -> operation() end) do
        {:ok, result, _duration} ->
          result
        {:error, kind, reason, stacktrace, _duration} ->
          :erlang.raise(kind, reason, stacktrace)
      end
  """
  @spec measure_safe((-> result)) :: safe_result(result) when result: term()
  def measure_safe(fun) when is_function(fun, 0) do
    start = System.monotonic_time()

    try do
      result = fun.()
      {:ok, result, duration_since(start)}
    catch
      kind, reason ->
        {:error, kind, reason, __STACKTRACE__, duration_since(start)}
    end
  end

  @doc """
  Executes a function and calls a callback with the duration.

  Useful for inline timing without pattern matching.

  ## Examples

      # Log duration without capturing it
      result = Timing.timed(fn -> fetch_user(id) end, fn duration ->
        Logger.info("Fetch took \#{duration.ms}ms")
      end)

      # Emit telemetry
      result = Timing.timed(fn -> process(data) end, fn duration ->
        :telemetry.execute([:app, :process], %{duration: duration.native}, %{})
      end)
  """
  @spec timed((-> result), (duration() -> any())) :: result when result: term()
  def timed(fun, callback) when is_function(fun, 0) and is_function(callback, 1) do
    {result, duration} = measure(fun)
    callback.(duration)
    result
  end

  @doc """
  Executes a function and conditionally calls a callback if duration exceeds threshold.

  ## Examples

      # Only log if slow
      result = Timing.timed_if_slow(fn -> query() end, 100, fn duration ->
        Logger.warning("Slow query: \#{duration.ms}ms")
      end)
  """
  @spec timed_if_slow((-> result), non_neg_integer() | duration(), (duration() -> any())) ::
          result
        when result: term()
  def timed_if_slow(fun, threshold_ms, callback)
      when is_function(fun, 0) and is_function(callback, 1) do
    {result, duration} = measure(fun)

    if slow?(duration, threshold_ms) do
      callback.(duration)
    end

    result
  end

  # ============================================
  # Duration Utilities
  # ============================================

  @doc """
  Returns the duration since a start time.

  Use with `System.monotonic_time()` for manual timing control.

  ## Examples

      start = System.monotonic_time()
      # ... do work ...
      duration = Timing.duration_since(start)
  """
  @spec duration_since(integer()) :: duration()
  def duration_since(start) when is_integer(start) do
    Duration.from_native(System.monotonic_time() - start)
  end

  @doc """
  Checks if a duration exceeds a threshold.

  Threshold can be:
  - Integer (milliseconds)
  - Duration struct

  ## Examples

      if Timing.slow?(duration, 100) do
        Logger.warning("Operation exceeded 100ms threshold")
      end

      threshold = Duration.from_ms(500)
      Timing.slow?(duration, threshold)
  """
  @spec slow?(duration(), non_neg_integer() | duration()) :: boolean()
  def slow?(%Duration{ms: ms}, threshold_ms) when is_integer(threshold_ms) do
    ms > threshold_ms
  end

  def slow?(%Duration{} = duration, %Duration{} = threshold) do
    Duration.compare(duration, threshold) == :gt
  end

  @doc """
  Checks if a duration is within a threshold (not slow).

  ## Examples

      if Timing.within?(duration, 100) do
        Logger.debug("Operation completed within SLA")
      end
  """
  @spec within?(duration(), non_neg_integer() | duration()) :: boolean()
  def within?(duration, threshold), do: not slow?(duration, threshold)

  @doc """
  Formats a duration as a human-readable string.

  Automatically chooses the most appropriate unit.

  ## Examples

      Timing.format(duration)
      #=> "150ms"
      #=> "1.5s"
      #=> "2m 30s"
      #=> "45μs"

  ## Options

  - `:precision` - Decimal places for seconds/minutes (default: 1)
  - `:unit` - Force specific unit: `:ns`, `:us`, `:ms`, `:seconds`, `:auto` (default: `:auto`)
  """
  @spec format(duration(), keyword()) :: String.t()
  def format(%Duration{} = duration, opts \\ []) do
    precision = Keyword.get(opts, :precision, 1)
    unit = Keyword.get(opts, :unit, :auto)

    case unit do
      :ns -> "#{duration.ns}ns"
      :us -> "#{duration.us}μs"
      :ms -> "#{duration.ms}ms"
      :seconds -> "#{Float.round(duration.seconds, precision)}s"
      :auto -> format_auto(duration, precision)
    end
  end

  defp format_auto(%Duration{} = d, precision) do
    cond do
      d.seconds >= 60 ->
        minutes = floor(d.seconds / 60)
        seconds = d.seconds - minutes * 60
        "#{minutes}m #{round(seconds)}s"

      d.seconds >= 1 ->
        "#{Float.round(d.seconds, precision)}s"

      d.ms >= 1 ->
        "#{d.ms}ms"

      d.us >= 1 ->
        "#{d.us}μs"

      true ->
        "#{d.ns}ns"
    end
  end

  # ============================================
  # Benchmarking
  # ============================================

  @doc """
  Runs a function multiple times and returns timing statistics.

  ## Options

  - `:iterations` - Number of times to run (default: 100)
  - `:warmup` - Warmup iterations before measuring (default: 10)

  ## Returns

  A map containing:
  - `:count` - Number of iterations
  - `:total` - Total duration
  - `:mean` - Mean duration
  - `:min` - Minimum duration
  - `:max` - Maximum duration
  - `:p50` - 50th percentile (median)
  - `:p90` - 90th percentile
  - `:p95` - 95th percentile
  - `:p99` - 99th percentile
  - `:stddev_ms` - Standard deviation in milliseconds

  ## Examples

      stats = Timing.benchmark(fn -> Repo.all(User) end, iterations: 1000)

      IO.puts("Mean: \#{stats.mean.ms}ms")
      IO.puts("P99: \#{stats.p99.ms}ms")
      IO.puts("Min: \#{stats.min.ms}ms, Max: \#{stats.max.ms}ms")
  """
  @spec benchmark((-> any()), keyword()) :: stats()
  def benchmark(fun, opts \\ []) when is_function(fun, 0) do
    iterations = Keyword.get(opts, :iterations, 100)
    warmup = Keyword.get(opts, :warmup, 10)

    # Warmup runs (not measured)
    for _ <- 1..warmup, do: fun.()

    # Measured runs
    durations =
      for _ <- 1..iterations do
        {_result, duration} = measure(fun)
        duration
      end

    calculate_stats(durations)
  end

  @doc """
  Calculates statistics from a list of durations.

  Useful when you've collected durations from multiple operations
  and want aggregate statistics.

  ## Examples

      durations = Enum.map(requests, fn req ->
        {_result, duration} = Timing.measure(fn -> process(req) end)
        duration
      end)

      stats = Timing.stats(durations)
  """
  @spec stats([duration()]) :: stats()
  def stats(durations) when is_list(durations) and length(durations) > 0 do
    calculate_stats(durations)
  end

  defp calculate_stats(durations) do
    count = length(durations)
    sorted = Enum.sort_by(durations, & &1.native)

    natives = Enum.map(durations, & &1.native)
    total_native = Enum.sum(natives)
    mean_native = div(total_native, count)

    # Standard deviation
    variance =
      natives
      |> Enum.map(fn n -> :math.pow(n - mean_native, 2) end)
      |> Enum.sum()
      |> Kernel./(count)

    stddev_native = :math.sqrt(variance)
    stddev_ms = System.convert_time_unit(round(stddev_native), :native, :millisecond)

    %{
      count: count,
      total: Duration.from_native(total_native),
      mean: Duration.from_native(mean_native),
      min: List.first(sorted),
      max: List.last(sorted),
      p50: percentile(sorted, 0.50),
      p90: percentile(sorted, 0.90),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99),
      stddev_ms: Float.round(stddev_ms / 1.0, 2)
    }
  end

  defp percentile(sorted_list, p) when p >= 0 and p <= 1 do
    count = length(sorted_list)
    index = round(p * (count - 1))
    Enum.at(sorted_list, index)
  end

  # ============================================
  # Comparison Functions
  # ============================================

  @doc """
  Returns the minimum of two durations.
  """
  @spec min(duration(), duration()) :: duration()
  def min(%Duration{} = a, %Duration{} = b) do
    case Duration.compare(a, b) do
      :lt -> a
      _ -> b
    end
  end

  @doc """
  Returns the maximum of two durations.
  """
  @spec max(duration(), duration()) :: duration()
  def max(%Duration{} = a, %Duration{} = b) do
    case Duration.compare(a, b) do
      :gt -> a
      _ -> b
    end
  end

  @doc """
  Sums a list of durations.

  ## Examples

      total = Timing.sum(durations)
  """
  @spec sum([duration()]) :: duration()
  def sum([]), do: Duration.zero()

  def sum(durations) when is_list(durations) do
    total = durations |> Enum.map(& &1.native) |> Enum.sum()
    Duration.from_native(total)
  end

  @doc """
  Calculates the average of a list of durations.

  ## Examples

      avg = Timing.average(durations)
  """
  @spec average([duration()]) :: duration()
  def average([]), do: Duration.zero()

  def average(durations) when is_list(durations) do
    total = durations |> Enum.map(& &1.native) |> Enum.sum()
    Duration.from_native(div(total, length(durations)))
  end

  # ============================================
  # Guards and Predicates
  # ============================================

  @doc """
  Checks if a value is a Duration struct.

  ## Examples

      Timing.duration?(some_value)  #=> true/false
  """
  @spec duration?(term()) :: boolean()
  def duration?(%Duration{}), do: true
  def duration?(_), do: false

  @doc """
  Returns true if duration is zero.
  """
  @spec zero?(duration()) :: boolean()
  def zero?(%Duration{native: 0}), do: true
  def zero?(%Duration{}), do: false

  @doc """
  Returns true if duration is positive (non-zero).
  """
  @spec positive?(duration()) :: boolean()
  def positive?(%Duration{native: n}) when n > 0, do: true
  def positive?(%Duration{}), do: false

  # ============================================
  # Conversion Helpers
  # ============================================

  @doc """
  Creates a duration from a time tuple like `{5, :seconds}`.

  Supports the same format used by `:timer` module.

  ## Examples

      Timing.duration({100, :milliseconds})
      Timing.duration({5, :seconds})
      Timing.duration({2, :minutes})
      Timing.duration({1, :hours})
  """
  @spec duration({number(), :nanoseconds | :microseconds | :milliseconds | :seconds | :minutes | :hours}) ::
          duration()
  def duration({value, :nanoseconds}) when is_number(value), do: Duration.from_native(round(value))
  def duration({value, :microseconds}) when is_number(value), do: Duration.from_us(round(value))
  def duration({value, :milliseconds}) when is_number(value), do: Duration.from_ms(round(value))
  def duration({value, :seconds}) when is_number(value), do: Duration.from_seconds(value)
  def duration({value, :minutes}) when is_number(value), do: Duration.from_seconds(value * 60)
  def duration({value, :hours}) when is_number(value), do: Duration.from_seconds(value * 3600)

  @doc """
  Converts a duration to a map (useful for JSON encoding).

  ## Examples

      Timing.to_map(duration)
      #=> %{native: 123456, ns: 123456000, us: 123456, ms: 123, seconds: 0.123}
  """
  @spec to_map(duration()) :: map()
  def to_map(%Duration{} = d) do
    Map.from_struct(d)
  end
end
