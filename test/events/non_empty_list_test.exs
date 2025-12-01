defmodule Events.Types.NonEmptyListTest do
  use ExUnit.Case, async: true

  alias Events.Types.NonEmptyList, as: NEL

  describe "construction" do
    test "new/2 creates from head and tail" do
      assert NEL.new(1, [2, 3]) == {1, [2, 3]}
      assert NEL.new("only") == {"only", []}
    end

    test "singleton/1 creates single element list" do
      assert NEL.singleton(42) == {42, []}
    end

    test "from_list/1 returns ok for non-empty list" do
      assert NEL.from_list([1, 2, 3]) == {:ok, {1, [2, 3]}}
      assert NEL.from_list([1]) == {:ok, {1, []}}
    end

    test "from_list/1 returns error for empty list" do
      assert NEL.from_list([]) == :error
    end

    test "from_list!/1 creates from non-empty list" do
      assert NEL.from_list!([1, 2, 3]) == {1, [2, 3]}
    end

    test "from_list!/1 raises on empty list" do
      assert_raise ArgumentError, fn -> NEL.from_list!([]) end
    end

    test "from_list_maybe/1 returns maybe" do
      assert NEL.from_list_maybe([1, 2]) == {:some, {1, [2]}}
      assert NEL.from_list_maybe([]) == :none
    end

    test "repeat/2 creates repeated elements" do
      assert NEL.repeat(0, 3) == {0, [0, 0]}
      assert NEL.repeat("x", 1) == {"x", []}
    end

    test "range/2 creates from range" do
      assert NEL.range(1, 5) == {1, [2, 3, 4, 5]}
      assert NEL.range(5, 5) == {5, []}
      assert NEL.range(5, 3) == {5, [4, 3]}
    end
  end

  describe "access" do
    test "head/1 returns first element" do
      assert NEL.head({1, [2, 3]}) == 1
      assert NEL.head({"only", []}) == "only"
    end

    test "tail/1 returns rest as list" do
      assert NEL.tail({1, [2, 3]}) == [2, 3]
      assert NEL.tail({1, []}) == []
    end

    test "last/1 returns last element" do
      assert NEL.last({1, [2, 3]}) == 3
      assert NEL.last({1, []}) == 1
    end

    test "init/1 returns all but last" do
      assert NEL.init({1, [2, 3]}) == [1, 2]
      assert NEL.init({1, []}) == []
    end

    test "at/2 returns element at index" do
      assert NEL.at({1, [2, 3]}, 0) == {:ok, 1}
      assert NEL.at({1, [2, 3]}, 2) == {:ok, 3}
      assert NEL.at({1, [2, 3]}, 10) == :error
    end

    test "at!/2 raises on out of bounds" do
      assert NEL.at!({1, [2, 3]}, 1) == 2
      assert_raise ArgumentError, fn -> NEL.at!({1, [2, 3]}, 10) end
    end
  end

  describe "predicates" do
    test "size/1 returns count" do
      assert NEL.size({1, [2, 3]}) == 3
      assert NEL.size({1, []}) == 1
    end

    test "singleton?/1 checks for single element" do
      assert NEL.singleton?({1, []})
      refute NEL.singleton?({1, [2]})
    end

    test "member?/2 checks membership" do
      assert NEL.member?({1, [2, 3]}, 2)
      refute NEL.member?({1, [2, 3]}, 5)
    end

    test "all?/2 checks all elements" do
      assert NEL.all?({2, [4, 6]}, &(rem(&1, 2) == 0))
      refute NEL.all?({2, [3, 4]}, &(rem(&1, 2) == 0))
    end

    test "any?/2 checks any element" do
      assert NEL.any?({1, [2, 3]}, &(&1 > 2))
      refute NEL.any?({1, [2, 3]}, &(&1 > 10))
    end
  end

  describe "transformation" do
    test "map/2 transforms elements" do
      assert NEL.map({1, [2, 3]}, &(&1 * 2)) == {2, [4, 6]}
    end

    test "map_with_index/2 includes index" do
      result = NEL.map_with_index({:a, [:b, :c]}, fn el, idx -> {el, idx} end)
      assert result == {{:a, 0}, [{:b, 1}, {:c, 2}]}
    end

    test "flat_map/2 flattens mapped nels" do
      result = NEL.flat_map({1, [2]}, fn x -> NEL.new(x, [x * 10]) end)
      assert result == {1, [10, 2, 20]}
    end

    test "filter/2 returns result" do
      assert NEL.filter({1, [2, 3, 4]}, &(rem(&1, 2) == 0)) == {:ok, {2, [4]}}
      assert NEL.filter({1, [3, 5]}, &(rem(&1, 2) == 0)) == :error
    end

    test "reject/2 rejects matching elements" do
      assert NEL.reject({1, [2, 3, 4]}, &(rem(&1, 2) == 0)) == {:ok, {1, [3]}}
    end

    test "take/2 takes first n elements" do
      assert NEL.take({1, [2, 3, 4]}, 2) == {:ok, {1, [2]}}
      assert NEL.take({1, [2, 3]}, 0) == :error
    end

    test "drop/2 drops first n elements" do
      assert NEL.drop({1, [2, 3, 4]}, 2) == {:ok, {3, [4]}}
      assert NEL.drop({1, [2]}, 3) == :error
    end

    test "reverse/1 reverses elements" do
      assert NEL.reverse({1, [2, 3]}) == {3, [2, 1]}
      assert NEL.reverse({1, []}) == {1, []}
    end

    test "sort/1 sorts elements" do
      assert NEL.sort({3, [1, 2]}) == {1, [2, 3]}
    end

    test "sort_by/2 sorts by key" do
      result = NEL.sort_by({%{n: 3}, [%{n: 1}, %{n: 2}]}, & &1.n)
      assert result == {%{n: 1}, [%{n: 2}, %{n: 3}]}
    end

    test "uniq/1 removes duplicates" do
      assert NEL.uniq({1, [2, 1, 3, 2]}) == {1, [2, 3]}
    end

    test "uniq_by/2 removes duplicates by key" do
      result = NEL.uniq_by({%{id: 1, n: "a"}, [%{id: 2, n: "b"}, %{id: 1, n: "c"}]}, & &1.id)
      assert result == {%{id: 1, n: "a"}, [%{id: 2, n: "b"}]}
    end

    test "flatten/1 flattens nested nels" do
      inner1 = NEL.new(1, [2])
      inner2 = NEL.new(3, [4])
      result = NEL.flatten(NEL.new(inner1, [inner2]))
      assert result == {1, [2, 3, 4]}
    end

    test "intersperse/2 adds separator" do
      assert NEL.intersperse({1, [2, 3]}, 0) == {1, [0, 2, 0, 3]}
      assert NEL.intersperse({1, []}, 0) == {1, []}
    end
  end

  describe "reduction" do
    test "reduce/2 without initial value" do
      assert NEL.reduce({1, [2, 3]}, &+/2) == 6
      assert NEL.reduce({5, []}, &+/2) == 5
    end

    test "fold/3 with initial value" do
      assert NEL.fold({1, [2, 3]}, 10, &+/2) == 16
    end

    test "max/1 returns maximum" do
      assert NEL.max({3, [1, 4, 1, 5]}) == 5
    end

    test "min/1 returns minimum" do
      assert NEL.min({3, [1, 4, 1, 5]}) == 1
    end

    test "max_by/2 returns element with max key" do
      result = NEL.max_by({%{n: 1}, [%{n: 3}, %{n: 2}]}, & &1.n)
      assert result == %{n: 3}
    end

    test "min_by/2 returns element with min key" do
      result = NEL.min_by({%{n: 1}, [%{n: 3}, %{n: 2}]}, & &1.n)
      assert result == %{n: 1}
    end

    test "sum/1 sums elements" do
      assert NEL.sum({1, [2, 3]}) == 6
    end

    test "product/1 multiplies elements" do
      assert NEL.product({2, [3, 4]}) == 24
    end
  end

  describe "combination" do
    test "cons/2 prepends element" do
      assert NEL.cons({2, [3]}, 1) == {1, [2, 3]}
    end

    test "append/2 appends element" do
      assert NEL.append({1, [2]}, 3) == {1, [2, 3]}
    end

    test "concat/2 concatenates two nels" do
      assert NEL.concat({1, [2]}, {3, [4]}) == {1, [2, 3, 4]}
    end

    test "concat_list/2 concatenates with list" do
      assert NEL.concat_list({1, [2]}, [3, 4]) == {1, [2, 3, 4]}
    end

    test "zip/2 zips two nels" do
      result = NEL.zip({1, [2, 3]}, {:a, [:b, :c]})
      assert result == {{1, :a}, [{2, :b}, {3, :c}]}
    end

    test "zip_with/3 zips with function" do
      result = NEL.zip_with({1, [2]}, {10, [20]}, &+/2)
      assert result == {11, [22]}
    end

    test "unzip/1 unzips tuples" do
      result = NEL.unzip({{1, :a}, [{2, :b}, {3, :c}]})
      assert result == {{1, [2, 3]}, {:a, [:b, :c]}}
    end
  end

  describe "grouping and partitioning" do
    test "group_by/2 groups by key" do
      result = NEL.group_by({1, [2, 3, 4]}, &rem(&1, 2))
      assert result == %{0 => {2, [4]}, 1 => {1, [3]}}
    end

    test "partition/2 splits by predicate" do
      result = NEL.partition({1, [2, 3, 4]}, &(rem(&1, 2) == 0))
      assert result == {[2, 4], [1, 3]}
    end

    test "split/2 splits at position" do
      result = NEL.split({1, [2, 3, 4]}, 2)
      assert result == {{1, [2]}, [3, 4]}
    end
  end

  describe "conversion" do
    test "to_list/1 converts to list" do
      assert NEL.to_list({1, [2, 3]}) == [1, 2, 3]
    end

    test "to_mapset/1 converts to mapset" do
      result = NEL.to_mapset({1, [2, 1, 3]})
      assert result == MapSet.new([1, 2, 3])
    end

    test "to_stream/1 converts to stream" do
      result = NEL.to_stream({1, [2, 3]}) |> Enum.take(2)
      assert result == [1, 2]
    end
  end

  describe "traversal" do
    test "traverse_result/2 with all success" do
      result = NEL.traverse_result({1, [2, 3]}, fn x -> {:ok, x * 2} end)
      assert result == {:ok, {2, [4, 6]}}
    end

    test "traverse_result/2 with failure" do
      result =
        NEL.traverse_result({1, [2, 3]}, fn
          2 -> {:error, :bad}
          x -> {:ok, x * 2}
        end)

      assert result == {:error, :bad}
    end

    test "traverse_maybe/2 with all some" do
      result = NEL.traverse_maybe({1, [2, 3]}, fn x -> {:some, x * 2} end)
      assert result == {:some, {2, [4, 6]}}
    end

    test "traverse_maybe/2 with none" do
      result =
        NEL.traverse_maybe({1, [2, 3]}, fn
          2 -> :none
          x -> {:some, x * 2}
        end)

      assert result == :none
    end
  end

  describe "utilities" do
    test "each/2 executes side effects" do
      test_pid = self()
      NEL.each({1, [2, 3]}, fn x -> send(test_pid, x) end)
      assert_receive 1
      assert_receive 2
      assert_receive 3
    end

    test "find/2 finds first match" do
      assert NEL.find({1, [2, 3, 4]}, &(&1 > 2)) == {:some, 3}
      assert NEL.find({1, [2, 3]}, &(&1 > 10)) == :none
    end

    test "find_index/2 finds index of first match" do
      assert NEL.find_index({:a, [:b, :c]}, &(&1 == :b)) == {:some, 1}
      assert NEL.find_index({:a, [:b, :c]}, &(&1 == :z)) == :none
    end

    test "count/2 counts matches" do
      assert NEL.count({1, [2, 3, 4]}, &(rem(&1, 2) == 0)) == 2
    end

    test "frequencies/1 counts occurrences" do
      result = NEL.frequencies({:a, [:b, :a, :c, :a]})
      assert result == %{a: 3, b: 1, c: 1}
    end

    test "frequencies_by/2 counts by key" do
      result = NEL.frequencies_by({1, [2, 3, 4, 5]}, &rem(&1, 2))
      assert result == %{0 => 2, 1 => 3}
    end

    test "join/2 joins to string" do
      assert NEL.join({1, [2, 3]}, ", ") == "1, 2, 3"
      assert NEL.join({"a", ["b", "c"]}) == "abc"
    end

    test "update_at/3 updates element" do
      assert NEL.update_at({1, [2, 3]}, 1, &(&1 * 10)) == {1, [20, 3]}
      assert NEL.update_at({1, [2, 3]}, 0, &(&1 * 10)) == {10, [2, 3]}
    end

    test "replace_at/3 replaces element" do
      assert NEL.replace_at({1, [2, 3]}, 1, 99) == {1, [99, 3]}
    end

    test "delete_at/2 deletes element" do
      assert NEL.delete_at({1, [2, 3]}, 1) == {:ok, {1, [3]}}
      assert NEL.delete_at({1, []}, 0) == :error
    end

    test "insert_at/3 inserts element" do
      assert NEL.insert_at({1, [3]}, 1, 2) == {1, [2, 3]}
      assert NEL.insert_at({2, [3]}, 0, 1) == {1, [2, 3]}
    end
  end

  describe "real-world examples" do
    test "safe head on user list" do
      users = NEL.new(%{id: 1, name: "Alice"}, [%{id: 2, name: "Bob"}])

      # Always safe - we know there's at least one user
      first_user = NEL.head(users)
      assert first_user.name == "Alice"
    end

    test "reduce without initial value" do
      prices = NEL.new(10.0, [20.0, 30.0])

      # Safe - no need for default value
      total = NEL.reduce(prices, &+/2)
      assert total == 60.0
    end

    test "max without error handling" do
      scores = NEL.new(85, [92, 78, 95, 88])

      # Safe - always returns a value
      highest = NEL.max(scores)
      assert highest == 95
    end

    test "grouping guarantees non-empty groups" do
      items = NEL.new(%{type: :a, val: 1}, [%{type: :b, val: 2}, %{type: :a, val: 3}])

      groups = NEL.group_by(items, & &1.type)

      # Each group is a NonEmptyList - safe to get head
      assert NEL.head(groups[:a]).val == 1
      assert NEL.head(groups[:b]).val == 2
    end
  end
end
