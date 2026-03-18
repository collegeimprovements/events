defmodule OmCache.Warming do
  @moduledoc """
  Cache warming utilities for preloading frequently accessed data.

  Provides two strategies for warming cache:
  - `warm/4` — Load individual keys via a loader function (parallel)
  - `warm_batch/4` — Bulk-insert pre-loaded data

  For periodic/scheduled warming, use OmScheduler with these functions.

  ## Usage

      # Warm specific keys in parallel
      user_ids = [1, 2, 3, 4, 5]
      OmCache.Warming.warm(MyApp.Cache, user_ids, fn id ->
        {:ok, Repo.get(User, id)}
      end, key_fn: fn id -> {User, id} end, ttl: :timer.hours(1))
      #=> {:ok, 5}

      # Warm with pre-loaded data
      users = Repo.all(from u in User, where: u.active)
      OmCache.Warming.warm_batch(MyApp.Cache, users, fn user ->
        {User, user.id}
      end, ttl: :timer.hours(1))
      #=> {:ok, 150}
  """

  require Logger

  alias FnTypes.AsyncResult
  alias OmCache.Error

  @doc """
  Warms cache by loading specific keys in parallel.

  ## Options

  - `:ttl` - TTL for warmed entries
  - `:concurrency` - Max concurrent loader calls (default: 10)
  - `:on_error` - `:skip` (default) or `:stop`
  - `:key_fn` - Transform identifier to cache key (default: identity)

  ## Examples

      user_ids = [1, 2, 3, 4, 5]
      OmCache.Warming.warm(MyApp.Cache, user_ids, fn id ->
        {:ok, Repo.get(User, id)}
      end, key_fn: fn id -> {User, id} end, ttl: :timer.hours(1))
      #=> {:ok, 5}
  """
  @spec warm(module(), [term()], (term() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def warm(cache, identifiers, loader_fn, opts \\ [])
      when is_list(identifiers) and is_function(loader_fn, 1) do
    concurrency = Keyword.get(opts, :concurrency, 10)
    on_error = Keyword.get(opts, :on_error, :skip)
    key_fn = Keyword.get(opts, :key_fn, & &1)
    ttl = Keyword.get(opts, :ttl)

    try do
      tasks =
        Enum.map(identifiers, fn identifier ->
          fn ->
            case loader_fn.(identifier) do
              {:ok, value} ->
                key = key_fn.(identifier)
                cache_opts = if ttl, do: [ttl: ttl], else: []

                try do
                  cache.put(key, value, cache_opts)
                  {:ok, 1}
                rescue
                  e ->
                    Logger.warning("OmCache.Warming: failed to cache key #{inspect(key)}: #{Exception.message(e)}")
                    {:ok, 0}
                end

              {:error, reason} ->
                case on_error do
                  :stop -> {:error, reason}
                  _ -> {:ok, 0}
                end
            end
          end
        end)

      case AsyncResult.parallel(tasks, max_concurrency: concurrency) do
        {:ok, results} ->
          count = Enum.sum(results)
          {:ok, count}

        {:error, reason} ->
          {:error, Error.operation_failed(:warm, "Warming failed: #{inspect(reason)}", cache: cache)}
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :warm, nil, cache: cache)}
    end
  end

  @doc """
  Warms cache with a list of already-loaded data.

  ## Options

  - `:ttl` - TTL for cached values

  ## Examples

      users = Repo.all(User)
      OmCache.Warming.warm_batch(MyApp.Cache, users, fn user ->
        {User, user.id}
      end, ttl: :timer.hours(1))
      #=> {:ok, 150}
  """
  @spec warm_batch(module(), [term()], (term() -> term()), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def warm_batch(cache, data_list, key_fn, opts \\ [])
      when is_list(data_list) and is_function(key_fn, 1) do
    ttl = Keyword.get(opts, :ttl)

    try do
      entries = Enum.map(data_list, fn item -> {key_fn.(item), item} end)
      cache_opts = if ttl, do: [ttl: ttl], else: []

      cache.put_all(entries, cache_opts)
      {:ok, length(entries)}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :warm_batch, nil, cache: cache)}
    end
  end
end
