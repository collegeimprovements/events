defmodule Events.Types.GuardsTest do
  use ExUnit.Case, async: true

  import Events.Types.Guards

  describe "result guards" do
    test "is_ok/1 returns true for ok tuples" do
      assert is_ok({:ok, 42})
      assert is_ok({:ok, nil})
    end

    test "is_ok/1 returns false for non-ok values" do
      refute is_ok({:error, :bad})
      refute is_ok(:ok)
      refute is_ok({:ok, 1, 2})
    end

    test "is_error/1 returns true for error tuples" do
      assert is_error({:error, :not_found})
      assert is_error({:error, nil})
    end

    test "is_error/1 returns false for non-error values" do
      refute is_error({:ok, 42})
      refute is_error(:error)
    end

    test "is_result/1 returns true for result tuples" do
      assert is_result({:ok, 42})
      assert is_result({:error, :bad})
    end

    test "is_result/1 returns false for non-results" do
      refute is_result(:ok)
      refute is_result({:some, 42})
    end
  end

  describe "maybe guards" do
    test "is_some/1 returns true for some tuples" do
      assert is_some({:some, 42})
      assert is_some({:some, nil})
    end

    test "is_some/1 returns false for non-some values" do
      refute is_some(:none)
      refute is_some({:ok, 42})
    end

    test "is_none/1 returns true for none" do
      assert is_none(:none)
    end

    test "is_none/1 returns false for non-none values" do
      refute is_none({:some, 42})
      refute is_none(nil)
    end

    test "is_maybe/1 returns true for maybe values" do
      assert is_maybe({:some, 42})
      assert is_maybe(:none)
    end

    test "is_maybe/1 returns false for non-maybes" do
      refute is_maybe({:ok, 42})
      refute is_maybe(nil)
    end
  end

  describe "pattern matching macros" do
    test "ok/1 pattern matches ok values" do
      result = {:ok, 42}

      value =
        case result do
          ok(v) -> v
          error(_) -> nil
        end

      assert value == 42
    end

    test "error/1 pattern matches error values" do
      result = {:error, :not_found}

      reason =
        case result do
          ok(_) -> nil
          error(r) -> r
        end

      assert reason == :not_found
    end

    test "some/1 pattern matches some values" do
      maybe = {:some, "hello"}

      value =
        case maybe do
          some(v) -> v
          none() -> nil
        end

      assert value == "hello"
    end

    test "none/0 pattern matches none" do
      maybe = :none

      result =
        case maybe do
          some(_) -> :found
          none() -> :not_found
        end

      assert result == :not_found
    end
  end

  describe "guards in function heads" do
    test "can use is_ok in function definition" do
      handle = fn
        result when is_ok(result) -> :success
        result when is_error(result) -> :failure
      end

      assert handle.({:ok, 42}) == :success
      assert handle.({:error, :bad}) == :failure
    end

    test "can use is_some in function definition" do
      handle = fn
        maybe when is_some(maybe) -> :present
        maybe when is_none(maybe) -> :absent
      end

      assert handle.({:some, 42}) == :present
      assert handle.(:none) == :absent
    end
  end

  describe "utility guards" do
    test "is_non_empty_string/1 returns true for non-empty strings" do
      assert is_non_empty_string("hello")
      assert is_non_empty_string("x")
    end

    test "is_non_empty_string/1 returns false for empty or non-strings" do
      refute is_non_empty_string("")
      refute is_non_empty_string(nil)
      refute is_non_empty_string(123)
    end

    test "is_non_empty_list/1 returns true for non-empty lists" do
      assert is_non_empty_list([1, 2, 3])
      assert is_non_empty_list([nil])
    end

    test "is_non_empty_list/1 returns false for empty or non-lists" do
      refute is_non_empty_list([])
      refute is_non_empty_list(nil)
    end

    test "is_non_empty_map/1 returns true for non-empty maps" do
      assert is_non_empty_map(%{a: 1})
    end

    test "is_non_empty_map/1 returns false for empty or non-maps" do
      refute is_non_empty_map(%{})
      refute is_non_empty_map(nil)
    end

    test "is_positive_integer/1 returns true for positive integers" do
      assert is_positive_integer(1)
      assert is_positive_integer(100)
    end

    test "is_positive_integer/1 returns false for zero, negative, or non-integers" do
      refute is_positive_integer(0)
      refute is_positive_integer(-1)
      refute is_positive_integer(1.5)
    end

    test "is_non_negative_integer/1 returns true for zero and positive integers" do
      assert is_non_negative_integer(0)
      assert is_non_negative_integer(1)
    end

    test "is_non_negative_integer/1 returns false for negative integers" do
      refute is_non_negative_integer(-1)
    end
  end
end
