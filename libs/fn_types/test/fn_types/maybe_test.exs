defmodule FnTypes.MaybeTest do
  use ExUnit.Case, async: true

  alias FnTypes.Maybe

  # ============================================
  # Creation
  # ============================================

  describe "Maybe.some/1" do
    test "creates some tuple with value" do
      assert Maybe.some(42) == {:some, 42}
    end

    test "creates some tuple with nil - wraps nil explicitly" do
      assert Maybe.some(nil) == {:some, nil}
    end

    test "creates some tuple with complex value" do
      assert Maybe.some(%{a: 1, b: [1, 2, 3]}) == {:some, %{a: 1, b: [1, 2, 3]}}
    end
  end

  describe "Maybe.none/0" do
    test "creates none" do
      assert Maybe.none() == :none
    end
  end

  # ============================================
  # Type Checking
  # ============================================

  describe "Maybe.some?/1" do
    test "returns true for some tuples" do
      assert Maybe.some?({:some, 42}) == true
      assert Maybe.some?({:some, nil}) == true
    end

    test "returns false for none" do
      assert Maybe.some?(:none) == false
    end

    test "returns false for non-maybe values" do
      assert Maybe.some?(:some) == false
      assert Maybe.some?(42) == false
      assert Maybe.some?(nil) == false
    end
  end

  describe "Maybe.none?/1" do
    test "returns true for none" do
      assert Maybe.none?(:none) == true
    end

    test "returns false for some tuples" do
      assert Maybe.none?({:some, 42}) == false
    end

    test "returns false for non-maybe values" do
      assert Maybe.none?(:nothing) == false
      assert Maybe.none?(nil) == false
    end
  end

  # ============================================
  # Creation from Values
  # ============================================

  describe "Maybe.from_nilable/1" do
    test "converts non-nil to some" do
      assert Maybe.from_nilable(42) == {:some, 42}
    end

    test "converts nil to none" do
      assert Maybe.from_nilable(nil) == :none
    end

    test "false is not nil" do
      assert Maybe.from_nilable(false) == {:some, false}
    end

    test "0 is not nil" do
      assert Maybe.from_nilable(0) == {:some, 0}
    end

    test "empty string is not nil" do
      assert Maybe.from_nilable("") == {:some, ""}
    end
  end

  describe "Maybe.from_result/1" do
    test "converts ok to some" do
      assert Maybe.from_result({:ok, 42}) == {:some, 42}
    end

    test "converts error to none" do
      assert Maybe.from_result({:error, :not_found}) == :none
    end
  end

  describe "Maybe.from_bool/2" do
    test "returns some when true" do
      assert Maybe.from_bool(true, "yes") == {:some, "yes"}
    end

    test "returns none when false" do
      assert Maybe.from_bool(false, "yes") == :none
    end
  end

  describe "Maybe.from_string/1" do
    test "converts non-empty string to some" do
      assert Maybe.from_string("hello") == {:some, "hello"}
    end

    test "converts empty string to none" do
      assert Maybe.from_string("") == :none
    end

    test "converts whitespace-only string to none" do
      assert Maybe.from_string("   ") == :none
      assert Maybe.from_string("\t\n") == :none
    end

    test "trims whitespace from result" do
      assert Maybe.from_string("  hello  ") == {:some, "hello"}
    end

    test "converts nil to none" do
      assert Maybe.from_string(nil) == :none
    end
  end

  describe "Maybe.from_list/1" do
    test "converts non-empty list to some" do
      assert Maybe.from_list([1, 2, 3]) == {:some, [1, 2, 3]}
    end

    test "converts empty list to none" do
      assert Maybe.from_list([]) == :none
    end
  end

  describe "Maybe.from_map/1" do
    test "converts non-empty map to some" do
      assert Maybe.from_map(%{a: 1}) == {:some, %{a: 1}}
    end

    test "converts empty map to none" do
      assert Maybe.from_map(%{}) == :none
    end
  end

  # ============================================
  # Transformation
  # ============================================

  describe "Maybe.map/2" do
    test "maps over some value" do
      assert Maybe.map({:some, 5}, &(&1 * 2)) == {:some, 10}
    end

    test "transforms string" do
      assert Maybe.map({:some, "hello"}, &String.upcase/1) == {:some, "HELLO"}
    end

    test "passes through none" do
      assert Maybe.map(:none, &(&1 * 2)) == :none
    end

    test "can change value type" do
      assert Maybe.map({:some, 5}, &Integer.to_string/1) == {:some, "5"}
    end
  end

  describe "Maybe.replace/2" do
    test "replaces value if some" do
      assert Maybe.replace({:some, 5}, 42) == {:some, 42}
    end

    test "returns none if none" do
      assert Maybe.replace(:none, 42) == :none
    end
  end

  # ============================================
  # Chaining
  # ============================================

  describe "Maybe.and_then/2" do
    test "chains some values" do
      result =
        {:some, 5}
        |> Maybe.and_then(fn x -> {:some, x * 2} end)
        |> Maybe.and_then(fn x -> {:some, x + 1} end)

      assert result == {:some, 11}
    end

    test "short-circuits on none" do
      result =
        {:some, 5}
        |> Maybe.and_then(fn _ -> :none end)
        |> Maybe.and_then(fn x -> {:some, x * 2} end)

      assert result == :none
    end

    test "passes through initial none" do
      result = :none |> Maybe.and_then(fn x -> {:some, x * 2} end)
      assert result == :none
    end
  end

  describe "Maybe.or_else/2" do
    test "returns some as-is" do
      result = Maybe.or_else({:some, 42}, fn -> {:some, 0} end)
      assert result == {:some, 42}
    end

    test "calls function on none" do
      result = Maybe.or_else(:none, fn -> {:some, :default} end)
      assert result == {:some, :default}
    end
  end

  describe "Maybe.or_value/2" do
    test "returns first some" do
      assert Maybe.or_value({:some, 1}, {:some, 2}) == {:some, 1}
    end

    test "returns second if first is none" do
      assert Maybe.or_value(:none, {:some, 2}) == {:some, 2}
    end

    test "returns none if both are none" do
      assert Maybe.or_value(:none, :none) == :none
    end
  end

  # ============================================
  # Filtering
  # ============================================

  describe "Maybe.filter/2" do
    test "keeps value when predicate is true" do
      assert Maybe.filter({:some, 5}, &(&1 > 3)) == {:some, 5}
    end

    test "returns none when predicate is false" do
      assert Maybe.filter({:some, 2}, &(&1 > 3)) == :none
    end

    test "passes through none" do
      assert Maybe.filter(:none, &(&1 > 3)) == :none
    end
  end

  describe "Maybe.reject/2" do
    test "returns none when predicate is true" do
      assert Maybe.reject({:some, 5}, &(&1 > 3)) == :none
    end

    test "keeps value when predicate is false" do
      assert Maybe.reject({:some, 2}, &(&1 > 3)) == {:some, 2}
    end

    test "passes through none" do
      assert Maybe.reject(:none, &(&1 > 3)) == :none
    end
  end

  # ============================================
  # Extraction
  # ============================================

  describe "Maybe.unwrap!/1" do
    test "returns value for some" do
      assert Maybe.unwrap!({:some, 42}) == 42
    end

    test "raises for none" do
      assert_raise ArgumentError, ~r/Expected {:some, value}/, fn ->
        Maybe.unwrap!(:none)
      end
    end
  end

  describe "Maybe.unwrap_or/2" do
    test "returns value for some" do
      assert Maybe.unwrap_or({:some, 42}, 0) == 42
    end

    test "returns default for none" do
      assert Maybe.unwrap_or(:none, 0) == 0
    end
  end

  describe "Maybe.unwrap_or_else/2" do
    test "returns value for some" do
      assert Maybe.unwrap_or_else({:some, 42}, fn -> 0 end) == 42
    end

    test "calls function for none" do
      result = Maybe.unwrap_or_else(:none, fn -> :computed_default end)
      assert result == :computed_default
    end
  end

  describe "Maybe.to_nilable/1" do
    test "converts some to value" do
      assert Maybe.to_nilable({:some, 42}) == 42
    end

    test "converts none to nil" do
      assert Maybe.to_nilable(:none) == nil
    end
  end

  # ============================================
  # Conversion
  # ============================================

  describe "Maybe.to_result/2" do
    test "converts some to ok" do
      assert Maybe.to_result({:some, 42}, :not_found) == {:ok, 42}
    end

    test "converts none to error" do
      assert Maybe.to_result(:none, :not_found) == {:error, :not_found}
    end
  end

  describe "Maybe.to_bool/1" do
    test "converts some to true" do
      assert Maybe.to_bool({:some, 42}) == true
    end

    test "converts none to false" do
      assert Maybe.to_bool(:none) == false
    end
  end

  describe "Maybe.to_list/1" do
    test "converts some to single-element list" do
      assert Maybe.to_list({:some, 42}) == [42]
    end

    test "converts none to empty list" do
      assert Maybe.to_list(:none) == []
    end
  end

  describe "Maybe.to_enum/1" do
    test "converts some to single-element list" do
      assert Maybe.to_enum({:some, 42}) == [42]
    end

    test "converts none to empty list" do
      assert Maybe.to_enum(:none) == []
    end
  end

  describe "Maybe.reduce/3" do
    test "reduces some value" do
      assert Maybe.reduce({:some, 5}, 0, &+/2) == 5
    end

    test "returns accumulator for none" do
      assert Maybe.reduce(:none, 0, &+/2) == 0
    end
  end

  # ============================================
  # Collection Operations
  # ============================================

  describe "Maybe.collect/1" do
    test "collects all some values" do
      maybes = [{:some, 1}, {:some, 2}, {:some, 3}]
      assert Maybe.collect(maybes) == {:some, [1, 2, 3]}
    end

    test "returns none if any is none" do
      maybes = [{:some, 1}, :none, {:some, 3}]
      assert Maybe.collect(maybes) == :none
    end

    test "handles empty list" do
      assert Maybe.collect([]) == {:some, []}
    end

    test "preserves order" do
      maybes = [{:some, "a"}, {:some, "b"}, {:some, "c"}]
      assert Maybe.collect(maybes) == {:some, ["a", "b", "c"]}
    end
  end

  describe "Maybe.traverse/2" do
    test "applies function to each element" do
      assert Maybe.traverse([1, 2, 3], fn x -> {:some, x * 2} end) == {:some, [2, 4, 6]}
    end

    test "returns none on first failure" do
      result =
        Maybe.traverse([1, 2, 3], fn
          2 -> :none
          x -> {:some, x * 2}
        end)

      assert result == :none
    end

    test "handles empty list" do
      assert Maybe.traverse([], fn x -> {:some, x} end) == {:some, []}
    end
  end

  describe "Maybe.cat_somes/1" do
    test "filters and unwraps some values" do
      maybes = [{:some, 1}, :none, {:some, 3}]
      assert Maybe.cat_somes(maybes) == [1, 3]
    end

    test "returns empty list for all nones" do
      maybes = [:none, :none]
      assert Maybe.cat_somes(maybes) == []
    end
  end

  describe "Maybe.filter_map/2" do
    test "maps and filters in one pass" do
      result =
        Maybe.filter_map([1, 2, 3, 4], fn
          x when rem(x, 2) == 0 -> {:some, x * 10}
          _ -> :none
        end)

      assert result == [20, 40]
    end
  end

  # ============================================
  # Flattening
  # ============================================

  describe "Maybe.flatten/1" do
    test "flattens nested some" do
      assert Maybe.flatten({:some, {:some, 42}}) == {:some, 42}
    end

    test "flattens some containing none" do
      assert Maybe.flatten({:some, :none}) == :none
    end

    test "returns none as-is" do
      assert Maybe.flatten(:none) == :none
    end

    test "wraps non-nested value" do
      assert Maybe.flatten({:some, 42}) == {:some, 42}
    end
  end

  # ============================================
  # Applicative
  # ============================================

  describe "Maybe.apply/2" do
    test "applies wrapped function to wrapped value" do
      assert Maybe.apply({:some, &String.upcase/1}, {:some, "hello"}) == {:some, "HELLO"}
    end

    test "returns none if function is none" do
      assert Maybe.apply(:none, {:some, "hello"}) == :none
    end

    test "returns none if value is none" do
      assert Maybe.apply({:some, &String.upcase/1}, :none) == :none
    end
  end

  describe "Maybe.apply/3" do
    test "applies wrapped 2-arity function" do
      assert Maybe.apply({:some, fn a, b -> a + b end}, {:some, 1}, {:some, 2}) == {:some, 3}
    end

    test "returns none if any argument is none" do
      assert Maybe.apply({:some, &+/2}, :none, {:some, 2}) == :none
    end
  end

  # ============================================
  # Zipping and Combining
  # ============================================

  describe "Maybe.zip/2" do
    test "zips two somes" do
      assert Maybe.zip({:some, 1}, {:some, 2}) == {:some, {1, 2}}
    end

    test "returns none if first is none" do
      assert Maybe.zip(:none, {:some, 2}) == :none
    end

    test "returns none if second is none" do
      assert Maybe.zip({:some, 1}, :none) == :none
    end
  end

  describe "Maybe.zip_with/3" do
    test "zips with combining function" do
      assert Maybe.zip_with({:some, 2}, {:some, 3}, &(&1 + &2)) == {:some, 5}
    end

    test "returns none if either is none" do
      assert Maybe.zip_with(:none, {:some, 3}, &(&1 + &2)) == :none
    end

    test "combines strings" do
      assert Maybe.zip_with({:some, "Hello, "}, {:some, "World!"}, &<>/2) ==
               {:some, "Hello, World!"}
    end
  end

  describe "Maybe.zip_all/1" do
    test "zips all somes" do
      assert Maybe.zip_all([{:some, 1}, {:some, 2}, {:some, 3}]) == {:some, [1, 2, 3]}
    end

    test "returns none if any is none" do
      assert Maybe.zip_all([{:some, 1}, :none, {:some, 3}]) == :none
    end
  end

  describe "Maybe.combine/2" do
    test "combines two somes into tuple" do
      assert Maybe.combine({:some, 1}, {:some, 2}) == {:some, {1, 2}}
    end

    test "returns none if either is none" do
      assert Maybe.combine(:none, {:some, 2}) == :none
      assert Maybe.combine({:some, 1}, :none) == :none
    end
  end

  describe "Maybe.combine_with/3" do
    test "combines two somes with function" do
      assert Maybe.combine_with({:some, 2}, {:some, 3}, &(&1 + &2)) == {:some, 5}
    end

    test "returns none if either is none" do
      assert Maybe.combine_with(:none, {:some, 3}, &(&1 + &2)) == :none
    end
  end

  describe "Maybe.first_some/1" do
    test "returns first some value" do
      result =
        Maybe.first_some([
          fn -> :none end,
          fn -> {:some, 42} end,
          fn -> raise "never called" end
        ])

      assert result == {:some, 42}
    end

    test "returns none if all are none" do
      result =
        Maybe.first_some([
          fn -> :none end,
          fn -> :none end
        ])

      assert result == :none
    end

    test "is lazy - stops at first some" do
      {:ok, pid} = Agent.start_link(fn -> 0 end)

      Maybe.first_some([
        fn ->
          Agent.update(pid, &(&1 + 1))
          :none
        end,
        fn ->
          Agent.update(pid, &(&1 + 1))
          {:some, 42}
        end,
        fn ->
          Agent.update(pid, &(&1 + 1))
          {:some, 100}
        end
      ])

      assert Agent.get(pid, & &1) == 2
      Agent.stop(pid)
    end
  end

  # ============================================
  # Utility
  # ============================================

  describe "Maybe.tap_some/2" do
    test "executes side effect for some" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      {:some, 42}
      |> Maybe.tap_some(fn value -> Agent.update(pid, fn _ -> value end) end)

      assert Agent.get(pid, & &1) == 42
      Agent.stop(pid)
    end

    test "returns original maybe" do
      assert Maybe.tap_some({:some, 42}, fn _ -> :ignored end) == {:some, 42}
    end

    test "skips side effect for none" do
      {:ok, pid} = Agent.start_link(fn -> :initial end)

      :none
      |> Maybe.tap_some(fn _ -> Agent.update(pid, fn _ -> :changed end) end)

      assert Agent.get(pid, & &1) == :initial
      Agent.stop(pid)
    end
  end

  describe "Maybe.tap_none/2" do
    test "executes side effect for none" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      :none
      |> Maybe.tap_none(fn -> Agent.update(pid, fn _ -> :executed end) end)

      assert Agent.get(pid, & &1) == :executed
      Agent.stop(pid)
    end

    test "skips side effect for some" do
      {:ok, pid} = Agent.start_link(fn -> :initial end)

      {:some, 42}
      |> Maybe.tap_none(fn -> Agent.update(pid, fn _ -> :changed end) end)

      assert Agent.get(pid, & &1) == :initial
      Agent.stop(pid)
    end
  end

  describe "Maybe.when_true/2" do
    test "returns some when true" do
      assert Maybe.when_true(true, 42) == {:some, 42}
    end

    test "returns none when false" do
      assert Maybe.when_true(false, 42) == :none
    end
  end

  describe "Maybe.when_true_lazy/2" do
    test "returns some with computed value when true" do
      assert Maybe.when_true_lazy(true, fn -> 42 end) == {:some, 42}
    end

    test "returns none without computing when false" do
      result = Maybe.when_true_lazy(false, fn -> raise "should not be called" end)
      assert result == :none
    end
  end

  describe "Maybe.unless_true/2" do
    test "returns some when false" do
      assert Maybe.unless_true(false, 42) == {:some, 42}
    end

    test "returns none when true" do
      assert Maybe.unless_true(true, 42) == :none
    end
  end

  describe "Maybe.unless_true_lazy/2" do
    test "returns some with computed value when false" do
      assert Maybe.unless_true_lazy(false, fn -> 42 end) == {:some, 42}
    end

    test "returns none without computing when true" do
      result = Maybe.unless_true_lazy(true, fn -> raise "should not be called" end)
      assert result == :none
    end
  end

  # ============================================
  # Map/Struct Access
  # ============================================

  describe "Maybe.get/2" do
    test "returns some for existing key" do
      assert Maybe.get(%{name: "Alice"}, :name) == {:some, "Alice"}
    end

    test "returns none for missing key" do
      assert Maybe.get(%{name: "Alice"}, :age) == :none
    end

    test "returns none for nil value" do
      assert Maybe.get(%{name: nil}, :name) == :none
    end
  end

  describe "Maybe.fetch_path/2" do
    test "fetches nested value" do
      data = %{user: %{profile: %{name: "Alice"}}}
      assert Maybe.fetch_path(data, [:user, :profile, :name]) == {:some, "Alice"}
    end

    test "returns none for missing path" do
      data = %{user: %{profile: nil}}
      assert Maybe.fetch_path(data, [:user, :profile, :name]) == :none
    end

    test "returns none for nil in path" do
      data = %{user: nil}
      assert Maybe.fetch_path(data, [:user, :profile, :name]) == :none
    end

    test "handles empty path" do
      assert Maybe.fetch_path(%{a: 1}, []) == {:some, %{a: 1}}
    end
  end

  # ============================================
  # Function Lifting
  # ============================================

  describe "Maybe.lift/1" do
    test "lifts 1-arity function" do
      upcase = Maybe.lift(&String.upcase/1)
      assert upcase.({:some, "hello"}) == {:some, "HELLO"}
      assert upcase.(:none) == :none
    end

    test "lifts 2-arity function" do
      add = Maybe.lift(&(&1 + &2))
      assert add.({:some, 1}, {:some, 2}) == {:some, 3}
    end
  end

  describe "Maybe.lift_apply/2" do
    test "lifts and applies 1-arity function" do
      assert Maybe.lift_apply(&String.upcase/1, {:some, "hello"}) == {:some, "HELLO"}
    end
  end

  describe "Maybe.lift_apply/3" do
    test "lifts and applies 2-arity function" do
      assert Maybe.lift_apply(&+/2, {:some, 1}, {:some, 2}) == {:some, 3}
    end
  end

  # ============================================
  # Pipeline Composition
  # ============================================

  describe "Maybe pipeline composition" do
    test "chains multiple operations" do
      result =
        {:some, "  hello world  "}
        |> Maybe.map(&String.trim/1)
        |> Maybe.map(&String.upcase/1)
        |> Maybe.filter(&(String.length(&1) > 5))

      assert result == {:some, "HELLO WORLD"}
    end

    test "short-circuits on none" do
      called = Agent.start_link(fn -> false end) |> elem(1)

      result =
        {:some, "hi"}
        |> Maybe.filter(&(String.length(&1) > 5))
        |> Maybe.map(fn s ->
          Agent.update(called, fn _ -> true end)
          s
        end)

      assert result == :none
      assert Agent.get(called, & &1) == false
      Agent.stop(called)
    end

    test "recovers from none with or_else" do
      result =
        :none
        |> Maybe.or_else(fn -> {:some, "default"} end)
        |> Maybe.map(&String.upcase/1)

      assert result == {:some, "DEFAULT"}
    end

    test "converts between Result and Maybe" do
      result =
        {:ok, 42}
        |> Maybe.from_result()
        |> Maybe.map(&(&1 * 2))
        |> Maybe.to_result(:not_found)

      assert result == {:ok, 84}
    end
  end
end
