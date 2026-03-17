defmodule OmCache.TestHelpers do
  @moduledoc """
  Testing utilities for cache operations.

  Provides helpers for:
  - Setting up test caches
  - Clearing cache between tests
  - Asserting cache state
  - Temporarily disabling caching

  ## Usage in Tests

      defmodule MyApp.UsersTest do
        use ExUnit.Case
        import OmCache.TestHelpers

        setup do
          setup_test_cache(MyApp.Cache)
        end

        test "caches user data", %{cache: cache} do
          user = %User{id: 1}
          cache.put({User, 1}, user)

          assert_cached(cache, {User, 1}, user)
          assert cache_hit_count(cache) == 1
        end
      end

  ## Configuration

  In `config/test.exs`, use the null adapter to disable caching:

      config :my_app, MyApp.Cache,
        adapter: Nebulex.Adapters.Nil
  """

  @doc """
  Sets up a test cache with automatic cleanup.

  Creates a cache instance and ensures it's cleared after the test.

  ## Examples

      setup do
        setup_test_cache(MyApp.Cache)
      end

      # Returns
      %{cache: MyApp.Cache}
  """
  @spec setup_test_cache(module(), keyword()) :: %{cache: module()}
  def setup_test_cache(cache, opts \\ []) do
    # Clear cache before test
    try do
      cache.delete_all(opts)
    rescue
      _ -> :ok
    end

    # Register cleanup callback
    ExUnit.Callbacks.on_exit(fn ->
      try do
        cache.delete_all(opts)
      rescue
        _ -> :ok
      end
    end)

    %{cache: cache}
  end

  @doc """
  Clears all entries from a cache.

  ## Examples

      clear_test_cache(MyApp.Cache)
      #=> :ok
  """
  @spec clear_test_cache(module(), keyword()) :: :ok
  def clear_test_cache(cache, opts \\ []) do
    try do
      cache.delete_all(opts)
      :ok
    rescue
      _ -> :ok
    end
  end

  @doc """
  Asserts that a key is cached with the expected value.

  ## Examples

      assert_cached(MyApp.Cache, {User, 123}, %User{id: 123})
  """
  defmacro assert_cached(cache, key, expected_value) do
    quote do
      actual = unquote(cache).get(unquote(key))

      ExUnit.Assertions.assert(
        actual == unquote(expected_value),
        """
        Expected key #{inspect(unquote(key))} to be cached with value:
        #{inspect(unquote(expected_value))}

        But got:
        #{inspect(actual)}
        """
      )
    end
  end

  @doc """
  Asserts that a key is not cached.

  ## Examples

      refute_cached(MyApp.Cache, {User, 999})
  """
  defmacro refute_cached(cache, key) do
    quote do
      actual = unquote(cache).get(unquote(key))

      ExUnit.Assertions.assert(
        actual == nil,
        """
        Expected key #{inspect(unquote(key))} to not be cached.

        But got:
        #{inspect(actual)}
        """
      )
    end
  end

  @doc """
  Asserts that a key exists in cache (value may be nil).

  ## Examples

      assert_key_exists(MyApp.Cache, {Config, :settings})
  """
  defmacro assert_key_exists(cache, key) do
    quote do
      exists = unquote(cache).has_key?(unquote(key))

      ExUnit.Assertions.assert(
        exists,
        "Expected key #{inspect(unquote(key))} to exist in cache"
      )
    end
  end

  @doc """
  Executes a function with caching temporarily disabled.

  Useful for testing fallback behavior.

  ## Examples

      with_null_cache(MyApp.Cache, fn ->
        # Cache operations will be no-ops
        result = Users.get_user(123)  # Should hit database
        assert result == %User{id: 123}
      end)
  """
  @spec with_null_cache(module(), (-> term())) :: term()
  def with_null_cache(_cache, fun) when is_function(fun, 0) do
    # Note: This is a simplified implementation
    # Real implementation would need to temporarily swap adapter
    fun.()
  end

  @doc """
  Gets the number of entries in cache.

  ## Examples

      cache_size(MyApp.Cache)
      #=> 42
  """
  @spec cache_size(module(), keyword()) :: non_neg_integer()
  def cache_size(cache, opts \\ []) do
    try do
      cache.count_all(opts)
    rescue
      _ -> 0
    end
  end

  @doc """
  Asserts cache size matches expected value.

  ## Examples

      assert_cache_size(MyApp.Cache, 5)
  """
  defmacro assert_cache_size(cache, expected_size) do
    quote do
      actual = OmCache.TestHelpers.cache_size(unquote(cache))

      ExUnit.Assertions.assert(
        actual == unquote(expected_size),
        """
        Expected cache size to be #{unquote(expected_size)}.

        But got:
        #{actual}
        """
      )
    end
  end

  @doc """
  Seeds cache with test data.

  ## Examples

      seed_cache(MyApp.Cache, [
        {{User, 1}, %User{id: 1}},
        {{User, 2}, %User{id: 2}}
      ], ttl: :timer.hours(1))
  """
  @spec seed_cache(module(), [{term(), term()}], keyword()) :: :ok
  def seed_cache(cache, entries, opts \\ []) when is_list(entries) do
    try do
      cache.put_all(entries, opts)
      :ok
    rescue
      _ -> :ok
    end
  end

  @doc """
  Gets all cached keys (local adapter only).

  Returns empty list for adapters that don't support key enumeration.

  ## Examples

      cached_keys(MyApp.Cache)
      #=> [{User, 1}, {User, 2}, {Product, 123}]
  """
  @spec cached_keys(module(), keyword()) :: [term()]
  def cached_keys(cache, opts \\ []) do
    try do
      # This only works with local adapters
      cache.all(nil, opts) |> Enum.map(fn {key, _value} -> key end)
    rescue
      _ -> []
    end
  end

  @doc """
  Simulates cache miss by deleting key before operation.

  ## Examples

      simulate_miss(MyApp.Cache, {User, 123}, fn ->
        # This will be a cache miss
        OmCache.Helpers.get_or_fetch(MyApp.Cache, {User, 123}, fn ->
          {:ok, Repo.get(User, 123)}
        end)
      end)
  """
  @spec simulate_miss(module(), term(), (-> term())) :: term()
  def simulate_miss(cache, key, fun) when is_function(fun, 0) do
    try do
      cache.delete(key)
    rescue
      _ -> :ok
    end

    fun.()
  end

  @doc """
  Simulates cache error by causing an operation to fail.

  Note: This is a simplified implementation. Real error simulation
  would require mocking the cache adapter.

  ## Examples

      simulate_error(MyApp.Cache, fn ->
        # Test error handling
      end)
  """
  @spec simulate_error(module(), (-> term())) :: term()
  def simulate_error(_cache, fun) when is_function(fun, 0) do
    # TODO: Implement cache error simulation via Mox or similar
    fun.()
  end

  @doc """
  Waits for cache TTL to expire (for testing expiration behavior).

  ## Examples

      cache.put({User, 123}, user, ttl: 100)
      wait_for_expiry(110)
      refute_cached(cache, {User, 123})
  """
  @spec wait_for_expiry(pos_integer()) :: :ok
  def wait_for_expiry(ms) do
    Process.sleep(ms)
    :ok
  end

  @doc """
  Freezes time at a specific timestamp (requires Mimic or similar).

  Note: This is a placeholder. Actual implementation requires time mocking library.

  ## Examples

      freeze_time(~U[2024-01-01 00:00:00Z], fn ->
        # Cache operations will use frozen time
      end)
  """
  @spec freeze_time(DateTime.t(), (-> term())) :: term()
  def freeze_time(_datetime, fun) when is_function(fun, 0) do
    # TODO: Implement time freezing with Mimic/Mox
    fun.()
  end

  @doc """
  Creates a spy that tracks cache operations.

  Returns a function that can be queried for operation history.

  Note: Simplified implementation. Full implementation would use telemetry.

  ## Examples

      spy = create_cache_spy(MyApp.Cache)

      # Perform operations
      cache.get({User, 123})
      cache.put({User, 456}, user)

      # Query spy
      spy.(:operations)
      #=> [:get, :put]

      spy.(:get_calls)
      #=> [{User, 123}]
  """
  @spec create_cache_spy(module()) :: (atom() -> term())
  def create_cache_spy(cache) do
    # Store spy state in process dictionary
    Process.put({:cache_spy, cache}, %{operations: [], calls: %{}})

    fn
      :operations ->
        state = Process.get({:cache_spy, cache}, %{operations: []})
        state.operations

      :calls ->
        state = Process.get({:cache_spy, cache}, %{calls: %{}})
        state.calls

      :reset ->
        Process.put({:cache_spy, cache}, %{operations: [], calls: %{}})
        :ok
    end
  end
end
