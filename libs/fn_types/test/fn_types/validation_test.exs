defmodule FnTypes.ValidationTest do
  use ExUnit.Case, async: true
  doctest FnTypes.Validation

  alias FnTypes.Validation, as: V

  # ============================================
  # Construction Tests
  # ============================================

  describe "ok/1" do
    test "wraps value in valid tuple" do
      assert V.ok(42) == {:ok, 42}
      assert V.ok("hello") == {:ok, "hello"}
      assert V.ok(%{a: 1}) == {:ok, %{a: 1}}
    end
  end

  describe "error/1" do
    test "creates error with single error as list" do
      assert V.error(:required) == {:error, [:required]}
    end

    test "preserves error list" do
      assert V.error([:e1, :e2]) == {:error, [:e1, :e2]}
    end
  end

  describe "new/1" do
    test "creates validation context from map" do
      result = V.new(%{name: "Alice", age: 25})
      assert {:context, %{name: "Alice", age: 25}, %{}} = result
    end
  end

  # ============================================
  # Type Checking Tests
  # ============================================

  describe "valid?/1" do
    test "returns true for ok tuple" do
      assert V.valid?({:ok, 42})
    end

    test "returns false for error tuple" do
      refute V.valid?({:error, [:required]})
    end

    test "returns true for context with no errors" do
      assert V.valid?({:context, %{}, %{}})
    end

    test "returns false for context with errors" do
      refute V.valid?({:context, %{}, %{name: [:required]}})
    end
  end

  describe "invalid?/1" do
    test "returns true for error tuple" do
      assert V.invalid?({:error, [:required]})
    end

    test "returns false for ok tuple" do
      refute V.invalid?({:ok, 42})
    end
  end

  # ============================================
  # Single Value Validation Tests
  # ============================================

  describe "validate/2" do
    test "returns ok when all validators pass" do
      result = V.validate("test@example.com", [
        V.required(),
        V.min_length(5)
      ])
      assert {:ok, "test@example.com"} = result
    end

    test "accumulates all errors" do
      result = V.validate("", [
        V.required(),
        V.min_length(5)
      ])
      assert {:error, errors} = result
      assert :required in errors
    end

    test "returns ok for empty validator list" do
      assert {:ok, "value"} = V.validate("value", [])
    end
  end

  # ============================================
  # Built-in Validators Tests
  # ============================================

  describe "required/0" do
    test "passes for non-nil values" do
      validator = V.required()
      assert {:ok, "value"} = validator.("value")
      assert {:ok, 0} = validator.(0)
      assert {:ok, false} = validator.(false)
    end

    test "fails for nil" do
      validator = V.required()
      assert {:error, [:required]} = validator.(nil)
    end

    test "fails for empty string" do
      validator = V.required()
      assert {:error, [:required]} = validator.("")
    end
  end

  describe "min_length/1" do
    test "passes when length >= min" do
      validator = V.min_length(3)
      assert {:ok, "abc"} = validator.("abc")
      assert {:ok, "abcd"} = validator.("abcd")
    end

    test "fails when length < min" do
      validator = V.min_length(3)
      assert {:error, [{:min_length, 3}]} = validator.("ab")
    end

    test "works with lists" do
      validator = V.min_length(2)
      assert {:ok, [1, 2]} = validator.([1, 2])
      assert {:error, [{:min_length, 2}]} = validator.([1])
    end
  end

  describe "max_length/1" do
    test "passes when length <= max" do
      validator = V.max_length(5)
      assert {:ok, "abc"} = validator.("abc")
      assert {:ok, "abcde"} = validator.("abcde")
    end

    test "fails when length > max" do
      validator = V.max_length(3)
      assert {:error, [{:max_length, 3}]} = validator.("abcd")
    end
  end

  describe "min/1" do
    test "passes when value >= min" do
      validator = V.min(18)
      assert {:ok, 18} = validator.(18)
      assert {:ok, 25} = validator.(25)
    end

    test "fails when value < min" do
      validator = V.min(18)
      assert {:error, [{:min, 18}]} = validator.(17)
    end
  end

  describe "max/1" do
    test "passes when value <= max" do
      validator = V.max(100)
      assert {:ok, 100} = validator.(100)
      assert {:ok, 50} = validator.(50)
    end

    test "fails when value > max" do
      validator = V.max(100)
      assert {:error, [{:max, 100}]} = validator.(101)
    end
  end

  describe "between/2" do
    test "passes when value in range" do
      validator = V.between(1, 10)
      assert {:ok, 1} = validator.(1)
      assert {:ok, 5} = validator.(5)
      assert {:ok, 10} = validator.(10)
    end

    test "fails when value outside range" do
      validator = V.between(1, 10)
      assert {:error, [{:between, 1, 10}]} = validator.(0)
      assert {:error, [{:between, 1, 10}]} = validator.(11)
    end
  end

  describe "format/1" do
    test "validates email format" do
      validator = V.format(:email)
      assert {:ok, "test@example.com"} = validator.("test@example.com")
      assert {:error, [{:format, :email}]} = validator.("invalid")
    end

    test "validates uuid format" do
      validator = V.format(:uuid)
      assert {:ok, _} = validator.("550e8400-e29b-41d4-a716-446655440000")
      assert {:error, [{:format, :uuid}]} = validator.("not-a-uuid")
    end

    test "validates custom regex" do
      validator = V.format(~r/^[A-Z]{2}\d{4}$/)
      assert {:ok, "AB1234"} = validator.("AB1234")
      assert {:error, [{:format, :custom}]} = validator.("invalid")
    end
  end

  describe "inclusion/1" do
    test "passes when value in list" do
      validator = V.inclusion([:admin, :user, :guest])
      assert {:ok, :admin} = validator.(:admin)
      assert {:ok, :user} = validator.(:user)
    end

    test "fails when value not in list" do
      validator = V.inclusion([:admin, :user])
      assert {:error, [{:inclusion, [:admin, :user]}]} = validator.(:superuser)
    end
  end

  describe "type/1" do
    test "validates string type" do
      validator = V.type(:string)
      assert {:ok, "hello"} = validator.("hello")
      assert {:error, [{:type, :string}]} = validator.(123)
    end

    test "validates integer type" do
      validator = V.type(:integer)
      assert {:ok, 42} = validator.(42)
      assert {:error, [{:type, :integer}]} = validator.("42")
    end

    test "validates boolean type" do
      validator = V.type(:boolean)
      assert {:ok, true} = validator.(true)
      assert {:ok, false} = validator.(false)
      assert {:error, [{:type, :boolean}]} = validator.("true")
    end
  end

  # ============================================
  # Field Validation Tests
  # ============================================

  describe "field/3" do
    test "validates a single field" do
      result =
        V.new(%{name: "Alice"})
        |> V.field(:name, [V.required()])
        |> V.to_result()

      assert {:ok, %{name: "Alice"}} = result
    end

    test "collects errors for invalid field" do
      result =
        V.new(%{name: ""})
        |> V.field(:name, [V.required()])
        |> V.to_result()

      assert {:error, %{name: [:required]}} = result
    end

    test "validates multiple fields" do
      result =
        V.new(%{name: "Alice", age: 25})
        |> V.field(:name, [V.required()])
        |> V.field(:age, [V.min(18)])
        |> V.to_result()

      assert {:ok, %{name: "Alice", age: 25}} = result
    end

    test "accumulates errors from multiple fields" do
      result =
        V.new(%{name: "", age: 15})
        |> V.field(:name, [V.required()])
        |> V.field(:age, [V.min(18)])
        |> V.to_result()

      assert {:error, errors} = result
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :age)
    end
  end

  describe "field/4 with options" do
    test "skips validation when :when condition is false" do
      result =
        V.new(%{phone: nil, contact_method: :email})
        |> V.field(:phone, [V.required()], when: &(&1[:contact_method] == :phone))
        |> V.to_result()

      assert {:ok, _} = result
    end

    test "runs validation when :when condition is true" do
      result =
        V.new(%{phone: nil, contact_method: :phone})
        |> V.field(:phone, [V.required()], when: &(&1[:contact_method] == :phone))
        |> V.to_result()

      assert {:error, _} = result
    end
  end

  # ============================================
  # Functor Operations Tests
  # ============================================

  describe "map/2" do
    test "transforms valid value" do
      result = V.map({:ok, 5}, &(&1 * 2))
      assert {:ok, 10} = result
    end

    test "passes through error" do
      result = V.map({:error, [:required]}, &(&1 * 2))
      assert {:error, [:required]} = result
    end
  end

  describe "map2/3" do
    test "combines two valid values" do
      result = V.map2({:ok, 2}, {:ok, 3}, &(&1 + &2))
      assert {:ok, 5} = result
    end

    test "accumulates errors from both" do
      result = V.map2({:error, [:e1]}, {:error, [:e2]}, &(&1 + &2))
      assert {:error, [:e1, :e2]} = result
    end

    test "returns error when first is invalid" do
      result = V.map2({:error, [:e1]}, {:ok, 2}, &(&1 + &2))
      assert {:error, [:e1]} = result
    end

    test "returns error when second is invalid" do
      result = V.map2({:ok, 1}, {:error, [:e2]}, &(&1 + &2))
      assert {:error, [:e2]} = result
    end
  end

  describe "map3/4" do
    test "combines three valid values" do
      result = V.map3({:ok, 1}, {:ok, 2}, {:ok, 3}, fn a, b, c -> a + b + c end)
      assert {:ok, 6} = result
    end

    test "accumulates errors from all three" do
      result = V.map3({:error, [:e1]}, {:error, [:e2]}, {:error, [:e3]}, fn a, b, c -> a + b + c end)
      assert {:error, errors} = result
      assert :e1 in errors
      assert :e2 in errors
      assert :e3 in errors
    end
  end

  # ============================================
  # Combining Validations Tests
  # ============================================

  describe "all/1" do
    test "returns ok with all values when all pass" do
      result = V.all([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      assert {:ok, [1, 2, 3]} = result
    end

    test "accumulates all errors when any fail" do
      result = V.all([{:ok, 1}, {:error, [:e1]}, {:error, [:e2]}])
      assert {:error, errors} = result
      assert :e1 in errors
      assert :e2 in errors
    end
  end

  # ============================================
  # Conversion Tests
  # ============================================

  describe "to_result/1" do
    test "converts valid validation to ok" do
      assert {:ok, 42} = V.to_result({:ok, 42})
    end

    test "converts invalid validation to error" do
      assert {:error, [:e1]} = V.to_result({:error, [:e1]})
    end

    test "converts context with no errors to ok" do
      result = V.to_result({:context, %{name: "Alice"}, %{}})
      assert {:ok, %{name: "Alice"}} = result
    end

    test "converts context with errors to error map" do
      result = V.to_result({:context, %{name: ""}, %{name: [:required]}})
      assert {:error, %{name: [:required]}} = result
    end
  end

  describe "from_result/1" do
    test "converts ok result to validation" do
      assert {:ok, 42} = V.from_result({:ok, 42})
    end

    test "converts error result to validation with list" do
      assert {:error, [:not_found]} = V.from_result({:error, :not_found})
    end
  end

  # ============================================
  # Behaviour Implementation Tests
  # ============================================

  describe "pure/1 (Applicative)" do
    test "wraps value in validation" do
      assert {:ok, 42} = V.pure(42)
    end
  end

  describe "ap/2 (Applicative)" do
    test "applies wrapped function to wrapped value" do
      result = V.ap({:ok, fn x -> x * 2 end}, {:ok, 5})
      assert {:ok, 10} = result
    end

    test "accumulates errors from both sides" do
      result = V.ap({:error, [:fn_err]}, {:error, [:val_err]})
      assert {:error, errors} = result
      assert :fn_err in errors
      assert :val_err in errors
    end
  end

  describe "combine/2 (Semigroup)" do
    test "keeps second value when both valid" do
      assert {:ok, 2} = V.combine({:ok, 1}, {:ok, 2})
    end

    test "accumulates errors when both invalid" do
      result = V.combine({:error, [:e1]}, {:error, [:e2]})
      assert {:error, [:e1, :e2]} = result
    end

    test "returns error when first is invalid" do
      assert {:error, [:e1]} = V.combine({:error, [:e1]}, {:ok, 2})
    end

    test "returns error when second is invalid" do
      assert {:error, [:e2]} = V.combine({:ok, 1}, {:error, [:e2]})
    end
  end

  # ============================================
  # Check Function Tests
  # ============================================

  describe "check/4" do
    test "adds error when check function returns error" do
      result =
        V.new(%{age: 15})
        |> V.check(:age, fn ctx -> if ctx.value >= 18, do: :ok, else: {:error, :too_young} end)
        |> V.to_result()

      assert {:error, %{age: [:too_young]}} = result
    end

    test "passes through when check function returns ok" do
      result =
        V.new(%{age: 25})
        |> V.check(:age, fn ctx -> if ctx.value >= 18, do: :ok, else: {:error, :too_young} end)
        |> V.to_result()

      assert {:ok, %{age: 25}} = result
    end
  end

  # ============================================
  # Unwrap Tests
  # ============================================

  describe "unwrap!/1" do
    test "returns value for valid validation" do
      assert 42 = V.unwrap!({:ok, 42})
    end

    test "raises for invalid validation" do
      assert_raise ArgumentError, fn -> V.unwrap!({:error, [:e1]}) end
    end
  end

  describe "unwrap_or/2" do
    test "returns value for valid validation" do
      assert 42 = V.unwrap_or({:ok, 42}, :default)
    end

    test "returns default for invalid validation" do
      assert :default = V.unwrap_or({:error, [:e1]}, :default)
    end
  end

  describe "errors/1" do
    test "returns errors list" do
      assert [:e1, :e2] = V.errors({:error, [:e1, :e2]})
    end

    test "returns empty list for valid" do
      assert [] = V.errors({:ok, 42})
    end
  end
end
