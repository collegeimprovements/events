defmodule FnTypes.MaybeTest do
  use ExUnit.Case, async: true

  alias FnTypes.Maybe

  describe "Maybe.some/1 and Maybe.none/0" do
    test "creates some tuple" do
      assert Maybe.some(42) == {:some, 42}
    end

    test "creates none" do
      assert Maybe.none() == :none
    end
  end

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
  end

  describe "Maybe.map/2" do
    test "maps over some value" do
      assert Maybe.map({:some, 5}, &(&1 * 2)) == {:some, 10}
    end

    test "passes through none" do
      assert Maybe.map(:none, &(&1 * 2)) == :none
    end
  end

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
  end

  describe "Maybe.unwrap_or/2" do
    test "returns value for some" do
      assert Maybe.unwrap_or({:some, 42}, 0) == 42
    end

    test "returns default for none" do
      assert Maybe.unwrap_or(:none, 0) == 0
    end
  end

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

  describe "Maybe.to_result/2" do
    test "converts some to ok" do
      assert Maybe.to_result({:some, 42}, :not_found) == {:ok, 42}
    end

    test "converts none to error" do
      assert Maybe.to_result(:none, :not_found) == {:error, :not_found}
    end
  end

  describe "Maybe.collect/1" do
    test "collects all some values" do
      maybes = [{:some, 1}, {:some, 2}, {:some, 3}]
      assert Maybe.collect(maybes) == {:some, [1, 2, 3]}
    end

    test "returns none if any is none" do
      maybes = [{:some, 1}, :none, {:some, 3}]
      assert Maybe.collect(maybes) == :none
    end
  end
end
