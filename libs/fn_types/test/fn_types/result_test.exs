defmodule FnTypes.ResultTest do
  use ExUnit.Case, async: true

  alias FnTypes.Result

  # ============================================
  # Creation
  # ============================================

  describe "Result.ok/1" do
    test "creates ok tuple with value" do
      assert Result.ok(42) == {:ok, 42}
    end

    test "creates ok tuple with nil" do
      assert Result.ok(nil) == {:ok, nil}
    end

    test "creates ok tuple with complex value" do
      assert Result.ok(%{a: 1, b: [1, 2, 3]}) == {:ok, %{a: 1, b: [1, 2, 3]}}
    end
  end

  describe "Result.error/1" do
    test "creates error tuple with atom" do
      assert Result.error(:not_found) == {:error, :not_found}
    end

    test "creates error tuple with string" do
      assert Result.error("something went wrong") == {:error, "something went wrong"}
    end

    test "creates error tuple with complex value" do
      assert Result.error(%{reason: :validation, fields: [:name]}) ==
               {:error, %{reason: :validation, fields: [:name]}}
    end
  end

  # ============================================
  # Type Checking
  # ============================================

  describe "Result.ok?/1" do
    test "returns true for ok tuples" do
      assert Result.ok?({:ok, 42}) == true
      assert Result.ok?({:ok, nil}) == true
    end

    test "returns false for error tuples" do
      assert Result.ok?({:error, :not_found}) == false
    end

    test "returns false for non-result values" do
      assert Result.ok?(:ok) == false
      assert Result.ok?(42) == false
      assert Result.ok?(nil) == false
    end
  end

  describe "Result.error?/1" do
    test "returns true for error tuples" do
      assert Result.error?({:error, :not_found}) == true
      assert Result.error?({:error, nil}) == true
    end

    test "returns false for ok tuples" do
      assert Result.error?({:ok, 42}) == false
    end

    test "returns false for non-result values" do
      assert Result.error?(:error) == false
      assert Result.error?(42) == false
      assert Result.error?(nil) == false
    end
  end

  # ============================================
  # Transformation
  # ============================================

  describe "Result.map/2" do
    test "maps over ok value" do
      assert Result.map({:ok, 5}, &(&1 * 2)) == {:ok, 10}
    end

    test "transforms string" do
      assert Result.map({:ok, "hello"}, &String.upcase/1) == {:ok, "HELLO"}
    end

    test "passes through error unchanged" do
      assert Result.map({:error, :not_found}, &(&1 * 2)) == {:error, :not_found}
    end

    test "can change value type" do
      assert Result.map({:ok, 5}, &Integer.to_string/1) == {:ok, "5"}
    end
  end

  describe "Result.map_error/2" do
    test "maps over error value" do
      assert Result.map_error({:error, "not found"}, &String.upcase/1) == {:error, "NOT FOUND"}
    end

    test "passes through ok unchanged" do
      assert Result.map_error({:ok, 42}, &String.upcase/1) == {:ok, 42}
    end

    test "can transform error type" do
      result = Result.map_error({:error, :not_found}, fn _ -> "Resource not found" end)
      assert result == {:error, "Resource not found"}
    end
  end

  describe "Result.bimap/3" do
    test "maps ok value with first function" do
      assert Result.bimap({:ok, 5}, &(&1 * 2), &String.upcase/1) == {:ok, 10}
    end

    test "maps error value with second function" do
      assert Result.bimap({:error, "bad"}, &(&1 * 2), &String.upcase/1) == {:error, "BAD"}
    end
  end

  # ============================================
  # Chaining
  # ============================================

  describe "Result.and_then/2" do
    test "chains ok values" do
      result =
        {:ok, 5}
        |> Result.and_then(fn x -> {:ok, x * 2} end)
        |> Result.and_then(fn x -> {:ok, x + 1} end)

      assert result == {:ok, 11}
    end

    test "short-circuits on error" do
      result =
        {:ok, 5}
        |> Result.and_then(fn _ -> {:error, :failed} end)
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:error, :failed}
    end

    test "passes through initial error" do
      result =
        {:error, :initial}
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:error, :initial}
    end

    test "allows transformation of value type" do
      result =
        {:ok, "42"}
        |> Result.and_then(fn s -> {:ok, String.to_integer(s)} end)

      assert result == {:ok, 42}
    end
  end

  describe "Result.or_else/2" do
    test "returns ok as-is" do
      result = Result.or_else({:ok, 42}, fn _ -> {:ok, :default} end)
      assert result == {:ok, 42}
    end

    test "applies function on error" do
      result = Result.or_else({:error, :not_found}, fn _ -> {:ok, :default} end)
      assert result == {:ok, :default}
    end

    test "can recover with different error" do
      result = Result.or_else({:error, :not_found}, fn reason -> {:error, {:wrapped, reason}} end)
      assert result == {:error, {:wrapped, :not_found}}
    end

    test "receives error reason in function" do
      result = Result.or_else({:error, :original}, fn reason -> {:ok, reason} end)
      assert result == {:ok, :original}
    end
  end

  # ============================================
  # Extraction
  # ============================================

  describe "Result.unwrap!/1" do
    test "returns value for ok" do
      assert Result.unwrap!({:ok, 42}) == 42
    end

    test "raises for error" do
      assert_raise ArgumentError, ~r/Expected {:ok, value}/, fn ->
        Result.unwrap!({:error, :not_found})
      end
    end
  end

  describe "Result.unwrap_or/2" do
    test "returns value for ok" do
      assert Result.unwrap_or({:ok, 42}, 0) == 42
    end

    test "returns default for error" do
      assert Result.unwrap_or({:error, :not_found}, 0) == 0
    end

    test "returns nil if that's the ok value" do
      assert Result.unwrap_or({:ok, nil}, 0) == nil
    end
  end

  describe "Result.unwrap_or_else/2" do
    test "returns value for ok" do
      assert Result.unwrap_or_else({:ok, 42}, fn _ -> 0 end) == 42
    end

    test "calls function for error" do
      result = Result.unwrap_or_else({:error, :not_found}, fn reason -> "Error: #{reason}" end)
      assert result == "Error: not_found"
    end
  end

  describe "Result.unwrap/1" do
    test "returns ok tuple as-is" do
      assert Result.unwrap({:ok, 42}) == {:ok, 42}
    end

    test "returns error tuple as-is" do
      assert Result.unwrap({:error, :not_found}) == {:error, :not_found}
    end
  end

  # ============================================
  # Flattening
  # ============================================

  describe "Result.flatten/1" do
    test "flattens nested ok" do
      assert Result.flatten({:ok, {:ok, 42}}) == {:ok, 42}
    end

    test "flattens nested error" do
      assert Result.flatten({:ok, {:error, :inner}}) == {:error, :inner}
    end

    test "returns outer error" do
      assert Result.flatten({:error, :outer}) == {:error, :outer}
    end

    test "wraps non-nested value" do
      assert Result.flatten({:ok, 42}) == {:ok, 42}
    end
  end

  # ============================================
  # Creation from Nilable
  # ============================================

  describe "Result.from_nilable/2" do
    test "converts non-nil to ok" do
      assert Result.from_nilable(42, :not_found) == {:ok, 42}
    end

    test "converts nil to error" do
      assert Result.from_nilable(nil, :not_found) == {:error, :not_found}
    end

    test "false is not nil" do
      assert Result.from_nilable(false, :not_found) == {:ok, false}
    end

    test "empty string is not nil" do
      assert Result.from_nilable("", :not_found) == {:ok, ""}
    end

    test "0 is not nil" do
      assert Result.from_nilable(0, :not_found) == {:ok, 0}
    end
  end

  describe "Result.from_nilable_lazy/2" do
    test "converts non-nil to ok without calling error function" do
      result = Result.from_nilable_lazy(42, fn -> raise "should not be called" end)
      assert result == {:ok, 42}
    end

    test "converts nil to error by calling function" do
      result = Result.from_nilable_lazy(nil, fn -> :computed_error end)
      assert result == {:error, :computed_error}
    end
  end

  # ============================================
  # Collection Operations
  # ============================================

  describe "Result.collect/1" do
    test "collects all ok values" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      assert Result.collect(results) == {:ok, [1, 2, 3]}
    end

    test "returns first error" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 3}]
      assert Result.collect(results) == {:error, :bad}
    end

    test "handles empty list" do
      assert Result.collect([]) == {:ok, []}
    end

    test "preserves order" do
      results = [{:ok, "a"}, {:ok, "b"}, {:ok, "c"}]
      assert Result.collect(results) == {:ok, ["a", "b", "c"]}
    end
  end

  describe "Result.traverse/2" do
    test "applies function to each element" do
      assert Result.traverse([1, 2, 3], fn x -> {:ok, x * 2} end) == {:ok, [2, 4, 6]}
    end

    test "stops on first error" do
      result =
        Result.traverse([1, 2, 3], fn
          2 -> {:error, :bad}
          x -> {:ok, x * 2}
        end)

      assert result == {:error, :bad}
    end

    test "handles empty list" do
      assert Result.traverse([], fn x -> {:ok, x} end) == {:ok, []}
    end
  end

  describe "Result.partition/1" do
    test "separates ok and error values" do
      results = [{:ok, 1}, {:error, :a}, {:ok, 2}, {:error, :b}]
      assert Result.partition(results) == %{ok: [1, 2], errors: [:a, :b]}
    end

    test "handles all ok values" do
      results = [{:ok, 1}, {:ok, 2}]
      assert Result.partition(results) == %{ok: [1, 2], errors: []}
    end

    test "handles all error values" do
      results = [{:error, :a}]
      assert Result.partition(results) == %{ok: [], errors: [:a]}
    end

    test "handles empty list" do
      assert Result.partition([]) == %{ok: [], errors: []}
    end
  end

  describe "Result.cat_ok/1" do
    test "filters and unwraps ok values" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 2}]
      assert Result.cat_ok(results) == [1, 2]
    end

    test "returns empty list for all errors" do
      results = [{:error, :a}, {:error, :b}]
      assert Result.cat_ok(results) == []
    end
  end

  describe "Result.cat_errors/1" do
    test "filters error reasons" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 2}, {:error, :worse}]
      assert Result.cat_errors(results) == [:bad, :worse]
    end

    test "returns empty list for all ok values" do
      results = [{:ok, 1}, {:ok, 2}]
      assert Result.cat_errors(results) == []
    end
  end

  # ============================================
  # Combination
  # ============================================

  describe "Result.combine/2" do
    test "combines two ok values into tuple" do
      assert Result.combine({:ok, 1}, {:ok, 2}) == {:ok, {1, 2}}
    end

    test "returns first error" do
      assert Result.combine({:error, :first}, {:ok, 2}) == {:error, :first}
    end

    test "returns second error if first is ok" do
      assert Result.combine({:ok, 1}, {:error, :second}) == {:error, :second}
    end

    test "returns first error when both are errors" do
      assert Result.combine({:error, :first}, {:error, :second}) == {:error, :first}
    end
  end

  describe "Result.combine_with/3" do
    test "combines two ok values with function" do
      assert Result.combine_with({:ok, 2}, {:ok, 3}, &(&1 + &2)) == {:ok, 5}
    end

    test "returns first error" do
      assert Result.combine_with({:error, :bad}, {:ok, 3}, &(&1 + &2)) == {:error, :bad}
    end
  end

  describe "Result.zip/2" do
    test "zips two ok values" do
      assert Result.zip({:ok, 1}, {:ok, 2}) == {:ok, {1, 2}}
    end

    test "returns error if either fails" do
      assert Result.zip({:error, :a}, {:ok, 2}) == {:error, :a}
    end
  end

  describe "Result.zip_with/3" do
    test "zips with combining function" do
      assert Result.zip_with({:ok, 2}, {:ok, 3}, &+/2) == {:ok, 5}
    end
  end

  # ============================================
  # Conversion
  # ============================================

  describe "Result.to_bool/1" do
    test "converts ok to true" do
      assert Result.to_bool({:ok, 42}) == true
    end

    test "converts error to false" do
      assert Result.to_bool({:error, :not_found}) == false
    end
  end

  describe "Result.to_option/1" do
    test "converts ok to value" do
      assert Result.to_option({:ok, 42}) == 42
    end

    test "converts error to nil" do
      assert Result.to_option({:error, :not_found}) == nil
    end
  end

  describe "Result.to_enum/1" do
    test "converts ok to single-element list" do
      assert Result.to_enum({:ok, 42}) == [42]
    end

    test "converts error to empty list" do
      assert Result.to_enum({:error, :bad}) == []
    end
  end

  describe "Result.reduce/3" do
    test "reduces ok value" do
      assert Result.reduce({:ok, 5}, 0, &+/2) == 5
    end

    test "returns accumulator for error" do
      assert Result.reduce({:error, :bad}, 0, &+/2) == 0
    end
  end

  # ============================================
  # Utility
  # ============================================

  describe "Result.tap/2" do
    test "executes side effect for ok" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      {:ok, 42}
      |> Result.tap(fn value -> Agent.update(pid, fn _ -> value end) end)

      assert Agent.get(pid, & &1) == 42
      Agent.stop(pid)
    end

    test "returns original result" do
      assert Result.tap({:ok, 42}, fn _ -> :ignored end) == {:ok, 42}
    end

    test "skips side effect for error" do
      {:ok, pid} = Agent.start_link(fn -> :initial end)

      {:error, :bad}
      |> Result.tap(fn _ -> Agent.update(pid, fn _ -> :changed end) end)

      assert Agent.get(pid, & &1) == :initial
      Agent.stop(pid)
    end
  end

  describe "Result.tap_error/2" do
    test "executes side effect for error" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      {:error, :bad}
      |> Result.tap_error(fn reason -> Agent.update(pid, fn _ -> reason end) end)

      assert Agent.get(pid, & &1) == :bad
      Agent.stop(pid)
    end

    test "skips side effect for ok" do
      {:ok, pid} = Agent.start_link(fn -> :initial end)

      {:ok, 42}
      |> Result.tap_error(fn _ -> Agent.update(pid, fn _ -> :changed end) end)

      assert Agent.get(pid, & &1) == :initial
      Agent.stop(pid)
    end
  end

  describe "Result.swap/1" do
    test "swaps ok to error" do
      assert Result.swap({:ok, 42}) == {:error, 42}
    end

    test "swaps error to ok" do
      assert Result.swap({:error, :not_found}) == {:ok, :not_found}
    end
  end

  # ============================================
  # Applicative
  # ============================================

  describe "Result.apply/2" do
    test "applies wrapped function to wrapped value" do
      assert Result.apply({:ok, &String.upcase/1}, {:ok, "hello"}) == {:ok, "HELLO"}
    end

    test "returns error if function is error" do
      assert Result.apply({:error, :no_fn}, {:ok, "hello"}) == {:error, :no_fn}
    end

    test "returns error if value is error" do
      assert Result.apply({:ok, &String.upcase/1}, {:error, :no_val}) == {:error, :no_val}
    end
  end

  describe "Result.apply/3" do
    test "applies wrapped 2-arity function" do
      assert Result.apply({:ok, &+/2}, {:ok, 1}, {:ok, 2}) == {:ok, 3}
    end

    test "returns error if any argument is error" do
      assert Result.apply({:ok, &+/2}, {:error, :a}, {:ok, 2}) == {:error, :a}
    end
  end

  # ============================================
  # Function Lifting
  # ============================================

  describe "Result.lift/1" do
    test "lifts 1-arity function" do
      upcase = Result.lift(&String.upcase/1)
      assert upcase.({:ok, "hello"}) == {:ok, "HELLO"}
      assert upcase.({:error, :bad}) == {:error, :bad}
    end

    test "lifts 2-arity function" do
      add = Result.lift(&(&1 + &2))
      assert add.({:ok, 1}, {:ok, 2}) == {:ok, 3}
    end
  end

  describe "Result.lift_apply/2" do
    test "lifts and applies 1-arity function" do
      assert Result.lift_apply(&String.upcase/1, {:ok, "hello"}) == {:ok, "HELLO"}
    end
  end

  describe "Result.lift_apply/3" do
    test "lifts and applies 2-arity function" do
      assert Result.lift_apply(&+/2, {:ok, 1}, {:ok, 2}) == {:ok, 3}
    end
  end

  # ============================================
  # Exception Handling
  # ============================================

  describe "Result.try_with/1" do
    test "wraps successful result" do
      assert Result.try_with(fn -> 1 + 1 end) == {:ok, 2}
    end

    test "catches exceptions" do
      {:error, error} = Result.try_with(fn -> raise "boom" end)
      assert %RuntimeError{message: "boom"} = error
    end

    test "catches throw" do
      {:error, error} = Result.try_with(fn -> throw(:ball) end)
      assert error == {:throw, :ball}
    end

    test "catches exit" do
      {:error, error} = Result.try_with(fn -> exit(:normal) end)
      assert error == {:exit, :normal}
    end
  end

  describe "Result.try_with/2" do
    test "passes argument to function" do
      assert Result.try_with(fn x -> x * 2 end, 5) == {:ok, 10}
    end

    test "catches exceptions with argument" do
      {:error, error} = Result.try_with(fn _ -> raise "boom" end, 5)
      assert %RuntimeError{message: "boom"} = error
    end
  end

  # ============================================
  # Step Context
  # ============================================

  describe "Result.with_step/2" do
    test "wraps error with step name" do
      result = Result.with_step({:error, :not_found}, :fetch_user)
      assert result == {:error, {:step_failed, :fetch_user, :not_found}}
    end

    test "passes through ok" do
      result = Result.with_step({:ok, 42}, :fetch_user)
      assert result == {:ok, 42}
    end
  end

  describe "Result.unwrap_step/1" do
    test "unwraps step-wrapped error" do
      result = Result.unwrap_step({:error, {:step_failed, :fetch, :not_found}})
      assert result == {:error, :not_found}
    end

    test "passes through simple error" do
      result = Result.unwrap_step({:error, :simple_error})
      assert result == {:error, :simple_error}
    end

    test "passes through ok" do
      result = Result.unwrap_step({:ok, 42})
      assert result == {:ok, 42}
    end
  end

  # ============================================
  # Pipeline Composition
  # ============================================

  describe "Result pipeline composition" do
    test "chains multiple operations" do
      result =
        {:ok, "  hello world  "}
        |> Result.map(&String.trim/1)
        |> Result.map(&String.upcase/1)
        |> Result.and_then(fn s ->
          if String.length(s) > 5, do: {:ok, s}, else: {:error, :too_short}
        end)

      assert result == {:ok, "HELLO WORLD"}
    end

    test "short-circuits on error" do
      called = Agent.start_link(fn -> false end) |> elem(1)

      result =
        {:ok, "hi"}
        |> Result.and_then(fn _ -> {:error, :failed} end)
        |> Result.map(fn s ->
          Agent.update(called, fn _ -> true end)
          s
        end)

      assert result == {:error, :failed}
      assert Agent.get(called, & &1) == false
      Agent.stop(called)
    end

    test "recovers from error" do
      result =
        {:error, :not_found}
        |> Result.or_else(fn _ -> {:ok, :default} end)
        |> Result.map(&Atom.to_string/1)

      assert result == {:ok, "default"}
    end
  end
end
