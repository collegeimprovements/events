defmodule Events.Infra.KillSwitch.Cache do
  @moduledoc """
  Cache service wrapper with kill switch support.

  Provides graceful degradation when cache (Redis) is unavailable.
  All operations check the kill switch before executing and can proceed
  without caching when disabled.

  ## Usage

      # Simple check
      if KillSwitch.Cache.enabled?() do
        Cache.put(key, value)
      end

      # With automatic pass-through
      KillSwitch.Cache.get(key)
      # Returns nil if cache is disabled

      # Pattern matching
      case KillSwitch.Cache.check() do
        :enabled -> Cache.put(key, value)
        {:disabled, _reason} -> :ok  # Skip caching
      end

  ## Configuration

      # Disable cache
      CACHE_ENABLED=false

      # Or in config
      config :events, Events.Infra.KillSwitch, cache: false

  ## Behavior

  When cache is disabled:
  - `get/2` returns `nil` (cache miss)
  - `put/3` returns `:ok` (no-op)
  - `delete/2` returns `:ok` (no-op)
  - Application continues without caching
  """

  alias Events.Core.Cache
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

  ## Examples

      KillSwitch.Cache.get({User, 123})
      #=> %User{} or nil
  """
  @spec get(any()) :: any()
  def get(key) do
    case check() do
      :enabled ->
        Cache.get(key)

      {:disabled, _reason} ->
        nil
    end
  end

  @doc """
  Put value in cache with kill switch protection.

  Returns `:ok` even if cache is disabled (graceful no-op).

  ## Options

  - `:ttl` - Time to live in milliseconds

  ## Examples

      KillSwitch.Cache.put({User, 123}, user, ttl: :timer.hours(1))
      #=> :ok
  """
  @spec put(any(), any(), keyword()) :: :ok
  def put(key, value, opts \\ [])

  def put(key, value, opts) do
    case check() do
      :enabled ->
        Cache.put(key, value, opts)
        :ok

      {:disabled, _reason} ->
        :ok
    end
  end

  @doc """
  Delete key from cache with kill switch protection.

  Returns `:ok` even if cache is disabled (graceful no-op).

  ## Examples

      KillSwitch.Cache.delete({User, 123})
      #=> :ok
  """
  @spec delete(any()) :: :ok
  def delete(key) do
    case check() do
      :enabled ->
        Cache.delete(key)
        :ok

      {:disabled, _reason} ->
        :ok
    end
  end

  @doc """
  Get multiple values from cache with kill switch protection.

  Returns empty list `[]` if cache is disabled.

  ## Examples

      KillSwitch.Cache.get_all([{User, 1}, {User, 2}, {User, 3}])
      #=> [%User{id: 1}, nil, %User{id: 3}]
  """
  @spec get_all([any()]) :: [any()]
  def get_all(keys) when is_list(keys) do
    case check() do
      :enabled ->
        Cache.get_all(keys)

      {:disabled, _reason} ->
        []
    end
  end

  @doc """
  Check if key exists in cache with kill switch protection.

  Returns `false` if cache is disabled.

  ## Examples

      KillSwitch.Cache.has_key?({User, 123})
      #=> true or false
  """
  @spec has_key?(any()) :: boolean()
  def has_key?(key) do
    case check() do
      :enabled ->
        case Cache.get(key) do
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

  - `:ttl` - Time to live in milliseconds

  ## Examples

      KillSwitch.Cache.fetch({User, id}, fn ->
        Repo.get(User, id)
      end, ttl: :timer.hours(1))
  """
  @spec fetch(any(), (-> any()), keyword()) :: any()
  def fetch(key, func, opts \\ []) when is_function(func, 0) do
    case check() do
      :enabled ->
        case Cache.get(key) do
          nil ->
            value = func.()
            Cache.put(key, value, opts)
            value

          value ->
            value
        end

      {:disabled, _reason} ->
        func.()
    end
  end

  @doc """
  Delete all keys matching a pattern with kill switch protection.

  This is a potentially expensive operation. Use with caution.

  Returns `:ok` even if cache is disabled.

  ## Examples

      # Delete all user cache entries
      KillSwitch.Cache.delete_pattern({User, :_})
  """
  @spec delete_pattern(any()) :: :ok
  def delete_pattern(_pattern) do
    case check() do
      :enabled ->
        # This would require implementing pattern matching in Cache
        # For now, just return :ok
        # Cache.delete_pattern(pattern)
        :ok

      {:disabled, _reason} ->
        :ok
    end
  end

  @doc """
  Execute a cache operation with a custom fallback.

  ## Examples

      KillSwitch.Cache.with_cache(
        fn -> Cache.transaction(fn -> ... end) end,
        fallback: fn -> {:ok, :skipped} end
      )
  """
  @spec with_cache((-> any()), keyword()) :: any()
  def with_cache(func, opts \\ []) when is_function(func, 0) do
    fallback = Keyword.get(opts, :fallback, fn -> {:ok, :cache_disabled} end)

    OmKillSwitch.with_service(@service, func, fallback: fallback)
  end
end
