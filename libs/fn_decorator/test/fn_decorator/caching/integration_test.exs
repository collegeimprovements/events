defmodule FnDecorator.Caching.IntegrationTest do
  @moduledoc """
  Integration tests for caching decorators with ETS adapter.

  Tests the full flow: decorator → runtime → store.
  """
  use ExUnit.Case, async: false

  # Define test cache using ETS adapter
  defmodule TestCache do
    use FnDecorator.Caching.Adapters.ETS, table: :integration_test_cache
  end

  # Define modules using decorators
  defmodule UserService do
    use FnDecorator
    alias FnDecorator.Caching.IntegrationTest.TestCache

    @decorate cacheable(
      store: [cache: TestCache, key: {:user, id}, ttl: 100],
      prevent_thunder_herd: false
    )
    def get_user(id) do
      send(self(), {:called, :get_user, id})
      {:ok, %{id: id, name: "User #{id}"}}
    end

    @decorate cacheable(
      store: [
        cache: TestCache,
        key: {:user_conditional, id},
        ttl: 100,
        only_if: &match?({:ok, _}, &1)
      ],
      prevent_thunder_herd: false
    )
    def get_user_conditional(id) do
      send(self(), {:called, :get_user_conditional, id})
      if id > 0, do: {:ok, %{id: id}}, else: {:error, :not_found}
    end

    @decorate cache_put(cache: TestCache, keys: [{:user, user.id}], ttl: 100)
    def update_user(user, attrs) do
      send(self(), {:called, :update_user, user.id})
      {:ok, Map.merge(user, attrs)}
    end

    @decorate cache_put(
      cache: TestCache,
      keys: [{:user, user.id}],
      ttl: 100,
      match: &match_ok/1
    )
    def update_user_conditional(user, attrs) do
      send(self(), {:called, :update_user_conditional, user.id})
      if attrs[:valid], do: {:ok, Map.merge(user, attrs)}, else: {:error, :invalid}
    end

    defp match_ok({:ok, user}), do: {true, user}
    defp match_ok(_), do: false

    @decorate cache_evict(cache: TestCache, keys: [{:user, id}])
    def delete_user(id) do
      send(self(), {:called, :delete_user, id})
      :ok
    end

    @decorate cache_evict(cache: TestCache, match: {:user, :_})
    def clear_all_users do
      send(self(), {:called, :clear_all_users})
      :ok
    end

    @decorate cache_evict(
      cache: TestCache,
      keys: [{:user, id}],
      only_if: &match?({:ok, _}, &1)
    )
    def soft_delete_user(id) do
      send(self(), {:called, :soft_delete_user, id})
      if id > 0, do: {:ok, :deleted}, else: {:error, :not_found}
    end

    @decorate cache_evict(cache: TestCache, keys: [{:session, token}], before_invocation: true)
    def logout(token) do
      send(self(), {:called, :logout, token})
      :ok
    end
  end

  setup do
    TestCache.start_link()
    TestCache.clear()
    :ok
  end

  describe "@cacheable decorator" do
    test "caches function result" do
      # First call - executes function
      assert {:ok, %{id: 1, name: "User 1"}} = UserService.get_user(1)
      assert_received {:called, :get_user, 1}

      # Second call - returns cached value
      assert {:ok, %{id: 1, name: "User 1"}} = UserService.get_user(1)
      refute_received {:called, :get_user, 1}
    end

    test "different keys cache separately" do
      assert {:ok, %{id: 1}} = UserService.get_user(1)
      assert {:ok, %{id: 2}} = UserService.get_user(2)

      assert_received {:called, :get_user, 1}
      assert_received {:called, :get_user, 2}

      # Both cached now
      UserService.get_user(1)
      UserService.get_user(2)
      refute_received {:called, :get_user, _}
    end

    test "respects only_if condition - caches ok results" do
      assert {:ok, %{id: 1}} = UserService.get_user_conditional(1)
      assert_received {:called, :get_user_conditional, 1}

      # Cached
      UserService.get_user_conditional(1)
      refute_received {:called, :get_user_conditional, 1}
    end

    test "respects only_if condition - doesn't cache error results" do
      assert {:error, :not_found} = UserService.get_user_conditional(-1)
      assert_received {:called, :get_user_conditional, -1}

      # Not cached - calls again
      UserService.get_user_conditional(-1)
      assert_received {:called, :get_user_conditional, -1}
    end

    test "cache expires after TTL" do
      assert {:ok, _} = UserService.get_user(1)
      assert_received {:called, :get_user, 1}

      # Wait for TTL to expire
      Process.sleep(150)

      # Should call function again
      UserService.get_user(1)
      assert_received {:called, :get_user, 1}
    end
  end

  describe "@cache_put decorator" do
    test "always executes and updates cache" do
      user = %{id: 1, name: "Original"}

      # Put updates the cache
      assert {:ok, %{id: 1, name: "Original", role: :admin}} =
        UserService.update_user(user, %{role: :admin})
      assert_received {:called, :update_user, 1}

      # Now get_user returns cached value from put
      result = TestCache.get({:user, 1})
      assert result == {:ok, %{id: 1, name: "Original", role: :admin}}
    end

    test "respects match function - caches on success" do
      user = %{id: 1, name: "Test"}

      {:ok, _} = UserService.update_user_conditional(user, %{valid: true, status: :active})
      assert_received {:called, :update_user_conditional, 1}

      # Should be cached
      result = TestCache.get({:user, 1})
      assert result == %{id: 1, name: "Test", valid: true, status: :active}
    end

    test "respects match function - doesn't cache on failure" do
      user = %{id: 2, name: "Test"}

      {:error, :invalid} = UserService.update_user_conditional(user, %{valid: false})
      assert_received {:called, :update_user_conditional, 2}

      # Should NOT be cached
      assert TestCache.get({:user, 2}) == nil
    end
  end

  describe "@cache_evict decorator" do
    test "evicts specific key" do
      # Populate cache
      TestCache.put({:user, 1}, %{id: 1}, ttl: 10000)
      assert TestCache.get({:user, 1}) != nil

      # Evict
      assert :ok = UserService.delete_user(1)
      assert_received {:called, :delete_user, 1}

      # Should be evicted
      assert TestCache.get({:user, 1}) == nil
    end

    test "evicts by pattern" do
      # Populate cache with multiple users
      TestCache.put({:user, 1}, %{id: 1}, ttl: 10000)
      TestCache.put({:user, 2}, %{id: 2}, ttl: 10000)
      TestCache.put({:user, 3}, %{id: 3}, ttl: 10000)
      TestCache.put({:other, 1}, %{type: :other}, ttl: 10000)

      assert TestCache.count(:all) == 4

      # Evict all users
      assert :ok = UserService.clear_all_users()
      assert_received {:called, :clear_all_users}

      # All user entries should be evicted
      assert TestCache.get({:user, 1}) == nil
      assert TestCache.get({:user, 2}) == nil
      assert TestCache.get({:user, 3}) == nil

      # Other entries should remain
      assert TestCache.get({:other, 1}) != nil
    end

    test "respects only_if condition - evicts on success" do
      TestCache.put({:user, 1}, %{id: 1}, ttl: 10000)

      {:ok, :deleted} = UserService.soft_delete_user(1)
      assert_received {:called, :soft_delete_user, 1}

      # Should be evicted
      assert TestCache.get({:user, 1}) == nil
    end

    test "respects only_if condition - doesn't evict on failure" do
      TestCache.put({:user, -1}, %{id: -1}, ttl: 10000)

      {:error, :not_found} = UserService.soft_delete_user(-1)
      assert_received {:called, :soft_delete_user, -1}

      # Should NOT be evicted
      assert TestCache.get({:user, -1}) != nil
    end

    test "before_invocation evicts before function runs" do
      TestCache.put({:session, "token123"}, %{user_id: 1}, ttl: 10000)

      # Eviction happens before function body
      :ok = UserService.logout("token123")
      assert_received {:called, :logout, "token123"}

      # Should be evicted
      assert TestCache.get({:session, "token123"}) == nil
    end
  end

  describe "combined decorator flows" do
    test "cacheable + cache_evict invalidation" do
      # Cache a user
      {:ok, _user} = UserService.get_user(1)
      assert_received {:called, :get_user, 1}

      # Verify cached
      UserService.get_user(1)
      refute_received {:called, :get_user, 1}

      # Delete invalidates cache
      UserService.delete_user(1)
      assert_received {:called, :delete_user, 1}

      # Now get_user should call function again
      UserService.get_user(1)
      assert_received {:called, :get_user, 1}
    end

    test "cache_put updates existing cached value" do
      # Cache initial value
      {:ok, _} = UserService.get_user(1)
      assert_received {:called, :get_user, 1}

      # Update via cache_put
      user = %{id: 1, name: "User 1"}
      {:ok, _updated} = UserService.update_user(user, %{role: :admin})

      # The cache now has the updated value
      cached = TestCache.get({:user, 1})
      assert cached == {:ok, %{id: 1, name: "User 1", role: :admin}}
    end
  end
end
