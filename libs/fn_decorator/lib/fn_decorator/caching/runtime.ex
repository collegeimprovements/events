defmodule FnDecorator.Caching.Runtime do
  @moduledoc """
  Runtime execution engine for the cacheable decorator.

  This module is called by generated decorator code to perform cache operations.
  It handles the full cache lifecycle:

  1. Cache lookup with freshness checking
  2. Thunder herd prevention via distributed locking
  3. Stale-while-revalidate pattern
  4. Background refresh triggering
  5. Error handling and fallbacks

  ## Flow Diagram

      Request
        │
        ▼
      ┌─────────────────┐
      │  Cache Lookup   │
      └────────┬────────┘
               │
         ┌─────┴─────┐
         │           │
       Found      Not Found
         │           │
         ▼           ▼
      ┌──────┐   ┌──────────────────┐
      │Status│   │ Thunder Herd?    │
      └──┬───┘   └────────┬─────────┘
         │                │
      ┌──┴──┬─────┐    ┌──┴──┐
      │     │     │    │     │
     Fresh Stale Exp. Yes    No
      │     │     │    │     │
      │     │     │    ▼     ▼
      │     │     │  Lock   Fetch
      │     │     │    │     │
      │     ▼     │    ▼     │
      │  Refresh? │  Fetch   │
      │     │     │    │     │
      └──┬──┴─────┴────┴─────┘
         │
         ▼
       Return

  ## Telemetry Events

  All events are prefixed with `[:fn_decorator, :cache]`:

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `:hit` | `%{time: ...}` | `%{key: ..., status: :fresh/:stale}` |
  | `:miss` | `%{time: ...}` | `%{key: ...}` |
  | `:fetch` | `%{duration: ...}` | `%{key: ..., success: bool}` |
  | `:refresh` | `%{duration: ...}` | `%{key: ..., success: bool}` |
  | `:lock` | `%{wait_time: ...}` | `%{key: ..., result: :acquired/:timeout}` |
  """

  alias FnDecorator.Caching.{Entry, Lock}

  @type cache :: module()
  @type key :: term()
  @type fetch_fn :: (-> term())

  @type opts :: keyword()

  # Default configuration
  @default_thunder_herd [
    max_wait: 5_000,
    lock_ttl: 30_000,
    on_timeout: :serve_stale
  ]

  # ============================================
  # Main Entry Point
  # ============================================

  @doc """
  Execute a cacheable operation.

  Called by generated decorator code at runtime.

  ## Parameters

  - `cache` - Cache module implementing `get/1` and `put/3`
  - `key` - Cache key
  - `fetch_fn` - Zero-arity function to fetch value on cache miss
  - `opts` - Configuration options (grouped structure)
  """
  @spec execute(cache(), key(), fetch_fn(), opts()) :: term()
  def execute(cache, key, fetch_fn, opts) do
    start_time = System.monotonic_time()

    case lookup(cache, key) do
      nil ->
        emit(:miss, key, start_time)
        handle_miss(cache, key, fetch_fn, opts)

      %Entry{} = entry ->
        handle_hit(cache, key, entry, fetch_fn, opts, start_time)
    end
  end

  # ============================================
  # Cache Lookup
  # ============================================

  defp lookup(cache, key) do
    cache.get(key) |> Entry.from_cache()
  end

  # ============================================
  # Hit Handling
  # ============================================

  defp handle_hit(cache, key, entry, fetch_fn, opts, start_time) do
    case Entry.status(entry) do
      :fresh ->
        emit(:hit, key, start_time, %{status: :fresh})
        Entry.value(entry)

      :stale ->
        emit(:hit, key, start_time, %{status: :stale})
        maybe_refresh_async(cache, key, fetch_fn, opts)
        Entry.value(entry)

      :expired ->
        emit(:miss, key, start_time)
        handle_miss(cache, key, fetch_fn, opts)
    end
  end

  # ============================================
  # Miss Handling
  # ============================================

  defp handle_miss(cache, key, fetch_fn, opts) do
    thunder_herd = normalize_thunder_herd(opts[:prevent_thunder_herd])

    if thunder_herd do
      handle_miss_with_lock(cache, key, fetch_fn, opts, thunder_herd)
    else
      fetch_and_store(cache, key, fetch_fn, opts)
    end
  end

  defp handle_miss_with_lock(cache, key, fetch_fn, opts, thunder_herd) do
    lock_ttl = thunder_herd[:lock_ttl]

    case Lock.acquire(key, lock_ttl) do
      {:ok, token} ->
        try do
          fetch_and_store(cache, key, fetch_fn, opts)
        after
          Lock.release(key, token)
        end

      :busy ->
        wait_for_value(cache, key, fetch_fn, opts, thunder_herd)
    end
  end

  defp wait_for_value(cache, key, fetch_fn, opts, thunder_herd) do
    max_wait = thunder_herd[:max_wait]
    on_timeout = thunder_herd[:on_timeout]
    deadline = System.monotonic_time(:millisecond) + max_wait
    start_time = System.monotonic_time()

    result = do_wait(cache, key, deadline)

    case result do
      {:ok, value} ->
        emit(:lock, key, start_time, %{result: :acquired})
        value

      :timeout ->
        emit(:lock, key, start_time, %{result: :timeout})
        handle_timeout(cache, key, fetch_fn, opts, on_timeout)
    end
  end

  defp do_wait(cache, key, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      :timeout
    else
      case lookup(cache, key) do
        nil ->
          Process.sleep(min(50, deadline - now))
          do_wait(cache, key, deadline)

        %Entry{} = entry ->
          case Entry.status(entry) do
            status when status in [:fresh, :stale] ->
              {:ok, Entry.value(entry)}

            :expired ->
              Process.sleep(min(50, deadline - now))
              do_wait(cache, key, deadline)
          end
      end
    end
  end

  defp handle_timeout(cache, key, fetch_fn, opts, on_timeout) do
    case on_timeout do
      :serve_stale ->
        case lookup(cache, key) do
          %Entry{} = entry -> Entry.value(entry)
          nil -> fetch_and_store(cache, key, fetch_fn, opts)
        end

      :error ->
        {:error, :cache_timeout}

      :proceed ->
        fetch_and_store(cache, key, fetch_fn, opts)

      {:call, fun} when is_function(fun, 0) ->
        fun.()

      {:value, value} ->
        value
    end
  end

  # ============================================
  # Fetch and Store
  # ============================================

  defp fetch_and_store(cache, key, fetch_fn, opts) do
    start_time = System.monotonic_time()

    try do
      value = fetch_fn.()
      emit(:fetch, key, start_time, %{success: true})

      store = opts[:store] || []
      only_if = store[:only_if]

      if should_cache?(value, only_if) do
        store_value(cache, key, value, opts)
      end

      value
    rescue
      error ->
        emit(:fetch, key, start_time, %{success: false, error: error})
        handle_fetch_error(cache, key, error, opts)
    end
  end

  defp should_cache?(_value, nil), do: true
  defp should_cache?(value, only_if) when is_function(only_if, 1), do: only_if.(value)

  defp store_value(cache, key, value, opts) do
    store = opts[:store] || []
    serve_stale = opts[:serve_stale]

    ttl = store[:ttl]
    stale_ttl = if serve_stale, do: serve_stale[:ttl], else: nil
    tags = resolve_tags(store[:tags], value)

    entry = Entry.new(value, ttl, stale_ttl)
    cache_ttl = stale_ttl || ttl

    put_opts =
      [ttl: cache_ttl]
      |> maybe_add_tags(tags)

    cache.put(key, Entry.to_tuple(entry), put_opts)
  end

  defp resolve_tags(nil, _value), do: nil
  defp resolve_tags(tags, _value) when is_list(tags), do: tags
  defp resolve_tags(tags_fn, value) when is_function(tags_fn, 1), do: tags_fn.(value)

  defp maybe_add_tags(opts, nil), do: opts
  defp maybe_add_tags(opts, tags), do: Keyword.put(opts, :tags, tags)

  # ============================================
  # Error Handling
  # ============================================

  defp handle_fetch_error(cache, key, error, opts) do
    fallback = opts[:fallback] || []
    on_error = fallback[:on_error] || :raise

    case on_error do
      :raise ->
        raise error

      :serve_stale ->
        case lookup(cache, key) do
          %Entry{} = entry -> Entry.value(entry)
          nil -> raise error
        end

      {:call, fun} when is_function(fun, 1) ->
        fun.(error)

      {:value, value} ->
        value
    end
  end

  # ============================================
  # Async Refresh
  # ============================================

  defp maybe_refresh_async(cache, key, fetch_fn, opts) do
    refresh = opts[:refresh]
    triggers = if refresh, do: List.wrap(refresh[:on]), else: []

    if :stale_access in triggers do
      refresh_async(cache, key, fetch_fn, opts)
    end
  end

  defp refresh_async(cache, key, fetch_fn, opts) do
    # Use a separate lock for refresh to not block readers
    refresh_key = {:refresh, key}

    Task.start(fn ->
      start_time = System.monotonic_time()

      case Lock.acquire(refresh_key, 5_000) do
        {:ok, token} ->
          try do
            value = fetch_fn.()

            store = opts[:store] || []
            only_if = store[:only_if]

            if should_cache?(value, only_if) do
              store_value(cache, key, value, opts)
            end

            emit(:refresh, key, start_time, %{success: true})
          rescue
            error ->
              emit(:refresh, key, start_time, %{success: false, error: error})
          after
            Lock.release(refresh_key, token)
          end

        :busy ->
          # Another process is already refreshing
          :ok
      end
    end)
  end

  # ============================================
  # Thunder Herd Normalization
  # ============================================

  defp normalize_thunder_herd(nil), do: nil
  defp normalize_thunder_herd(false), do: nil

  defp normalize_thunder_herd(true) do
    @default_thunder_herd
  end

  defp normalize_thunder_herd(opts) when is_list(opts) do
    Keyword.merge(@default_thunder_herd, opts)
  end

  # ============================================
  # Telemetry
  # ============================================

  defp emit(event, key, start_time, metadata \\ %{}) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:fn_decorator, :cache, event],
      %{duration: duration, time: System.system_time()},
      Map.put(metadata, :key, key)
    )
  rescue
    _ -> :ok
  end
end
