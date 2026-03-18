defmodule OmCache.Batch do
  @moduledoc """
  Enhanced batch cache operations with parallel processing and automatic fallback.

  Provides high-performance batch operations using `FnTypes.AsyncResult` for
  parallel processing and automatic fallback to source when keys are missing.

  ## Features

  - Parallel fetching with `AsyncResult`
  - Automatic fallback for missing keys
  - Batch warming from source
  - Redis pipeline support (when available)
  - Result partitioning (hits vs misses)

  ## Usage

      # Fetch batch with automatic loading for misses
      OmCache.Batch.fetch_batch(MyApp.Cache, [1, 2, 3], fn id ->
        {:ok, Repo.get(User, id)}
      end, ttl: :timer.minutes(30))
      #=> {:ok, %{1 => user1, 2 => user2, 3 => user3}}

      # Batch put
      entries = %{{User, 1} => user1, {User, 2} => user2}
      OmCache.Batch.put_batch(MyApp.Cache, entries, ttl: :timer.hours(1))
      #=> {:ok, :ok}

      # Parallel fetch (no auto-loading)
      OmCache.Batch.fetch_parallel(MyApp.Cache, [{User, 1}, {User, 2}])
      #=> {:ok, %{{User, 1} => user1, {User, 2} => user2}}
  """

  require Logger

  alias FnTypes.AsyncResult
  alias OmCache.Error

  @doc """
  Fetches multiple keys in parallel with automatic loading for misses.

  Missing keys are loaded using the provided loader function and stored in cache.

  ## Options

  - `:ttl` - TTL for cached values
  - `:concurrency` - Max concurrent loader calls (default: 10)
  - `:skip_cache_on_error` - Don't cache if loader returns error (default: true)
  - Plus all standard cache options

  ## Examples

      # Basic usage
      OmCache.Batch.fetch_batch(MyApp.Cache, [1, 2, 3], fn id ->
        {:ok, Repo.get(User, id)}
      end)
      #=> {:ok, %{1 => %User{id: 1}, 2 => %User{id: 2}, 3 => %User{id: 3}}}

      # With key transformation
      OmCache.Batch.fetch_batch(MyApp.Cache, [1, 2, 3], fn id ->
        {:ok, Repo.get(User, id)}
      end, key_fn: fn id -> {User, id} end)
      #=> {:ok, %{1 => %User{}, 2 => %User{}, 3 => %User{}}}
  """
  @spec fetch_batch(module(), [term()], (term() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, %{term() => term()}} | {:error, Error.t()}
  def fetch_batch(cache, identifiers, loader_fn, opts \\ [])
      when is_list(identifiers) and is_function(loader_fn, 1) do
    concurrency = Keyword.get(opts, :concurrency, 10)
    key_fn = Keyword.get(opts, :key_fn, & &1)
    skip_cache_on_error = Keyword.get(opts, :skip_cache_on_error, true)
    ttl = Keyword.get(opts, :ttl)

    try do
      # Build keys from identifiers
      keys = Enum.map(identifiers, key_fn)

      # Fetch from cache
      cached_results = cache.get_all(keys, opts)

      # Partition into hits and misses
      {hits, misses} =
        Enum.reduce(identifiers, {%{}, []}, fn identifier, {hits_acc, misses_acc} ->
          key = key_fn.(identifier)

          case Map.get(cached_results, key) do
            nil -> {hits_acc, [identifier | misses_acc]}
            value -> {Map.put(hits_acc, identifier, value), misses_acc}
          end
        end)

      # Load misses in parallel
      if Enum.empty?(misses) do
        {:ok, hits}
      else
        load_and_cache_misses(cache, misses, hits, loader_fn, key_fn, skip_cache_on_error, ttl,
          concurrency, opts
        )
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :fetch_batch, nil, cache: cache)}
    end
  end

  @doc """
  Fetches multiple keys in parallel without auto-loading.

  Returns hits and misses separately.

  ## Examples

      OmCache.Batch.fetch_parallel(MyApp.Cache, [{User, 1}, {User, 2}, {User, 999}])
      #=> {:ok, %{
      #     hits: %{{User, 1} => user1, {User, 2} => user2},
      #     misses: [{User, 999}]
      #   }}
  """
  @spec fetch_parallel(module(), [term()], keyword()) ::
          {:ok, %{hits: map(), misses: [term()]}} | {:error, Error.t()}
  def fetch_parallel(cache, keys, opts \\ []) when is_list(keys) do
    concurrency = Keyword.get(opts, :concurrency, 10)

    try do
      tasks =
        Enum.map(keys, fn key ->
          fn -> {key, cache.get(key, opts)} end
        end)

      results = AsyncResult.parallel(tasks, max_concurrency: concurrency)

      case results do
        {:ok, key_value_pairs} ->
          {hits, misses} =
            Enum.reduce(key_value_pairs, {%{}, []}, fn {key, value}, {hits_acc, misses_acc} ->
              case value do
                nil -> {hits_acc, [key | misses_acc]}
                val -> {Map.put(hits_acc, key, val), misses_acc}
              end
            end)

          {:ok, %{hits: hits, misses: misses}}

        {:error, _reason} = error ->
          error
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :fetch_parallel, nil, cache: cache)}
    end
  end

  @doc """
  Puts multiple key-value pairs in a single batch operation.

  Uses optimized bulk insert when available (Redis MSET, etc.).

  ## Examples

      entries = [{{User, 1}, user1}, {{User, 2}, user2}]
      OmCache.Batch.put_batch(MyApp.Cache, entries, ttl: :timer.hours(1))
      #=> {:ok, :ok}

      # With map
      entries = %{{User, 1} => user1, {User, 2} => user2}
      OmCache.Batch.put_batch(MyApp.Cache, entries)
      #=> {:ok, :ok}
  """
  @spec put_batch(module(), [{term(), term()}] | %{term() => term()}, keyword()) ::
          {:ok, :ok} | {:error, Error.t()}
  def put_batch(cache, entries, opts \\ [])

  def put_batch(cache, entries, opts) when is_map(entries) do
    put_batch(cache, Map.to_list(entries), opts)
  end

  def put_batch(cache, entries, opts) when is_list(entries) do
    try do
      cache.put_all(entries, opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :put_batch, nil, cache: cache)}
    end
  end

  @doc """
  Warms cache by preloading data in batches.

  ## Options

  - `:batch_size` - Number of items to load per batch (default: 100)
  - `:concurrency` - Max concurrent batches (default: 5)
  - `:ttl` - TTL for cached values
  - `:on_error` - `:skip` (default) or `:stop`

  ## Examples

      # Warm cache with all active users
      user_ids = Repo.all(from u in User, where: u.active, select: u.id)

      OmCache.Batch.warm_cache(MyApp.Cache, user_ids, fn batch_ids ->
        users = Repo.all(from u in User, where: u.id in ^batch_ids)
        {:ok, Map.new(users, fn u -> {{User, u.id}, u} end)}
      end, ttl: :timer.hours(1))
      #=> {:ok, 1500}  # Warmed 1500 entries
  """
  @spec warm_cache(
          module(),
          [term()],
          ([term()] -> {:ok, %{term() => term()}} | {:error, term()}),
          keyword()
        ) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def warm_cache(cache, identifiers, batch_loader_fn, opts \\ [])
      when is_list(identifiers) and is_function(batch_loader_fn, 1) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    concurrency = Keyword.get(opts, :concurrency, 5)
    on_error = Keyword.get(opts, :on_error, :skip)
    ttl = Keyword.get(opts, :ttl)

    try do
      batches = Enum.chunk_every(identifiers, batch_size)

      tasks =
        Enum.map(batches, fn batch ->
          fn ->
            case batch_loader_fn.(batch) do
              {:ok, entries} ->
                cache_opts = if ttl, do: [ttl: ttl], else: []
                cache.put_all(Map.to_list(entries), cache_opts)
                {:ok, map_size(entries)}

              {:error, reason} ->
                if on_error == :stop do
                  {:error, reason}
                else
                  {:ok, 0}
                end
            end
          end
        end)

      case AsyncResult.parallel(tasks, max_concurrency: concurrency) do
        {:ok, counts} ->
          total = Enum.sum(counts)
          {:ok, total}

        {:error, reason} ->
          {:error, Error.operation_failed(:warm_cache, "Warming failed: #{inspect(reason)}")}
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :warm_cache, nil, cache: cache)}
    end
  end

  @doc """
  Deletes multiple keys in a batch operation.

  ## Examples

      OmCache.Batch.delete_batch(MyApp.Cache, [{User, 1}, {User, 2}, {User, 3}])
      #=> {:ok, :ok}
  """
  @spec delete_batch(module(), [term()], keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def delete_batch(cache, keys, opts \\ []) when is_list(keys) do
    try do
      Enum.each(keys, fn key -> cache.delete(key, opts) end)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :delete_batch, nil, cache: cache)}
    end
  end

  @doc """
  Executes multiple cache operations sequentially, returning all results.

  Supported operations: `{:get, key}`, `{:put, key, value}`, `{:delete, key}`.

  ## Examples

      operations = [
        {:get, {User, 1}},
        {:put, {User, 2}, user2},
        {:delete, {User, 3}}
      ]

      OmCache.Batch.pipeline(MyApp.Cache, operations)
      #=> {:ok, [user1, :ok, :ok]}
  """
  @spec pipeline(module(), [tuple()], keyword()) ::
          {:ok, [term()]} | {:error, Error.t()}
  def pipeline(cache, operations, opts \\ []) when is_list(operations) do
    # This is a simplified implementation
    # Real Redis pipeline support would use Redix.pipeline
    try do
      results =
        Enum.map(operations, fn
          {:get, key} -> cache.get(key, opts)
          {:put, key, value} -> cache.put(key, value, opts)
          {:delete, key} -> cache.delete(key, opts)
          _ -> {:error, :unknown_operation}
        end)

      {:ok, results}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :pipeline, nil, cache: cache)}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp load_and_cache_misses(
         cache,
         misses,
         hits,
         loader_fn,
         key_fn,
         skip_cache_on_error,
         ttl,
         concurrency,
         _opts
       ) do
    cache_opts = if ttl, do: [ttl: ttl], else: []

    tasks =
      Enum.map(misses, fn identifier ->
        fn ->
          case loader_fn.(identifier) do
            {:ok, value} ->
              key = key_fn.(identifier)
              safe_cache_put(cache, key, value, cache_opts)
              {identifier, {:ok, value}}

            {:error, _reason} = error ->
              if not skip_cache_on_error do
                key = key_fn.(identifier)
                safe_cache_put(cache, key, error, cache_opts)
              end

              {identifier, error}
          end
        end
      end)

    case AsyncResult.parallel(tasks, max_concurrency: concurrency) do
      {:ok, results} ->
        loaded =
          Enum.reduce(results, hits, fn
            {identifier, {:ok, value}}, acc ->
              Map.put(acc, identifier, value)

            {_identifier, {:error, _reason}}, acc ->
              acc
          end)

        {:ok, loaded}

      {:error, reason} ->
        {:error, Error.operation_failed(:fetch_batch, "Batch loading failed: #{inspect(reason)}")}
    end
  end

  defp safe_cache_put(cache, key, value, opts) do
    try do
      cache.put(key, value, opts)
    rescue
      e ->
        Logger.warning("OmCache.Batch: failed to cache key #{inspect(key)}: #{Exception.message(e)}")
        :ok
    end
  end
end
