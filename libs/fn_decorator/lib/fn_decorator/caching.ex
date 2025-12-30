defmodule FnDecorator.Caching do
  @moduledoc """
  Caching decorators for function memoization with advanced features.

  Provides three core caching patterns inspired by Spring Cache:

  - `@cacheable` - Read-through caching with refresh, stale serving, and stampede prevention
  - `@cache_put` - Write-through caching (always execute, update cache)
  - `@cache_evict` - Cache invalidation (remove entries from cache)

  ## Quick Start

      use FnDecorator
      alias FnDecorator.Caching.Presets

      @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
      def get_user(id), do: Repo.get(User, id)

  ## Full API

      @decorate cacheable(
        store: [
          cache: MyCache,
          key: {User, id},
          ttl: :timer.minutes(5),
          only_if: &match?({:ok, _}, &1)
        ],
        serve_stale: [ttl: :timer.hours(1)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: [
          max_wait: :timer.seconds(5),
          lock_ttl: :timer.seconds(30),
          on_timeout: :serve_stale
        ],
        fallback: [on_error: :serve_stale]
      )
      def get_user(id), do: Repo.get(User, id)

  ## Architecture

  The caching system uses several supporting modules:

  - `FnDecorator.Caching.Entry` - Stores values with metadata for freshness tracking
  - `FnDecorator.Caching.Lock` - Atomic lock management for thunder herd prevention
  - `FnDecorator.Caching.Runtime` - Runtime cache operations
  - `FnDecorator.Caching.Presets` - Built-in configuration presets
  - `FnDecorator.Caching.Validation` - Compile-time option validation

  ## Telemetry Events

  All events are prefixed with `[:fn_decorator, :cache]`:

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `:hit` | `%{duration: ns}` | `%{key: ..., status: :fresh/:stale}` |
  | `:miss` | `%{duration: ns}` | `%{key: ...}` |
  | `:fetch` | `%{duration: ns}` | `%{key: ..., success: bool}` |
  | `:refresh` | `%{duration: ns}` | `%{key: ..., success: bool}` |
  | `:lock` | `%{duration: ns}` | `%{key: ..., result: :acquired/:timeout}` |

  ## See Also

  - `FnDecorator.Caching.Presets` - Built-in presets for common use cases
  - `FnDecorator.Caching.Validation` - Schema documentation
  """

  import FnDecorator.Shared, only: [eval_match: 2, merge_opts: 2]
  alias FnDecorator.Caching.Validation

  # ============================================
  # @cacheable - Read-through caching
  # ============================================

  @doc """
  Read-through caching decorator with advanced features.

  Caches function results and returns cached values on subsequent calls.
  Only executes the function when cache misses or data is stale/expired.

  ## Options

  ### store (required)

  - `:cache` - Cache module implementing `get/1` and `put/3`
  - `:key` - Cache key (any term)
  - `:ttl` - Time-to-live in milliseconds
  - `:only_if` - Function `(result -> boolean)` to conditionally cache
  - `:tags` - List of tags or function `(result -> [tag])` for bulk invalidation

  ### serve_stale (optional)

  - `:ttl` - Extended TTL for stale-while-revalidate pattern

  ### refresh (optional)

  - `:on` - Refresh trigger: `:stale_access`

  ### prevent_thunder_herd (optional, default: true)

  - `:max_wait` - Max wait time for lock (default: 5000ms)
  - `:lock_ttl` - Lock validity duration (default: 30000ms)
  - `:on_timeout` - Action on timeout: `:serve_stale`, `:error`, `:proceed`, `{:call, fn}`, `{:value, term}`

  ### fallback (optional)

  - `:on_error` - Error handling: `:raise`, `:serve_stale`, `{:call, fn}`, `{:value, term}`

  ## Cache Entry States

  - **Fresh** - Within TTL, returned immediately
  - **Stale** - TTL expired but within stale_ttl, returned while refreshing
  - **Expired** - Beyond stale_ttl, treated as cache miss

  ## Examples

      # Using presets (recommended)
      alias FnDecorator.Caching.Presets

      @decorate cacheable(Presets.database(store: [cache: MyCache, key: {User, id}]))
      def get_user(id), do: Repo.get(User, id)

      # Full configuration
      @decorate cacheable(
        store: [cache: MyCache, key: {User, id}, ttl: :timer.minutes(5)],
        serve_stale: [ttl: :timer.hours(1)],
        refresh: [on: :stale_access],
        prevent_thunder_herd: true
      )
      def get_user(id), do: Repo.get(User, id)

      # Conditional caching
      @decorate cacheable(
        store: [
          cache: MyCache,
          key: {:result, id},
          ttl: :timer.minutes(5),
          only_if: &match?({:ok, _}, &1)
        ]
      )
      def maybe_get(id), do: ...
  """
  def cacheable(opts, body, context) do
    # Validate at compile time
    Validation.validate!(opts)

    store = Keyword.fetch!(opts, :store)
    serve_stale = Keyword.get(opts, :serve_stale)
    refresh = Keyword.get(opts, :refresh)
    prevent_thunder_herd = Keyword.get(opts, :prevent_thunder_herd, true)
    fallback = Keyword.get(opts, :fallback)

    cache = resolve_cache(store)
    key = resolve_key(store, context)

    # Build runtime options - must handle functions specially (no escape)
    runtime_opts = build_runtime_opts(store, serve_stale, refresh, prevent_thunder_herd, fallback)

    quote do
      FnDecorator.Caching.Runtime.execute(
        unquote(cache),
        unquote(key),
        fn -> unquote(body) end,
        unquote(runtime_opts)
      )
    end
  end

  # Build runtime options, handling functions as AST (not escaped)
  defp build_runtime_opts(store, serve_stale, refresh, prevent_thunder_herd, fallback) do
    store_ast = build_store_ast(store)
    serve_stale_ast = if serve_stale, do: escape_keyword(serve_stale), else: nil
    refresh_ast = if refresh, do: escape_keyword(refresh), else: nil
    fallback_ast = if fallback, do: build_fallback_ast(fallback), else: nil

    thunder_herd_ast =
      case prevent_thunder_herd do
        nil -> nil
        false -> false
        true -> true
        opts when is_list(opts) -> build_thunder_herd_ast(opts)
      end

    opts_ast =
      [
        store: store_ast,
        serve_stale: serve_stale_ast,
        refresh: refresh_ast,
        prevent_thunder_herd: thunder_herd_ast,
        fallback: fallback_ast
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:%{}, [], opts_ast} |> keyword_from_map_ast()
  end

  defp keyword_from_map_ast({:%{}, _, pairs}), do: pairs
  defp keyword_from_map_ast(other), do: other

  defp build_store_ast(store) do
    # Handle functions specially - don't escape them
    only_if = store[:only_if]
    tags = store[:tags]

    store_without_fns =
      store
      |> Keyword.delete(:only_if)
      |> Keyword.delete(:tags)
      |> escape_keyword()

    # Build up the store opts, adding functions back unescaped
    result = store_without_fns

    result =
      if only_if do
        quote do: Keyword.put(unquote(result), :only_if, unquote(only_if))
      else
        result
      end

    result =
      case tags do
        nil ->
          result

        tags when is_list(tags) ->
          # Static list of tags - can escape
          quote do: Keyword.put(unquote(result), :tags, unquote(Macro.escape(tags)))

        tags_fn ->
          # Function - don't escape
          quote do: Keyword.put(unquote(result), :tags, unquote(tags_fn))
      end

    result
  end

  defp build_fallback_ast(fallback) do
    on_error = fallback[:on_error]

    case on_error do
      {:call, fun} ->
        quote do: [on_error: {:call, unquote(fun)}]

      _ ->
        escape_keyword(fallback)
    end
  end

  defp build_thunder_herd_ast(opts) do
    on_timeout = opts[:on_timeout]

    case on_timeout do
      {:call, fun} ->
        other_opts = Keyword.delete(opts, :on_timeout) |> escape_keyword()
        quote do: Keyword.put(unquote(other_opts), :on_timeout, {:call, unquote(fun)})

      _ ->
        escape_keyword(opts)
    end
  end

  defp escape_keyword(list) when is_list(list) do
    Macro.escape(list)
  end

  # ============================================
  # @cache_put - Write-through caching
  # ============================================

  @doc """
  Write-through caching decorator.

  Always executes the function and updates the cache with the result.
  Useful for update operations where you want to keep the cache fresh.

  ## Options

  - `:cache` - Cache module (required)
  - `:keys` - List of cache keys to update (required)
  - `:ttl` - Time-to-live in milliseconds
  - `:match` - Function to determine if result should be cached

  ## Examples

      @decorate cache_put(cache: MyCache, keys: [{User, user.id}])
      def update_user(user, attrs) do
        user |> User.changeset(attrs) |> Repo.update()
      end

      # With match function
      @decorate cache_put(cache: MyCache, keys: [{User, user.id}], match: &match_ok/1)
      def update_user(user, attrs) do
        user |> User.changeset(attrs) |> Repo.update()
      end

      defp match_ok({:ok, user}), do: {true, user}
      defp match_ok({:error, _}), do: false
  """
  def cache_put(opts, body, _context) do
    validated_opts = Validation.validate_cache_put!(opts)

    cache = resolve_cache_simple(validated_opts)
    keys = validated_opts[:keys]
    match = eval_match(validated_opts, quote(do: result))
    ttl_opt = if validated_opts[:ttl], do: [ttl: validated_opts[:ttl]], else: []

    quote do
      cache = unquote(cache)
      result = unquote(body)

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

      result
    end
  end

  # ============================================
  # @cache_evict - Cache invalidation
  # ============================================

  @doc """
  Cache eviction decorator.

  Removes entries from the cache after (or before) function execution.
  Useful for delete operations or invalidating stale data.

  ## Options

  - `:cache` - Cache module (required)
  - `:keys` - List of specific cache keys to evict
  - `:match` - Pattern to match keys for eviction (e.g., `{User, :_}`)
  - `:tags` - List of tags or function `(result -> [tag])` for tag-based eviction
  - `:all_entries` - If true, delete all cache entries (shorthand for `match: :all`)
  - `:before_invocation` - If true, evict before function executes (default: false)
  - `:only_if` - Function to conditionally evict based on result

  At least one of `:keys`, `:match`, `:tags`, or `:all_entries` is required.

  ## Pattern Syntax

      :all              # Match all entries
      {User, :_}        # Match {User, 1}, {User, 2}, etc.
      {:_, :profile}    # Match {X, :profile} for any X

  ## Examples

      # Delete specific key
      @decorate cache_evict(cache: MyCache, keys: [{User, id}])
      def delete_user(id), do: Repo.delete(User, id)

      # Delete by pattern - all user entries
      @decorate cache_evict(cache: MyCache, match: {User, :_})
      def reset_all_users(), do: Repo.update_all(User, set: [active: false])

      # Delete before execution
      @decorate cache_evict(cache: MyCache, keys: [{Session, token}], before_invocation: true)
      def logout(token), do: revoke_session(token)

      # Conditional eviction
      @decorate cache_evict(
        cache: MyCache,
        keys: [{User, id}],
        only_if: &match?({:ok, _}, &1)
      )
      def update_user(id, attrs), do: ...

      # Clear all entries
      @decorate cache_evict(cache: MyCache, all_entries: true)
      def clear_cache(), do: :ok

      # Combine keys and pattern
      @decorate cache_evict(cache: MyCache, keys: [{User, id}], match: {:user_list, :_})
      def delete_user(id), do: ...

      # Tag-based eviction with static tags
      @decorate cache_evict(cache: MyCache, tags: [:users])
      def delete_all_users(), do: ...

      # Tag-based eviction with dynamic tags from result
      @decorate cache_evict(cache: MyCache, tags: fn %{org_id: org_id} -> ["org:\#{org_id}"] end)
      def update_org(id, attrs), do: ...
  """
  def cache_evict(opts, body, _context) do
    validated_opts = Validation.validate_cache_evict!(opts)

    cache = resolve_cache_simple(validated_opts)
    keys = validated_opts[:keys] || []
    match_pattern = validated_opts[:match]
    tags = validated_opts[:tags]
    all_entries = validated_opts[:all_entries]
    before_invocation = validated_opts[:before_invocation]
    only_if = validated_opts[:only_if]

    # Normalize: all_entries: true is equivalent to match: :all
    effective_pattern =
      cond do
        all_entries -> :all
        match_pattern -> match_pattern
        true -> nil
      end

    if before_invocation do
      # Evict before - can't use result-based tags
      evict_code = build_evict_code(cache, keys, effective_pattern, nil)

      quote do
        unquote(evict_code)
        unquote(body)
      end
    else
      # Build evict code - may reference result for dynamic tags
      evict_code = build_evict_code(cache, keys, effective_pattern, tags)

      if only_if do
        # Conditional eviction after
        quote do
          result = unquote(body)
          if unquote(only_if).(result) do
            unquote(evict_code)
          end
          result
        end
      else
        # Unconditional eviction after
        quote do
          result = unquote(body)
          unquote(evict_code)
          result
        end
      end
    end
  end

  defp build_evict_code(cache, keys, pattern, tags) do
    has_keys = is_list(keys) and length(keys) > 0
    has_pattern = not is_nil(pattern)

    # Build the base eviction code
    base_evict =
      cond do
        has_keys and has_pattern ->
          # Both: delete specific keys AND pattern
          quote do
            for key <- unquote(keys), do: cache.delete(key)
            cache.delete_all(unquote(Macro.escape(pattern)))
          end

        has_pattern ->
          # Only pattern
          quote do
            cache.delete_all(unquote(Macro.escape(pattern)))
          end

        has_keys ->
          # Only specific keys
          quote do
            for key <- unquote(keys), do: cache.delete(key)
          end

        true ->
          nil
      end

    # Build tag eviction code
    tag_evict =
      case tags do
        nil ->
          nil

        tags when is_list(tags) ->
          # Static list of tags
          quote do
            cache.invalidate_tags(unquote(Macro.escape(tags)))
          end

        tags_fn ->
          # Function that takes result
          quote do
            computed_tags = unquote(tags_fn).(result)
            cache.invalidate_tags(computed_tags)
          end
      end

    # Combine base and tag eviction
    cond do
      base_evict && tag_evict ->
        quote do
          cache = unquote(cache)
          unquote(base_evict)
          unquote(tag_evict)
        end

      base_evict ->
        quote do
          cache = unquote(cache)
          unquote(base_evict)
        end

      tag_evict ->
        quote do
          cache = unquote(cache)
          unquote(tag_evict)
        end

      true ->
        # Should not happen due to validation
        quote do: :ok
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp resolve_cache(store) do
    cache = Keyword.fetch!(store, :cache)
    resolve_cache_value(cache)
  end

  defp resolve_cache_simple(opts) do
    cache = Keyword.fetch!(opts, :cache)
    resolve_cache_value(cache)
  end

  # MFA tuple at compile time - build a call
  defp resolve_cache_value({mod, fun, args})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    quote do: unquote(mod).unquote(fun)(unquote_splicing(args))
  end

  # Atom at compile time - use directly
  defp resolve_cache_value(module) when is_atom(module) do
    module
  end

  # AST node (alias, etc.) - quote it back
  defp resolve_cache_value(ast) do
    quote do: unquote(ast)
  end

  defp resolve_key(store, _context) do
    key = Keyword.fetch!(store, :key)
    quote do: unquote(key)
  end
end
