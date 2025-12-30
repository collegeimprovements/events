defmodule FnDecorator.Caching.Adapters.ETSTest do
  use ExUnit.Case, async: false

  # Define test cache
  defmodule TestCache do
    use FnDecorator.Caching.Adapters.ETS, table: :ets_adapter_test
  end

  setup do
    TestCache.init()
    TestCache.clear()
    :ok
  end

  describe "get/1 and put/3" do
    test "stores and retrieves values" do
      TestCache.put({User, 1}, %{name: "Alice"}, ttl: 60_000)

      assert TestCache.get({User, 1}) == %{name: "Alice"}
    end

    test "returns nil for missing keys" do
      assert TestCache.get({User, 999}) == nil
    end

    test "handles various key types" do
      TestCache.put(:atom_key, "value1", ttl: 60_000)
      TestCache.put("string_key", "value2", ttl: 60_000)
      TestCache.put({:tuple, :key}, "value3", ttl: 60_000)
      TestCache.put({User, 1, :nested}, "value4", ttl: 60_000)

      assert TestCache.get(:atom_key) == "value1"
      assert TestCache.get("string_key") == "value2"
      assert TestCache.get({:tuple, :key}) == "value3"
      assert TestCache.get({User, 1, :nested}) == "value4"
    end

    test "respects TTL expiration" do
      TestCache.put({User, 1}, "value", ttl: 1)
      Process.sleep(10)

      assert TestCache.get({User, 1}) == nil
    end

    test "works without TTL" do
      TestCache.put({User, 1}, "value", [])

      assert TestCache.get({User, 1}) == "value"
    end
  end

  describe "delete/1" do
    test "removes entry" do
      TestCache.put({User, 1}, "value", ttl: 60_000)
      TestCache.delete({User, 1})

      assert TestCache.get({User, 1}) == nil
    end

    test "succeeds for non-existent key" do
      assert TestCache.delete({User, 999}) == :ok
    end
  end

  describe "get!/1" do
    test "returns value when exists" do
      TestCache.put({User, 1}, "value", ttl: 60_000)

      assert TestCache.get!({User, 1}) == "value"
    end

    test "raises KeyError when missing" do
      assert_raise KeyError, fn ->
        TestCache.get!({User, 999})
      end
    end
  end

  describe "exists?/1" do
    test "returns true for existing key" do
      TestCache.put({User, 1}, "value", ttl: 60_000)

      assert TestCache.exists?({User, 1}) == true
    end

    test "returns false for missing key" do
      assert TestCache.exists?({User, 999}) == false
    end

    test "returns false for expired key" do
      TestCache.put({User, 1}, "value", ttl: 1)
      Process.sleep(10)

      assert TestCache.exists?({User, 1}) == false
    end
  end

  describe "touch/2" do
    test "updates TTL for existing key" do
      TestCache.put({User, 1}, "value", ttl: 10)
      TestCache.touch({User, 1}, ttl: 60_000)

      Process.sleep(20)
      assert TestCache.get({User, 1}) == "value"
    end

    test "returns error for missing key" do
      assert TestCache.touch({User, 999}, ttl: 60_000) == {:error, :not_found}
    end
  end

  describe "all/1" do
    setup do
      TestCache.put({User, 1}, %{id: 1}, ttl: 60_000)
      TestCache.put({User, 2}, %{id: 2}, ttl: 60_000)
      TestCache.put({Admin, 1}, %{id: 1}, ttl: 60_000)
      TestCache.put({:session, "abc"}, %{user_id: 1}, ttl: 60_000)
      :ok
    end

    test "returns all entries for :all" do
      entries = TestCache.all(:all)

      assert length(entries) == 4
    end

    test "filters by pattern" do
      entries = TestCache.all({User, :_})

      assert length(entries) == 2
      assert {{User, 1}, %{id: 1}} in entries
      assert {{User, 2}, %{id: 2}} in entries
    end

    test "returns empty list when no matches" do
      assert TestCache.all({Unknown, :_}) == []
    end

    test "excludes expired entries" do
      TestCache.put({User, 3}, %{id: 3}, ttl: 1)
      Process.sleep(10)

      entries = TestCache.all({User, :_})
      keys = Enum.map(entries, fn {k, _} -> k end)

      refute {User, 3} in keys
    end
  end

  describe "keys/1" do
    setup do
      TestCache.put({User, 1}, "v1", ttl: 60_000)
      TestCache.put({User, 2}, "v2", ttl: 60_000)
      TestCache.put({Admin, 1}, "v3", ttl: 60_000)
      :ok
    end

    test "returns all keys for :all" do
      keys = TestCache.keys(:all)

      assert length(keys) == 3
      assert {User, 1} in keys
      assert {User, 2} in keys
      assert {Admin, 1} in keys
    end

    test "filters by pattern" do
      keys = TestCache.keys({User, :_})

      assert length(keys) == 2
      assert {User, 1} in keys
      assert {User, 2} in keys
    end
  end

  describe "values/1" do
    setup do
      TestCache.put({User, 1}, %{name: "Alice"}, ttl: 60_000)
      TestCache.put({User, 2}, %{name: "Bob"}, ttl: 60_000)
      TestCache.put({Admin, 1}, %{name: "Admin"}, ttl: 60_000)
      :ok
    end

    test "returns all values for :all" do
      values = TestCache.values(:all)

      assert length(values) == 3
    end

    test "filters by pattern" do
      values = TestCache.values({User, :_})

      assert length(values) == 2
      assert %{name: "Alice"} in values
      assert %{name: "Bob"} in values
    end
  end

  describe "count/1" do
    setup do
      TestCache.put({User, 1}, "v1", ttl: 60_000)
      TestCache.put({User, 2}, "v2", ttl: 60_000)
      TestCache.put({Admin, 1}, "v3", ttl: 60_000)
      :ok
    end

    test "counts all entries for :all" do
      assert TestCache.count(:all) == 3
    end

    test "counts by pattern" do
      assert TestCache.count({User, :_}) == 2
      assert TestCache.count({Admin, :_}) == 1
      assert TestCache.count({Unknown, :_}) == 0
    end
  end

  describe "delete_all/1" do
    setup do
      TestCache.put({User, 1}, "v1", ttl: 60_000)
      TestCache.put({User, 2}, "v2", ttl: 60_000)
      TestCache.put({Admin, 1}, "v3", ttl: 60_000)
      :ok
    end

    test "deletes all entries for :all" do
      assert {:ok, 3} = TestCache.delete_all(:all)
      assert TestCache.count(:all) == 0
    end

    test "deletes by pattern" do
      assert {:ok, 2} = TestCache.delete_all({User, :_})
      assert TestCache.count(:all) == 1
      assert TestCache.exists?({Admin, 1}) == true
    end

    test "returns 0 when no matches" do
      assert {:ok, 0} = TestCache.delete_all({Unknown, :_})
    end
  end

  describe "get_all/1" do
    setup do
      TestCache.put({User, 1}, %{id: 1}, ttl: 60_000)
      TestCache.put({User, 2}, %{id: 2}, ttl: 60_000)
      :ok
    end

    test "returns map of found entries" do
      result = TestCache.get_all([{User, 1}, {User, 2}])

      assert result == %{
               {User, 1} => %{id: 1},
               {User, 2} => %{id: 2}
             }
    end

    test "omits missing keys" do
      result = TestCache.get_all([{User, 1}, {User, 999}])

      assert result == %{{User, 1} => %{id: 1}}
    end

    test "returns empty map when none found" do
      result = TestCache.get_all([{User, 998}, {User, 999}])

      assert result == %{}
    end
  end

  describe "put_all/2" do
    test "stores multiple entries" do
      TestCache.put_all(
        [
          {{User, 1}, %{id: 1}},
          {{User, 2}, %{id: 2}}
        ],
        ttl: 60_000
      )

      assert TestCache.get({User, 1}) == %{id: 1}
      assert TestCache.get({User, 2}) == %{id: 2}
    end

    test "respects TTL" do
      TestCache.put_all(
        [{{User, 1}, "v1"}, {{User, 2}, "v2"}],
        ttl: 1
      )

      Process.sleep(10)

      assert TestCache.get({User, 1}) == nil
      assert TestCache.get({User, 2}) == nil
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      TestCache.put({User, 1}, "v1", ttl: 60_000)
      TestCache.put({User, 2}, "v2", ttl: 60_000)

      TestCache.clear()

      assert TestCache.count(:all) == 0
    end
  end

  describe "stream/1" do
    setup do
      for i <- 1..100 do
        TestCache.put({User, i}, %{id: i}, ttl: 60_000)
      end

      :ok
    end

    test "streams all entries for :all" do
      count =
        TestCache.stream(:all)
        |> Enum.count()

      assert count == 100
    end

    test "streams by pattern" do
      # Add some admin entries
      TestCache.put({Admin, 1}, %{id: 1}, ttl: 60_000)
      TestCache.put({Admin, 2}, %{id: 2}, ttl: 60_000)

      admin_count =
        TestCache.stream({Admin, :_})
        |> Enum.count()

      assert admin_count == 2
    end

    test "can be used with Stream operations" do
      result =
        TestCache.stream({User, :_})
        |> Stream.filter(fn {{User, id}, _} -> id <= 10 end)
        |> Stream.map(fn {_, v} -> v.id end)
        |> Enum.sort()

      assert result == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    end
  end

  describe "complex patterns" do
    setup do
      TestCache.put({User, 1, :profile}, %{type: :profile}, ttl: 60_000)
      TestCache.put({User, 1, :settings}, %{type: :settings}, ttl: 60_000)
      TestCache.put({User, 2, :profile}, %{type: :profile}, ttl: 60_000)
      TestCache.put({Admin, 1, :profile}, %{type: :profile}, ttl: 60_000)
      :ok
    end

    test "matches three-element tuples" do
      entries = TestCache.all({User, :_, :profile})

      assert length(entries) == 2
    end

    test "wildcard in middle position" do
      entries = TestCache.all({User, :_, :_})

      assert length(entries) == 3
    end

    test "wildcard in first position" do
      entries = TestCache.all({:_, :_, :profile})

      assert length(entries) == 3
    end
  end

  describe "tags/1" do
    test "returns empty list for key without tags" do
      TestCache.put({User, 1}, "value", ttl: 60_000)

      assert TestCache.tags({User, 1}) == []
    end

    test "returns tags for key with tags" do
      TestCache.put({User, 1}, "value", ttl: 60_000, tags: [:users, :admins])

      tags = TestCache.tags({User, 1})
      assert :users in tags
      assert :admins in tags
      assert length(tags) == 2
    end

    test "returns empty list for non-existent key" do
      assert TestCache.tags({User, 999}) == []
    end
  end

  describe "keys_by_tag/1" do
    setup do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      TestCache.put({User, 2}, "bob", ttl: 60_000, tags: [:users, :admins])
      TestCache.put({Session, "abc"}, "session", ttl: 60_000, tags: [:sessions])
      :ok
    end

    test "returns all keys with given tag" do
      keys = TestCache.keys_by_tag(:users)

      assert length(keys) == 2
      assert {User, 1} in keys
      assert {User, 2} in keys
    end

    test "returns keys matching specific tag" do
      keys = TestCache.keys_by_tag(:admins)

      assert length(keys) == 1
      assert {User, 2} in keys
    end

    test "returns empty list for unknown tag" do
      assert TestCache.keys_by_tag(:unknown) == []
    end
  end

  describe "count_by_tag/1" do
    setup do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      TestCache.put({User, 2}, "bob", ttl: 60_000, tags: [:users, :admins])
      TestCache.put({User, 3}, "charlie", ttl: 60_000, tags: [:users])
      :ok
    end

    test "counts keys with tag" do
      assert TestCache.count_by_tag(:users) == 3
      assert TestCache.count_by_tag(:admins) == 1
    end

    test "returns 0 for unknown tag" do
      assert TestCache.count_by_tag(:unknown) == 0
    end
  end

  describe "invalidate_tag/1" do
    setup do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      TestCache.put({User, 2}, "bob", ttl: 60_000, tags: [:users, :admins])
      TestCache.put({Session, "abc"}, "session", ttl: 60_000, tags: [:sessions])
      :ok
    end

    test "deletes all entries with tag" do
      {:ok, count} = TestCache.invalidate_tag(:users)

      assert count == 2
      assert TestCache.get({User, 1}) == nil
      assert TestCache.get({User, 2}) == nil
      # Session entry should remain
      assert TestCache.get({Session, "abc"}) == "session"
    end

    test "returns 0 for unknown tag" do
      {:ok, count} = TestCache.invalidate_tag(:unknown)
      assert count == 0
    end

    test "also removes from tags table" do
      TestCache.invalidate_tag(:users)

      assert TestCache.keys_by_tag(:users) == []
    end
  end

  describe "invalidate_tags/1" do
    setup do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      TestCache.put({User, 2}, "bob", ttl: 60_000, tags: [:users, :admins])
      TestCache.put({Session, "abc"}, "session", ttl: 60_000, tags: [:sessions])
      :ok
    end

    test "deletes entries matching any of the tags" do
      {:ok, count} = TestCache.invalidate_tags([:users, :sessions])

      # User 1 and 2 (tagged :users) + Session (tagged :sessions) = 3 unique entries
      assert count == 3
      assert TestCache.get({User, 1}) == nil
      assert TestCache.get({User, 2}) == nil
      assert TestCache.get({Session, "abc"}) == nil
    end

    test "counts each entry only once" do
      # User 2 has both :users and :admins tags
      {:ok, count} = TestCache.invalidate_tags([:users, :admins])

      # Should be 2 (User 1 + User 2), not 3 (User 1 + User 2 via :users + User 2 via :admins)
      assert count == 2
    end
  end

  describe "tag cleanup on delete" do
    test "removes tag mapping when key is deleted" do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      assert TestCache.keys_by_tag(:users) == [{User, 1}]

      TestCache.delete({User, 1})

      assert TestCache.keys_by_tag(:users) == []
    end

    test "removes tag mapping when key expires" do
      TestCache.put({User, 1}, "alice", ttl: 1, tags: [:users])
      Process.sleep(10)

      # Access triggers cleanup
      assert TestCache.get({User, 1}) == nil
      assert TestCache.keys_by_tag(:users) == []
    end
  end

  describe "put updates tags" do
    test "replaces tags when key is updated" do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: [:users])
      assert TestCache.keys_by_tag(:users) == [{User, 1}]

      TestCache.put({User, 1}, "alice v2", ttl: 60_000, tags: [:vips])

      assert TestCache.keys_by_tag(:users) == []
      assert TestCache.keys_by_tag(:vips) == [{User, 1}]
    end
  end

  describe "string tags" do
    test "works with string tags" do
      TestCache.put({User, 1}, "alice", ttl: 60_000, tags: ["org:acme", "team:engineering"])

      assert TestCache.keys_by_tag("org:acme") == [{User, 1}]
      assert TestCache.keys_by_tag("team:engineering") == [{User, 1}]

      {:ok, count} = TestCache.invalidate_tag("org:acme")
      assert count == 1
    end
  end

  describe "warm/2" do
    defmodule TestWarmer do
      use FnDecorator.Caching.Warmable

      def entries do
        [
          {{User, 1}, %{name: "Alice"}},
          {{User, 2}, %{name: "Bob"}},
          {{User, 3}, %{name: "Charlie"}}
        ]
      end

      def opts do
        [ttl: 60_000]
      end
    end

    defmodule TestWarmerNoOpts do
      use FnDecorator.Caching.Warmable

      def entries do
        [
          {{Admin, 1}, %{role: "admin"}}
        ]
      end
    end

    test "warms cache from module implementing Warmable" do
      :ok = TestCache.warm(TestWarmer)

      assert TestCache.get({User, 1}) == %{name: "Alice"}
      assert TestCache.get({User, 2}) == %{name: "Bob"}
      assert TestCache.get({User, 3}) == %{name: "Charlie"}
    end

    test "uses opts from Warmable module" do
      :ok = TestCache.warm(TestWarmer)

      # Since TTL is 60_000, entry should still exist
      assert TestCache.exists?({User, 1}) == true
    end

    test "works with Warmable module without opts callback" do
      :ok = TestCache.warm(TestWarmerNoOpts, ttl: 30_000)

      assert TestCache.get({Admin, 1}) == %{role: "admin"}
    end

    test "warms cache from function" do
      entries_fn = fn ->
        [
          {{Session, "a"}, %{active: true}},
          {{Session, "b"}, %{active: false}}
        ]
      end

      :ok = TestCache.warm(entries_fn, ttl: 60_000)

      assert TestCache.get({Session, "a"}) == %{active: true}
      assert TestCache.get({Session, "b"}) == %{active: false}
    end

    test "warms cache from list of entries" do
      entries = [
        {{Role, "admin"}, %{permissions: [:read, :write]}},
        {{Role, "user"}, %{permissions: [:read]}}
      ]

      :ok = TestCache.warm(entries, ttl: 60_000)

      assert TestCache.get({Role, "admin"}) == %{permissions: [:read, :write]}
      assert TestCache.get({Role, "user"}) == %{permissions: [:read]}
    end

    test "allows overriding opts from caller" do
      # Warmer has ttl: 60_000, but we override with ttl: 1
      :ok = TestCache.warm(TestWarmer, ttl: 1)

      Process.sleep(10)
      assert TestCache.get({User, 1}) == nil
    end

    test "supports tags in warming" do
      entries = [
        {{User, 100}, "value100"},
        {{User, 101}, "value101"}
      ]

      :ok = TestCache.warm(entries, ttl: 60_000, tags: [:warmed])

      assert TestCache.keys_by_tag(:warmed) |> length() == 2
    end
  end
end
