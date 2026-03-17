defmodule FnTypes.TestingTest do
  @moduledoc """
  Tests for FnTypes.Testing module - ExUnit assertions and helpers for functional types.
  """
  use ExUnit.Case, async: true
  import FnTypes.Testing

  # ============================================
  # Result Assertions
  # ============================================

  describe "assert_ok/1" do
    test "returns value when result is {:ok, value}" do
      result = {:ok, 42}
      value = assert_ok(result)
      assert value == 42
    end

    test "returns complex values" do
      user = %{id: 1, name: "Alice"}
      result = {:ok, user}
      value = assert_ok(result)
      assert value == user
    end

    test "works with expressions" do
      value = assert_ok({:ok, 1 + 2})
      assert value == 3
    end

    test "works with function calls" do
      fun = fn -> {:ok, "computed"} end
      value = assert_ok(fun.())
      assert value == "computed"
    end
  end

  describe "assert_ok/2" do
    test "passes when value matches expected" do
      value = assert_ok(42, {:ok, 42})
      assert value == 42
    end

    test "works with complex expected values" do
      expected = %{status: :active}
      value = assert_ok(expected, {:ok, %{status: :active}})
      assert value == expected
    end
  end

  describe "assert_error/1" do
    test "returns reason when result is {:error, reason}" do
      result = {:error, :not_found}
      reason = assert_error(result)
      assert reason == :not_found
    end

    test "returns complex error reasons" do
      error = %{code: :validation, field: :email}
      result = {:error, error}
      reason = assert_error(result)
      assert reason == error
    end

    test "works with expressions" do
      reason = assert_error({:error, "error_" <> "message"})
      assert reason == "error_message"
    end
  end

  describe "assert_error/2" do
    test "passes when reason matches expected" do
      reason = assert_error(:not_found, {:error, :not_found})
      assert reason == :not_found
    end

    test "works with complex expected reasons" do
      expected = {:validation, :email, "invalid format"}
      reason = assert_error(expected, {:error, {:validation, :email, "invalid format"}})
      assert reason == expected
    end
  end

  describe "assert_error_type/2" do
    test "matches direct atom" do
      reason = assert_error_type(:not_found, {:error, :not_found})
      assert reason == :not_found
    end

    test "matches FnTypes.Error type field" do
      error = FnTypes.Error.new(:validation, :invalid_email)
      reason = assert_error_type(:validation, {:error, error})
      assert reason.type == :validation
    end

    test "matches struct pattern" do
      error = FnTypes.Error.new(:validation, :invalid_email, message: "bad email")
      pattern = %FnTypes.Error{type: :validation}
      reason = assert_error_type(pattern, {:error, error})
      assert reason.type == :validation
    end

    test "matches tuple error type with two elements" do
      reason = assert_error_type(:validation, {:error, {:validation, :field}})
      assert reason == {:validation, :field}
    end

    test "matches tuple error type with three elements" do
      reason = assert_error_type(:validation, {:error, {:validation, :field, "message"}})
      assert reason == {:validation, :field, "message"}
    end
  end

  describe "match_struct_pattern?/2" do
    test "matches when all non-nil pattern fields match" do
      error = FnTypes.Error.new(:validation, :invalid_email, message: "bad")
      pattern = %FnTypes.Error{type: :validation, code: :invalid_email}
      assert match_struct_pattern?(pattern, error)
    end

    test "nil pattern fields match any value" do
      error = FnTypes.Error.new(:validation, :invalid_email)
      pattern = %FnTypes.Error{type: :validation}
      assert match_struct_pattern?(pattern, error)
    end

    test "returns false when fields don't match" do
      error = FnTypes.Error.new(:validation, :invalid_email)
      pattern = %FnTypes.Error{type: :not_found}
      refute match_struct_pattern?(pattern, error)
    end

    test "returns false for non-structs" do
      refute match_struct_pattern?(:atom, %{})
      refute match_struct_pattern?(%{}, :atom)
    end
  end

  describe "assert_ok_match/2" do
    test "matches simple pattern" do
      value = assert_ok_match(%{status: :active}, {:ok, %{status: :active, name: "test"}})
      assert value.status == :active
    end

    test "matches list pattern" do
      value = assert_ok_match([_ | _], {:ok, [1, 2, 3]})
      assert value == [1, 2, 3]
    end

    test "matches with guards in pattern" do
      value = assert_ok_match(x when x > 0, {:ok, 42})
      assert value == 42
    end
  end

  describe "assert_error_match/2" do
    test "matches simple pattern" do
      reason = assert_error_match({:validation, _}, {:error, {:validation, :field}})
      assert reason == {:validation, :field}
    end

    test "matches struct pattern" do
      error = FnTypes.Error.new(:not_found, :user)
      reason = assert_error_match(%FnTypes.Error{type: :not_found}, {:error, error})
      assert reason.type == :not_found
    end

    test "matches tuple with three elements" do
      reason = assert_error_match({:validation, _, _}, {:error, {:validation, :email, "invalid"}})
      assert reason == {:validation, :email, "invalid"}
    end
  end

  # ============================================
  # Maybe Assertions
  # ============================================

  describe "assert_some/1" do
    test "returns value when maybe is {:some, value}" do
      result = {:some, 42}
      value = assert_some(result)
      assert value == 42
    end

    test "returns complex values" do
      user = %{id: 1, name: "Alice"}
      result = {:some, user}
      value = assert_some(result)
      assert value == user
    end

    test "works with nil value" do
      # {:some, nil} is valid - it means "some nil"
      value = assert_some({:some, nil})
      assert value == nil
    end
  end

  describe "assert_none/1" do
    test "returns :none when maybe is :none" do
      result = assert_none(:none)
      assert result == :none
    end
  end

  describe "assert_just/1 (deprecated alias)" do
    test "delegates to assert_some" do
      result = {:some, 42}
      value = assert_just(result)
      assert value == 42
    end
  end

  describe "assert_nothing/1 (deprecated alias)" do
    test "delegates to assert_none" do
      result = assert_nothing(:none)
      assert result == :none
    end
  end

  # ============================================
  # Pipeline Assertions
  # ============================================

  describe "assert_pipeline_ok/1" do
    test "returns context on successful pipeline" do
      result = {:ok, %{user: %{id: 1}, data: "computed"}}
      ctx = assert_pipeline_ok(result)
      assert ctx.user.id == 1
      assert ctx.data == "computed"
    end

    test "works with empty context" do
      result = {:ok, %{}}
      ctx = assert_pipeline_ok(result)
      assert ctx == %{}
    end
  end

  describe "assert_pipeline_error/2" do
    test "returns reason when pipeline failed at expected step" do
      result = {:error, {:step_failed, :validate, :invalid_input}}
      reason = assert_pipeline_error(:validate, result)
      assert reason == :invalid_input
    end

    test "works with complex failure reasons" do
      error = %{field: :email, message: "invalid format"}
      result = {:error, {:step_failed, :validate, error}}
      reason = assert_pipeline_error(:validate, result)
      assert reason == error
    end
  end

  describe "assert_pipeline_error/3" do
    test "passes when step and reason match" do
      result = {:error, {:step_failed, :fetch, :not_found}}
      reason = assert_pipeline_error(:fetch, :not_found, result)
      assert reason == :not_found
    end
  end

  # ============================================
  # Collection Assertions
  # ============================================

  describe "assert_all_ok/1" do
    test "returns all values when all results are ok" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      values = assert_all_ok(results)
      assert values == [1, 2, 3]
    end

    test "returns empty list for empty input" do
      values = assert_all_ok([])
      assert values == []
    end

    test "works with complex values" do
      results = [{:ok, %{id: 1}}, {:ok, %{id: 2}}]
      values = assert_all_ok(results)
      assert Enum.map(values, & &1.id) == [1, 2]
    end
  end

  describe "assert_any_error/1" do
    test "passes when at least one error exists" do
      results = [{:ok, 1}, {:error, :failed}, {:ok, 3}]
      returned = assert_any_error(results)
      assert returned == results
    end

    test "works with all errors" do
      results = [{:error, :a}, {:error, :b}]
      returned = assert_any_error(results)
      assert returned == results
    end
  end

  # ============================================
  # Helpers
  # ============================================

  describe "ok_values/1" do
    test "extracts ok values from list" do
      results = [{:ok, 1}, {:error, :failed}, {:ok, 2}, {:error, :timeout}]
      values = ok_values(results)
      assert values == [1, 2]
    end

    test "returns empty list when no ok values" do
      results = [{:error, :a}, {:error, :b}]
      values = ok_values(results)
      assert values == []
    end

    test "returns all values when all ok" do
      results = [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      values = ok_values(results)
      assert values == [1, 2, 3]
    end

    test "handles empty list" do
      assert ok_values([]) == []
    end

    test "handles complex values" do
      results = [{:ok, %{id: 1}}, {:error, :x}, {:ok, %{id: 2}}]
      values = ok_values(results)
      assert Enum.map(values, & &1.id) == [1, 2]
    end
  end

  describe "error_reasons/1" do
    test "extracts error reasons from list" do
      results = [{:ok, 1}, {:error, :failed}, {:ok, 2}, {:error, :timeout}]
      reasons = error_reasons(results)
      assert reasons == [:failed, :timeout]
    end

    test "returns empty list when no errors" do
      results = [{:ok, 1}, {:ok, 2}]
      reasons = error_reasons(results)
      assert reasons == []
    end

    test "returns all reasons when all errors" do
      results = [{:error, :a}, {:error, :b}, {:error, :c}]
      reasons = error_reasons(results)
      assert reasons == [:a, :b, :c]
    end

    test "handles empty list" do
      assert error_reasons([]) == []
    end

    test "handles complex reasons" do
      results = [{:ok, 1}, {:error, %{code: :a}}, {:error, %{code: :b}}]
      reasons = error_reasons(results)
      assert Enum.map(reasons, & &1.code) == [:a, :b]
    end
  end

  describe "wrap_ok/1" do
    test "wraps value in {:ok, value}" do
      assert wrap_ok(42) == {:ok, 42}
    end

    test "wraps complex values" do
      user = %{id: 1, name: "Alice"}
      assert wrap_ok(user) == {:ok, user}
    end

    test "wraps nil" do
      assert wrap_ok(nil) == {:ok, nil}
    end

    test "wraps atoms" do
      assert wrap_ok(:done) == {:ok, :done}
    end
  end

  describe "wrap_error/1" do
    test "wraps reason in {:error, reason}" do
      assert wrap_error(:not_found) == {:error, :not_found}
    end

    test "wraps complex reasons" do
      error = %{code: :validation, field: :email}
      assert wrap_error(error) == {:error, error}
    end

    test "wraps strings" do
      assert wrap_error("something went wrong") == {:error, "something went wrong"}
    end
  end

  describe "always_ok/1" do
    test "creates function that always returns {:ok, value}" do
      fun = always_ok(42)
      assert fun.() == {:ok, 42}
      assert fun.() == {:ok, 42}
      assert fun.() == {:ok, 42}
    end

    test "works with complex values" do
      user = %{id: 1, name: "Alice"}
      fun = always_ok(user)
      assert fun.() == {:ok, user}
    end
  end

  describe "always_error/1" do
    test "creates function that always returns {:error, reason}" do
      fun = always_error(:not_found)
      assert fun.() == {:error, :not_found}
      assert fun.() == {:error, :not_found}
      assert fun.() == {:error, :not_found}
    end

    test "works with complex reasons" do
      error = %{code: :validation}
      fun = always_error(error)
      assert fun.() == {:error, error}
    end
  end

  describe "flaky_fn/3" do
    test "returns ok for first N calls, then error" do
      flaky = flaky_fn(2, {:ok, :success}, {:error, :exhausted})

      # First 2 calls succeed (index 0 and 1 are < 2)
      assert flaky.() == {:ok, :success}
      assert flaky.() == {:ok, :success}
      # Then fails
      assert flaky.() == {:error, :exhausted}
      assert flaky.() == {:error, :exhausted}
    end

    test "with success_count of 0 always fails" do
      flaky = flaky_fn(0, {:ok, :success}, {:error, :immediate_fail})

      assert flaky.() == {:error, :immediate_fail}
      assert flaky.() == {:error, :immediate_fail}
    end

    test "with high success_count succeeds many times" do
      flaky = flaky_fn(100, {:ok, :success}, {:error, :fail})

      for _ <- 1..50 do
        assert flaky.() == {:ok, :success}
      end
    end

    test "works with complex values" do
      flaky = flaky_fn(1, {:ok, %{id: 1}}, {:error, %{reason: :limit}})

      assert flaky.() == {:ok, %{id: 1}}
      assert flaky.() == {:error, %{reason: :limit}}
    end
  end

  describe "eventually_ok_fn/3" do
    test "returns error for first N calls, then ok" do
      eventually = eventually_ok_fn(2, {:ok, :success}, {:error, :temporary})

      # First 2 calls fail (index 0 and 1 are < 2)
      assert eventually.() == {:error, :temporary}
      assert eventually.() == {:error, :temporary}
      # Then succeeds
      assert eventually.() == {:ok, :success}
      assert eventually.() == {:ok, :success}
    end

    test "with fail_count of 0 always succeeds" do
      eventually = eventually_ok_fn(0, {:ok, :immediate_success}, {:error, :fail})

      assert eventually.() == {:ok, :immediate_success}
      assert eventually.() == {:ok, :immediate_success}
    end

    test "with high fail_count fails many times before success" do
      eventually = eventually_ok_fn(5, {:ok, :success}, {:error, :retry})

      for _ <- 1..5 do
        assert eventually.() == {:error, :retry}
      end

      assert eventually.() == {:ok, :success}
    end

    test "useful for testing retry logic" do
      # Simulates an API that fails twice then succeeds
      api_call = eventually_ok_fn(2, {:ok, %{data: "response"}}, {:error, :timeout})

      # Retry loop
      result =
        Enum.reduce_while(1..5, {:error, :max_retries}, fn attempt, _acc ->
          case api_call.() do
            {:ok, data} -> {:halt, {:ok, data, attempt}}
            {:error, _} -> {:cont, {:error, :max_retries}}
          end
        end)

      assert {:ok, %{data: "response"}, 3} = result
    end
  end

  # ============================================
  # __using__ macro
  # ============================================

  describe "__using__/1" do
    test "imports Testing functions" do
      # This module uses FnTypes.Testing via __using__
      defmodule TestUsingMacro do
        use FnTypes.Testing

        def test_assert_ok do
          assert_ok({:ok, 42})
        end
      end

      assert TestUsingMacro.test_assert_ok() == 42
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "integration with Result type" do
    alias FnTypes.Result

    test "assert_ok works with Result.and_then chain" do
      result =
        {:ok, 10}
        |> Result.and_then(fn x -> {:ok, x * 2} end)
        |> Result.and_then(fn x -> {:ok, x + 5} end)

      value = assert_ok(result)
      assert value == 25
    end

    test "assert_error works with Result operations" do
      result =
        {:ok, 10}
        |> Result.and_then(fn _ -> {:error, :validation_failed} end)
        |> Result.and_then(fn x -> {:ok, x * 2} end)

      reason = assert_error(result)
      assert reason == :validation_failed
    end
  end

  describe "integration with Maybe type" do
    alias FnTypes.Maybe

    test "assert_some works with Maybe.from_nilable" do
      maybe = Maybe.from_nilable("value")
      value = assert_some(maybe)
      assert value == "value"
    end

    test "assert_none works with Maybe.from_nilable(nil)" do
      maybe = Maybe.from_nilable(nil)
      assert_none(maybe)
    end
  end

  describe "integration with Pipeline" do
    alias FnTypes.Pipeline

    test "assert_pipeline_ok with real pipeline" do
      ctx =
        assert_pipeline_ok(
          Pipeline.new(%{value: 10})
          |> Pipeline.step(:double, fn ctx -> {:ok, %{result: ctx.value * 2}} end)
          |> Pipeline.step(:add, fn ctx -> {:ok, %{final: ctx.result + 5}} end)
          |> Pipeline.run()
        )

      assert ctx.value == 10
      assert ctx.result == 20
      assert ctx.final == 25
    end

    test "assert_pipeline_error with real pipeline" do
      reason =
        assert_pipeline_error(
          :validate,
          Pipeline.new(%{value: -1})
          |> Pipeline.step(:validate, fn ctx ->
            if ctx.value < 0, do: {:error, :negative_value}, else: {:ok, %{}}
          end)
          |> Pipeline.step(:process, fn _ctx -> {:ok, %{}} end)
          |> Pipeline.run()
        )

      assert reason == :negative_value
    end
  end
end
