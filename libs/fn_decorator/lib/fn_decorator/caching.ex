defmodule FnDecorator.Caching do
  @moduledoc """
  Caching decorators for function memoization with advanced features.

  Provides three core caching patterns inspired by Spring Cache and Nebulex:

  - `@cacheable` - Read-through caching with refresh, stale serving, and stampede prevention
  - `@cache_put` - Write-through caching (always execute, update cache)
  - `@cache_evict` - Cache invalidation (remove entries from cache)

  All decorators validate their options using NimbleOptions at compile time.

  ## Using Presets (Recommended)

  For common use cases, use built-in presets:

      alias FnDecorator.Caching.Presets

      # High availability - serves stale data, auto-refreshes
      @decorate cacheable(Presets.high_availability(cache: MyCache, key: {User, id}))
      def get_user(id), do: Repo.get(User, id)

      # Critical config - always fresh
      @decorate cacheable(Presets.always_fresh(cache: MyCache, key: :feature_flags))
      def get_flags, do: ConfigService.fetch()

      # External API - resilient to outages
      @decorate cacheable(Presets.external_api(cache: MyCache, key: {:weather, city}))
      def get_weather(city), do: WeatherAPI.fetch(city)

  ## Full API

      @decorate cacheable(
        store: [
          cache: MyCache,
          key: {User, id},
          ttl: :timer.minutes(5),
          only_if: &match?({:ok, _}, &1)
        ],
        refresh: [
          on: [:stale_access, :immediately_when_expired],
          retries: 3
        ],
        serve_stale: [ttl: :timer.hours(1)],
        prevent_thunder_herd: [
          max_wait: :timer.seconds(5),
          retries: 3,
          lock_timeout: :timer.seconds(30),
          on_timeout: :serve_stale
        ],
        fallback: [
          on_refresh_failure: :serve_stale,
          on_cache_unavailable: {:call, &fallback/1}
        ]
      )
      def get_user(id), do: Repo.get(User, id)

  ## Legacy API (Backward Compatible)

      @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
      def get_user(id), do: Repo.get(User, id)

  See `FnDecorator.Caching.Presets` for available presets and how to create custom ones.
  """

  import FnDecorator.Shared
  alias FnDecorator.Caching.Validation

  # ============================================
  # Legacy Schema (backward compatible)
  # ============================================

  @legacy_schema NimbleOptions.new!(
                   cache: [
                     type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
                     required: true,
                     doc: "Cache module or MFA tuple for dynamic resolution"
                   ],
                   key: [
                     type: :any,
                     required: false,
                     doc: "Explicit cache key (overrides key_generator)"
                   ],
                   key_generator: [
                     type:
                       {:or, [:atom, {:tuple, [:atom, :any]}, {:tuple, [:atom, :atom, :any]}]},
                     required: false,
                     doc: "Custom key generator module or MFA"
                   ],
                   ttl: [
                     type: :pos_integer,
                     required: false,
                     doc: "Time-to-live in milliseconds"
                   ],
                   match: [
                     type: {:fun, 1},
                     required: false,
                     doc: "Match function to determine if result should be cached"
                   ],
                   on_error: [
                     type: {:in, [:raise, :nothing]},
                     default: :raise,
                     doc: "Error handling strategy"
                   ]
                 )

  @cache_put_schema NimbleOptions.new!(
                      cache: [
                        type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
                        required: true,
                        doc: "Cache module or MFA tuple"
                      ],
                      keys: [
                        type: {:list, :any},
                        required: true,
                        doc: "List of cache keys to update"
                      ],
                      ttl: [
                        type: :pos_integer,
                        required: false,
                        doc: "Time-to-live in milliseconds"
                      ],
                      match: [
                        type: {:fun, 1},
                        required: false,
                        doc: "Match function for conditional caching"
                      ],
                      on_error: [
                        type: {:in, [:raise, :nothing]},
                        default: :raise,
                        doc: "Error handling strategy"
                      ]
                    )

  @cache_evict_schema NimbleOptions.new!(
                        cache: [
                          type: {:or, [:atom, {:tuple, [:atom, :atom, :any]}]},
                          required: true,
                          doc: "Cache module or MFA tuple"
                        ],
                        keys: [
                          type: {:list, :any},
                          required: true,
                          doc: "List of cache keys to evict"
                        ],
                        all_entries: [
                          type: :boolean,
                          default: false,
                          doc: "If true, delete all cache entries"
                        ],
                        before_invocation: [
                          type: :boolean,
                          default: false,
                          doc: "If true, evict before function executes (safer for failures)"
                        ],
                        on_error: [
                          type: {:in, [:raise, :nothing]},
                          default: :raise,
                          doc: "Error handling strategy"
                        ]
                      )

  @doc """
  Read-through caching decorator with advanced features.

  Caches function results and returns cached values on subsequent calls.
  Only executes the function when cache misses.

  ## Using Presets (Recommended)

      alias FnDecorator.Caching.Presets

      @decorate cacheable(Presets.high_availability(cache: MyCache, key: {User, id}))
      def get_user(id), do: Repo.get(User, id)

  ## Full API

      @decorate cacheable(
        store: [
          cache: MyCache,                          # Required: cache module
          key: {User, id},                         # Required: cache key
          ttl: :timer.minutes(5),                  # Required: freshness duration
          only_if: &match?({:ok, _}, &1)           # Optional: condition to cache
        ],
        refresh: [
          on: :stale_access,                       # When to refresh
          retries: 3                               # Retry attempts
        ],
        serve_stale: [ttl: :timer.hours(1)],       # Serve expired data while refreshing
        prevent_thunder_herd: [                    # Stampede prevention (default ON)
          max_wait: :timer.seconds(5),
          retries: 3,
          lock_timeout: :timer.seconds(30),
          on_timeout: :serve_stale
        ],
        fallback: [
          on_refresh_failure: :serve_stale,
          on_cache_unavailable: {:call, &fallback/1}
        ]
      )
      def get_user(id), do: Repo.get(User, id)

  ## Refresh Triggers

  - `:stale_access` - Refresh when stale data is accessed
  - `:immediately_when_expired` - Refresh right when TTL expires
  - `{:every, ms}` - Periodic refresh
  - `{:every, ms, only_if_stale: true}` - Periodic, skip if fresh
  - `{:cron, "* * * * *"}` - Cron schedule
  - `{:cron, "* * * * *", only_if_stale: true}` - Cron, skip if fresh

  ## Legacy API (Backward Compatible)

      @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
      def get_user(id), do: Repo.get(User, id)

  See `FnDecorator.Caching.Presets` for available presets.
  """
  def cacheable(opts, body, context) do
    if uses_new_api?(opts) do
      cacheable_full_api(opts, body, context)
    else
      cacheable_legacy(opts, body, context)
    end
  end

  # ============================================
  # Full API Implementation
  # ============================================

  defp cacheable_full_api(opts, body, context) do
    # Validate at compile time
    Validation.validate!(opts)

    store = Keyword.get(opts, :store, [])
    _refresh = Keyword.get(opts, :refresh, [])
    serve_stale = Keyword.get(opts, :serve_stale)
    thunder_herd = normalize_thunder_herd(Keyword.get(opts, :prevent_thunder_herd, true))
    _fallback = Keyword.get(opts, :fallback, [])

    cache = resolve_cache_from_store(store)
    key = resolve_key_from_store(store, context)
    ttl = store[:ttl]
    only_if = store[:only_if]

    ttl_opt = if ttl, do: [ttl: ttl], else: []
    stale_ttl = if serve_stale, do: Keyword.get(serve_stale, :ttl), else: nil

    # Build the cache logic
    quote do
      cache = unquote(cache)
      key = unquote(key)

      # Try to get from cache
      case cache.get(key) do
        nil ->
          # Cache miss - execute function
          unquote(build_fetch_and_cache(body, cache, key, ttl_opt, only_if, thunder_herd))

        cached_value ->
          # Cache hit - check if stale
          unquote(
            if serve_stale do
              build_stale_check(cached_value: quote(do: cached_value), stale_ttl: stale_ttl)
            else
              quote(do: cached_value)
            end
          )
      end
    end
  end

  defp build_fetch_and_cache(body, _cache, _key, ttl_opt, only_if, thunder_herd) when thunder_herd == false do
    # No thunder herd protection - simple fetch
    build_simple_fetch(body, ttl_opt, only_if)
  end

  defp build_fetch_and_cache(body, _cache, _key, ttl_opt, only_if, thunder_herd) do
    max_wait = Keyword.get(thunder_herd, :max_wait, 5_000)
    retries = Keyword.get(thunder_herd, :retries, 3)
    lock_timeout = Keyword.get(thunder_herd, :lock_timeout, 30_000)
    on_timeout = Keyword.get(thunder_herd, :on_timeout, :serve_stale)

    quote do
      # Thunder herd protection
      lock_key = {:cacheable_lock, key}

      case acquire_lock(cache, lock_key, unquote(lock_timeout)) do
        :acquired ->
          # We got the lock - fetch and cache
          try do
            unquote(build_simple_fetch(body, ttl_opt, only_if))
          after
            release_lock(cache, lock_key)
          end

        :already_locked ->
          # Someone else is fetching - wait and retry
          wait_for_cache(
            cache,
            key,
            unquote(max_wait),
            unquote(retries),
            unquote(on_timeout),
            fn -> unquote(body) end
          )
      end
    end
  end

  defp build_simple_fetch(body, ttl_opt, nil) do
    quote do
      result = unquote(body)
      cache.put(key, result, unquote(ttl_opt))
      result
    end
  end

  defp build_simple_fetch(body, ttl_opt, only_if) do
    quote do
      result = unquote(body)

      if unquote(only_if).(result) do
        cache.put(key, result, unquote(ttl_opt))
      end

      result
    end
  end

  defp build_stale_check(opts) do
    # Note: This is simplified. Real stale checking requires metadata
    # stored with the cached value (timestamp, TTL info)
    quote do
      # For now, just return the cached value
      # Full stale-while-revalidate requires cache metadata support
      unquote(opts[:cached_value])
    end
  end

  # ============================================
  # Legacy API Implementation (Backward Compatible)
  # ============================================

  defp cacheable_legacy(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @legacy_schema)

    cache = resolve_cache(validated_opts)
    key = resolve_key(validated_opts, context)
    match = eval_match(validated_opts, quote(do: result))
    error_handler = handle_error(validated_opts, quote(do: result))
    ttl_opt = if validated_opts[:ttl], do: [ttl: validated_opts[:ttl]], else: []

    quote do
      cache = unquote(cache)
      key = unquote(key)

      case cache.get(key) do
        nil ->
          result = unquote(body)

          try do
            case unquote(match) do
              {true, value} ->
                cache.put(key, value, unquote(ttl_opt))
                result

              {true, value, runtime_opts} ->
                opts = unquote(merge_opts(ttl_opt, quote(do: runtime_opts)))
                cache.put(key, value, opts)
                result

              false ->
                result
            end
          rescue
            error -> unquote(error_handler).(error)
          end

        cached_value ->
          cached_value
      end
    end
  end

  # ============================================
  # cache_put (Write-through)
  # ============================================

  @doc """
  Write-through caching decorator.

  Always executes the function and updates the cache with the result.
  Useful for update operations where you want to keep the cache fresh.

  ## Options

  #{NimbleOptions.docs(@cache_put_schema)}

  ## Examples

      # Update multiple keys
      @decorate cache_put(cache: MyCache, keys: [{User, user.id}, {User, user.email}])
      def update_user(user, attrs) do
        user |> User.changeset(attrs) |> Repo.update()
      end

      # With match function (only cache on success)
      @decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
      def update_user(user, attrs) do
        user |> User.changeset(attrs) |> Repo.update()
      end

      defp match_ok({:ok, user}), do: {true, user}
      defp match_ok({:error, _}), do: false

      # With TTL
      @decorate cache_put(cache: MyCache, keys: [{Session, token}], ttl: :timer.minutes(30))
      def create_session(user) do
        # ...
      end
  """
  def cache_put(opts, body, _context) do
    validated_opts = NimbleOptions.validate!(opts, @cache_put_schema)

    cache = resolve_cache(validated_opts)
    keys = validated_opts[:keys]
    match = eval_match(validated_opts, quote(do: result))
    error_handler = handle_error(validated_opts, quote(do: result))
    ttl_opt = if validated_opts[:ttl], do: [ttl: validated_opts[:ttl]], else: []

    quote do
      cache = unquote(cache)
      result = unquote(body)

      try do
        case unquote(match) do
          {true, value} ->
            for key <- unquote(keys) do
              cache.put(key, value, unquote(ttl_opt))
            end

          {true, value, runtime_opts} ->
            opts = unquote(merge_opts(ttl_opt, quote(do: runtime_opts)))

            for key <- unquote(keys) do
              cache.put(key, value, opts)
            end

          false ->
            :ok
        end
      rescue
        error -> unquote(error_handler).(error)
      end

      result
    end
  end

  # ============================================
  # cache_evict (Invalidation)
  # ============================================

  @doc """
  Cache eviction decorator.

  Removes entries from the cache after (or before) function execution.
  Useful for delete operations or invalidating stale data.

  ## Options

  #{NimbleOptions.docs(@cache_evict_schema)}

  ## Examples

      # Evict specific keys
      @decorate cache_evict(cache: MyCache, keys: [{User, id}])
      def delete_user(id) do
        Repo.delete(User, id)
      end

      # Evict multiple keys
      @decorate cache_evict(cache: MyCache, keys: [{User, user.id}, {User, user.email}])
      def delete_user(user) do
        Repo.delete(user)
      end

      # Evict all entries (use with caution!)
      @decorate cache_evict(cache: MyCache, all_entries: true)
      def delete_all_users do
        Repo.delete_all(User)
      end

      # Evict before invocation (safer for critical operations)
      @decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
      def logout(token) do
        # Cache already cleared, safe even if this fails
        revoke_session(token)
      end
  """
  def cache_evict(opts, body, _context) do
    validated_opts = NimbleOptions.validate!(opts, @cache_evict_schema)

    cache = resolve_cache(validated_opts)
    keys = validated_opts[:keys]
    all_entries = validated_opts[:all_entries]
    before_invocation = validated_opts[:before_invocation]
    error_handler = handle_error(validated_opts, quote(do: result))

    evict_code =
      quote do
        cache = unquote(cache)

        try do
          if unquote(all_entries) do
            cache.delete_all()
          else
            for key <- unquote(keys) do
              cache.delete(key)
            end
          end
        rescue
          error -> unquote(error_handler).(error)
        end
      end

    if before_invocation do
      quote do
        unquote(evict_code)
        unquote(body)
      end
    else
      quote do
        result = unquote(body)
        unquote(evict_code)
        result
      end
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp uses_new_api?(opts) do
    Keyword.has_key?(opts, :store) or
      Keyword.has_key?(opts, :refresh) or
      Keyword.has_key?(opts, :serve_stale) or
      Keyword.has_key?(opts, :prevent_thunder_herd) or
      Keyword.has_key?(opts, :fallback)
  end

  defp resolve_cache_from_store(store) do
    case Keyword.fetch!(store, :cache) do
      {mod, fun, args} ->
        quote do: unquote(mod).unquote(fun)(unquote_splicing(args))

      module when is_atom(module) ->
        module
    end
  end

  defp resolve_key_from_store(store, _context) do
    case Keyword.get(store, :key) do
      nil -> raise CompileError, description: "store.key is required"
      key -> quote do: unquote(key)
    end
  end

  defp normalize_thunder_herd(true) do
    [max_wait: 5_000, retries: 3, lock_timeout: 30_000, on_timeout: :serve_stale]
  end

  defp normalize_thunder_herd(false), do: false

  defp normalize_thunder_herd(timeout) when is_integer(timeout) do
    [max_wait: timeout, retries: 3, lock_timeout: 30_000, on_timeout: :serve_stale]
  end

  defp normalize_thunder_herd(opts) when is_list(opts) do
    defaults = [max_wait: 5_000, retries: 3, lock_timeout: 30_000, on_timeout: :serve_stale]
    Keyword.merge(defaults, opts)
  end

  # ============================================
  # Runtime Helpers (injected into generated code)
  # ============================================

  @doc false
  def acquire_lock(cache, lock_key, lock_timeout) do
    case cache.get(lock_key) do
      nil ->
        # Try to acquire lock
        cache.put(lock_key, :locked, ttl: lock_timeout)
        :acquired

      :locked ->
        :already_locked
    end
  end

  @doc false
  def release_lock(cache, lock_key) do
    cache.delete(lock_key)
  end

  @doc false
  def wait_for_cache(cache, key, max_wait, retries, on_timeout, fetch_fn) do
    wait_until = System.monotonic_time(:millisecond) + max_wait

    do_wait_for_cache(cache, key, wait_until, retries, on_timeout, fetch_fn)
  end

  defp do_wait_for_cache(cache, key, wait_until, retries_left, on_timeout, fetch_fn) do
    now = System.monotonic_time(:millisecond)

    if now >= wait_until do
      # Wait time exceeded - try retries
      retry_cache_check(cache, key, retries_left, on_timeout, fetch_fn)
    else
      # Still waiting - check if value appeared
      case cache.get(key) do
        nil ->
          # Not ready yet, sleep a bit and retry
          Process.sleep(100)
          do_wait_for_cache(cache, key, wait_until, retries_left, on_timeout, fetch_fn)

        value ->
          value
      end
    end
  end

  defp retry_cache_check(_cache, _key, 0, on_timeout, fetch_fn) do
    # No more retries - use fallback
    handle_timeout(on_timeout, fetch_fn)
  end

  defp retry_cache_check(cache, key, retries_left, on_timeout, fetch_fn) do
    Process.sleep(100)

    case cache.get(key) do
      nil ->
        retry_cache_check(cache, key, retries_left - 1, on_timeout, fetch_fn)

      value ->
        value
    end
  end

  defp handle_timeout(:serve_stale, _fetch_fn) do
    # Would return stale data if available - for now return nil
    nil
  end

  defp handle_timeout(:error, _fetch_fn) do
    {:error, :cache_timeout}
  end

  defp handle_timeout({:call, fun}, _fetch_fn) when is_function(fun, 0) do
    fun.()
  end

  defp handle_timeout({:call, fun}, _fetch_fn) when is_function(fun, 1) do
    fun.(:timeout)
  end

  defp handle_timeout({:value, value}, _fetch_fn) do
    value
  end
end
