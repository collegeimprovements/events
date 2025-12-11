defmodule FnTypes.ResultTest do
  use ExUnit.Case, async: true

  alias FnTypes.Result

  describe "Result.ok/1 and Result.error/1" do
    test "creates ok tuple" do
      assert Result.ok(42) == {:ok, 42}
    end

    test "creates error tuple" do
      assert Result.error(:not_found) == {:error, :not_found}
    end
  end

  describe "Result.ok?/1 and Result.error?/1" do
    test "ok? returns true for ok tuples" do
      assert Result.ok?({:ok, 42}) == true
      assert Result.ok?({:error, :not_found}) == false
    end

    test "error? returns true for error tuples" do
      assert Result.error?({:error, :not_found}) == true
      assert Result.error?({:ok, 42}) == false
    end
  end

  describe "Result.map/2" do
    test "maps over ok value" do
      assert Result.map({:ok, 5}, &(&1 * 2)) == {:ok, 10}
    end

    test "passes through error" do
      assert Result.map({:error, :not_found}, &(&1 * 2)) == {:error, :not_found}
    end
  end

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
  end

  describe "Result.unwrap_or/2" do
    test "returns value for ok" do
      assert Result.unwrap_or({:ok, 42}, 0) == 42
    end

    test "returns default for error" do
      assert Result.unwrap_or({:error, :not_found}, 0) == 0
    end
  end

  describe "Result.collect/1" do
    test "collects all ok values" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      assert Result.collect(results) == {:ok, [1, 2, 3]}
    end

    test "returns first error" do
      results = [{:ok, 1}, {:error, :bad}, {:ok, 3}]
      assert Result.collect(results) == {:error, :bad}
    end
  end

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
  end

  describe "Result.try_with/1" do
    test "wraps successful result" do
      assert Result.try_with(fn -> 1 + 1 end) == {:ok, 2}
    end

    test "catches exceptions" do
      {:error, error} = Result.try_with(fn -> raise "boom" end)
      assert %RuntimeError{message: "boom"} = error
    end
  end
end
