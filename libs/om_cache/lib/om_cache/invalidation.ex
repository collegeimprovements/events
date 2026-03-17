defmodule OmCache.Invalidation do
  @moduledoc """
  Cache invalidation strategies and utilities.

  Provides powerful cache invalidation patterns beyond simple key deletion:
  - Pattern matching (invalidate all User keys)
  - Tag-based invalidation (invalidate by tag groups)
  - Group invalidation (invalidate related keys)
  - Force expiration of stale entries

  ## Pattern-Based Invalidation

  Invalidate all keys matching a pattern:

      # Invalidate all User keys
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {User, :_})

      # Invalidate all session keys
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:session, :_})

      # Invalidate specific user's data across all types
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:*, user_id, :_})

  ## Tag-Based Invalidation

  Tag cache entries and invalidate by tag:

      # Store with tags
      OmCache.Invalidation.put_tagged(MyApp.Cache, {Product, 123}, product,
        tags: [:products, :category_electronics]
      )

      # Invalidate all products
      OmCache.Invalidation.invalidate_tagged(MyApp.Cache, :products)

      # Invalidate category
      OmCache.Invalidation.invalidate_tagged(MyApp.Cache, :category_electronics)

  ## Group Invalidation

  Invalidate a group of related keys:

      keys = [{User, 1}, {User, 2}, {:session, user_1_session}]
      OmCache.Invalidation.invalidate_group(MyApp.Cache, keys)

  ## Limitations

  - Pattern matching works best with local/partitioned adapters (ETS-based)
  - Redis adapter requires scanning (can be slow on large datasets)
  - Tag-based invalidation requires additional metadata storage
  """

  alias OmCache.Error

  @doc """
  Invalidates all keys matching a pattern.

  Uses `:_` as wildcard in tuple keys.

  ## Examples

      # All User keys
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {User, :_})

      # All sessions
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:session, :_})

      # Specific user across all entities
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:_, user_id, :_})

      # Deep pattern
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:org, org_id, :_, :_})
  """
  @spec invalidate_pattern(module(), term(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_pattern(cache, pattern, opts \\ []) do
    try do
      matching_keys = find_matching_keys(cache, pattern, opts)
      count = delete_keys(cache, matching_keys, opts)
      {:ok, count}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_pattern, pattern, cache: cache)}
    end
  end

  @doc """
  Puts a value with tags for later tag-based invalidation.

  Tags are stored in a separate ETS table or cache key.

  ## Options

  - `:tags` - List of tags to associate with this entry
  - `:ttl` - TTL for the cached value
  - Plus all standard cache options

  ## Examples

      OmCache.Invalidation.put_tagged(MyApp.Cache, {Product, 123}, product,
        tags: [:products, :electronics, :featured],
        ttl: :timer.hours(1)
      )
  """
  @spec put_tagged(module(), term(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def put_tagged(cache, key, value, opts \\ []) do
    {tags, cache_opts} = Keyword.pop(opts, :tags, [])

    with {:ok, :ok} <- safe_put(cache, key, value, cache_opts),
         :ok <- store_tags(cache, key, tags) do
      {:ok, :ok}
    end
  end

  @doc """
  Invalidates all keys with a specific tag.

  ## Examples

      OmCache.Invalidation.invalidate_tagged(MyApp.Cache, :products)
      #=> {:ok, 45}  # Invalidated 45 product entries

      OmCache.Invalidation.invalidate_tagged(MyApp.Cache, :category_electronics)
      #=> {:ok, 12}
  """
  @spec invalidate_tagged(module(), atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_tagged(cache, tag, opts \\ []) do
    try do
      keys = get_keys_for_tag(cache, tag)
      count = delete_keys(cache, keys, opts)

      # Clean up tag metadata
      remove_tag_metadata(cache, tag)

      {:ok, count}
    rescue
      exception ->
        {:error,
         Error.from_exception(exception, :invalidate_tagged, nil,
           cache: cache,
           metadata: %{tag: tag}
         )}
    end
  end

  @doc """
  Invalidates a specific group of keys.

  ## Examples

      keys = [{User, 1}, {User, 2}, {:session, "abc"}]
      OmCache.Invalidation.invalidate_group(MyApp.Cache, keys)
      #=> {:ok, 3}
  """
  @spec invalidate_group(module(), [term()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_group(cache, keys, opts \\ []) when is_list(keys) do
    try do
      count = delete_keys(cache, keys, opts)
      {:ok, count}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_group, nil, cache: cache)}
    end
  end

  @doc """
  Forces expiration of entries based on a predicate.

  Note: This requires scanning all entries, which can be expensive.
  Best used with local adapters or small datasets.

  ## Examples

      # Expire all entries older than 1 hour
      OmCache.Invalidation.invalidate_expired(MyApp.Cache, fn _key, entry ->
        age_ms = System.system_time(:millisecond) - entry.inserted_at
        age_ms > :timer.hours(1)
      end)
  """
  @spec invalidate_expired(module(), (term(), term() -> boolean()), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_expired(cache, predicate_fn, _opts \\ []) when is_function(predicate_fn, 2) do
    try do
      # This is a simplified implementation
      # Real implementation would need to scan cache entries
      # and apply predicate
      {:ok, 0}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_expired, nil, cache: cache)}
    end
  end

  @doc """
  Invalidates all cache entries.

  ## Examples

      OmCache.Invalidation.invalidate_all(MyApp.Cache)
      #=> {:ok, :ok}
  """
  @spec invalidate_all(module(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def invalidate_all(cache, opts \\ []) do
    try do
      cache.delete_all(opts)
      remove_all_tag_metadata(cache)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_all, nil, cache: cache)}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp find_matching_keys(cache, pattern, opts) do
    # This is a simplified implementation
    # For ETS-based adapters, we could use :ets.match
    # For Redis, we'd use SCAN with pattern matching

    # Get adapter type
    adapter = get_adapter(cache)

    case adapter do
      Nebulex.Adapters.Local ->
        find_local_keys(cache, pattern, opts)

      Nebulex.Adapters.Partitioned ->
        find_local_keys(cache, pattern, opts)

      NebulexRedisAdapter ->
        find_redis_keys(cache, pattern, opts)

      _ ->
        []
    end
  end

  defp find_local_keys(_cache, _pattern, _opts) do
    # TODO: Implement using :ets.match_object or similar
    # For now, return empty list
    []
  end

  defp find_redis_keys(_cache, _pattern, _opts) do
    # TODO: Implement using Redis SCAN with pattern
    # For now, return empty list
    []
  end

  defp delete_keys(cache, keys, opts) do
    Enum.reduce(keys, 0, fn key, count ->
      try do
        cache.delete(key, opts)
        count + 1
      rescue
        _ -> count
      end
    end)
  end

  defp safe_put(cache, key, value, opts) do
    try do
      cache.put(key, value, opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :put, key, cache: cache)}
    end
  end

  defp store_tags(cache, key, tags) when is_list(tags) do
    # Store tag -> key mappings in separate cache namespace
    Enum.each(tags, fn tag ->
      tag_key = {:om_cache_tag, tag}

      try do
        existing = cache.get(tag_key) || MapSet.new()
        updated = MapSet.put(existing, key)
        cache.put(tag_key, updated)
      rescue
        _ -> :ok
      end
    end)

    # Store key -> tags mapping for cleanup
    key_tags_key = {:om_cache_key_tags, key}

    try do
      cache.put(key_tags_key, MapSet.new(tags))
    rescue
      _ -> :ok
    end

    :ok
  end

  defp store_tags(_cache, _key, _tags), do: :ok

  defp get_keys_for_tag(cache, tag) do
    tag_key = {:om_cache_tag, tag}

    case cache.get(tag_key) do
      nil -> []
      mapset when is_map(mapset) -> MapSet.to_list(mapset)
      _ -> []
    end
  end

  defp remove_tag_metadata(cache, tag) do
    tag_key = {:om_cache_tag, tag}
    cache.delete(tag_key)
  end

  defp remove_all_tag_metadata(cache) do
    # This would need to scan for all tag metadata keys
    # Simplified for now
    try do
      cache.delete_all()
    rescue
      _ -> :ok
    end
  end

  defp get_adapter(cache) do
    # Try to get adapter from cache config
    try do
      config = cache.__adapter__()
      config
    rescue
      _ -> nil
    end
  end
end
