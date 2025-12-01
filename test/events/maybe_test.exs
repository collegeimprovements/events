defmodule Events.Types.MaybeTest do
  use ExUnit.Case, async: true
  # Note: Doctests disabled because examples use short `Maybe` alias.
  # Comprehensive unit tests below provide full coverage.

  alias Events.Types.Maybe

  describe "type checking" do
    test "some?/1 returns true for some values" do
      assert Maybe.some?({:some, 42})
      assert Maybe.some?({:some, nil})
      assert Maybe.some?({:some, false})
    end

    test "some?/1 returns false for none" do
      refute Maybe.some?(:none)
    end

    test "none?/1 returns true for none" do
      assert Maybe.none?(:none)
    end

    test "none?/1 returns false for some values" do
      refute Maybe.none?({:some, 42})
    end
  end

  describe "creation" do
    test "some/1 wraps value" do
      assert Maybe.some(42) == {:some, 42}
      assert Maybe.some(nil) == {:some, nil}
    end

    test "none/0 returns none" do
      assert Maybe.none() == :none
    end

    test "from_nilable/1 converts nil to none" do
      assert Maybe.from_nilable(nil) == :none
    end

    test "from_nilable/1 wraps non-nil values" do
      assert Maybe.from_nilable(42) == {:some, 42}
      assert Maybe.from_nilable(false) == {:some, false}
      assert Maybe.from_nilable(0) == {:some, 0}
    end

    test "from_result/1 converts ok to some" do
      assert Maybe.from_result({:ok, 42}) == {:some, 42}
    end

    test "from_result/1 converts error to none" do
      assert Maybe.from_result({:error, :reason}) == :none
    end

    test "from_bool/2 returns some when true" do
      assert Maybe.from_bool(true, "value") == {:some, "value"}
    end

    test "from_bool/2 returns none when false" do
      assert Maybe.from_bool(false, "value") == :none
    end

    test "from_string/1 handles empty strings" do
      assert Maybe.from_string("") == :none
      assert Maybe.from_string("   ") == :none
      assert Maybe.from_string(nil) == :none
    end

    test "from_string/1 wraps non-empty strings" do
      assert Maybe.from_string("hello") == {:some, "hello"}
      assert Maybe.from_string("  hello  ") == {:some, "hello"}
    end

    test "from_list/1 handles empty lists" do
      assert Maybe.from_list([]) == :none
    end

    test "from_list/1 wraps non-empty lists" do
      assert Maybe.from_list([1, 2, 3]) == {:some, [1, 2, 3]}
    end

    test "from_map/1 handles empty maps" do
      assert Maybe.from_map(%{}) == :none
    end

    test "from_map/1 wraps non-empty maps" do
      assert Maybe.from_map(%{a: 1}) == {:some, %{a: 1}}
    end
  end

  describe "transformation" do
    test "map/2 transforms some values" do
      assert Maybe.map({:some, 5}, &(&1 * 2)) == {:some, 10}
    end

    test "map/2 returns none for none" do
      assert Maybe.map(:none, &(&1 * 2)) == :none
    end

    test "replace/2 replaces some value" do
      assert Maybe.replace({:some, 5}, 42) == {:some, 42}
    end

    test "replace/2 keeps none as none" do
      assert Maybe.replace(:none, 42) == :none
    end
  end

  describe "chaining" do
    test "and_then/2 chains some values" do
      result =
        {:some, 5}
        |> Maybe.and_then(fn x -> {:some, x * 2} end)

      assert result == {:some, 10}
    end

    test "and_then/2 short-circuits on none" do
      result =
        {:some, 5}
        |> Maybe.and_then(fn _ -> :none end)
        |> Maybe.and_then(fn x -> {:some, x * 2} end)

      assert result == :none
    end

    test "and_then/2 returns none for none" do
      result =
        :none
        |> Maybe.and_then(fn x -> {:some, x * 2} end)

      assert result == :none
    end

    test "or_else/2 returns some if some" do
      result = Maybe.or_else({:some, 5}, fn -> {:some, 42} end)
      assert result == {:some, 5}
    end

    test "or_else/2 calls function if none" do
      result = Maybe.or_else(:none, fn -> {:some, 42} end)
      assert result == {:some, 42}
    end

    test "or_value/2 returns first if some" do
      assert Maybe.or_value({:some, 1}, {:some, 2}) == {:some, 1}
    end

    test "or_value/2 returns second if first is none" do
      assert Maybe.or_value(:none, {:some, 2}) == {:some, 2}
    end
  end

  describe "filtering" do
    test "filter/2 keeps value if predicate passes" do
      assert Maybe.filter({:some, 5}, &(&1 > 3)) == {:some, 5}
    end

    test "filter/2 returns none if predicate fails" do
      assert Maybe.filter({:some, 2}, &(&1 > 3)) == :none
    end

    test "filter/2 returns none for none" do
      assert Maybe.filter(:none, &(&1 > 3)) == :none
    end

    test "reject/2 returns none if predicate passes" do
      assert Maybe.reject({:some, 5}, &(&1 > 3)) == :none
    end

    test "reject/2 keeps value if predicate fails" do
      assert Maybe.reject({:some, 2}, &(&1 > 3)) == {:some, 2}
    end
  end

  describe "extraction" do
    test "unwrap!/1 extracts some value" do
      assert Maybe.unwrap!({:some, 42}) == 42
    end

    test "unwrap!/1 raises on none" do
      assert_raise ArgumentError, fn ->
        Maybe.unwrap!(:none)
      end
    end

    test "unwrap_or/2 returns value for some" do
      assert Maybe.unwrap_or({:some, 42}, 0) == 42
    end

    test "unwrap_or/2 returns default for none" do
      assert Maybe.unwrap_or(:none, 0) == 0
    end

    test "unwrap_or_else/2 returns value for some" do
      assert Maybe.unwrap_or_else({:some, 42}, fn -> 0 end) == 42
    end

    test "unwrap_or_else/2 calls function for none" do
      assert Maybe.unwrap_or_else(:none, fn -> 0 end) == 0
    end

    test "to_nilable/1 extracts value from some" do
      assert Maybe.to_nilable({:some, 42}) == 42
    end

    test "to_nilable/1 returns nil for none" do
      assert Maybe.to_nilable(:none) == nil
    end
  end

  describe "conversion" do
    test "to_result/2 converts some to ok" do
      assert Maybe.to_result({:some, 42}, :error) == {:ok, 42}
    end

    test "to_result/2 converts none to error" do
      assert Maybe.to_result(:none, :not_found) == {:error, :not_found}
    end

    test "to_bool/1 converts some to true" do
      assert Maybe.to_bool({:some, 42}) == true
    end

    test "to_bool/1 converts none to false" do
      assert Maybe.to_bool(:none) == false
    end

    test "to_list/1 converts some to singleton list" do
      assert Maybe.to_list({:some, 42}) == [42]
    end

    test "to_list/1 converts none to empty list" do
      assert Maybe.to_list(:none) == []
    end
  end

  describe "collection operations" do
    test "collect/1 collects all some values" do
      maybes = [{:some, 1}, {:some, 2}, {:some, 3}]
      assert Maybe.collect(maybes) == {:some, [1, 2, 3]}
    end

    test "collect/1 returns none if any is none" do
      maybes = [{:some, 1}, :none, {:some, 3}]
      assert Maybe.collect(maybes) == :none
    end

    test "collect/1 returns some for empty list" do
      assert Maybe.collect([]) == {:some, []}
    end

    test "cat_somes/1 filters and unwraps some values" do
      maybes = [{:some, 1}, :none, {:some, 3}]
      assert Maybe.cat_somes(maybes) == [1, 3]
    end

    test "traverse/2 applies function and collects" do
      list = [1, 2, 3]
      result = Maybe.traverse(list, fn x -> {:some, x * 2} end)
      assert result == {:some, [2, 4, 6]}
    end

    test "traverse/2 returns none if any function returns none" do
      list = [1, 2, 3]

      result =
        Maybe.traverse(list, fn
          2 -> :none
          x -> {:some, x * 2}
        end)

      assert result == :none
    end

    test "filter_map/2 maps and filters in one pass" do
      list = [1, 2, 3, 4]

      result =
        Maybe.filter_map(list, fn
          x when rem(x, 2) == 0 -> {:some, x * 10}
          _ -> :none
        end)

      assert result == [20, 40]
    end
  end

  describe "flattening" do
    test "flatten/1 flattens nested some" do
      assert Maybe.flatten({:some, {:some, 42}}) == {:some, 42}
    end

    test "flatten/1 returns none for some containing none" do
      assert Maybe.flatten({:some, :none}) == :none
    end

    test "flatten/1 returns none for none" do
      assert Maybe.flatten(:none) == :none
    end

    test "flatten/1 handles non-nested some" do
      assert Maybe.flatten({:some, 42}) == {:some, 42}
    end
  end

  describe "applicative" do
    test "apply/2 applies wrapped function to wrapped value" do
      assert Maybe.apply({:some, &String.upcase/1}, {:some, "hello"}) == {:some, "HELLO"}
    end

    test "apply/2 returns none if function is none" do
      assert Maybe.apply(:none, {:some, "hello"}) == :none
    end

    test "apply/2 returns none if value is none" do
      assert Maybe.apply({:some, &String.upcase/1}, :none) == :none
    end

    test "apply/3 applies wrapped 2-arity function" do
      add = fn a, b -> a + b end
      assert Maybe.apply({:some, add}, {:some, 1}, {:some, 2}) == {:some, 3}
    end

    test "apply/3 returns none if any argument is none" do
      add = fn a, b -> a + b end
      assert Maybe.apply(:none, {:some, 1}, {:some, 2}) == :none
      assert Maybe.apply({:some, add}, :none, {:some, 2}) == :none
      assert Maybe.apply({:some, add}, {:some, 1}, :none) == :none
    end
  end

  describe "zipping" do
    test "zip/2 combines two some values" do
      assert Maybe.zip({:some, 1}, {:some, 2}) == {:some, {1, 2}}
    end

    test "zip/2 returns none if either is none" do
      assert Maybe.zip(:none, {:some, 2}) == :none
      assert Maybe.zip({:some, 1}, :none) == :none
    end

    test "zip_with/3 combines with function" do
      assert Maybe.zip_with({:some, 2}, {:some, 3}, &(&1 + &2)) == {:some, 5}
    end

    test "zip_all/1 collects list of maybes" do
      assert Maybe.zip_all([{:some, 1}, {:some, 2}]) == {:some, [1, 2]}
      assert Maybe.zip_all([{:some, 1}, :none]) == :none
    end
  end

  describe "combining" do
    test "combine/2 combines two some values into tuple" do
      assert Maybe.combine({:some, 1}, {:some, 2}) == {:some, {1, 2}}
    end

    test "combine/2 returns none if either is none" do
      assert Maybe.combine(:none, {:some, 2}) == :none
      assert Maybe.combine({:some, 1}, :none) == :none
    end

    test "combine_with/3 combines with function" do
      assert Maybe.combine_with({:some, 2}, {:some, 3}, &(&1 + &2)) == {:some, 5}
    end

    test "first_some/1 returns first some lazily" do
      result =
        Maybe.first_some([
          fn -> :none end,
          fn -> {:some, 42} end,
          fn -> raise "should not be called" end
        ])

      assert result == {:some, 42}
    end

    test "first_some/1 returns none if all are none" do
      result = Maybe.first_some([fn -> :none end, fn -> :none end])
      assert result == :none
    end
  end

  describe "conditional creation" do
    test "when_true/2 returns some for true" do
      assert Maybe.when_true(true, 42) == {:some, 42}
    end

    test "when_true/2 returns none for false" do
      assert Maybe.when_true(false, 42) == :none
    end

    test "unless_true/2 returns some for false" do
      assert Maybe.unless_true(false, 42) == {:some, 42}
    end

    test "unless_true/2 returns none for true" do
      assert Maybe.unless_true(true, 42) == :none
    end

    test "when_true_lazy/2 evaluates lazily" do
      assert Maybe.when_true_lazy(true, fn -> 42 end) == {:some, 42}
      assert Maybe.when_true_lazy(false, fn -> raise "not called" end) == :none
    end

    test "unless_true_lazy/2 evaluates lazily" do
      assert Maybe.unless_true_lazy(false, fn -> 42 end) == {:some, 42}
      assert Maybe.unless_true_lazy(true, fn -> raise "not called" end) == :none
    end
  end

  describe "utility" do
    test "tap_some/2 executes side effect for some" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      result =
        {:some, 42}
        |> Maybe.tap_some(fn v -> Agent.update(agent, fn _ -> v end) end)

      assert result == {:some, 42}
      assert Agent.get(agent, & &1) == 42
    end

    test "tap_some/2 does nothing for none" do
      result =
        :none
        |> Maybe.tap_some(fn _ -> raise "should not be called" end)

      assert result == :none
    end

    test "tap_none/2 executes side effect for none" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      result =
        :none
        |> Maybe.tap_none(fn -> Agent.update(agent, fn _ -> :called end) end)

      assert result == :none
      assert Agent.get(agent, & &1) == :called
    end
  end

  describe "map/struct access" do
    test "get/2 returns some for existing key with value" do
      assert Maybe.get(%{name: "Alice"}, :name) == {:some, "Alice"}
    end

    test "get/2 returns none for missing key" do
      assert Maybe.get(%{name: "Alice"}, :age) == :none
    end

    test "get/2 returns none for nil value" do
      assert Maybe.get(%{name: nil}, :name) == :none
    end

    test "fetch_path/2 fetches nested values" do
      map = %{user: %{profile: %{name: "Alice"}}}
      assert Maybe.fetch_path(map, [:user, :profile, :name]) == {:some, "Alice"}
    end

    test "fetch_path/2 returns none for missing path" do
      map = %{user: %{profile: nil}}
      assert Maybe.fetch_path(map, [:user, :profile, :name]) == :none
    end
  end

  describe "function lifting" do
    test "lift/1 lifts unary function" do
      upcase = Maybe.lift(&String.upcase/1)
      assert upcase.({:some, "hello"}) == {:some, "HELLO"}
      assert upcase.(:none) == :none
    end

    test "lift/1 lifts binary function" do
      add = Maybe.lift(&+/2)
      assert add.({:some, 1}, {:some, 2}) == {:some, 3}
      assert add.({:some, 1}, :none) == :none
      assert add.(:none, {:some, 2}) == :none
    end

    test "lift_apply/2 applies lifted unary function" do
      assert Maybe.lift_apply(&String.upcase/1, {:some, "hello"}) == {:some, "HELLO"}
      assert Maybe.lift_apply(&String.upcase/1, :none) == :none
    end

    test "lift_apply/3 applies lifted binary function" do
      assert Maybe.lift_apply(&+/2, {:some, 1}, {:some, 2}) == {:some, 3}
    end
  end

  describe "enumerable support" do
    test "to_enum/1 converts some to list" do
      assert Maybe.to_enum({:some, 42}) == [42]
    end

    test "to_enum/1 converts none to empty list" do
      assert Maybe.to_enum(:none) == []
    end

    test "to_enum/1 works with Enum functions" do
      result = {:some, 5} |> Maybe.to_enum() |> Enum.map(&(&1 * 2))
      assert result == [10]
    end

    test "reduce/3 reduces over some value" do
      assert Maybe.reduce({:some, 5}, 0, &+/2) == 5
    end

    test "reduce/3 returns accumulator for none" do
      assert Maybe.reduce(:none, 0, &+/2) == 0
    end
  end
end
