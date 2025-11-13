defmodule Events.Decorators.Performance do
  @moduledoc """
  Performance measurement and benchmarking decorators.

  Provides tools for measuring execution time, benchmarking,
  and performance analysis.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate benchmark(runs: 1000, warmup: 100)
        def algorithm(data) do
          # Benchmarks with statistics
        end

        @decorate measure(unit: :millisecond)
        def timed_operation do
          # Measures execution time
        end
      end
  """

  @doc """
  Comprehensive benchmarking with statistics.

  Runs function multiple times and reports statistics.

  ## Options

  - `:runs` - Number of benchmark runs (default: 100)
  - `:warmup` - Number of warmup runs (default: 10)
  - `:unit` - Time unit (:nanosecond, :microsecond, :millisecond, :second)
  - `:percentiles` - Percentiles to calculate (default: [50, 95, 99])
  - `:output` - Output destination (:log, :return, :telemetry)
  """
  defmacro benchmark(opts \\ []) do
    quote do
      use Decorator.Define, benchmark: 1
      unquote(opts)
    end
  end

  @doc """
  Simple execution time measurement.

  Measures and logs execution time.

  ## Options

  - `:unit` - Time unit (default: :microsecond)
  - `:label` - Custom label for measurement
  - `:log_level` - Log level for output (default: :info)
  """
  defmacro measure(opts \\ []) do
    quote do
      use Decorator.Define, measure: 1
      unquote(opts)
    end
  end

  @doc """
  Profile function execution.

  Uses Erlang profiling tools.

  ## Options

  - `:profiler` - Profiler to use (:eprof, :fprof, :cprof)
  - `:output` - Output file for profile results
  - `:analysis` - Analysis options
  """
  defmacro profile(opts \\ []) do
    quote do
      use Decorator.Define, profile: 1
      unquote(opts)
    end
  end

  @doc """
  Rate limiting decorator.

  Limits function execution rate.

  ## Options

  - `:rate` - Maximum calls per period (required)
  - `:period` - Time period in milliseconds (default: 1000)
  - `:scope` - Rate limit scope (:global, :process, :user)
  - `:on_limit` - Action when rate limited (:wait, :drop, :error)
  """
  defmacro rate_limit(opts) do
    quote do
      use Decorator.Define, rate_limit: 1
      unquote(opts)
    end
  end

  @doc """
  Timeout decorator.

  Enforces execution timeout.

  ## Options

  - `:timeout` - Timeout in milliseconds (required)
  - `:on_timeout` - Action on timeout (:error, :default_value)
  """
  defmacro timeout(timeout_ms, opts \\ []) do
    quote do
      use Decorator.Define, timeout: 2
      unquote(timeout_ms)
      unquote(opts)
    end
  end
end
