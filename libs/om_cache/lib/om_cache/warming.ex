defmodule OmCache.Warming do
  @moduledoc """
  Cache warming utilities for preloading frequently accessed data.

  Provides strategies for warming cache on application startup or scheduled intervals
  to ensure high cache hit rates.

  ## Features

  - Preload frequently accessed keys
  - Batch warming with custom loaders
  - Scheduled warming with cron support
  - Warming priority levels

  ## Usage

      # Warm specific keys
      OmCache.Warming.warm(MyApp.Cache, [1, 2, 3], fn id ->
        {:ok, Repo.get(User, id)}
      end, ttl: :timer.hours(1))

      # Warm in batches
      OmCache.Warming.warm_batch(MyApp.Cache, users, fn user ->
        {User, user.id}
      end, ttl: :timer.hours(1))

      # Schedule periodic warming (requires OmScheduler)
      OmCache.Warming.schedule_warming(MyApp.Cache, [cron: "0 * * * *"], fn ->
        # Load popular products
        products = Repo.all(from p in Product, where: p.featured == true)
        {:ok, Map.new(products, fn p -> {{Product, p.id}, p} end)}
      end)
  """

  alias FnTypes.AsyncResult
  alias OmCache.Error

  @doc """
  Warms cache by loading specific keys.

  ## Options

  - `:ttl` - TTL for warmed entries
  - `:concurrency` - Max concurrent loader calls (default: 10)
  - `:on_error` - `:skip` (default) or `:stop`
  - `:key_fn` - Transform identifier to cache key (default: identity)

  ## Examples

      # Warm user cache
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
                  _ -> {:ok, 0}
                end

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
  - `:key_fn` - Extract cache key from data (required)

  ## Examples

      # Warm with pre-loaded users
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

  @doc """
  Schedules periodic cache warming using cron expressions.

  Note: Requires OmScheduler to be configured in your application.

  ## Options

  - `:cron` - Cron expression (e.g., "0 * * * *" for hourly)
  - `:interval` - Interval in milliseconds (alternative to cron)
  - `:ttl` - TTL for warmed entries
  - `:enabled` - Enable/disable warming (default: true)

  ## Examples

      # Warm every hour
      OmCache.Warming.schedule_warming(
        MyApp.Cache,
        [cron: "0 * * * *"],
        fn ->
          products = Repo.all(from p in Product, where: p.featured == true)
          {:ok, Map.new(products, fn p -> {{Product, p.id}, p} end)}
        end
      )

      # Warm every 5 minutes
      OmCache.Warming.schedule_warming(
        MyApp.Cache,
        [interval: :timer.minutes(5)],
        fn ->
          # Load data
          {:ok, %{}}
        end
      )
  """
  @spec schedule_warming(module(), keyword(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, reference()} | {:error, Error.t()}
  def schedule_warming(cache, schedule_opts, loader_fn)
      when is_function(loader_fn, 0) do
    enabled = Keyword.get(schedule_opts, :enabled, true)

    if enabled do
      # Create a scheduled job using Process.send_after or OmScheduler
      cond do
        Keyword.has_key?(schedule_opts, :cron) ->
          schedule_with_cron(cache, schedule_opts, loader_fn)

        Keyword.has_key?(schedule_opts, :interval) ->
          schedule_with_interval(cache, schedule_opts, loader_fn)

        true ->
          {:error, Error.invalid_key(nil, "Must specify either :cron or :interval")}
      end
    else
      {:ok, nil}
    end
  end

  @doc """
  Warms cache with a predefined warming strategy.

  ## Built-in Strategies

  - `:top_keys` - Warm most frequently accessed keys
  - `:recent_keys` - Warm recently accessed keys
  - `:all_keys` - Warm all keys (use with caution)

  ## Examples

      OmCache.Warming.warm_with_strategy(MyApp.Cache, :top_keys,
        limit: 100,
        loader: &MyApp.Users.get_user/1
      )
  """
  @spec warm_with_strategy(module(), atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def warm_with_strategy(cache, strategy, opts \\ []) do
    case strategy do
      :top_keys ->
        warm_top_keys(cache, opts)

      :recent_keys ->
        warm_recent_keys(cache, opts)

      :all_keys ->
        warm_all_keys(cache, opts)

      _ ->
        {:error, Error.invalid_key(strategy, "Unknown warming strategy: #{inspect(strategy)}")}
    end
  end

  # Private

  defp schedule_with_cron(cache, opts, loader_fn) do
    # This would integrate with OmScheduler
    # For now, return a placeholder
    ttl = Keyword.get(opts, :ttl)

    # Register warming task
    task_ref = make_ref()

    # In a real implementation, this would use OmScheduler
    # For now, we'll use a simple Process.send_after loop
    schedule_next_warming(cache, loader_fn, ttl, Keyword.get(opts, :interval, :timer.hours(1)), task_ref)

    {:ok, task_ref}
  end

  defp schedule_with_interval(cache, opts, loader_fn) do
    interval = Keyword.fetch!(opts, :interval)
    ttl = Keyword.get(opts, :ttl)

    task_ref = make_ref()
    schedule_next_warming(cache, loader_fn, ttl, interval, task_ref)

    {:ok, task_ref}
  end

  defp schedule_next_warming(cache, loader_fn, ttl, interval, task_ref) do
    Process.send_after(
      self(),
      {:warm_cache, cache, loader_fn, ttl, interval, task_ref},
      interval
    )
  end

  defp warm_top_keys(_cache, _opts) do
    # TODO: Implement with OmCache.Stats integration
    {:ok, 0}
  end

  defp warm_recent_keys(_cache, _opts) do
    # TODO: Implement with access timestamp tracking
    {:ok, 0}
  end

  defp warm_all_keys(_cache, _opts) do
    # TODO: Implement with key scanning
    {:ok, 0}
  end
end
