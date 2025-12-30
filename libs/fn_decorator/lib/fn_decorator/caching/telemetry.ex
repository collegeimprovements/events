defmodule FnDecorator.Caching.Telemetry do
  @moduledoc """
  Telemetry events for cache operations.

  All events are prefixed with `[:fn_decorator, :cache]`.

  ## Events

  ### Cache Operations

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:fn_decorator, :cache, :get]` | `%{duration: ns}` | `%{key: term, result: :hit \| :miss \| :stale}` |
  | `[:fn_decorator, :cache, :put]` | `%{duration: ns}` | `%{key: term, ttl: ms}` |
  | `[:fn_decorator, :cache, :delete]` | `%{duration: ns}` | `%{key: term}` |

  ### Bulk Operations

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:fn_decorator, :cache, :get_all]` | `%{duration: ns, count: n}` | `%{keys: [term]}` |
  | `[:fn_decorator, :cache, :put_all]` | `%{duration: ns, count: n}` | `%{ttl: ms}` |
  | `[:fn_decorator, :cache, :delete_all]` | `%{duration: ns, count: n}` | `%{pattern: term}` |

  ### Decorator Events

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:fn_decorator, :cache, :hit]` | `%{duration: ns}` | `%{key: term, status: :fresh \| :stale}` |
  | `[:fn_decorator, :cache, :miss]` | `%{duration: ns}` | `%{key: term}` |
  | `[:fn_decorator, :cache, :fetch]` | `%{duration: ns}` | `%{key: term, success: bool}` |
  | `[:fn_decorator, :cache, :refresh]` | `%{duration: ns}` | `%{key: term, success: bool}` |
  | `[:fn_decorator, :cache, :lock]` | `%{duration: ns}` | `%{key: term, result: :acquired \| :timeout}` |

  ## Usage

      # Attach a handler
      :telemetry.attach(
        "my-cache-logger",
        [:fn_decorator, :cache, :get],
        &MyApp.CacheLogger.handle_event/4,
        nil
      )

      # Or use attach_many
      events = [
        [:fn_decorator, :cache, :hit],
        [:fn_decorator, :cache, :miss],
        [:fn_decorator, :cache, :fetch]
      ]

      :telemetry.attach_many("my-cache-handler", events, &handler/4, nil)
  """

  @prefix [:fn_decorator, :cache]

  # ============================================
  # Event Emission
  # ============================================

  @doc """
  Emit a cache get event.
  """
  def emit_get(key, result, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:get],
      %{duration: duration_ns},
      %{key: key, result: result}
    )
  end

  @doc """
  Emit a cache put event.
  """
  def emit_put(key, ttl, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:put],
      %{duration: duration_ns},
      %{key: key, ttl: ttl}
    )
  end

  @doc """
  Emit a cache delete event.
  """
  def emit_delete(key, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:delete],
      %{duration: duration_ns},
      %{key: key}
    )
  end

  @doc """
  Emit a cache hit event (from decorator).
  """
  def emit_hit(key, status, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:hit],
      %{duration: duration_ns},
      %{key: key, status: status}
    )
  end

  @doc """
  Emit a cache miss event (from decorator).
  """
  def emit_miss(key, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:miss],
      %{duration: duration_ns},
      %{key: key}
    )
  end

  @doc """
  Emit a fetch event (actual function execution).
  """
  def emit_fetch(key, success, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:fetch],
      %{duration: duration_ns},
      %{key: key, success: success}
    )
  end

  @doc """
  Emit a background refresh event.
  """
  def emit_refresh(key, success, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:refresh],
      %{duration: duration_ns},
      %{key: key, success: success}
    )
  end

  @doc """
  Emit a lock acquisition event.
  """
  def emit_lock(key, result, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:lock],
      %{duration: duration_ns},
      %{key: key, result: result}
    )
  end

  @doc """
  Emit a delete_all event.
  """
  def emit_delete_all(pattern, count, duration_ns) do
    :telemetry.execute(
      @prefix ++ [:delete_all],
      %{duration: duration_ns, count: count},
      %{pattern: pattern}
    )
  end

  # ============================================
  # Span Helpers
  # ============================================

  @doc """
  Execute a function and emit timing telemetry.

  ## Examples

      Telemetry.span(:get, %{key: key}, fn ->
        do_get(key)
      end)
  """
  def span(event, metadata, fun) when is_atom(event) and is_function(fun, 0) do
    start = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start

      :telemetry.execute(
        @prefix ++ [event],
        %{duration: duration},
        metadata
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start

        :telemetry.execute(
          @prefix ++ [event, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  # ============================================
  # Stats Tracking (optional ETS-based)
  # ============================================

  @doc """
  Initialize stats tracking for a cache.

  Creates an ETS table to track hits/misses.
  """
  def init_stats(cache_name) do
    table = stats_table_name(cache_name)

    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:set, :public, :named_table])
        :ets.insert(table, [
          {:hits, 0},
          {:misses, 0},
          {:started_at, System.monotonic_time(:millisecond)}
        ])
        :ok

      _ref ->
        :ok
    end
  end

  @doc """
  Increment hit counter.
  """
  def record_hit(cache_name) do
    table = stats_table_name(cache_name)
    safe_update_counter(table, :hits)
  end

  @doc """
  Increment miss counter.
  """
  def record_miss(cache_name) do
    table = stats_table_name(cache_name)
    safe_update_counter(table, :misses)
  end

  @doc """
  Get current stats for a cache.
  """
  def get_stats(cache_name) do
    table = stats_table_name(cache_name)

    case :ets.whereis(table) do
      :undefined ->
        %{hits: 0, misses: 0, hit_rate: 0.0, uptime_ms: 0}

      _ref ->
        hits = get_counter(table, :hits)
        misses = get_counter(table, :misses)
        started_at = get_counter(table, :started_at)
        total = hits + misses
        hit_rate = if total > 0, do: hits / total, else: 0.0
        uptime_ms = System.monotonic_time(:millisecond) - started_at

        %{
          hits: hits,
          misses: misses,
          hit_rate: Float.round(hit_rate, 4),
          uptime_ms: uptime_ms
        }
    end
  end

  defp stats_table_name(cache_name) do
    :"#{cache_name}_stats"
  end

  defp safe_update_counter(table, key) do
    case :ets.whereis(table) do
      :undefined -> :ok
      _ref -> :ets.update_counter(table, key, 1, {key, 0})
    end
  end

  defp get_counter(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end
end
