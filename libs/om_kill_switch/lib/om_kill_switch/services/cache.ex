defmodule OmKillSwitch.Services.Cache do
  @moduledoc """
  Cache service wrapper with kill switch support.

  Provides graceful degradation when cache (Redis/Nebulex) is unavailable.
  All operations check the kill switch before executing and can proceed
  without caching when disabled.

  ## Configuration

  Configure the cache module in your application:

      config :om_kill_switch, :cache_module, MyApp.Cache

  Or pass it explicitly to each function:

      OmKillSwitch.Services.Cache.get(key, cache: MyApp.Cache)

  ## Usage

      # Simple check
      if OmKillSwitch.Services.Cache.enabled?() do
        MyApp.Cache.put(key, value)
      end

      # With automatic pass-through
      OmKillSwitch.Services.Cache.get(key)
      # Returns nil if cache is disabled

      # Pattern matching
      case OmKillSwitch.Services.Cache.check() do
        :enabled -> MyApp.Cache.put(key, value)
        {:disabled, _reason} -> :ok  # Skip caching
      end

  ## Configuration

      # Disable cache via environment
      CACHE_ENABLED=false

      # Or in config
      config :om_kill_switch, services: [:s3, :cache, :database, :email]

  ## Behavior

  When cache is disabled:
  - `get/2` returns `nil` (cache miss)
  - `put/3` returns `:ok` (no-op)
  - `delete/2` returns `:ok` (no-op)
  - Application continues without caching
  """

  alias OmKillSwitch

  @service :cache

  @doc "Check if Cache service is enabled"
  @spec enabled?() :: boolean()
  def enabled?, do: OmKillSwitch.enabled?(@service)

  @doc "Check Cache service status"
  @spec check() :: :enabled | {:disabled, String.t()}
  def check, do: OmKillSwitch.check(@service)

  @doc "Get detailed Cache service status"
  @spec status() :: OmKillSwitch.status()
  def status, do: OmKillSwitch.status(@service)

  @doc "Disable Cache service"
  @spec disable(keyword()) :: :ok
  def disable(opts \\ []), do: OmKillSwitch.disable(@service, opts)

  @doc "Enable Cache service"
  @spec enable() :: :ok
  def enable, do: OmKillSwitch.enable(@service)

  ## Cache Operations with Kill Switch

  @doc """
  Get value from cache with kill switch protection.

  Returns `nil` if cache is disabled (cache miss behavior).

  ## Options

  - `:cache` - Cache module to use (default: configured module)

  ## Examples

      OmKillSwitch.Services.Cache.get({User, 123})
      #=> %User{} or nil
  """
  @spec get(any(), keyword()) :: any()
  def get(key, opts \\ []) do
    cache = cache_module(opts)

    case check() do
      :enabled ->
        cache.get(key)

      {:disabled, _reason} ->
        nil
    end
  end

  @doc """
  Put value in cache with kill switch protection.

  Returns `:ok` even if cache is disabled (graceful no-op).

  ## Options

  - `:cache` - Cache module to use (default: configured module)
  - `:ttl` - Time to live in milliseconds

  ## Examples

      OmKillSwitch.Services.Cache.put({User, 123}, user, ttl: :timer.hours(1))
      #=> :ok
  """
  @spec put(any(), any(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    cache = cache_module(opts)
    cache_opts = Keyword.drop(opts, [:cache])

    case check() do
      :enabled ->
        cache.put(key, value, cache_opts)
        :ok

      {:disabled, _reason} ->
        :ok
    end
  end

  @doc """
  Delete key from cache with kill switch protection.

  Returns `:ok` even if cache is disabled (graceful no-op).

  ## Options

  - `:cache` - Cache module to use (default: configured module)

  ## Examples

      OmKillSwitch.Services.Cache.delete({User, 123})
      #=> :ok
  """
  @spec delete(any(), keyword()) :: :ok
  def delete(key, opts \\ []) do
    cache = cache_module(opts)

    case check() do
      :enabled ->
        cache.delete(key)
        :ok

      {:disabled, _reason} ->
        :ok
    end
  end

  @doc """
  Get multiple values from cache with kill switch protection.

  Returns empty list `[]` if cache is disabled.

  ## Options

  - `:cache` - Cache module to use (default: configured module)

  ## Examples

      OmKillSwitch.Services.Cache.get_all([{User, 1}, {User, 2}, {User, 3}])
      #=> [%User{id: 1}, nil, %User{id: 3}]
  """
  @spec get_all([any()], keyword()) :: [any()]
  def get_all(keys, opts \\ []) when is_list(keys) do
    cache = cache_module(opts)

    case check() do
      :enabled ->
        cache.get_all(keys)

      {:disabled, _reason} ->
        []
    end
  end

  @doc """
  Check if key exists in cache with kill switch protection.

  Returns `false` if cache is disabled.

  ## Options

  - `:cache` - Cache module to use (default: configured module)

  ## Examples

      OmKillSwitch.Services.Cache.has_key?({User, 123})
      #=> true or false
  """
  @spec has_key?(any(), keyword()) :: boolean()
  def has_key?(key, opts \\ []) do
    cache = cache_module(opts)

    case check() do
      :enabled ->
        case cache.get(key) do
          nil -> false
          _value -> true
        end

      {:disabled, _reason} ->
        false
    end
  end

  @doc """
  Fetch value from cache or compute with kill switch protection.

  If cache is disabled, always computes the value (never caches).

  ## Options

  - `:cache` - Cache module to use (default: configured module)
  - `:ttl` - Time to live in milliseconds

  ## Examples

      OmKillSwitch.Services.Cache.fetch({User, id}, fn ->
        Repo.get(User, id)
      end, ttl: :timer.hours(1))
  """
  @spec fetch(any(), (-> any()), keyword()) :: any()
  def fetch(key, func, opts \\ []) when is_function(func, 0) do
    cache = cache_module(opts)
    cache_opts = Keyword.drop(opts, [:cache])

    case check() do
      :enabled ->
        case cache.get(key) do
          nil ->
            value = func.()
            cache.put(key, value, cache_opts)
            value

          value ->
            value
        end

      {:disabled, _reason} ->
        func.()
    end
  end

  @doc """
  Execute a cache operation with a custom fallback.

  ## Options

  - `:fallback` - Function to call if cache is disabled

  ## Examples

      OmKillSwitch.Services.Cache.with_cache(
        fn -> MyApp.Cache.transaction(fn -> ... end) end,
        fallback: fn -> {:ok, :skipped} end
      )
  """
  @spec with_cache((-> any()), keyword()) :: any()
  def with_cache(func, opts \\ []) when is_function(func, 0) do
    fallback = Keyword.get(opts, :fallback, fn -> {:ok, :cache_disabled} end)

    OmKillSwitch.with_service(@service, func, fallback: fallback)
  end

  ## Private Helpers

  defp cache_module(opts) do
    Keyword.get(opts, :cache) ||
      Application.get_env(:om_kill_switch, :cache_module) ||
      raise "No cache module configured. Set :cache option or configure :om_kill_switch, :cache_module"
  end
end
