defmodule OmCache.Helpers do
  @moduledoc """
  Helper functions for cache operations with result tuples.

  Provides a consistent `{:ok, value} | {:error, OmCache.Error.t()}` API
  on top of Nebulex's raw operations.

  ## Usage

  Instead of calling the cache module directly, use these helpers for
  operations that benefit from structured error handling:

      # Raw Nebulex - returns nil on miss
      MyApp.Cache.get(key)
      #=> nil

      # With fetch - returns {:ok, value} | {:error, :not_found}
      OmCache.Helpers.fetch(MyApp.Cache, key)
      #=> {:error, %OmCache.Error{type: :key_not_found}}

      # With fetch! - raises on miss
      OmCache.Helpers.fetch!(MyApp.Cache, key)
      #=> ** (OmCache.Error) Cache key not found

  ## Available Functions

  - `fetch/3` - Get with result tuple
  - `fetch!/3` - Get or raise
  - `put_safe/4` - Put with error handling
  - `delete_safe/3` - Delete with error handling
  - `get_or_fetch/4` - Cache-aside pattern with loader
  """

  alias OmCache.Error

  @doc """
  Fetches a value from cache, returning a result tuple.

  ## Options

  - `:default` - Default value if key not found (returns `{:ok, default}`)
  - Plus all standard Nebulex.Cache.get/2 options

  ## Examples

      # Key exists
      OmCache.Helpers.fetch(MyApp.Cache, {User, 123})
      #=> {:ok, %User{id: 123}}

      # Key missing
      OmCache.Helpers.fetch(MyApp.Cache, {User, 999})
      #=> {:error, %OmCache.Error{type: :key_not_found, key: {User, 999}}}

      # With default value
      OmCache.Helpers.fetch(MyApp.Cache, {User, 999}, default: %User{})
      #=> {:ok, %User{}}
  """
  @spec fetch(module(), term(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def fetch(cache, key, opts \\ []) do
    {default, cache_opts} = Keyword.pop(opts, :default)

    try do
      case cache.get(key, cache_opts) do
        nil when not is_nil(default) ->
          {:ok, default}

        nil ->
          {:error, Error.not_found(key, :get, cache: cache)}

        value ->
          {:ok, value}
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :get, key, cache: cache)}
    end
  end

  @doc """
  Fetches a value from cache or raises on error.

  ## Examples

      # Key exists
      OmCache.Helpers.fetch!(MyApp.Cache, {User, 123})
      #=> %User{id: 123}

      # Key missing - raises
      OmCache.Helpers.fetch!(MyApp.Cache, {User, 999})
      #=> ** (OmCache.Error) Cache key not found: {User, 999}
  """
  @spec fetch!(module(), term(), keyword()) :: term() | no_return()
  def fetch!(cache, key, opts \\ []) do
    case fetch(cache, key, opts) do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  @doc """
  Puts a value in cache with error handling.

  ## Options

  - `:ttl` - Time to live in milliseconds
  - `:validate_ttl` - Validate TTL is positive (default: true)
  - Plus all standard Nebulex.Cache.put/3 options

  ## Examples

      # Success
      OmCache.Helpers.put_safe(MyApp.Cache, {User, 123}, user)
      #=> {:ok, :ok}

      # With TTL
      OmCache.Helpers.put_safe(MyApp.Cache, {User, 123}, user, ttl: :timer.minutes(30))
      #=> {:ok, :ok}

      # Invalid TTL
      OmCache.Helpers.put_safe(MyApp.Cache, {User, 123}, user, ttl: -100)
      #=> {:error, %OmCache.Error{type: :invalid_ttl}}
  """
  @spec put_safe(module(), term(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def put_safe(cache, key, value, opts \\ []) do
    validate_ttl = Keyword.get(opts, :validate_ttl, true)

    with :ok <- validate_key(key),
         :ok <- maybe_validate_ttl(opts[:ttl], validate_ttl) do
      try do
        cache.put(key, value, opts)
        {:ok, :ok}
      rescue
        exception ->
          {:error, Error.from_exception(exception, :put, key, cache: cache)}
      end
    end
  end

  @doc """
  Deletes a key from cache with error handling.

  ## Examples

      # Success
      OmCache.Helpers.delete_safe(MyApp.Cache, {User, 123})
      #=> {:ok, :ok}

      # Error
      OmCache.Helpers.delete_safe(MyApp.Cache, nil)
      #=> {:error, %OmCache.Error{type: :invalid_key}}
  """
  @spec delete_safe(module(), term(), keyword()) :: {:ok, :ok} | {:error, Error.t()}
  def delete_safe(cache, key, opts \\ []) do
    with :ok <- validate_key(key) do
      try do
        cache.delete(key, opts)
        {:ok, :ok}
      rescue
        exception ->
          {:error, Error.from_exception(exception, :delete, key, cache: cache)}
      end
    end
  end

  @doc """
  Gets value from cache or loads it using the provided function.

  Implements cache-aside pattern with proper error handling.

  ## Options

  - `:ttl` - TTL for cached value
  - `:put_on_load` - Store loaded value in cache (default: true)
  - Plus all standard cache options

  ## Examples

      # Cache hit
      OmCache.Helpers.get_or_fetch(MyApp.Cache, {User, 123}, fn ->
        {:ok, Repo.get(User, 123)}
      end)
      #=> {:ok, %User{id: 123}}

      # Cache miss - loads and caches
      OmCache.Helpers.get_or_fetch(MyApp.Cache, {User, 999}, fn ->
        case Repo.get(User, 999) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end
      end, ttl: :timer.minutes(30))
      #=> {:ok, %User{id: 999}}

      # Loader returns error - not cached
      OmCache.Helpers.get_or_fetch(MyApp.Cache, {User, 999}, fn ->
        {:error, :database_down}
      end)
      #=> {:error, :database_down}
  """
  @spec get_or_fetch(module(), term(), (-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def get_or_fetch(cache, key, loader_fn, opts \\ []) when is_function(loader_fn, 0) do
    {put_on_load, cache_opts} = Keyword.pop(opts, :put_on_load, true)

    case fetch(cache, key, cache_opts) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Error{type: :key_not_found}} ->
        case loader_fn.() do
          {:ok, value} when put_on_load ->
            # Store in cache and return
            case put_safe(cache, key, value, cache_opts) do
              {:ok, :ok} -> {:ok, value}
              {:error, _} -> {:ok, value}
            end

          {:ok, value} ->
            {:ok, value}

          {:error, _reason} = error ->
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Batch fetch multiple keys with result tuples.

  Returns a map of keys to `{:ok, value}` or `{:error, reason}`.

  ## Examples

      OmCache.Helpers.fetch_batch(MyApp.Cache, [{User, 1}, {User, 2}, {User, 999}])
      #=> %{
      #     {User, 1} => {:ok, %User{id: 1}},
      #     {User, 2} => {:ok, %User{id: 2}},
      #     {User, 999} => {:error, %OmCache.Error{type: :key_not_found}}
      #   }
  """
  @spec fetch_batch(module(), [term()], keyword()) :: %{term() => {:ok, term()} | {:error, Error.t()}}
  def fetch_batch(cache, keys, opts \\ []) when is_list(keys) do
    try do
      results = cache.get_all(keys, opts)

      Map.new(keys, fn key ->
        case Map.get(results, key) do
          nil -> {key, {:error, Error.not_found(key, :get_all, cache: cache)}}
          value -> {key, {:ok, value}}
        end
      end)
    rescue
      exception ->
        error = Error.from_exception(exception, :get_all, nil, cache: cache)
        Map.new(keys, fn key -> {key, {:error, error}} end)
    end
  end

  @doc """
  Batch put multiple key-value pairs with error handling.

  ## Examples

      entries = [{User, 1} => user1, {User, 2} => user2]
      OmCache.Helpers.put_batch(MyApp.Cache, entries, ttl: :timer.minutes(30))
      #=> {:ok, :ok}
  """
  @spec put_batch(module(), [{term(), term()}] | %{term() => term()}, keyword()) ::
          {:ok, :ok} | {:error, Error.t()}
  def put_batch(cache, entries, opts \\ [])

  def put_batch(cache, entries, opts) when is_list(entries) do
    try do
      cache.put_all(entries, opts)
      {:ok, :ok}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :put_all, nil, cache: cache)}
    end
  end

  def put_batch(cache, entries, opts) when is_map(entries) do
    put_batch(cache, Map.to_list(entries), opts)
  end

  @doc """
  Checks if a key exists in cache.

  ## Examples

      OmCache.Helpers.exists?(MyApp.Cache, {User, 123})
      #=> {:ok, true}

      OmCache.Helpers.exists?(MyApp.Cache, {User, 999})
      #=> {:ok, false}
  """
  @spec exists?(module(), term(), keyword()) :: {:ok, boolean()} | {:error, Error.t()}
  def exists?(cache, key, opts \\ []) do
    try do
      result = cache.has_key?(key, opts)
      {:ok, result}
    rescue
      exception ->
        {:error, Error.from_exception(exception, :has_key?, key, cache: cache)}
    end
  end

  @doc """
  Gets remaining TTL for a key.

  ## Examples

      OmCache.Helpers.ttl(MyApp.Cache, {User, 123})
      #=> {:ok, 1_800_000}  # 30 minutes in ms

      OmCache.Helpers.ttl(MyApp.Cache, {User, 999})
      #=> {:error, %OmCache.Error{type: :key_not_found}}
  """
  @spec ttl(module(), term(), keyword()) :: {:ok, pos_integer() | :infinity} | {:error, Error.t()}
  def ttl(cache, key, opts \\ []) do
    try do
      case cache.ttl(key, opts) do
        nil -> {:error, Error.not_found(key, :ttl, cache: cache)}
        ttl_value -> {:ok, ttl_value}
      end
    rescue
      exception ->
        {:error, Error.from_exception(exception, :ttl, key, cache: cache)}
    end
  end

  # ============================================
  # Private
  # ============================================

  defp validate_key(nil) do
    {:error, Error.invalid_key(nil, "Key cannot be nil")}
  end

  defp validate_key(_key), do: :ok

  defp maybe_validate_ttl(nil, _validate), do: :ok
  defp maybe_validate_ttl(_ttl, false), do: :ok

  defp maybe_validate_ttl(ttl, true) when is_integer(ttl) and ttl > 0, do: :ok

  defp maybe_validate_ttl(ttl, true) when is_integer(ttl) do
    {:error, Error.invalid_ttl(ttl, "TTL must be positive, got: #{ttl}")}
  end

  defp maybe_validate_ttl(ttl, true) do
    {:error, Error.invalid_ttl(ttl, "TTL must be a positive integer, got: #{inspect(ttl)}")}
  end
end
