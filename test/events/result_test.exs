defmodule Events.Types.ResultTest do
  use ExUnit.Case, async: true
  # Note: Doctests disabled because examples use short `Result` alias.
  # Comprehensive unit tests below provide full coverage.

  alias Events.Types.Result

  describe "type checking" do
    test "ok?/1 returns true for ok tuples" do
      assert Result.ok?({:ok, 42})
      assert Result.ok?({:ok, nil})
    end

    test "ok?/1 returns false for error tuples" do
      refute Result.ok?({:error, :reason})
    end

    test "error?/1 returns true for error tuples" do
      assert Result.error?({:error, :reason})
      assert Result.error?({:error, nil})
    end

    test "error?/1 returns false for ok tuples" do
      refute Result.error?({:ok, 42})
    end
  end

  describe "creation" do
    test "ok/1 wraps value in ok tuple" do
      assert Result.ok(42) == {:ok, 42}
      assert Result.ok(nil) == {:ok, nil}
    end

    test "error/1 wraps reason in error tuple" do
      assert Result.error(:not_found) == {:error, :not_found}
      assert Result.error("error") == {:error, "error"}
    end
  end

  describe "transformation" do
    test "map/2 transforms ok value" do
      assert Result.map({:ok, 5}, &(&1 * 2)) == {:ok, 10}
    end

    test "map/2 returns error unchanged" do
      assert Result.map({:error, :bad}, &(&1 * 2)) == {:error, :bad}
    end

    test "map_error/2 transforms error reason" do
      assert Result.map_error({:error, "not found"}, &String.upcase/1) == {:error, "NOT FOUND"}
    end

    test "map_error/2 returns ok unchanged" do
      assert Result.map_error({:ok, 42}, &String.upcase/1) == {:ok, 42}
    end
  end

  describe "chaining" do
    test "and_then/2 chains ok values" do
      result =
        {:ok, 5}
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:ok, 10}
    end

    test "and_then/2 short-circuits on error" do
      result =
        {:ok, 5}
        |> Result.and_then(fn _ -> {:error, :failed} end)
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:error, :failed}
    end

    test "and_then/2 returns error unchanged" do
      result =
        {:error, :bad}
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      assert result == {:error, :bad}
    end

    test "or_else/2 returns ok unchanged" do
      result = Result.or_else({:ok, 5}, fn _ -> {:ok, 42} end)
      assert result == {:ok, 5}
    end

    test "or_else/2 calls function on error" do
      result = Result.or_else({:error, :not_found}, fn _ -> {:ok, :default} end)
      assert result == {:ok, :default}
    end
  end

  describe "extraction" do
    test "unwrap!/1 extracts ok value" do
      assert Result.unwrap!({:ok, 42}) == 42
    end

    test "unwrap!/1 raises on error" do
      assert_raise ArgumentError, fn ->
        Result.unwrap!({:error, :bad})
      end
    end

    test "unwrap_or/2 returns value for ok" do
      assert Result.unwrap_or({:ok, 42}, 0) == 42
    end

    test "unwrap_or/2 returns default for error" do
      assert Result.unwrap_or({:error, :bad}, 0) == 0
    end

    test "unwrap_or_else/2 returns value for ok" do
      assert Result.unwrap_or_else({:ok, 42}, fn _ -> 0 end) == 42
    end

    test "unwrap_or_else/2 calls function for error" do
      assert Result.unwrap_or_else({:error, :bad}, fn _ -> 0 end) == 0
    end

    test "unwrap/1 returns result unchanged" do
      assert Result.unwrap({:ok, 42}) == {:ok, 42}
      assert Result.unwrap({:error, :bad}) == {:error, :bad}
    end
  end

  describe "flattening" do
    test "flatten/1 flattens nested ok" do
      assert Result.flatten({:ok, {:ok, 42}}) == {:ok, 42}
    end

    test "flatten/1 flattens ok containing error" do
      assert Result.flatten({:ok, {:error, :inner}}) == {:error, :inner}
    end

    test "flatten/1 returns outer error" do
      assert Result.flatten({:error, :outer}) == {:error, :outer}
    end

    test "flatten/1 handles non-nested ok" do
      assert Result.flatten({:ok, 42}) == {:ok, 42}
    end
  end

  describe "from_nilable" do
    test "from_nilable/2 converts non-nil to ok" do
      assert Result.from_nilable(42, :not_found) == {:ok, 42}
      assert Result.from_nilable(false, :not_found) == {:ok, false}
    end

    test "from_nilable/2 converts nil to error" do
      assert Result.from_nilable(nil, :not_found) == {:error, :not_found}
    end

    test "from_nilable_lazy/2 evaluates error lazily" do
      assert Result.from_nilable_lazy(42, fn -> :not_found end) == {:ok, 42}
      assert Result.from_nilable_lazy(nil, fn -> :not_found end) == {:error, :not_found}
    end
  end

  describe "collection operations" do
    test "collect/1 collects all ok values" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      assert Result.collect(results) == {:ok, [1, 2, 3]}
    end

    test "collect/1 returns first error" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 3}]
      assert Result.collect(results) == {:error, :bad}
    end

    test "collect/1 returns ok for empty list" do
      assert Result.collect([]) == {:ok, []}
    end

    test "traverse/2 applies function and collects" do
      list = [1, 2, 3]
      result = Result.traverse(list, fn x -> {:ok, x * 2} end)
      assert result == {:ok, [2, 4, 6]}
    end

    test "traverse/2 returns first error" do
      list = [1, 2, 3]

      result =
        Result.traverse(list, fn
          2 -> {:error, :bad}
          x -> {:ok, x * 2}
        end)

      assert result == {:error, :bad}
    end

    test "partition/1 separates ok and error values" do
      results = [{:ok, 1}, {:error, :a}, {:ok, 2}, {:error, :b}]
      assert Result.partition(results) == %{ok: [1, 2], errors: [:a, :b]}
    end

    test "cat_ok/1 filters and unwraps ok values" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 2}]
      assert Result.cat_ok(results) == [1, 2]
    end

    test "cat_errors/1 filters error reasons" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 2}, {:error, :worse}]
      assert Result.cat_errors(results) == [:bad, :worse]
    end
  end

  describe "combination" do
    test "combine/2 combines two ok values" do
      assert Result.combine({:ok, 1}, {:ok, 2}) == {:ok, {1, 2}}
    end

    test "combine/2 returns first error" do
      assert Result.combine({:error, :first}, {:ok, 2}) == {:error, :first}
      assert Result.combine({:ok, 1}, {:error, :second}) == {:error, :second}
    end

    test "combine_with/3 combines with function" do
      assert Result.combine_with({:ok, 2}, {:ok, 3}, &(&1 + &2)) == {:ok, 5}
    end

    test "combine_with/3 returns error if any fails" do
      assert Result.combine_with({:error, :bad}, {:ok, 3}, &(&1 + &2)) == {:error, :bad}
    end
  end

  describe "conversion" do
    test "to_bool/1 converts ok to true" do
      assert Result.to_bool({:ok, 42}) == true
    end

    test "to_bool/1 converts error to false" do
      assert Result.to_bool({:error, :bad}) == false
    end

    test "to_option/1 extracts ok value" do
      assert Result.to_option({:ok, 42}) == 42
    end

    test "to_option/1 returns nil for error" do
      assert Result.to_option({:error, :bad}) == nil
    end
  end

  describe "utility" do
    test "tap/2 executes side effect for ok" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      result =
        {:ok, 42}
        |> Result.tap(fn v -> Agent.update(agent, fn _ -> v end) end)

      assert result == {:ok, 42}
      assert Agent.get(agent, & &1) == 42
    end

    test "tap/2 does nothing for error" do
      result =
        {:error, :bad}
        |> Result.tap(fn _ -> raise "should not be called" end)

      assert result == {:error, :bad}
    end

    test "tap_error/2 executes side effect for error" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      result =
        {:error, :bad}
        |> Result.tap_error(fn r -> Agent.update(agent, fn _ -> r end) end)

      assert result == {:error, :bad}
      assert Agent.get(agent, & &1) == :bad
    end
  end

  describe "swap" do
    test "swap/1 swaps ok to error" do
      assert Result.swap({:ok, 42}) == {:error, 42}
    end

    test "swap/1 swaps error to ok" do
      assert Result.swap({:error, :bad}) == {:ok, :bad}
    end
  end

  describe "applicative" do
    test "apply/2 applies wrapped function to wrapped value" do
      assert Result.apply({:ok, &String.upcase/1}, {:ok, "hello"}) == {:ok, "HELLO"}
    end

    test "apply/2 returns error if function is error" do
      assert Result.apply({:error, :no_fn}, {:ok, "hello"}) == {:error, :no_fn}
    end

    test "apply/2 returns error if value is error" do
      assert Result.apply({:ok, &String.upcase/1}, {:error, :no_val}) == {:error, :no_val}
    end

    test "apply/3 applies wrapped 2-arity function" do
      assert Result.apply({:ok, &+/2}, {:ok, 1}, {:ok, 2}) == {:ok, 3}
    end
  end

  describe "zipping" do
    test "zip/2 combines two ok values" do
      assert Result.zip({:ok, 1}, {:ok, 2}) == {:ok, {1, 2}}
    end

    test "zip_with/3 combines with function" do
      assert Result.zip_with({:ok, 2}, {:ok, 3}, &+/2) == {:ok, 5}
    end
  end

  describe "try_with/1" do
    test "wraps successful result" do
      assert Result.try_with(fn -> 1 + 1 end) == {:ok, 2}
    end

    test "catches exceptions" do
      result = Result.try_with(fn -> raise "boom" end)
      assert {:error, %RuntimeError{message: "boom"}} = result
    end

    test "catches throws" do
      result = Result.try_with(fn -> throw(:ball) end)
      assert result == {:error, {:throw, :ball}}
    end

    test "catches exits" do
      result = Result.try_with(fn -> exit(:normal) end)
      assert result == {:error, {:exit, :normal}}
    end

    test "try_with/2 passes argument" do
      assert Result.try_with(fn x -> x * 2 end, 5) == {:ok, 10}
    end
  end

  describe "bimap/3" do
    test "maps ok value with ok_fun" do
      assert Result.bimap({:ok, 5}, &(&1 * 2), &String.upcase/1) == {:ok, 10}
    end

    test "maps error value with error_fun" do
      assert Result.bimap({:error, "bad"}, &(&1 * 2), &String.upcase/1) == {:error, "BAD"}
    end
  end

  describe "function lifting" do
    test "lift/1 lifts unary function" do
      upcase = Result.lift(&String.upcase/1)
      assert upcase.({:ok, "hello"}) == {:ok, "HELLO"}
      assert upcase.({:error, :bad}) == {:error, :bad}
    end

    test "lift/1 lifts binary function" do
      add = Result.lift(&+/2)
      assert add.({:ok, 1}, {:ok, 2}) == {:ok, 3}
      assert add.({:ok, 1}, {:error, :bad}) == {:error, :bad}
    end

    test "lift_apply/2 applies lifted unary function" do
      assert Result.lift_apply(&String.upcase/1, {:ok, "hello"}) == {:ok, "HELLO"}
    end

    test "lift_apply/3 applies lifted binary function" do
      assert Result.lift_apply(&+/2, {:ok, 1}, {:ok, 2}) == {:ok, 3}
    end
  end

  describe "enumerable support" do
    test "to_enum/1 converts ok to list" do
      assert Result.to_enum({:ok, 42}) == [42]
    end

    test "to_enum/1 converts error to empty list" do
      assert Result.to_enum({:error, :bad}) == []
    end

    test "reduce/3 reduces over ok value" do
      assert Result.reduce({:ok, 5}, 0, &+/2) == 5
    end

    test "reduce/3 returns accumulator for error" do
      assert Result.reduce({:error, :bad}, 0, &+/2) == 0
    end
  end

  describe "error integration" do
    test "wrap_error/2 adds context to error" do
      result = {:error, :not_found} |> Result.wrap_error(user_id: 123, action: :fetch)
      assert result == {:error, %{reason: :not_found, context: %{user_id: 123, action: :fetch}}}
    end

    test "wrap_error/2 passes through ok" do
      result = {:ok, 42} |> Result.wrap_error(user_id: 123)
      assert result == {:ok, 42}
    end

    test "with_step/2 wraps error with step info" do
      result = {:error, :not_found} |> Result.with_step(:fetch_user)
      assert result == {:error, {:step_failed, :fetch_user, :not_found}}
    end

    test "with_step/2 passes through ok" do
      result = {:ok, 42} |> Result.with_step(:fetch_user)
      assert result == {:ok, 42}
    end

    test "unwrap_step/1 extracts error from step wrapper" do
      result = {:error, {:step_failed, :fetch, :not_found}} |> Result.unwrap_step()
      assert result == {:error, :not_found}
    end

    test "unwrap_step/1 passes through simple errors" do
      result = {:error, :simple} |> Result.unwrap_step()
      assert result == {:error, :simple}
    end

    test "unwrap_step/1 passes through ok" do
      result = {:ok, 42} |> Result.unwrap_step()
      assert result == {:ok, 42}
    end
  end

  describe "normalize_error/2" do
    test "normalizes atom errors" do
      {:error, error} = Result.normalize_error({:error, :not_found})
      assert %Events.Types.Error{} = error
      assert error.type == :not_found
      assert error.code == :not_found
    end

    test "normalizes string errors" do
      {:error, error} = Result.normalize_error({:error, "Something went wrong"})
      assert %Events.Types.Error{} = error
      assert error.message == "Something went wrong"
    end

    test "normalizes Ecto changesets" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [email: {"is invalid", []}]
      }

      {:error, error} = Result.normalize_error({:error, changeset})
      assert %Events.Types.Error{} = error
      assert error.type == :validation
    end

    test "accepts context option" do
      {:error, error} = Result.normalize_error({:error, :not_found}, context: %{user_id: 123})
      assert error.context == %{user_id: 123}
    end

    test "passes through ok results" do
      result = Result.normalize_error({:ok, 42})
      assert result == {:ok, 42}
    end

    test "works in pipelines" do
      result =
        {:error, :not_found}
        |> Result.normalize_error(context: %{action: :fetch})
        |> Result.map_error(&Events.Types.Error.with_details(&1, extra: "info"))

      {:error, error} = result
      assert error.context == %{action: :fetch}
      assert error.details.extra == "info"
    end
  end
end
