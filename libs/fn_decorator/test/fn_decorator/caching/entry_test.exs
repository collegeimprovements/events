defmodule FnDecorator.Caching.EntryTest do
  use ExUnit.Case, async: true

  alias FnDecorator.Caching.Entry

  describe "new/3" do
    test "creates entry with value and TTL" do
      entry = Entry.new("hello", 5_000)

      assert entry.value == "hello"
      assert is_integer(entry.cached_at)
      assert entry.fresh_until > entry.cached_at
      assert entry.fresh_until - entry.cached_at == 5_000
      assert entry.stale_until == nil
    end

    test "creates entry with stale TTL" do
      entry = Entry.new("hello", 5_000, 60_000)

      assert entry.value == "hello"
      assert entry.stale_until != nil
      assert entry.stale_until - entry.cached_at == 60_000
      assert entry.stale_until > entry.fresh_until
    end

    test "handles complex values" do
      value = %{users: [%{id: 1, name: "Alice"}], meta: {:ok, 42}}
      entry = Entry.new(value, 1_000)

      assert entry.value == value
    end

    test "raises when stale_ttl <= ttl" do
      assert_raise FunctionClauseError, fn ->
        Entry.new("value", 5_000, 3_000)
      end
    end
  end

  describe "to_tuple/1 and from_cache/1" do
    test "round-trips entry through storage format" do
      original = Entry.new("test_value", 5_000, 30_000)
      tuple = Entry.to_tuple(original)

      # Tuple should be tagged
      assert is_tuple(tuple)
      assert elem(tuple, 0) == :fn_cache

      # Round-trip
      restored = Entry.from_cache(tuple)

      assert restored.value == original.value
      assert restored.cached_at == original.cached_at
      assert restored.fresh_until == original.fresh_until
      assert restored.stale_until == original.stale_until
    end

    test "tuple format includes version" do
      entry = Entry.new("value", 5_000)
      tuple = Entry.to_tuple(entry)

      assert {:fn_cache, 1, "value", _, _, _} = tuple
    end

    test "from_cache returns nil for nil" do
      assert Entry.from_cache(nil) == nil
    end

    test "from_cache returns nil for unknown formats" do
      assert Entry.from_cache("raw_string") == nil
      assert Entry.from_cache(42) == nil
      assert Entry.from_cache(%{foo: "bar"}) == nil
      assert Entry.from_cache([1, 2, 3]) == nil
    end

    test "from_cache handles versioned tuples" do
      tuple = {:fn_cache, 1, "versioned", 1000, 2000, 3000}

      entry = Entry.from_cache(tuple)
      assert %Entry{} = entry
      assert entry.value == "versioned"
      assert entry.cached_at == 1000
      assert entry.fresh_until == 2000
      assert entry.stale_until == 3000
    end
  end

  describe "freshness checks" do
    test "fresh? returns true when within TTL" do
      entry = Entry.new("value", 10_000)
      assert Entry.fresh?(entry) == true
    end

    test "fresh? returns false when TTL expired" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "old",
        cached_at: now - 10_000,
        fresh_until: now - 5_000,
        stale_until: now + 5_000
      }

      assert Entry.fresh?(entry) == false
    end

    test "stale? returns false when fresh" do
      entry = Entry.new("value", 10_000, 60_000)
      assert Entry.stale?(entry) == false
    end

    test "stale? returns true when in stale window" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "stale",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: now + 50_000
      }

      assert Entry.stale?(entry) == true
    end

    test "stale? returns false when stale_until is nil" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "no_stale",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: nil
      }

      assert Entry.stale?(entry) == false
    end

    test "expired? returns true when completely expired" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "expired",
        cached_at: now - 100_000,
        fresh_until: now - 50_000,
        stale_until: now - 10_000
      }

      assert Entry.expired?(entry) == true
    end

    test "expired? returns true when fresh_until passed and no stale window" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "expired",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: nil
      }

      assert Entry.expired?(entry) == true
    end

    test "expired? returns false when in stale window" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "stale",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: now + 50_000
      }

      assert Entry.expired?(entry) == false
    end
  end

  describe "status/1" do
    test "returns :fresh for fresh entries" do
      entry = Entry.new("value", 10_000)
      assert Entry.status(entry) == :fresh
    end

    test "returns :stale for stale entries" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "stale",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: now + 50_000
      }

      assert Entry.status(entry) == :stale
    end

    test "returns :expired for expired entries" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "expired",
        cached_at: now - 100_000,
        fresh_until: now - 50_000,
        stale_until: now - 10_000
      }

      assert Entry.status(entry) == :expired
    end
  end

  describe "value/1" do
    test "extracts value from entry" do
      entry = Entry.new(%{data: "important"}, 5_000)
      assert Entry.value(entry) == %{data: "important"}
    end
  end

  describe "ttl_remaining/1" do
    test "returns positive time when fresh" do
      entry = Entry.new("value", 10_000)
      time = Entry.ttl_remaining(entry)

      assert time > 0
      assert time <= 10_000
    end

    test "returns 0 when already stale" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "stale",
        cached_at: now - 10_000,
        fresh_until: now - 1_000,
        stale_until: now + 50_000
      }

      assert Entry.ttl_remaining(entry) == 0
    end
  end

  describe "time_to_expiry/1" do
    test "returns positive time when not expired" do
      entry = Entry.new("value", 5_000, 60_000)
      time = Entry.time_to_expiry(entry)

      assert time > 0
      assert time <= 60_000
    end

    test "returns time until fresh_until when no stale_until" do
      entry = Entry.new("value", 5_000)
      time = Entry.time_to_expiry(entry)

      assert time > 0
      assert time <= 5_000
    end

    test "returns 0 when expired" do
      now = System.monotonic_time(:millisecond)

      entry = %Entry{
        value: "expired",
        cached_at: now - 100_000,
        fresh_until: now - 50_000,
        stale_until: now - 10_000
      }

      assert Entry.time_to_expiry(entry) == 0
    end
  end

  describe "age/1" do
    test "returns age in milliseconds" do
      entry = Entry.new("value", 5_000)
      age = Entry.age(entry)

      assert age >= 0
      assert age < 100
    end
  end
end
