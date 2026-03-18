defmodule OmCache.Invalidation do
  @moduledoc """
  Cache invalidation strategies and utilities.

  Provides cache invalidation patterns beyond simple key deletion:
  - Pattern matching (invalidate all User keys) — local/partitioned adapters only
  - Tag-based invalidation (invalidate by tag groups)
  - Group invalidation (invalidate a list of known keys)

  ## Pattern-Based Invalidation (ETS adapters only)

  Invalidate all keys matching a pattern. Uses `:_` as wildcard in tuple keys:

      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {User, :_})
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:session, :_})

  Pattern matching requires scanning all keys and only works with ETS-backed
  adapters (local, partitioned). For Redis, use tag-based or group invalidation.

  ## Tag-Based Invalidation

  Tag cache entries and invalidate by tag:

      OmCache.Invalidation.put_tagged(MyApp.Cache, {Product, 123}, product,
        tags: [:products, :category_electronics]
      )

      OmCache.Invalidation.invalidate_tagged(MyApp.Cache, :products)

  Note: Tag metadata is stored in the cache itself using reserved key prefixes.
  Concurrent `put_tagged` calls for the same tag may lose associations under
  high write contention.

  ## Group Invalidation

  Invalidate a list of known keys:

      keys = [{User, 1}, {User, 2}, {:session, user_1_session}]
      OmCache.Invalidation.invalidate_group(MyApp.Cache, keys)

  ## Known Limitations

  - **Pattern matching scans all keys** — O(n) on cache size. Avoid on large caches
    in hot paths. Use group or tag-based invalidation instead.
  - **Partitioned adapters only scan the local node's keys** — pattern invalidation
    won't reach keys on other nodes. Use group invalidation for distributed caches.
  - **Tag metadata is not atomic** — concurrent `put_tagged` for the same tag can
    lose key associations. For write-heavy tag scenarios, prefer group invalidation.
  - **Redis adapter** — pattern and tag invalidation are not supported with Redis.
    Use `invalidate_group` with explicit key lists.
  """

  require Logger

  alias OmCache.Error

  @tag_prefix :om_cache_tag
  @key_tags_prefix :om_cache_key_tags

  @doc """
  Invalidates all keys matching a pattern.

  Uses `:_` as wildcard in tuple keys. Only works with ETS-backed adapters
  (local, partitioned). Returns `{:ok, 0}` for unsupported adapters.

  ## Examples

      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {User, :_})
      OmCache.Invalidation.invalidate_pattern(MyApp.Cache, {:session, :_})
  """
  @spec invalidate_pattern(module(), term(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_pattern(cache, pattern, opts \\ []) do
    try do
      matching_keys = find_matching_keys(cache, pattern)
      count = delete_keys(cache, matching_keys, opts)
      {:ok, count}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_pattern, pattern, cache: cache)}
    end
  end

  @doc """
  Puts a value with tags for later tag-based invalidation.

  Tags are stored as cache entries with reserved key prefixes.

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
      #=> {:ok, 45}
  """
  @spec invalidate_tagged(module(), atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def invalidate_tagged(cache, tag, opts \\ []) do
    try do
      keys = get_keys_for_tag(cache, tag)
      count = delete_keys(cache, keys, opts)

      # Clean up tag metadata entry
      try do
        cache.delete({@tag_prefix, tag})
      rescue
        _ -> :ok
      end

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
  Invalidates all cache entries and clears tag metadata.

  ## Examples

      OmCache.Invalidation.invalidate_all(MyApp.Cache)
      #=> {:ok, :ok}
  """
  @spec invalidate_all(module(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def invalidate_all(cache, opts \\ []) do
    try do
      cache.delete_all(nil, opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :invalidate_all, nil, cache: cache)}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp find_matching_keys(cache, pattern) do
    try do
      # stream/2 works with ETS-backed adapters (local, partitioned)
      cache.stream()
      |> Enum.filter(&matches_pattern?(&1, pattern))
    rescue
      # Adapter doesn't support stream (e.g., Redis) — return empty
      _ -> []
    end
  end

  @doc false
  def matches_pattern?(key, pattern) when is_tuple(key) and is_tuple(pattern) do
    key_size = tuple_size(key)
    pattern_size = tuple_size(pattern)

    key_size == pattern_size and
      Enum.all?(0..(pattern_size - 1), fn i ->
        p = elem(pattern, i)
        p == :_ or p == elem(key, i)
      end)
  end

  def matches_pattern?(key, :_), do: not is_nil(key)
  def matches_pattern?(key, pattern), do: key == pattern

  defp delete_keys(cache, keys, opts) do
    Enum.reduce(keys, 0, fn key, count ->
      try do
        cache.delete(key, opts)
        count + 1
      rescue
        e ->
          Logger.warning("OmCache.Invalidation: failed to delete key #{inspect(key)}: #{Exception.message(e)}")
          count
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

  defp store_tags(cache, key, tags) when is_list(tags) and tags != [] do
    Enum.each(tags, fn tag ->
      tag_key = {@tag_prefix, tag}

      try do
        existing = cache.get(tag_key) || MapSet.new()
        updated = MapSet.put(existing, key)
        cache.put(tag_key, updated)
      rescue
        e ->
          Logger.warning("OmCache.Invalidation: failed to store tag #{inspect(tag)} for key #{inspect(key)}: #{Exception.message(e)}")
      end
    end)

    try do
      cache.put({@key_tags_prefix, key}, MapSet.new(tags))
    rescue
      e ->
        Logger.warning("OmCache.Invalidation: failed to store key-tags mapping for #{inspect(key)}: #{Exception.message(e)}")
    end

    :ok
  end

  defp store_tags(_cache, _key, _tags), do: :ok

  defp get_keys_for_tag(cache, tag) do
    tag_key = {@tag_prefix, tag}

    case cache.get(tag_key) do
      nil -> []
      %MapSet{} = mapset -> MapSet.to_list(mapset)
      _ -> []
    end
  end
end
