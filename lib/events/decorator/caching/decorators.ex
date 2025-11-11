defmodule Events.Decorator.Caching do
  @moduledoc """
  Caching decorators for function memoization.

  Provides three core caching patterns inspired by Spring Cache and Nebulex:

  - `@cacheable` - Read-through caching (cache miss executes function)
  - `@cache_put` - Write-through caching (always execute, update cache)
  - `@cache_evict` - Cache invalidation (remove entries from cache)

  All decorators validate their options using NimbleOptions at compile time.

  ## Examples

      defmodule MyApp.Users do
        use Events.Decorator

        @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
        def get_user(id) do
          Repo.get(User, id)
        end

        @decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
        def update_user(user, attrs) do
          user
          |> User.changeset(attrs)
          |> Repo.update()
        end

        @decorate cache_evict(cache: MyCache, keys: [{User, id}])
        def delete_user(id) do
          Repo.delete(User, id)
        end

        defp match_ok({:ok, result}), do: {true, result}
        defp match_ok(_), do: false
      end
  """

  import Events.Decorator.Shared

  @cacheable_schema NimbleOptions.new!(
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
  Read-through caching decorator.

  Caches function results and returns cached values on subsequent calls.
  Only executes the function when cache misses.

  ## Options

  #{NimbleOptions.docs(@cacheable_schema)}

  ## Examples

      # Simple caching with explicit key
      @decorate cacheable(cache: MyCache, key: {User, id})
      def get_user(id), do: Repo.get(User, id)

      # With TTL
      @decorate cacheable(cache: MyCache, key: id, ttl: :timer.hours(1))
      def get_user(id), do: Repo.get(User, id)

      # With match function (only cache successful results)
      @decorate cacheable(cache: MyCache, key: id, match: &match_ok/1)
      def get_user(id), do: Repo.get(User, id)

      defp match_ok(%User{}), do: true
      defp match_ok(nil), do: false

      # With custom key generator
      @decorate cacheable(cache: MyCache, key_generator: MyKeyGen)
      def get_user(id), do: Repo.get(User, id)

      # Dynamic cache resolution
      @decorate cacheable(cache: {MyApp.Config, :get_cache, []}, key: id)
      def get_user(id), do: Repo.get(User, id)
  """
  def cacheable(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @cacheable_schema)

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
end
