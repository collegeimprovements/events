defmodule OmCache.MultiLevel do
  @moduledoc """
  Multi-tier cache coordination for L1 (local) and L2 (distributed) caching.

  Implements a two-level cache hierarchy:
  - **L1 Cache**: Fast process-local or ETS cache
  - **L2 Cache**: Slower but shared cache (Redis, distributed ETS)

  ## Features

  - Automatic promotion from L2 to L1 on hits
  - Write-through to all levels
  - Consistent invalidation across levels
  - Configurable L1 TTL (shorter than L2)

  ## Usage

      # Define L1 and L2 caches
      defmodule MyApp.L1Cache do
        use OmCache, otp_app: :my_app, default_adapter: :local
      end

      defmodule MyApp.L2Cache do
        use OmCache, otp_app: :my_app, default_adapter: :redis
      end

      # Get with automatic L1 promotion
      OmCache.MultiLevel.get(MyApp.L1Cache, MyApp.L2Cache, {User, 123})

      # Put to both levels
      OmCache.MultiLevel.put(MyApp.L1Cache, MyApp.L2Cache, {User, 123}, user,
        l1_ttl: :timer.minutes(5),
        l2_ttl: :timer.hours(1)
      )

  ## Strategy

  ```
  Read Path:
  1. Check L1 (fast, local)
  2. If miss, check L2 (slower, shared)
  3. If L2 hit, promote to L1
  4. If both miss, return nil

  Write Path:
  1. Write to L1
  2. Write to L2
  3. Return success if both succeed
  ```
  """

  alias OmCache.Error

  @doc """
  Gets value from multi-level cache.

  Checks L1 first, then L2. Promotes L2 hits to L1.

  ## Options

  - `:l1_ttl` - TTL for L1 promotion (default: :timer.minutes(5))
  - `:skip_l1` - Skip L1 and go directly to L2 (default: false)
  - `:skip_promotion` - Don't promote L2 hits to L1 (default: false)

  ## Examples

      OmCache.MultiLevel.get(MyApp.L1Cache, MyApp.L2Cache, {User, 123})
      #=> %User{id: 123}
  """
  @spec get(module(), module(), term(), keyword()) :: term() | nil
  def get(l1_cache, l2_cache, key, opts \\ []) do
    skip_l1 = Keyword.get(opts, :skip_l1, false)
    skip_promotion = Keyword.get(opts, :skip_promotion, false)
    l1_ttl = Keyword.get(opts, :l1_ttl, :timer.minutes(5))

    cond do
      skip_l1 ->
        fetch_from_l2(l2_cache, key)

      true ->
        case l1_cache.get(key, opts) do
          nil ->
            # L1 miss, try L2
            case l2_cache.get(key, opts) do
              nil ->
                nil

              value ->
                # L2 hit, promote to L1
                unless skip_promotion do
                  try do
                    l1_cache.put(key, value, ttl: l1_ttl)
                  rescue
                    _ -> :ok
                  end
                end

                value
            end

          value ->
            # L1 hit
            value
        end
    end
  end

  @doc """
  Puts value in both cache levels.

  ## Options

  - `:l1_ttl` - TTL for L1 (default: :timer.minutes(5))
  - `:l2_ttl` - TTL for L2 (default: :timer.hours(1))
  - `:l1_only` - Only write to L1 (default: false)
  - `:l2_only` - Only write to L2 (default: false)

  ## Examples

      OmCache.MultiLevel.put(MyApp.L1Cache, MyApp.L2Cache, {User, 123}, user)
      #=> {:ok, :ok}
  """
  @spec put(module(), module(), term(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def put(l1_cache, l2_cache, key, value, opts \\ []) do
    l1_only = Keyword.get(opts, :l1_only, false)
    l2_only = Keyword.get(opts, :l2_only, false)
    l1_ttl = Keyword.get(opts, :l1_ttl, :timer.minutes(5))
    l2_ttl = Keyword.get(opts, :l2_ttl, :timer.hours(1))

    try do
      unless l2_only do
        l1_cache.put(key, value, ttl: l1_ttl)
      end

      unless l1_only do
        l2_cache.put(key, value, ttl: l2_ttl)
      end

      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :put, key)}
    end
  end

  @doc """
  Deletes key from both cache levels.

  ## Examples

      OmCache.MultiLevel.delete(MyApp.L1Cache, MyApp.L2Cache, {User, 123})
      #=> {:ok, :ok}
  """
  @spec delete(module(), module(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def delete(l1_cache, l2_cache, key, opts \\ []) do
    try do
      l1_cache.delete(key, opts)
      l2_cache.delete(key, opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :delete, key)}
    end
  end

  @doc """
  Gets value or loads it, storing in both levels.

  ## Examples

      OmCache.MultiLevel.get_or_fetch(
        MyApp.L1Cache,
        MyApp.L2Cache,
        {User, 123},
        fn -> {:ok, Repo.get(User, 123)} end
      )
  """
  @spec get_or_fetch(module(), module(), term(), (-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def get_or_fetch(l1_cache, l2_cache, key, loader_fn, opts \\ [])
      when is_function(loader_fn, 0) do
    case get(l1_cache, l2_cache, key, opts) do
      nil ->
        case loader_fn.() do
          {:ok, value} ->
            # Store in both levels
            _ = put(l1_cache, l2_cache, key, value, opts)
            {:ok, value}

          {:error, _reason} = error ->
            error
        end

      value ->
        {:ok, value}
    end
  end

  @doc """
  Invalidates key from both levels.

  Alias for `delete/4`.
  """
  @spec invalidate(module(), module(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def invalidate(l1_cache, l2_cache, key, opts \\ []) do
    delete(l1_cache, l2_cache, key, opts)
  end

  @doc """
  Clears all entries from both cache levels.

  ## Examples

      OmCache.MultiLevel.clear_all(MyApp.L1Cache, MyApp.L2Cache)
      #=> {:ok, :ok}
  """
  @spec clear_all(module(), module(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def clear_all(l1_cache, l2_cache, opts \\ []) do
    try do
      l1_cache.delete_all(opts)
      l2_cache.delete_all(opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :clear_all, nil)}
    end
  end

  # Private

  defp fetch_from_l2(l2_cache, key) do
    try do
      l2_cache.get(key)
    rescue
      _ -> nil
    end
  end
end
