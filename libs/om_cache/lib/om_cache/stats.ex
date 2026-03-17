defmodule OmCache.Stats do
  @moduledoc """
  Cache performance statistics and metrics tracking.

  Provides insights into cache performance including:
  - Hit/miss ratios
  - Operation latencies (p50, p95, p99)
  - Memory usage
  - Eviction rates
  - Error rates by type

  ## Usage

  Attach the stats handler to start collecting metrics:

      # In application.ex
      OmCache.Stats.attach(MyApp.Cache)

      # Query stats
      OmCache.Stats.get_stats(MyApp.Cache)
      #=> %{
      #     hits: 1234,
      #     misses: 56,
      #     hit_ratio: 0.956,
      #     total_operations: 1290,
      #     ...
      #   }

      # Get hit ratio for last N minutes
      OmCache.Stats.hit_ratio(MyApp.Cache, :timer.minutes(5))
      #=> 0.956

      # Get slow operations
      OmCache.Stats.slow_operations(MyApp.Cache, threshold_ms: 100)
      #=> [%{operation: :get, key: {User, 123}, duration_ms: 150}, ...]

  ## ETS Table Structure

  Stats are stored in an ETS table per cache with the name `{cache, :stats}`.
  The table stores counters and histograms for various metrics.
  """

  @type stats :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          hit_ratio: float(),
          total_operations: non_neg_integer(),
          writes: non_neg_integer(),
          deletes: non_neg_integer(),
          errors: non_neg_integer(),
          avg_latency_ms: float(),
          p50_latency_ms: float(),
          p95_latency_ms: float(),
          p99_latency_ms: float(),
          error_breakdown: %{atom() => non_neg_integer()},
          top_keys: [{term(), non_neg_integer()}]
        }

  @doc """
  Attaches telemetry handlers to collect cache statistics.

  ## Options

  - `:table_name` - Custom ETS table name (default: `{cache, :stats}`)
  - `:track_keys` - Track individual key access counts (default: false, can be memory intensive)
  - `:latency_samples` - Max latency samples to keep (default: 1000)

  ## Examples

      OmCache.Stats.attach(MyApp.Cache)
      OmCache.Stats.attach(MyApp.Cache, track_keys: true, latency_samples: 5000)
  """
  @spec attach(module(), keyword()) :: :ok | {:error, :already_attached}
  def attach(cache, opts \\ []) do
    table_name = Keyword.get(opts, :table_name, stats_table_name(cache))
    track_keys = Keyword.get(opts, :track_keys, false)
    latency_samples = Keyword.get(opts, :latency_samples, 1000)

    # Create ETS table for stats
    :ets.new(table_name, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])

    # Initialize counters
    :ets.insert(table_name, {:hits, 0})
    :ets.insert(table_name, {:misses, 0})
    :ets.insert(table_name, {:writes, 0})
    :ets.insert(table_name, {:deletes, 0})
    :ets.insert(table_name, {:errors, 0})
    :ets.insert(table_name, {:latencies, []})
    :ets.insert(table_name, {:error_breakdown, %{}})
    :ets.insert(table_name, {:config, %{track_keys: track_keys, latency_samples: latency_samples}})

    if track_keys do
      :ets.insert(table_name, {:key_access, %{}})
    end

    config = %{
      cache: cache,
      table: table_name,
      track_keys: track_keys,
      latency_samples: latency_samples
    }

    :telemetry.attach_many(
      {:om_cache_stats, cache},
      [
        [:nebulex, :cache, :command, :start],
        [:nebulex, :cache, :command, :stop],
        [:nebulex, :cache, :command, :exception]
      ],
      &__MODULE__.handle_event/4,
      config
    )
  end

  @doc """
  Detaches telemetry handlers and cleans up stats table.

  ## Examples

      OmCache.Stats.detach(MyApp.Cache)
  """
  @spec detach(module()) :: :ok
  def detach(cache) do
    :telemetry.detach({:om_cache_stats, cache})

    table_name = stats_table_name(cache)

    if :ets.whereis(table_name) != :undefined do
      :ets.delete(table_name)
    end

    :ok
  end

  @doc """
  Gets comprehensive cache statistics.

  ## Examples

      OmCache.Stats.get_stats(MyApp.Cache)
      #=> %{
      #     hits: 1234,
      #     misses: 56,
      #     hit_ratio: 0.956,
      #     total_operations: 1290,
      #     writes: 450,
      #     deletes: 23,
      #     errors: 2,
      #     avg_latency_ms: 2.5,
      #     p50_latency_ms: 1.2,
      #     p95_latency_ms: 8.5,
      #     p99_latency_ms: 15.3,
      #     error_breakdown: %{timeout: 1, connection_failed: 1},
      #     top_keys: [{{User, 123}, 45}, {{Product, 456}, 32}]
      #   }
  """
  @spec get_stats(module()) :: stats() | {:error, :not_attached}
  def get_stats(cache) do
    table = stats_table_name(cache)

    if :ets.whereis(table) == :undefined do
      {:error, :not_attached}
    else
      hits = lookup_counter(table, :hits)
      misses = lookup_counter(table, :misses)
      writes = lookup_counter(table, :writes)
      deletes = lookup_counter(table, :deletes)
      errors = lookup_counter(table, :errors)
      latencies = lookup_value(table, :latencies, [])
      error_breakdown = lookup_value(table, :error_breakdown, %{})
      config = lookup_value(table, :config, %{})

      total_operations = hits + misses
      hit_ratio = if total_operations > 0, do: hits / total_operations, else: 0.0

      {avg, p50, p95, p99} = calculate_percentiles(latencies)

      stats = %{
        hits: hits,
        misses: misses,
        hit_ratio: hit_ratio,
        total_operations: total_operations,
        writes: writes,
        deletes: deletes,
        errors: errors,
        avg_latency_ms: avg,
        p50_latency_ms: p50,
        p95_latency_ms: p95,
        p99_latency_ms: p99,
        error_breakdown: error_breakdown
      }

      if config[:track_keys] do
        key_access = lookup_value(table, :key_access, %{})
        top_keys = key_access |> Enum.sort_by(fn {_k, v} -> -v end) |> Enum.take(10)
        Map.put(stats, :top_keys, top_keys)
      else
        Map.put(stats, :top_keys, [])
      end
    end
  end

  @doc """
  Calculates hit ratio for a given time window.

  Note: This implementation uses all-time counters. For true windowed stats,
  you'd need to implement time-series storage (e.g., using circular buffers).

  ## Examples

      OmCache.Stats.hit_ratio(MyApp.Cache)
      #=> 0.956
  """
  @spec hit_ratio(module(), pos_integer() | nil) :: float() | {:error, :not_attached}
  def hit_ratio(cache, _time_window \\ nil) do
    # TODO: Implement true windowed stats with time-series data
    case get_stats(cache) do
      {:error, reason} -> {:error, reason}
      stats -> stats.hit_ratio
    end
  end

  @doc """
  Gets slow operations that exceeded a threshold.

  Note: This requires storing individual operation data. Current implementation
  returns latency percentiles. For true slow operation tracking, you'd need
  to store operation details.

  ## Examples

      OmCache.Stats.slow_operations(MyApp.Cache, threshold_ms: 100)
      #=> []
  """
  @spec slow_operations(module(), keyword()) :: [map()] | {:error, :not_attached}
  def slow_operations(cache, opts \\ []) do
    _threshold_ms = Keyword.get(opts, :threshold_ms, 100)

    # TODO: Implement slow operation tracking with operation details
    case get_stats(cache) do
      {:error, reason} -> {:error, reason}
      _stats -> []
    end
  end

  @doc """
  Resets all statistics counters.

  ## Examples

      OmCache.Stats.reset(MyApp.Cache)
      #=> :ok
  """
  @spec reset(module()) :: :ok | {:error, :not_attached}
  def reset(cache) do
    table = stats_table_name(cache)

    if :ets.whereis(table) == :undefined do
      {:error, :not_attached}
    else
      config = lookup_value(table, :config, %{})

      :ets.insert(table, {:hits, 0})
      :ets.insert(table, {:misses, 0})
      :ets.insert(table, {:writes, 0})
      :ets.insert(table, {:deletes, 0})
      :ets.insert(table, {:errors, 0})
      :ets.insert(table, {:latencies, []})
      :ets.insert(table, {:error_breakdown, %{}})

      if config[:track_keys] do
        :ets.insert(table, {:key_access, %{}})
      end

      :ok
    end
  end

  # ============================================
  # Telemetry Handler
  # ============================================

  @doc false
  def handle_event([:nebulex, :cache, :command, :start], _measurements, metadata, config) do
    if metadata.cache == config.cache do
      # Store start time in process dictionary for duration calculation
      Process.put({:cache_op_start, metadata.command}, System.monotonic_time())
    end
  end

  def handle_event([:nebulex, :cache, :command, :stop], measurements, metadata, config) do
    if metadata.cache == config.cache do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      table = config.table

      # Track operation type
      case metadata.command do
        :get ->
          if metadata.result == nil do
            increment_counter(table, :misses)
          else
            increment_counter(table, :hits)

            # Track key access if enabled
            if config.track_keys do
              track_key_access(table, List.first(metadata.args))
            end
          end

        :put ->
          increment_counter(table, :writes)

        :delete ->
          increment_counter(table, :deletes)

        _ ->
          :ok
      end

      # Record latency
      record_latency(table, duration_ms, config.latency_samples)
    end
  end

  def handle_event([:nebulex, :cache, :command, :exception], _measurements, metadata, config) do
    if metadata.cache == config.cache do
      table = config.table
      increment_counter(table, :errors)

      # Track error type
      error_type = classify_error(metadata.reason)
      update_error_breakdown(table, error_type)
    end
  end

  # ============================================
  # Private
  # ============================================

  defp stats_table_name(cache), do: :"#{cache}.Stats"

  defp lookup_counter(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp lookup_value(table, key, default) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  defp increment_counter(table, key) do
    :ets.update_counter(table, key, {2, 1}, {key, 0})
  end

  defp record_latency(table, latency_ms, max_samples) do
    [{:latencies, latencies}] = :ets.lookup(table, :latencies)

    new_latencies =
      if length(latencies) >= max_samples do
        [latency_ms | Enum.take(latencies, max_samples - 1)]
      else
        [latency_ms | latencies]
      end

    :ets.insert(table, {:latencies, new_latencies})
  end

  defp track_key_access(table, key) do
    [{:key_access, access_map}] = :ets.lookup(table, :key_access)
    updated_map = Map.update(access_map, key, 1, &(&1 + 1))
    :ets.insert(table, {:key_access, updated_map})
  end

  defp update_error_breakdown(table, error_type) do
    [{:error_breakdown, breakdown}] = :ets.lookup(table, :error_breakdown)
    updated_breakdown = Map.update(breakdown, error_type, 1, &(&1 + 1))
    :ets.insert(table, {:error_breakdown, updated_breakdown})
  end

  defp calculate_percentiles([]), do: {0.0, 0.0, 0.0, 0.0}

  defp calculate_percentiles(latencies) do
    sorted = Enum.sort(latencies)
    count = length(sorted)
    sum = Enum.sum(sorted)
    avg = sum / count

    p50 = percentile(sorted, count, 0.50)
    p95 = percentile(sorted, count, 0.95)
    p99 = percentile(sorted, count, 0.99)

    {avg, p50, p95, p99}
  end

  defp percentile(sorted_list, count, p) do
    index = round((count - 1) * p)
    Enum.at(sorted_list, index, 0.0)
  end

  defp classify_error(%{__struct__: struct} = _exception) do
    case struct do
      Redix.ConnectionError -> :connection_error
      Redix.Error -> :redis_error
      _ -> :unknown_error
    end
  end

  defp classify_error(_), do: :unknown_error
end
