defmodule Events.Types.DiffTest do
  use ExUnit.Case, async: true

  alias Events.Types.Diff

  describe "diff/2 with maps" do
    test "returns nil for identical values" do
      assert Diff.diff(%{a: 1}, %{a: 1}) == nil
      assert Diff.diff("hello", "hello") == nil
      assert Diff.diff(42, 42) == nil
    end

    test "detects added keys" do
      diff = Diff.diff(%{a: 1}, %{a: 1, b: 2})
      assert diff == %{b: {:added, 2}}
    end

    test "detects removed keys" do
      diff = Diff.diff(%{a: 1, b: 2}, %{a: 1})
      assert diff == %{b: {:removed, 2}}
    end

    test "detects changed values" do
      diff = Diff.diff(%{a: 1}, %{a: 2})
      assert diff == %{a: {:changed, 1, 2}}
    end

    test "detects nested changes" do
      old = %{x: %{y: 1}}
      new = %{x: %{y: 2}}

      diff = Diff.diff(old, new)
      assert diff == %{x: {:nested, %{y: {:changed, 1, 2}}}}
    end

    test "handles multiple changes" do
      old = %{a: 1, b: 2, c: 3}
      new = %{a: 10, b: 2, d: 4}

      diff = Diff.diff(old, new)

      assert diff[:a] == {:changed, 1, 10}
      assert diff[:c] == {:removed, 3}
      assert diff[:d] == {:added, 4}
      # Unchanged
      refute Map.has_key?(diff, :b)
    end

    test "handles deeply nested maps" do
      old = %{a: %{b: %{c: %{d: 1}}}}
      new = %{a: %{b: %{c: %{d: 2}}}}

      diff = Diff.diff(old, new)
      assert diff == %{a: {:nested, %{b: {:nested, %{c: {:nested, %{d: {:changed, 1, 2}}}}}}}}
    end
  end

  describe "diff/2 with lists" do
    test "detects added elements" do
      diff = Diff.diff([1, 2], [1, 2, 3])
      assert {:list_diff, ops} = diff
      assert {:add, 3} in ops
    end

    test "detects removed elements" do
      diff = Diff.diff([1, 2, 3], [1, 3])
      assert {:list_diff, ops} = diff
      assert {:remove, 2} in ops
    end

    test "keeps unchanged elements" do
      diff = Diff.diff([1, 2, 3], [1, 2, 3, 4])
      assert {:list_diff, ops} = diff

      kept = Enum.filter(ops, &match?({:keep, _}, &1))
      assert length(kept) == 3
    end
  end

  describe "diff_list/3" do
    test "simple diff" do
      ops = Diff.diff_list([1, 2, 3], [1, 3, 4])

      assert {:keep, 1} in ops
      assert {:remove, 2} in ops
      assert {:keep, 3} in ops
      assert {:add, 4} in ops
    end

    test "with key function" do
      old = [%{id: 1, name: "a"}, %{id: 2, name: "b"}]
      new = [%{id: 1, name: "A"}, %{id: 3, name: "c"}]

      ops = Diff.diff_list(old, new, by: & &1.id)

      # id: 1 changed (same key, different content)
      assert Enum.any?(ops, &match?({:change, %{id: 1, name: "a"}, %{id: 1, name: "A"}}, &1))
      # id: 2 -> id: 3 is a change (positional change when no LCS match)
      # The simple key-based LCS shows as change from old[1] to new[1]
      assert length(ops) == 2
    end
  end

  describe "patch/2" do
    test "applies additions" do
      diff = %{b: {:added, 2}}
      assert Diff.patch(%{a: 1}, diff) == %{a: 1, b: 2}
    end

    test "applies removals" do
      diff = %{b: {:removed, 2}}
      assert Diff.patch(%{a: 1, b: 2}, diff) == %{a: 1}
    end

    test "applies changes" do
      diff = %{a: {:changed, 1, 2}}
      assert Diff.patch(%{a: 1}, diff) == %{a: 2}
    end

    test "applies nested changes" do
      diff = %{x: {:nested, %{y: {:changed, 1, 2}}}}
      assert Diff.patch(%{x: %{y: 1}}, diff) == %{x: %{y: 2}}
    end

    test "applies list diffs" do
      diff = {:list_diff, [{:keep, 1}, {:remove, 2}, {:keep, 3}, {:add, 4}]}
      assert Diff.patch([1, 2, 3], diff) == [1, 3, 4]
    end

    test "returns unchanged value for nil diff" do
      value = %{a: 1, b: 2}
      assert Diff.patch(value, nil) == value
    end

    test "roundtrip: diff then patch" do
      old = %{name: "Alice", age: 30, tags: ["a", "b"]}
      new = %{name: "Alice", age: 31, tags: ["a", "c"]}

      diff = Diff.diff(old, new)
      result = Diff.patch(old, diff)

      assert result.age == 31
    end
  end

  describe "apply_patch/2" do
    test "returns ok tuple on success" do
      diff = %{a: {:changed, 1, 2}}
      assert {:ok, %{a: 2}} = Diff.apply_patch(%{a: 1}, diff)
    end
  end

  describe "reverse/1" do
    test "reverses additions to removals" do
      diff = %{a: {:added, 1}}
      assert Diff.reverse(diff) == %{a: {:removed, 1}}
    end

    test "reverses removals to additions" do
      diff = %{a: {:removed, 1}}
      assert Diff.reverse(diff) == %{a: {:added, 1}}
    end

    test "reverses changes" do
      diff = %{a: {:changed, 1, 2}}
      assert Diff.reverse(diff) == %{a: {:changed, 2, 1}}
    end

    test "reverses nested diffs" do
      diff = %{x: {:nested, %{y: {:changed, 1, 2}}}}
      assert Diff.reverse(diff) == %{x: {:nested, %{y: {:changed, 2, 1}}}}
    end

    test "roundtrip: reverse then patch undoes change" do
      old = %{a: 1, b: 2}
      new = %{a: 10, b: 2, c: 3}

      diff = Diff.diff(old, new)
      patched = Diff.patch(old, diff)
      reversed = Diff.reverse(diff)
      restored = Diff.patch(patched, reversed)

      assert restored == old
    end
  end

  describe "merge3/4" do
    test "merges non-conflicting changes" do
      base = %{x: 1, y: 2, z: 3}
      # Changed x
      left = %{x: 10, y: 2, z: 3}
      # Changed y
      right = %{x: 1, y: 20, z: 3}

      assert {:ok, merged} = Diff.merge3(base, left, right)
      assert merged == %{x: 10, y: 20, z: 3}
    end

    test "handles additions on both sides" do
      base = %{a: 1}
      left = %{a: 1, b: 2}
      right = %{a: 1, c: 3}

      assert {:ok, merged} = Diff.merge3(base, left, right)
      assert merged == %{a: 1, b: 2, c: 3}
    end

    test "handles removal on one side, no change on other" do
      base = %{a: 1, b: 2}
      # Removed b
      left = %{a: 1}
      # No change
      right = %{a: 1, b: 2}

      assert {:ok, merged} = Diff.merge3(base, left, right)
      assert merged == %{a: 1}
    end

    test "detects conflicts" do
      base = %{x: 1}
      left = %{x: 10}
      right = %{x: 20}

      assert {:conflict, result, conflicts} = Diff.merge3(base, left, right)
      assert result.x == {:conflict, 10, 20}
      assert [{[:x], 10, 20}] = conflicts
    end

    test "uses :left_wins resolver" do
      base = %{x: 1}
      left = %{x: 10}
      right = %{x: 20}

      assert {:ok, merged} = Diff.merge3(base, left, right, :left_wins)
      assert merged.x == 10
    end

    test "uses :right_wins resolver" do
      base = %{x: 1}
      left = %{x: 10}
      right = %{x: 20}

      assert {:ok, merged} = Diff.merge3(base, left, right, :right_wins)
      assert merged.x == 20
    end

    test "uses custom resolver function" do
      base = %{x: 1}
      left = %{x: 10}
      right = %{x: 20}

      resolver = fn _key, left_val, right_val ->
        {:ok, max(left_val, right_val)}
      end

      assert {:ok, merged} = Diff.merge3(base, left, right, resolver)
      assert merged.x == 20
    end

    test "merges nested structures" do
      base = %{config: %{a: 1, b: 2}}
      # Changed a
      left = %{config: %{a: 10, b: 2}}
      # Changed b
      right = %{config: %{a: 1, b: 20}}

      assert {:ok, merged} = Diff.merge3(base, left, right)
      assert merged.config == %{a: 10, b: 20}
    end
  end

  describe "empty?/1" do
    test "nil is empty" do
      assert Diff.empty?(nil)
    end

    test "empty map is empty" do
      assert Diff.empty?(%{})
    end

    test "non-empty diff is not empty" do
      refute Diff.empty?(%{a: {:changed, 1, 2}})
    end

    test "list diff with only keeps is empty" do
      assert Diff.empty?({:list_diff, [{:keep, 1}, {:keep, 2}]})
    end

    test "list diff with changes is not empty" do
      refute Diff.empty?({:list_diff, [{:keep, 1}, {:add, 2}]})
    end
  end

  describe "changed_paths/1" do
    test "returns empty for nil" do
      assert Diff.changed_paths(nil) == []
    end

    test "returns paths for flat diff" do
      diff = %{a: {:changed, 1, 2}, b: {:added, 3}}
      paths = Diff.changed_paths(diff)

      assert [:a] in paths
      assert [:b] in paths
    end

    test "returns paths for nested diff" do
      diff = %{
        a: {:changed, 1, 2},
        x: {:nested, %{y: {:changed, 3, 4}, z: {:added, 5}}}
      }

      paths = Diff.changed_paths(diff)

      assert [:a] in paths
      assert [:x, :y] in paths
      assert [:x, :z] in paths
    end
  end

  describe "summarize/1" do
    test "summarizes nil as zeros" do
      assert Diff.summarize(nil) == %{added: 0, removed: 0, changed: 0, nested: 0}
    end

    test "counts operations" do
      diff = %{
        a: {:added, 1},
        b: {:removed, 2},
        c: {:changed, 3, 4}
      }

      summary = Diff.summarize(diff)
      assert summary.added == 1
      assert summary.removed == 1
      assert summary.changed == 1
    end

    test "counts nested operations" do
      diff = %{
        x:
          {:nested,
           %{
             a: {:added, 1},
             b: {:changed, 2, 3}
           }}
      }

      summary = Diff.summarize(diff)
      assert summary.added == 1
      assert summary.changed == 1
      assert summary.nested == 1
    end
  end

  describe "filter/2" do
    test "filters to specified keys" do
      diff = %{a: {:changed, 1, 2}, b: {:added, 3}, c: {:removed, 4}}
      filtered = Diff.filter(diff, [:a, :b])

      assert Map.has_key?(filtered, :a)
      assert Map.has_key?(filtered, :b)
      refute Map.has_key?(filtered, :c)
    end

    test "returns nil for nil diff" do
      assert Diff.filter(nil, [:a]) == nil
    end
  end

  describe "reject/2" do
    test "excludes specified keys" do
      diff = %{a: {:changed, 1, 2}, b: {:added, 3}, c: {:removed, 4}}
      rejected = Diff.reject(diff, [:c])

      assert Map.has_key?(rejected, :a)
      assert Map.has_key?(rejected, :b)
      refute Map.has_key?(rejected, :c)
    end

    test "returns nil for nil diff" do
      assert Diff.reject(nil, [:a]) == nil
    end
  end

  describe "real-world scenarios" do
    test "user profile update tracking" do
      old_profile = %{
        name: "Alice",
        email: "alice@example.com",
        preferences: %{theme: "light", notifications: true}
      }

      new_profile = %{
        name: "Alice",
        email: "alice@newdomain.com",
        preferences: %{theme: "dark", notifications: true}
      }

      diff = Diff.diff(old_profile, new_profile)

      # Check what changed
      assert diff[:email] == {:changed, "alice@example.com", "alice@newdomain.com"}
      assert diff[:preferences] == {:nested, %{theme: {:changed, "light", "dark"}}}
      # Unchanged
      refute Map.has_key?(diff, :name)

      # Apply to get new value
      result = Diff.patch(old_profile, diff)
      assert result.email == "alice@newdomain.com"
      assert result.preferences.theme == "dark"
    end

    test "concurrent editing with merge" do
      # Original document
      base = %{
        title: "Draft",
        content: "Initial text",
        metadata: %{author: "Alice", version: 1}
      }

      # User 1 changes title
      user1 = %{
        title: "Final Title",
        content: "Initial text",
        metadata: %{author: "Alice", version: 1}
      }

      # User 2 changes content and version
      user2 = %{
        title: "Draft",
        content: "Updated content",
        metadata: %{author: "Alice", version: 2}
      }

      assert {:ok, merged} = Diff.merge3(base, user1, user2)

      assert merged.title == "Final Title"
      assert merged.content == "Updated content"
      assert merged.metadata.version == 2
    end

    test "undo/redo with reverse" do
      states = [
        %{count: 0},
        %{count: 1},
        %{count: 2},
        %{count: 3}
      ]

      # Calculate diffs between states
      diffs =
        states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [old, new] -> Diff.diff(old, new) end)

      # Apply all diffs to get final state
      final = Enum.reduce(diffs, hd(states), &Diff.patch(&2, &1))
      assert final.count == 3

      # Undo last change
      last_diff = List.last(diffs)
      undone = Diff.patch(final, Diff.reverse(last_diff))
      assert undone.count == 2
    end

    test "configuration diff for audit log" do
      old_config = %{
        database: %{pool_size: 10, timeout: 5000},
        cache: %{enabled: true, ttl: 3600}
      }

      new_config = %{
        database: %{pool_size: 20, timeout: 5000},
        cache: %{enabled: true, ttl: 7200}
      }

      diff = Diff.diff(old_config, new_config)
      paths = Diff.changed_paths(diff)

      # Log changed paths
      assert [:database, :pool_size] in paths
      assert [:cache, :ttl] in paths
      refute [:database, :timeout] in paths
      refute [:cache, :enabled] in paths
    end
  end
end
