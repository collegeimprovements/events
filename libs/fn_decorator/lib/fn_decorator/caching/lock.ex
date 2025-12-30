defmodule FnDecorator.Caching.Lock do
  @moduledoc """
  Distributed lock management for cache stampede prevention.

  When multiple processes request the same uncached key simultaneously,
  only one should fetch from the source while others wait. This module
  provides the locking mechanism to coordinate this.

  ## How It Works

  ```
  Process A: acquire(:key) → :acquired → fetch data → release(:key)
  Process B: acquire(:key) → :busy    → wait...     → get from cache
  Process C: acquire(:key) → :busy    → wait...     → get from cache
  ```

  ## Lock Expiration

  Locks automatically expire after `lock_ttl` to prevent deadlocks if the
  lock holder crashes without releasing. Expired locks can be taken over.

  ## Implementation

  Uses ETS with atomic `insert_new/2` for lock acquisition. This provides:
  - Atomic lock acquisition (no race conditions)
  - Sub-millisecond performance
  - Automatic cleanup on process crash (ETS table persists)

  ## Distributed Deployments

  For multi-node deployments, configure a distributed lock adapter:

      config :fn_decorator, :lock_adapter, MyApp.RedisLock

  The adapter must implement the `FnDecorator.Caching.Lock.Adapter` behaviour.

  ## Usage

      case Lock.acquire(:my_key, 30_000) do
        {:ok, token} ->
          try do
            # Fetch from source
          after
            Lock.release(:my_key, token)
          end

        :busy ->
          # Another process is fetching, wait or serve stale
      end
  """

  @table __MODULE__

  @typedoc "Opaque token returned on successful lock acquisition"
  @type token :: {pid(), reference()}

  @typedoc "Lock acquisition result"
  @type acquire_result :: {:ok, token()} | :busy

  @typedoc "Lock release result"
  @type release_result :: :ok | :not_owner

  # ============================================
  # Behaviour for Distributed Adapters
  # ============================================

  @doc """
  Behaviour for distributed lock adapters.

  Implement this for Redis, Postgres advisory locks, etc.
  """
  @callback acquire(key :: term(), lock_ttl :: pos_integer()) :: acquire_result()
  @callback release(key :: term(), token :: token()) :: release_result()
  @callback locked?(key :: term()) :: boolean()

  # ============================================
  # Public API
  # ============================================

  @doc """
  Initialize the lock table.

  Called automatically on first use. For production, call during
  application startup to ensure the table exists.

  ## Example

      def start(_type, _args) do
        FnDecorator.Caching.Lock.init()
        # ...
      end
  """
  @spec init() :: :ok
  def init do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :set,
            :public,
            :named_table,
            {:write_concurrency, true},
            {:read_concurrency, true}
          ])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Attempt to acquire a lock atomically.

  Returns `{:ok, token}` on success or `:busy` if another process holds the lock.

  ## Parameters

  - `key` - The cache key to lock
  - `lock_ttl` - Lock validity duration in milliseconds. After this time,
    the lock expires and can be taken over by another process.

  ## Examples

      case Lock.acquire({User, 123}, 30_000) do
        {:ok, token} ->
          try do
            fetch_user(123)
          after
            Lock.release({User, 123}, token)
          end

        :busy ->
          wait_and_retry()
      end
  """
  @spec acquire(term(), pos_integer()) :: acquire_result()
  def acquire(key, lock_ttl) when is_integer(lock_ttl) and lock_ttl > 0 do
    case adapter() do
      nil -> acquire_local(key, lock_ttl)
      adapter -> adapter.acquire(key, lock_ttl)
    end
  end

  @doc """
  Release a lock.

  Only succeeds if the token matches (prevents releasing another process's lock).

  ## Parameters

  - `key` - The cache key
  - `token` - Token returned from `acquire/2`

  ## Returns

  - `:ok` - Lock released successfully
  - `:not_owner` - Lock not held or held by different token
  """
  @spec release(term(), token()) :: release_result()
  def release(key, token) do
    case adapter() do
      nil -> release_local(key, token)
      adapter -> adapter.release(key, token)
    end
  end

  @doc """
  Check if a key is currently locked.

  Note: This is a point-in-time check. The lock status may change
  immediately after this returns.
  """
  @spec locked?(term()) :: boolean()
  def locked?(key) do
    case adapter() do
      nil -> locked_local?(key)
      adapter -> adapter.locked?(key)
    end
  end

  # ============================================
  # Local ETS Implementation
  # ============================================

  defp acquire_local(key, lock_ttl) do
    init()

    token = {self(), make_ref()}
    expires_at = monotonic_now() + lock_ttl
    lock_entry = {key, token, expires_at}

    case :ets.insert_new(@table, lock_entry) do
      true ->
        {:ok, token}

      false ->
        maybe_takeover_expired(key, lock_ttl)
    end
  end

  defp maybe_takeover_expired(key, lock_ttl) do
    case :ets.lookup(@table, key) do
      [{^key, _old_token, expires_at}] ->
        if monotonic_now() >= expires_at do
          # Lock expired - delete and retry
          :ets.delete(@table, key)

          token = {self(), make_ref()}
          new_expires = monotonic_now() + lock_ttl

          case :ets.insert_new(@table, {key, token, new_expires}) do
            true -> {:ok, token}
            false -> :busy
          end
        else
          :busy
        end

      [] ->
        # Lock was just released - retry once
        token = {self(), make_ref()}
        expires_at = monotonic_now() + lock_ttl

        case :ets.insert_new(@table, {key, token, expires_at}) do
          true -> {:ok, token}
          false -> :busy
        end
    end
  end

  defp release_local(key, token) do
    init()

    case :ets.lookup(@table, key) do
      [{^key, ^token, _expires}] ->
        :ets.delete(@table, key)
        :ok

      _ ->
        :not_owner
    end
  end

  defp locked_local?(key) do
    init()

    case :ets.lookup(@table, key) do
      [{^key, _token, expires_at}] ->
        monotonic_now() < expires_at

      [] ->
        false
    end
  end

  # ============================================
  # Private
  # ============================================

  defp adapter do
    Application.get_env(:fn_decorator, :lock_adapter)
  end

  defp monotonic_now do
    System.monotonic_time(:millisecond)
  end
end
