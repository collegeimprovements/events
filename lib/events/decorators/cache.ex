defmodule Events.Decorators.Cache do
  @moduledoc """
  Caching decorators for the Events application.

  Provides read-through, write-through, and cache eviction decorators.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate cacheable(cache: MyCache, key: {User, id}, ttl: 3600)
        def get_user(id) do
          Repo.get(User, id)
        end

        @decorate cache_put(cache: MyCache, keys: [{User, user.id}])
        def update_user(user, attrs) do
          # Updates cache after successful operation
        end

        @decorate cache_evict(cache: MyCache, keys: [{User, id}])
        def delete_user(id) do
          # Removes from cache
        end
      end
  """

  @doc """
  Read-through cache decorator.

  Checks cache first, executes function on miss, caches result.

  ## Options

  - `:cache` - Cache module (required)
  - `:key` - Cache key or key generator (required)
  - `:ttl` - Time to live in milliseconds
  - `:match` - Function to determine if result should be cached
  - `:on_error` - Error handling strategy (:default, :raise, :cache_nil)
  """
  defmacro cacheable(opts \\ []) do
    quote do
      use Decorator.Define, cacheable: 1
      unquote(opts)
    end
  end

  @doc """
  Write-through cache decorator.

  Updates cache with function result.

  ## Options

  - `:cache` - Cache module (required)
  - `:keys` - List of cache keys to update (required)
  - `:match` - Function to extract value from result
  - `:ttl` - Time to live in milliseconds
  """
  defmacro cache_put(opts \\ []) do
    quote do
      use Decorator.Define, cache_put: 1
      unquote(opts)
    end
  end

  @doc """
  Cache eviction decorator.

  Removes entries from cache.

  ## Options

  - `:cache` - Cache module (required)
  - `:keys` - List of cache keys to evict (required)
  - `:condition` - Function to determine if eviction should occur
  """
  defmacro cache_evict(opts \\ []) do
    quote do
      use Decorator.Define, cache_evict: 1
      unquote(opts)
    end
  end

  @doc """
  Cache stats decorator.

  Tracks cache hit/miss rates.

  ## Options

  - `:cache` - Cache module (required)
  - `:metric_name` - Name for metrics (default: function name)
  """
  defmacro cache_stats(opts \\ []) do
    quote do
      use Decorator.Define, cache_stats: 1
      unquote(opts)
    end
  end
end
