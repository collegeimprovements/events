defmodule FnDecorator.Caching.Adapters.RedisTest do
  @moduledoc """
  Tests for the Redis cache adapter.

  Uses a mock Redis module to test without requiring an actual Redis server.
  """
  use ExUnit.Case, async: true

  # Mock Redis module that simulates Redix behavior using ETS
  defmodule MockRedix do
    def start_link do
      :ets.new(__MODULE__, [:set, :public, :named_table])
      {:ok, self()}
    end

    def command(_conn \\ __MODULE__, cmd) do
      case cmd do
        ["PING"] ->
          {:ok, "PONG"}

        ["GET", key] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, value, expires_at}] ->
              if expired?(expires_at) do
                :ets.delete(__MODULE__, key)
                {:ok, nil}
              else
                {:ok, value}
              end
            [] ->
              {:ok, nil}
          end

        ["PTTL", key] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, _value, nil}] ->
              {:ok, -1}  # No TTL

            [{^key, _value, expires_at}] ->
              if expired?(expires_at) do
                :ets.delete(__MODULE__, key)
                {:ok, -2}  # Key doesn't exist
              else
                {:ok, expires_at - System.monotonic_time(:millisecond)}
              end

            [] ->
              {:ok, -2}  # Key doesn't exist
          end

        ["SET", key, value] ->
          :ets.insert(__MODULE__, {key, value, nil})
          {:ok, "OK"}

        ["SET", key, value, "NX"] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, _, expires_at}] ->
              if expired?(expires_at) do
                :ets.insert(__MODULE__, {key, value, nil})
                {:ok, "OK"}
              else
                {:ok, nil}  # Key exists, don't set
              end

            [] ->
              :ets.insert(__MODULE__, {key, value, nil})
              {:ok, "OK"}
          end

        ["SET", key, value, "PX", ttl] ->
          expires_at = System.monotonic_time(:millisecond) + ttl
          :ets.insert(__MODULE__, {key, value, expires_at})
          {:ok, "OK"}

        ["SET", key, value, "PX", ttl, "NX"] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, _, old_expires_at}] ->
              if expired?(old_expires_at) do
                expires_at = System.monotonic_time(:millisecond) + ttl
                :ets.insert(__MODULE__, {key, value, expires_at})
                {:ok, "OK"}
              else
                {:ok, nil}  # Key exists, don't set
              end

            [] ->
              expires_at = System.monotonic_time(:millisecond) + ttl
              :ets.insert(__MODULE__, {key, value, expires_at})
              {:ok, "OK"}
          end

        ["DEL" | keys] ->
          count = Enum.count(keys, fn key ->
            case :ets.lookup(__MODULE__, key) do
              [{^key, _, _}] ->
                :ets.delete(__MODULE__, key)
                true
              [] ->
                false
            end
          end)
          {:ok, count}

        ["EXISTS", key] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, _, expires_at}] ->
              if expired?(expires_at) do
                :ets.delete(__MODULE__, key)
                {:ok, 0}
              else
                {:ok, 1}
              end
            [] ->
              {:ok, 0}
          end

        ["PEXPIRE", key, ttl] ->
          case :ets.lookup(__MODULE__, key) do
            [{^key, value, _}] ->
              expires_at = System.monotonic_time(:millisecond) + ttl
              :ets.insert(__MODULE__, {key, value, expires_at})
              {:ok, 1}
            [] ->
              {:ok, 0}
          end

        ["MGET" | keys] ->
          values = Enum.map(keys, fn key ->
            case :ets.lookup(__MODULE__, key) do
              [{^key, value, expires_at}] ->
                if expired?(expires_at), do: nil, else: value
              [] ->
                nil
            end
          end)
          {:ok, values}

        ["MEMORY", "USAGE", _pattern] ->
          {:ok, nil}  # Not supported in mock

        ["SCAN", cursor, "MATCH", pattern, "COUNT", _count] ->
          all_keys = :ets.tab2list(__MODULE__)
            |> Enum.reject(fn
              {{:set, _}, _} -> true  # Exclude sets
              {_, _, expires_at} -> expired?(expires_at)
            end)
            |> Enum.map(fn {k, _, _} -> k end)
            |> Enum.filter(&matches_glob?(&1, pattern))

          # Simple implementation: return all on first call
          if cursor == "0" do
            {:ok, ["0", all_keys]}
          else
            {:ok, ["0", []]}
          end

        # SET operations (Redis SETs, not SET command)
        ["SADD", set_key | members] ->
          current_members =
            case :ets.lookup(__MODULE__, {:set, set_key}) do
              [{{:set, ^set_key}, existing}] -> existing
              [] -> MapSet.new()
            end

          new_members = Enum.reduce(members, current_members, &MapSet.put(&2, &1))
          :ets.insert(__MODULE__, {{:set, set_key}, new_members})
          {:ok, length(members)}

        ["SMEMBERS", set_key] ->
          case :ets.lookup(__MODULE__, {:set, set_key}) do
            [{{:set, ^set_key}, members}] -> {:ok, MapSet.to_list(members)}
            [] -> {:ok, []}
          end

        ["SREM", set_key, member] ->
          case :ets.lookup(__MODULE__, {:set, set_key}) do
            [{{:set, ^set_key}, members}] ->
              if MapSet.member?(members, member) do
                new_members = MapSet.delete(members, member)
                if MapSet.size(new_members) == 0 do
                  :ets.delete(__MODULE__, {:set, set_key})
                else
                  :ets.insert(__MODULE__, {{:set, set_key}, new_members})
                end
                {:ok, 1}
              else
                {:ok, 0}
              end
            [] ->
              {:ok, 0}
          end

        _ ->
          {:error, "Unknown command: #{inspect(cmd)}"}
      end
    end

    defp expired?(nil), do: false
    defp expired?(expires_at), do: System.monotonic_time(:millisecond) > expires_at

    def pipeline(_conn \\ __MODULE__, commands) do
      results = Enum.map(commands, &command(&1))
      {:ok, results}
    end

    defp matches_glob?(key, pattern) do
      # Simple glob matching - just check prefix
      prefix = String.replace(pattern, "*", "")
      String.starts_with?(key, prefix)
    end

    def clear do
      :ets.delete_all_objects(__MODULE__)
    end
  end

  # Define test cache using Redis adapter with mock
  defmodule TestRedisCache do
    use FnDecorator.Caching.Adapters.Redis,
      redis: FnDecorator.Caching.Adapters.RedisTest.MockRedix,
      prefix: "test:"
  end

  setup do
    MockRedix.start_link()
    MockRedix.clear()
    :ok
  end

  describe "basic operations" do
    test "get returns nil for missing key" do
      assert TestRedisCache.get({:user, 1}) == nil
    end

    test "put and get" do
      :ok = TestRedisCache.put({:user, 1}, %{name: "Alice"})
      assert TestRedisCache.get({:user, 1}) == %{name: "Alice"}
    end

    test "put with ttl" do
      :ok = TestRedisCache.put({:user, 2}, %{name: "Bob"}, ttl: 100)
      assert TestRedisCache.get({:user, 2}) == %{name: "Bob"}

      Process.sleep(150)
      assert TestRedisCache.get({:user, 2}) == nil
    end

    test "delete removes key" do
      TestRedisCache.put({:user, 1}, %{name: "Alice"})
      assert TestRedisCache.get({:user, 1}) != nil

      :ok = TestRedisCache.delete({:user, 1})
      assert TestRedisCache.get({:user, 1}) == nil
    end
  end

  describe "single key operations" do
    test "get! raises on missing key" do
      assert_raise KeyError, fn ->
        TestRedisCache.get!({:missing, 999})
      end
    end

    test "get! returns value when present" do
      TestRedisCache.put({:user, 1}, "value")
      assert TestRedisCache.get!({:user, 1}) == "value"
    end

    test "exists? returns true for existing key" do
      TestRedisCache.put({:user, 1}, "value")
      assert TestRedisCache.exists?({:user, 1}) == true
    end

    test "exists? returns false for missing key" do
      assert TestRedisCache.exists?({:user, 999}) == false
    end

    test "touch updates TTL" do
      TestRedisCache.put({:user, 1}, "value", ttl: 50)

      # Touch with new TTL
      :ok = TestRedisCache.touch({:user, 1}, ttl: 200)

      # Should still exist after original TTL
      Process.sleep(100)
      assert TestRedisCache.exists?({:user, 1}) == true
    end

    test "touch returns error for missing key" do
      assert {:error, :not_found} = TestRedisCache.touch({:missing, 1}, ttl: 100)
    end
  end

  describe "bulk operations by pattern" do
    setup do
      TestRedisCache.put({:user, 1}, %{id: 1})
      TestRedisCache.put({:user, 2}, %{id: 2})
      TestRedisCache.put({:user, 3}, %{id: 3})
      TestRedisCache.put({:session, "abc"}, %{user_id: 1})
      :ok
    end

    test "keys returns all keys for :all pattern" do
      keys = TestRedisCache.keys(:all)
      assert length(keys) == 4
    end

    test "count returns count matching pattern" do
      assert TestRedisCache.count(:all) == 4
    end

    test "delete_all removes matching keys" do
      {:ok, count} = TestRedisCache.delete_all(:all)
      assert count == 4
      assert TestRedisCache.count(:all) == 0
    end

    test "all returns key-value pairs" do
      entries = TestRedisCache.all(:all)
      assert length(entries) == 4
    end

    test "values returns just values" do
      values = TestRedisCache.values(:all)
      assert length(values) == 4
    end
  end

  describe "bulk operations by keys" do
    test "get_all returns map of existing keys" do
      TestRedisCache.put({:user, 1}, "one")
      TestRedisCache.put({:user, 2}, "two")

      result = TestRedisCache.get_all([{:user, 1}, {:user, 2}, {:user, 99}])

      assert result[{:user, 1}] == "one"
      assert result[{:user, 2}] == "two"
      refute Map.has_key?(result, {:user, 99})
    end

    test "put_all writes multiple entries" do
      entries = [
        {{:user, 10}, "ten"},
        {{:user, 11}, "eleven"}
      ]

      :ok = TestRedisCache.put_all(entries)

      assert TestRedisCache.get({:user, 10}) == "ten"
      assert TestRedisCache.get({:user, 11}) == "eleven"
    end

    test "put_all with ttl" do
      entries = [{{:temp, 1}, "a"}, {{:temp, 2}, "b"}]

      :ok = TestRedisCache.put_all(entries, ttl: 100)

      assert TestRedisCache.get({:temp, 1}) == "a"

      Process.sleep(150)
      assert TestRedisCache.get({:temp, 1}) == nil
    end
  end

  describe "maintenance" do
    test "clear removes all entries" do
      TestRedisCache.put({:a, 1}, "a")
      TestRedisCache.put({:b, 2}, "b")

      :ok = TestRedisCache.clear()

      assert TestRedisCache.count(:all) == 0
    end
  end

  describe "serialization" do
    test "handles complex Elixir terms" do
      complex = %{
        list: [1, 2, 3],
        tuple: {:ok, "value"},
        nested: %{a: %{b: %{c: 1}}}
      }

      TestRedisCache.put(:complex, complex)
      assert TestRedisCache.get(:complex) == complex
    end

    test "handles atoms" do
      TestRedisCache.put(:key, :value)
      assert TestRedisCache.get(:key) == :value
    end

    test "handles pids and references" do
      ref = make_ref()
      TestRedisCache.put(:ref, ref)
      assert TestRedisCache.get(:ref) == ref
    end
  end

  describe "health checks" do
    test "ping returns :pong when healthy" do
      assert TestRedisCache.ping() == :pong
    end

    test "healthy? returns true when healthy" do
      assert TestRedisCache.healthy?() == true
    end
  end

  describe "stats" do
    test "returns stats map" do
      TestRedisCache.put({:user, 1}, "a")
      TestRedisCache.put({:user, 2}, "b")

      stats = TestRedisCache.stats()

      assert is_map(stats)
      assert stats.keys == 2
      assert is_number(stats.uptime_ms)
    end
  end

  describe "info" do
    test "returns info for existing key" do
      TestRedisCache.put({:user, 1}, %{name: "Alice"}, ttl: 5000)

      info = TestRedisCache.info({:user, 1})

      assert info != nil
      assert info.status == :fresh
      assert info.value == %{name: "Alice"}
      assert info.ttl_remaining_ms > 0
      assert info.ttl_remaining_ms <= 5000
    end

    test "returns nil for missing key" do
      assert TestRedisCache.info({:missing, 999}) == nil
    end

    test "returns info for key without TTL" do
      TestRedisCache.put({:user, 1}, "value")

      info = TestRedisCache.info({:user, 1})

      assert info != nil
      assert info.status == :fresh
      assert info.value == "value"
      assert info.ttl_remaining_ms == nil
    end
  end

  describe "put_new" do
    test "stores value when key doesn't exist" do
      result = TestRedisCache.put_new({:user, 1}, "first", ttl: 5000)

      assert result == {:ok, :stored}
      assert TestRedisCache.get({:user, 1}) == "first"
    end

    test "doesn't overwrite when key exists" do
      TestRedisCache.put({:user, 1}, "first")

      result = TestRedisCache.put_new({:user, 1}, "second", ttl: 5000)

      assert result == {:ok, :exists}
      assert TestRedisCache.get({:user, 1}) == "first"
    end

    test "works without ttl" do
      result = TestRedisCache.put_new({:user, 1}, "value")

      assert result == {:ok, :stored}
      assert TestRedisCache.get({:user, 1}) == "value"
    end
  end

  describe "tags/1" do
    test "returns empty list for key without tags" do
      TestRedisCache.put({:user, 1}, "value")

      assert TestRedisCache.tags({:user, 1}) == []
    end

    test "returns tags for key with tags" do
      TestRedisCache.put({:user, 1}, "value", tags: [:users, :admins])

      tags = TestRedisCache.tags({:user, 1})
      assert :users in tags
      assert :admins in tags
      assert length(tags) == 2
    end

    test "returns empty list for non-existent key" do
      assert TestRedisCache.tags({:user, 999}) == []
    end
  end

  describe "keys_by_tag/1" do
    setup do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      TestRedisCache.put({:user, 2}, "bob", tags: [:users, :admins])
      TestRedisCache.put({:session, "abc"}, "session", tags: [:sessions])
      :ok
    end

    test "returns all keys with given tag" do
      keys = TestRedisCache.keys_by_tag(:users)

      assert length(keys) == 2
      assert {:user, 1} in keys
      assert {:user, 2} in keys
    end

    test "returns keys matching specific tag" do
      keys = TestRedisCache.keys_by_tag(:admins)

      assert length(keys) == 1
      assert {:user, 2} in keys
    end

    test "returns empty list for unknown tag" do
      assert TestRedisCache.keys_by_tag(:unknown) == []
    end
  end

  describe "count_by_tag/1" do
    setup do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      TestRedisCache.put({:user, 2}, "bob", tags: [:users, :admins])
      TestRedisCache.put({:user, 3}, "charlie", tags: [:users])
      :ok
    end

    test "counts keys with tag" do
      assert TestRedisCache.count_by_tag(:users) == 3
      assert TestRedisCache.count_by_tag(:admins) == 1
    end

    test "returns 0 for unknown tag" do
      assert TestRedisCache.count_by_tag(:unknown) == 0
    end
  end

  describe "invalidate_tag/1" do
    setup do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      TestRedisCache.put({:user, 2}, "bob", tags: [:users, :admins])
      TestRedisCache.put({:session, "abc"}, "session", tags: [:sessions])
      :ok
    end

    test "deletes all entries with tag" do
      {:ok, count} = TestRedisCache.invalidate_tag(:users)

      assert count == 2
      assert TestRedisCache.get({:user, 1}) == nil
      assert TestRedisCache.get({:user, 2}) == nil
      # Session entry should remain
      assert TestRedisCache.get({:session, "abc"}) == "session"
    end

    test "returns 0 for unknown tag" do
      {:ok, count} = TestRedisCache.invalidate_tag(:unknown)
      assert count == 0
    end

    test "also removes from tags set" do
      TestRedisCache.invalidate_tag(:users)

      assert TestRedisCache.keys_by_tag(:users) == []
    end
  end

  describe "invalidate_tags/1" do
    setup do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      TestRedisCache.put({:user, 2}, "bob", tags: [:users, :admins])
      TestRedisCache.put({:session, "abc"}, "session", tags: [:sessions])
      :ok
    end

    test "deletes entries matching any of the tags" do
      {:ok, count} = TestRedisCache.invalidate_tags([:users, :sessions])

      # User 1 and 2 (tagged :users) + Session (tagged :sessions) = 3 unique entries
      assert count == 3
      assert TestRedisCache.get({:user, 1}) == nil
      assert TestRedisCache.get({:user, 2}) == nil
      assert TestRedisCache.get({:session, "abc"}) == nil
    end

    test "counts each entry only once" do
      # User 2 has both :users and :admins tags
      {:ok, count} = TestRedisCache.invalidate_tags([:users, :admins])

      # Should be 2 (User 1 + User 2), not 3 (User 1 + User 2 via :users + User 2 via :admins)
      assert count == 2
    end
  end

  describe "tag cleanup on delete" do
    test "removes tag mapping when key is deleted" do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      assert TestRedisCache.keys_by_tag(:users) == [{:user, 1}]

      TestRedisCache.delete({:user, 1})

      assert TestRedisCache.keys_by_tag(:users) == []
    end
  end

  describe "put updates tags" do
    test "replaces tags when key is updated" do
      TestRedisCache.put({:user, 1}, "alice", tags: [:users])
      assert TestRedisCache.keys_by_tag(:users) == [{:user, 1}]

      TestRedisCache.put({:user, 1}, "alice v2", tags: [:vips])

      assert TestRedisCache.keys_by_tag(:users) == []
      assert TestRedisCache.keys_by_tag(:vips) == [{:user, 1}]
    end
  end

  describe "string tags" do
    test "works with string tags" do
      TestRedisCache.put({:user, 1}, "alice", tags: ["org:acme", "team:engineering"])

      assert TestRedisCache.keys_by_tag("org:acme") == [{:user, 1}]
      assert TestRedisCache.keys_by_tag("team:engineering") == [{:user, 1}]

      {:ok, count} = TestRedisCache.invalidate_tag("org:acme")
      assert count == 1
    end
  end

  describe "warm/2" do
    defmodule TestWarmer do
      use FnDecorator.Caching.Warmable

      def entries do
        [
          {{:user, 1}, %{name: "Alice"}},
          {{:user, 2}, %{name: "Bob"}},
          {{:user, 3}, %{name: "Charlie"}}
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
          {{:admin, 1}, %{role: "admin"}}
        ]
      end
    end

    test "warms cache from module implementing Warmable" do
      :ok = TestRedisCache.warm(TestWarmer)

      assert TestRedisCache.get({:user, 1}) == %{name: "Alice"}
      assert TestRedisCache.get({:user, 2}) == %{name: "Bob"}
      assert TestRedisCache.get({:user, 3}) == %{name: "Charlie"}
    end

    test "uses opts from Warmable module" do
      :ok = TestRedisCache.warm(TestWarmer)

      # Since TTL is 60_000, entry should still exist
      assert TestRedisCache.exists?({:user, 1}) == true
    end

    test "works with Warmable module without opts callback" do
      :ok = TestRedisCache.warm(TestWarmerNoOpts, ttl: 30_000)

      assert TestRedisCache.get({:admin, 1}) == %{role: "admin"}
    end

    test "warms cache from function" do
      entries_fn = fn ->
        [
          {{:session, "a"}, %{active: true}},
          {{:session, "b"}, %{active: false}}
        ]
      end

      :ok = TestRedisCache.warm(entries_fn, ttl: 60_000)

      assert TestRedisCache.get({:session, "a"}) == %{active: true}
      assert TestRedisCache.get({:session, "b"}) == %{active: false}
    end

    test "warms cache from list of entries" do
      entries = [
        {{:role, "admin"}, %{permissions: [:read, :write]}},
        {{:role, "user"}, %{permissions: [:read]}}
      ]

      :ok = TestRedisCache.warm(entries, ttl: 60_000)

      assert TestRedisCache.get({:role, "admin"}) == %{permissions: [:read, :write]}
      assert TestRedisCache.get({:role, "user"}) == %{permissions: [:read]}
    end

    test "allows overriding opts from caller" do
      # Warmer has ttl: 60_000, but we override with ttl: 1
      :ok = TestRedisCache.warm(TestWarmer, ttl: 1)

      Process.sleep(10)
      assert TestRedisCache.get({:user, 1}) == nil
    end

    test "supports tags in warming" do
      entries = [
        {{:user, 100}, "value100"},
        {{:user, 101}, "value101"}
      ]

      :ok = TestRedisCache.warm(entries, ttl: 60_000, tags: [:warmed])

      assert TestRedisCache.keys_by_tag(:warmed) |> length() == 2
    end
  end
end
