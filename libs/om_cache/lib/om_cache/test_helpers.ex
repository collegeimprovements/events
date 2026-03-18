defmodule OmCache.TestHelpers do
  @moduledoc """
  Testing utilities for cache operations.

  Provides helpers for:
  - Setting up test caches with automatic cleanup
  - Asserting cache state
  - Seeding test data
  - Simulating cache misses

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
          assert_cache_size(cache, 1)
        end
      end

  ## Configuration

  In `config/test.exs`, use the null adapter to disable caching:

      config :my_app, MyApp.Cache,
        adapter: Nebulex.Adapters.Nil
  """

  @doc """
  Sets up a test cache with automatic cleanup.

  Clears the cache before and after each test.

  ## Examples

      setup do
        setup_test_cache(MyApp.Cache)
      end

      # Returns %{cache: MyApp.Cache}
  """
  @spec setup_test_cache(module(), keyword()) :: %{cache: module()}
  def setup_test_cache(cache, opts \\ []) do
    try do
      cache.delete_all(nil, opts)
    rescue
      _ -> :ok
    end

    ExUnit.Callbacks.on_exit(fn ->
      try do
        cache.delete_all(nil, opts)
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
      cache.delete_all(nil, opts)
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
  Asserts that a key exists in cache.

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
  Simulates cache miss by deleting key before running the function.

  ## Examples

      simulate_miss(MyApp.Cache, {User, 123}, fn ->
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
end
