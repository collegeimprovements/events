defmodule OmCache.Stats do
  @moduledoc """
  Cache performance statistics and metrics tracking.

  Provides insights into cache performance including:
  - Hit/miss ratios
  - Operation latencies (p50, p95, p99)
  - Error rates by type
  - Per-key access tracking (optional)

  All counters use atomic ETS operations, safe for concurrent access.

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

      # Get hit ratio
      OmCache.Stats.hit_ratio(MyApp.Cache)
      #=> 0.956
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

  - `:table_name` - Custom ETS table name (default: derived from cache module)
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

    # Create ETS table for stats — all writes use atomic update_counter or single-key insert
    :ets.new(table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Initialize counters (all use :ets.update_counter for atomic increments)
    :ets.insert(table_name, {:hits, 0})
    :ets.insert(table_name, {:misses, 0})
    :ets.insert(table_name, {:writes, 0})
    :ets.insert(table_name, {:deletes, 0})
    :ets.insert(table_name, {:errors, 0})

    # Circular buffer for latencies: atomic index + per-slot storage
    :ets.insert(table_name, {:latency_write_index, -1})
    :ets.insert(table_name, {:latency_count, 0})

    # Config
    :ets.insert(table_name, {:config, %{track_keys: track_keys, latency_samples: latency_samples}})

    config = %{
      cache: cache,
      table: table_name,
      track_keys: track_keys,
      latency_samples: latency_samples
    }

    :telemetry.attach_many(
      {:om_cache_stats, cache},
      [
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
      config = lookup_value(table, :config, %{})

      latencies = read_latencies(table, config[:latency_samples] || 1000)
      error_breakdown = read_error_breakdown(table)

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
        top_keys = read_top_keys(table, 10)
        Map.put(stats, :top_keys, top_keys)
      else
        Map.put(stats, :top_keys, [])
      end
    end
  end

  @doc """
  Returns the all-time hit ratio.

  ## Examples

      OmCache.Stats.hit_ratio(MyApp.Cache)
      #=> 0.956
  """
  @spec hit_ratio(module()) :: float() | {:error, :not_attached}
  def hit_ratio(cache) do
    case get_stats(cache) do
      {:error, reason} -> {:error, reason}
      stats -> stats.hit_ratio
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
      :ets.insert(table, {:latency_write_index, -1})
      :ets.insert(table, {:latency_count, 0})

      # Clear latency slots
      max = config[:latency_samples] || 1000

      for i <- 0..(max - 1) do
        :ets.delete(table, {:latency, i})
      end

      # Clear per-key access counters
      if config[:track_keys] do
        :ets.match_delete(table, {{:key_access, :_}, :_})
      end

      # Clear per-type error counters
      :ets.match_delete(table, {{:error_type, :_}, :_})

      :ok
    end
  end

  # ============================================
  # Telemetry Handler
  # ============================================

  @doc false
  def handle_event([:nebulex, :cache, :command, :stop], measurements, metadata, config) do
    if metadata.cache == config.cache do
      duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
      table = config.table

      case metadata.command do
        :get ->
          case metadata.result do
            nil ->
              increment_counter(table, :misses)

            _value ->
              increment_counter(table, :hits)

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

      record_latency(table, duration_ms, config.latency_samples)
    end
  end

  def handle_event([:nebulex, :cache, :command, :exception], _measurements, metadata, config) do
    if metadata.cache == config.cache do
      table = config.table
      increment_counter(table, :errors)

      error_type = classify_error(metadata.reason)
      track_error_type(table, error_type)
    end
  end

  # ============================================
  # Private — all write operations are atomic
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

  # Atomic counter increment
  defp increment_counter(table, key) do
    :ets.update_counter(table, key, {2, 1}, {key, 0})
  end

  # Circular buffer: atomic index advance + single-key write per slot
  defp record_latency(table, latency_ms, max_samples) do
    # Atomically advance the write index, wrapping at max_samples
    index = :ets.update_counter(table, :latency_write_index, {2, 1, max_samples - 1, 0})
    # Write to this slot — single-key insert is atomic
    :ets.insert(table, {{:latency, index}, latency_ms})
    # Track total count, capped at max_samples to prevent overflow
    :ets.update_counter(table, :latency_count, {2, 1, max_samples, max_samples}, {:latency_count, 0})
  end

  # Read all filled latency slots
  defp read_latencies(table, max_samples) do
    count = min(lookup_counter(table, :latency_count), max_samples)

    if count <= 0 do
      []
    else
      for i <- 0..(count - 1),
          [{_, val}] <- [:ets.lookup(table, {:latency, i})],
          do: val
    end
  end

  # Per-key access counter — fully atomic via update_counter
  defp track_key_access(table, key) do
    :ets.update_counter(table, {:key_access, key}, {2, 1}, {{:key_access, key}, 0})
  end

  # Read top-N accessed keys
  defp read_top_keys(table, limit) do
    :ets.match(table, {{:key_access, :"$1"}, :"$2"})
    |> Enum.map(fn [key, count] -> {key, count} end)
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.take(limit)
  end

  # Per-error-type counter — fully atomic via update_counter
  defp track_error_type(table, error_type) do
    :ets.update_counter(table, {:error_type, error_type}, {2, 1}, {{:error_type, error_type}, 0})
  end

  # Read all error type counters
  defp read_error_breakdown(table) do
    :ets.match(table, {{:error_type, :"$1"}, :"$2"})
    |> Map.new(fn [type, count] -> {type, count} end)
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

  defp classify_error(%{__struct__: struct}) do
    struct_name = Atom.to_string(struct)

    cond do
      String.contains?(struct_name, "ConnectionError") -> :connection_error
      String.contains?(struct_name, "Redix.Error") -> :redis_error
      true -> :unknown_error
    end
  end

  defp classify_error(_), do: :unknown_error
end
