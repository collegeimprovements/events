defmodule OmQuery.PaginationValidatorTest do
  @moduledoc """
  Tests for OmQuery.PaginationValidator - Cursor pagination configuration validation.

  Ensures cursor_fields match the order_by specification to prevent data loss
  from skipped or duplicated records during pagination.

  ## Key Behaviors

  - `validate/2` checks cursor_fields against order_by for correct fields, order, and direction
  - `infer/1` derives cursor_fields from order_by, appending {:id, :asc} as tiebreaker
  - `validate_or_infer/2` combines both: validates if provided, infers if nil
  """

  use ExUnit.Case, async: true

  alias OmQuery.PaginationValidator

  # ============================================
  # validate/2 - nil and empty cases
  # ============================================

  describe "validate/2 nil and empty" do
    test "nil cursor_fields is always valid" do
      assert :ok = PaginationValidator.validate([{:title, :asc}], nil)
      assert :ok = PaginationValidator.validate([{:title, :asc}, {:age, :desc}], nil)
      assert :ok = PaginationValidator.validate([], nil)
    end

    test "empty order_by is always valid" do
      assert :ok = PaginationValidator.validate([], [{:id, :asc}])
      assert :ok = PaginationValidator.validate([], [{:title, :desc}, {:id, :asc}])
    end
  end

  # ============================================
  # validate/2 - Valid configurations
  # ============================================

  describe "validate/2 valid configurations" do
    test "exact match is valid" do
      assert :ok = PaginationValidator.validate(
        [{:title, :asc}],
        [{:title, :asc}]
      )
    end

    test "exact match with multiple fields is valid" do
      assert :ok = PaginationValidator.validate(
        [{:title, :asc}, {:age, :desc}],
        [{:title, :asc}, {:age, :desc}]
      )
    end

    test "with :id appended is valid" do
      assert :ok = PaginationValidator.validate(
        [{:title, :asc}],
        [{:title, :asc}, {:id, :asc}]
      )
    end

    test "with :id appended and desc direction is valid" do
      assert :ok = PaginationValidator.validate(
        [{:title, :asc}, {:age, :desc}],
        [{:title, :asc}, {:age, :desc}, {:id, :desc}]
      )
    end

    test "simple atoms are normalized to :asc for comparison" do
      assert :ok = PaginationValidator.validate(
        [:title],
        [{:title, :asc}]
      )
    end

    test "both sides with simple atoms" do
      assert :ok = PaginationValidator.validate(
        [:title],
        [:title]
      )
    end

    test "simple atoms with :id appended" do
      assert :ok = PaginationValidator.validate(
        [:title, :age],
        [{:title, :asc}, {:age, :asc}, {:id, :asc}]
      )
    end
  end

  # ============================================
  # validate/2 - Invalid configurations
  # ============================================

  describe "validate/2 invalid configurations" do
    test "wrong field order is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}, {:age, :desc}],
        [{:age, :desc}, {:title, :asc}]
      )

      assert msg =~ "order" or msg =~ "Expected"
    end

    test "wrong direction is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}],
        [{:title, :desc}]
      )

      assert msg =~ "direction"
      assert msg =~ ":title"
      assert msg =~ ":asc"
      assert msg =~ ":desc"
    end

    test "wrong direction on second field is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}, {:age, :desc}],
        [{:title, :asc}, {:age, :asc}]
      )

      assert msg =~ "direction"
      assert msg =~ ":age"
    end

    test "missing fields from order_by is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}, {:age, :desc}],
        [{:title, :asc}]
      )

      assert is_binary(msg)
    end

    test "extra non-:id field is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}],
        [{:title, :asc}, {:name, :asc}]
      )

      assert msg =~ "name" or msg =~ "extra"
    end

    test "too many extra fields is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}],
        [{:title, :asc}, {:id, :asc}, {:name, :asc}]
      )

      assert is_binary(msg)
    end

    test "completely different fields is invalid" do
      assert {:error, msg} = PaginationValidator.validate(
        [{:title, :asc}],
        [{:email, :desc}]
      )

      assert is_binary(msg)
    end
  end

  # ============================================
  # infer/1
  # ============================================

  describe "infer/1" do
    test "empty list returns [{:id, :asc}]" do
      assert PaginationValidator.infer([]) == [{:id, :asc}]
    end

    test "single field adds :id" do
      assert PaginationValidator.infer([{:title, :asc}]) == [{:title, :asc}, {:id, :asc}]
    end

    test "multiple fields add :id" do
      result = PaginationValidator.infer([{:title, :asc}, {:age, :desc}])
      assert result == [{:title, :asc}, {:age, :desc}, {:id, :asc}]
    end

    test "already has :id does not duplicate" do
      result = PaginationValidator.infer([{:title, :asc}, {:id, :desc}])
      assert result == [{:title, :asc}, {:id, :desc}]
    end

    test ":id alone does not duplicate" do
      result = PaginationValidator.infer([{:id, :asc}])
      assert result == [{:id, :asc}]
    end

    test "simple atoms get :asc direction" do
      result = PaginationValidator.infer([:title, :age])
      assert result == [{:title, :asc}, {:age, :asc}, {:id, :asc}]
    end

    test "mixed atoms and tuples" do
      result = PaginationValidator.infer([:title, {:age, :desc}])
      assert result == [{:title, :asc}, {:age, :desc}, {:id, :asc}]
    end

    test "simple atom :id does not get duplicated" do
      result = PaginationValidator.infer([:title, :id])
      assert result == [{:title, :asc}, {:id, :asc}]
    end
  end

  # ============================================
  # validate_or_infer/2
  # ============================================

  describe "validate_or_infer/2" do
    test "nil cursor_fields infers from order_by" do
      assert {:ok, inferred} = PaginationValidator.validate_or_infer([{:title, :asc}], nil)
      assert inferred == [{:title, :asc}, {:id, :asc}]
    end

    test "nil cursor_fields with empty order_by infers :id" do
      assert {:ok, inferred} = PaginationValidator.validate_or_infer([], nil)
      assert inferred == [{:id, :asc}]
    end

    test "nil cursor_fields preserves directions" do
      assert {:ok, inferred} = PaginationValidator.validate_or_infer(
        [{:title, :asc}, {:age, :desc}],
        nil
      )

      assert inferred == [{:title, :asc}, {:age, :desc}, {:id, :asc}]
    end

    test "valid cursor_fields returns normalized version" do
      assert {:ok, normalized} = PaginationValidator.validate_or_infer(
        [{:title, :asc}],
        [{:title, :asc}, {:id, :asc}]
      )

      assert normalized == [{:title, :asc}, {:id, :asc}]
    end

    test "valid cursor_fields with simple atoms are normalized" do
      assert {:ok, normalized} = PaginationValidator.validate_or_infer(
        [:title],
        [:title, :id]
      )

      assert normalized == [{:title, :asc}, {:id, :asc}]
    end

    test "invalid cursor_fields returns error" do
      assert {:error, msg} = PaginationValidator.validate_or_infer(
        [{:title, :asc}],
        [{:title, :desc}]
      )

      assert msg =~ "direction"
    end

    test "invalid cursor_fields with wrong order returns error" do
      assert {:error, msg} = PaginationValidator.validate_or_infer(
        [{:title, :asc}, {:age, :desc}],
        [{:age, :desc}, {:title, :asc}]
      )

      assert is_binary(msg)
    end

    test "invalid cursor_fields with extra non-id field returns error" do
      assert {:error, msg} = PaginationValidator.validate_or_infer(
        [{:title, :asc}],
        [{:title, :asc}, {:name, :asc}]
      )

      assert is_binary(msg)
    end
  end
end
