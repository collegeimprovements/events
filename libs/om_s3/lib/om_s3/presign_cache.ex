defmodule OmS3.PresignCache do
  @moduledoc """
  Caching utilities for presigned URLs.

  Prevents regeneration storms by caching presigned URLs and returning
  cached versions when they're still valid.

  ## Why Cache Presigned URLs?

  Presigned URL generation is computationally inexpensive, but can become
  a bottleneck in high-traffic scenarios:

  - Each generation requires cryptographic signing
  - Concurrent requests may generate duplicate URLs
  - URLs can be safely reused until near expiration

  ## Usage

  ### With GenServer Cache

      # Start the cache (add to supervision tree)
      OmS3.PresignCache.start_link(name: MyApp.S3PresignCache)

      # Get cached presigned URL
      {:ok, url} = OmS3.PresignCache.get_or_generate(
        MyApp.S3PresignCache,
        "s3://bucket/file.pdf",
        config,
        expires_in: {1, :hour}
      )

  ### With External Cache (e.g., Nebulex)

      # Configure cache module
      OmS3.PresignCache.configure(cache: MyApp.Cache)

      # Use with decorator pattern
      @decorate cacheable(OmS3.PresignCache.preset(
        cache: MyApp.Cache,
        key: {:presign, uri}
      ))
      def get_download_url(uri) do
        OmS3.presign(uri, config())
      end

  ### Cache Key Strategies

      # Simple key (just URI)
      OmS3.PresignCache.key(uri)
      #=> {:om_s3_presign, "s3://bucket/file.pdf"}

      # With user context
      OmS3.PresignCache.key(uri, user_id: user_id)
      #=> {:om_s3_presign, "s3://bucket/file.pdf", user_id: 123}

  ## Expiration Strategy

  URLs are cached for `expires_in - buffer` time, where buffer defaults
  to 60 seconds. This ensures URLs are refreshed before they expire.
  """

  use GenServer

  alias OmS3.Config
  alias OmS3.Duration

  @type cache_entry :: %{
          url: String.t(),
          generated_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @default_buffer_seconds 60
  @default_expires_in 3600

  # ============================================
  # Public API - Cache Key Generation
  # ============================================

  @doc """
  Generates a cache key for a presigned URL.

  ## Examples

      OmS3.PresignCache.key("s3://bucket/file.pdf")
      #=> {:om_s3_presign, "s3://bucket/file.pdf"}

      OmS3.PresignCache.key("s3://bucket/file.pdf", user_id: 123)
      #=> {:om_s3_presign, "s3://bucket/file.pdf", [user_id: 123]}

      OmS3.PresignCache.key("s3://bucket/file.pdf", method: :put)
      #=> {:om_s3_presign, "s3://bucket/file.pdf", [method: :put]}
  """
  @spec key(String.t(), keyword()) :: tuple()
  def key(uri, context \\ []) do
    case context do
      [] -> {:om_s3_presign, uri}
      ctx -> {:om_s3_presign, uri, ctx}
    end
  end

  @doc """
  Returns a caching preset for use with `@cacheable` decorator.

  The preset automatically calculates TTL based on the presigned URL
  expiration, minus a safety buffer.

  ## Options

  - `:cache` - Cache module to use (required)
  - `:key` - Cache key or key function (required)
  - `:expires_in` - Presigned URL expiration in seconds (default: 3600)
  - `:buffer` - Seconds to subtract from TTL for safety (default: 60)

  ## Examples

      @decorate cacheable(OmS3.PresignCache.preset(
        cache: MyApp.Cache,
        key: {:presign, uri},
        expires_in: 3600
      ))
      def get_download_url(uri) do
        OmS3.presign(uri, config())
      end

      # With dynamic key
      @decorate cacheable(OmS3.PresignCache.preset(
        cache: MyApp.Cache,
        key: fn uri, user_id -> {:presign, uri, user_id} end,
        expires_in: {1, :hour}
      ))
      def get_user_download_url(uri, user_id) do
        OmS3.presign(uri, config())
      end
  """
  @spec preset(keyword()) :: keyword()
  def preset(opts) do
    cache = Keyword.fetch!(opts, :cache)
    key = Keyword.fetch!(opts, :key)
    expires_in = Duration.to_seconds(Keyword.get(opts, :expires_in, @default_expires_in))
    buffer = Keyword.get(opts, :buffer, @default_buffer_seconds)
    ttl = max((expires_in - buffer) * 1000, 1000)

    [
      store: [cache: cache, key: key, ttl: ttl],
      # Only cache successful presigned URLs
      only_if: &match?({:ok, _}, &1)
    ]
  end

  # ============================================
  # GenServer Implementation
  # ============================================

  @doc """
  Starts the presign cache GenServer.

  ## Options

  - `:name` - GenServer name (default: `OmS3.PresignCache`)
  - `:cleanup_interval` - Interval for cleaning expired entries (default: 60_000ms)
  - `:max_entries` - Maximum cached entries before LRU eviction (default: 10_000)

  ## Examples

      OmS3.PresignCache.start_link(name: MyApp.S3PresignCache)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets a cached presigned URL or generates a new one.

  ## Options

  - `:method` - HTTP method `:get` or `:put` (default: `:get`)
  - `:expires_in` - Expiration in seconds or duration tuple (default: 3600)
  - `:buffer` - Seconds to subtract from cache TTL (default: 60)
  - `:context` - Additional context for cache key differentiation

  ## Examples

      {:ok, url} = OmS3.PresignCache.get_or_generate(
        MyApp.S3PresignCache,
        "s3://bucket/file.pdf",
        config
      )

      {:ok, url} = OmS3.PresignCache.get_or_generate(
        MyApp.S3PresignCache,
        "s3://bucket/upload.jpg",
        config,
        method: :put,
        expires_in: {5, :minutes}
      )
  """
  @spec get_or_generate(GenServer.server(), String.t(), Config.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_or_generate(server, uri, %Config{} = config, opts \\ []) do
    method = Keyword.get(opts, :method, :get)
    expires_in = Duration.to_seconds(Keyword.get(opts, :expires_in, @default_expires_in))
    buffer = Keyword.get(opts, :buffer, @default_buffer_seconds)
    context = Keyword.get(opts, :context, [])

    cache_key = key(uri, [method: method] ++ context)

    GenServer.call(server, {:get_or_generate, cache_key, uri, config, method, expires_in, buffer})
  end

  @doc """
  Invalidates a cached presigned URL.

  ## Examples

      OmS3.PresignCache.invalidate(MyApp.S3PresignCache, "s3://bucket/file.pdf")
      OmS3.PresignCache.invalidate(MyApp.S3PresignCache, "s3://bucket/file.pdf", method: :put)
  """
  @spec invalidate(GenServer.server(), String.t(), keyword()) :: :ok
  def invalidate(server, uri, opts \\ []) do
    method = Keyword.get(opts, :method, :get)
    context = Keyword.get(opts, :context, [])
    cache_key = key(uri, [method: method] ++ context)
    GenServer.cast(server, {:invalidate, cache_key})
  end

  @doc """
  Clears all cached presigned URLs.

  ## Examples

      OmS3.PresignCache.clear(MyApp.S3PresignCache)
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server) do
    GenServer.cast(server, :clear)
  end

  @doc """
  Returns cache statistics.

  ## Examples

      stats = OmS3.PresignCache.stats(MyApp.S3PresignCache)
      #=> %{entries: 150, hits: 1000, misses: 50, hit_rate: 0.95}
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(opts) do
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)
    max_entries = Keyword.get(opts, :max_entries, 10_000)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       cache: %{},
       access_order: [],
       max_entries: max_entries,
       cleanup_interval: cleanup_interval,
       stats: %{hits: 0, misses: 0}
     }}
  end

  @impl true
  def handle_call({:get_or_generate, cache_key, uri, config, method, expires_in, buffer}, _from, state) do
    now = DateTime.utc_now()

    case Map.get(state.cache, cache_key) do
      %{url: url, expires_at: expires_at} = entry when is_struct(expires_at, DateTime) ->
        # Check if entry is still valid (not expired)
        case DateTime.compare(expires_at, now) do
          :gt ->
            # Cache hit - return cached URL and update access order
            new_state = %{
              state
              | access_order: update_access_order(state.access_order, cache_key),
                stats: Map.update!(state.stats, :hits, &(&1 + 1))
            }

            {:reply, {:ok, url}, maybe_log_entry(new_state, entry, :hit)}

          _ ->
            # Expired entry - fall through to cache miss
            handle_cache_miss(state, cache_key, uri, config, method, expires_in, buffer, now)
        end

      _ ->
        # Cache miss - generate new URL
        handle_cache_miss(state, cache_key, uri, config, method, expires_in, buffer, now)
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    total = state.stats.hits + state.stats.misses

    hit_rate =
      if total > 0 do
        Float.round(state.stats.hits / total, 4)
      else
        0.0
      end

    stats = %{
      entries: map_size(state.cache),
      hits: state.stats.hits,
      misses: state.stats.misses,
      hit_rate: hit_rate
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:invalidate, cache_key}, state) do
    new_cache = Map.delete(state.cache, cache_key)
    new_access = Enum.reject(state.access_order, &(&1 == cache_key))
    {:noreply, %{state | cache: new_cache, access_order: new_access}}
  end

  @impl true
  def handle_cast(:clear, state) do
    {:noreply, %{state | cache: %{}, access_order: [], stats: %{hits: 0, misses: 0}}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    # Remove expired entries
    {new_cache, expired_keys} =
      Enum.reduce(state.cache, {%{}, []}, fn {key, entry}, {cache, expired} ->
        if DateTime.compare(entry.expires_at, now) == :gt do
          {Map.put(cache, key, entry), expired}
        else
          {cache, [key | expired]}
        end
      end)

    new_access = Enum.reject(state.access_order, &(&1 in expired_keys))

    schedule_cleanup(state.cleanup_interval)

    {:noreply, %{state | cache: new_cache, access_order: new_access}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp generate_presigned_url(uri, config, method, expires_in_seconds) do
    # expires_in should be in seconds for OmS3.presign
    OmS3.presign(uri, config, method: method, expires_in: expires_in_seconds)
  end

  defp handle_cache_miss(state, cache_key, uri, config, method, expires_in, buffer, now) do
    result = generate_presigned_url(uri, config, method, expires_in)

    case result do
      {:ok, url} ->
        expires_at = DateTime.add(now, expires_in - buffer, :second)

        entry = %{
          url: url,
          generated_at: now,
          expires_at: expires_at
        }

        new_cache = Map.put(state.cache, cache_key, entry)
        new_access = update_access_order(state.access_order, cache_key)

        new_state =
          %{
            state
            | cache: new_cache,
              access_order: new_access,
              stats: Map.update!(state.stats, :misses, &(&1 + 1))
          }
          |> maybe_evict()

        {:reply, {:ok, url}, new_state}

      error ->
        new_state = %{state | stats: Map.update!(state.stats, :misses, &(&1 + 1))}
        {:reply, error, new_state}
    end
  end

  defp update_access_order(order, key) do
    # Move key to front (most recently accessed)
    [key | Enum.reject(order, &(&1 == key))]
  end

  defp maybe_evict(%{cache: cache, access_order: order, max_entries: max} = state)
       when map_size(cache) > max do
    # Evict least recently used entries
    to_evict = length(order) - max
    {evict_keys, keep_order} = Enum.split(Enum.reverse(order), to_evict)
    new_cache = Map.drop(cache, evict_keys)
    %{state | cache: new_cache, access_order: Enum.reverse(keep_order)}
  end

  defp maybe_evict(state), do: state

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp maybe_log_entry(state, _entry, _type), do: state
end
