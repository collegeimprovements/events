defmodule OmQuery.ErrorTest do
  @moduledoc """
  Tests for OmQuery error types.
  """

  use ExUnit.Case, async: true

  # ============================================
  # ParameterLimitError
  # ============================================

  describe "ParameterLimitError" do
    test "has correct fields" do
      error = %OmQuery.ParameterLimitError{
        count: 25,
        max_allowed: 20,
        sql_preview: "col1 = ? AND col2 = ?"
      }

      assert error.count == 25
      assert error.max_allowed == 20
      assert error.sql_preview == "col1 = ? AND col2 = ?"
    end

    test "message includes count and max_allowed" do
      error = %OmQuery.ParameterLimitError{count: 25, max_allowed: 20}
      msg = Exception.message(error)

      assert msg =~ "maximum 20 parameters"
      assert msg =~ "got 25"
    end

    test "message includes SQL preview when provided" do
      error = %OmQuery.ParameterLimitError{
        count: 25,
        max_allowed: 20,
        sql_preview: "SELECT * FROM users WHERE id = ?"
      }

      msg = Exception.message(error)
      assert msg =~ "SQL fragment:"
      assert msg =~ "SELECT * FROM users"
    end

    test "message includes alternatives" do
      error = %OmQuery.ParameterLimitError{count: 25, max_allowed: 20}
      msg = Exception.message(error)

      assert msg =~ "Alternatives:"
      assert msg =~ "Split into multiple"
    end

    test "truncates long SQL previews" do
      long_sql = String.duplicate("x", 150)
      error = %OmQuery.ParameterLimitError{
        count: 25,
        max_allowed: 20,
        sql_preview: long_sql
      }

      msg = Exception.message(error)
      assert msg =~ "..."
    end
  end

  # ============================================
  # CastError
  # ============================================

  describe "CastError" do
    test "has correct fields" do
      error = %OmQuery.CastError{value: "abc", target_type: :integer}
      assert error.value == "abc"
      assert error.target_type == :integer
    end

    test "message shows value and target type" do
      error = %OmQuery.CastError{value: "abc", target_type: :integer}
      msg = Exception.message(error)

      assert msg =~ "Cannot cast"
      assert msg =~ "\"abc\""
      assert msg =~ "integer"
    end

    test "includes suggestion for integer" do
      error = %OmQuery.CastError{value: "abc", target_type: :integer}
      msg = Exception.message(error)

      assert msg =~ "valid integer"
    end

    test "includes suggestion for float" do
      error = %OmQuery.CastError{value: "abc", target_type: :float}
      msg = Exception.message(error)

      assert msg =~ "valid number"
    end

    test "includes suggestion for uuid" do
      error = %OmQuery.CastError{value: "invalid", target_type: :uuid}
      msg = Exception.message(error)

      assert msg =~ "UUID string"
    end

    test "includes suggestion for boolean" do
      error = %OmQuery.CastError{value: "maybe", target_type: :boolean}
      msg = Exception.message(error)

      assert msg =~ "true, false"
    end

    test "uses custom suggestion when provided" do
      error = %OmQuery.CastError{
        value: "x",
        target_type: :custom,
        suggestion: "Use a special format"
      }

      msg = Exception.message(error)
      assert msg =~ "Use a special format"
    end
  end

  # ============================================
  # OperatorError
  # ============================================

  describe "OperatorError" do
    test "has correct fields" do
      error = %OmQuery.OperatorError{
        operator: :invalid,
        context: :filter,
        supported: [:eq, :neq, :gt]
      }

      assert error.operator == :invalid
      assert error.context == :filter
      assert error.supported == [:eq, :neq, :gt]
    end

    test "message shows operator and context" do
      error = %OmQuery.OperatorError{
        operator: :invalid,
        context: :filter,
        supported: [:eq, :neq]
      }

      msg = Exception.message(error)
      assert msg =~ "Unknown filter operator"
      assert msg =~ ":invalid"
    end

    test "message lists supported operators" do
      error = %OmQuery.OperatorError{
        operator: :invalid,
        context: :filter,
        supported: [:eq, :neq, :gt]
      }

      msg = Exception.message(error)
      assert msg =~ "Supported operators:"
      assert msg =~ ":eq"
      assert msg =~ ":neq"
      assert msg =~ ":gt"
    end

    test "includes suggestion when provided" do
      error = %OmQuery.OperatorError{
        operator: :invalid,
        context: :filter,
        supported: [:eq],
        suggestion: "Did you mean :eq?"
      }

      msg = Exception.message(error)
      assert msg =~ "Suggestion:"
      assert msg =~ "Did you mean"
    end
  end

  # ============================================
  # SearchModeError
  # ============================================

  describe "SearchModeError" do
    test "has correct fields" do
      error = %OmQuery.SearchModeError{mode: :invalid, field: :name}
      assert error.mode == :invalid
      assert error.field == :name
    end

    test "message shows mode and field" do
      error = %OmQuery.SearchModeError{mode: :fuzzy, field: :title}
      msg = Exception.message(error)

      assert msg =~ "Unknown search mode"
      assert msg =~ ":fuzzy"
      assert msg =~ ":title"
    end

    test "message lists supported modes" do
      error = %OmQuery.SearchModeError{mode: :invalid, field: :name}
      msg = Exception.message(error)

      assert msg =~ "Supported modes:"
      assert msg =~ ":ilike"
      assert msg =~ ":similarity"
    end

    test "message includes usage example" do
      error = %OmQuery.SearchModeError{mode: :invalid, field: :name}
      msg = Exception.message(error)

      assert msg =~ "Example usage:"
      assert msg =~ "OmQuery.search"
    end
  end

  # ============================================
  # WindowFunctionError
  # ============================================

  describe "WindowFunctionError" do
    test "has correct fields" do
      error = %OmQuery.WindowFunctionError{
        function: :row_number,
        context: :select
      }

      assert error.function == :row_number
      assert error.context == :select
    end

    test "message explains limitation" do
      error = %OmQuery.WindowFunctionError{
        function: :row_number,
        context: :select
      }

      msg = Exception.message(error)
      assert msg =~ "Window function"
      assert msg =~ ":row_number"
      assert msg =~ "cannot be used dynamically"
      assert msg =~ "compile-time"
    end

    test "message provides alternatives" do
      error = %OmQuery.WindowFunctionError{
        function: :rank,
        context: :order_by
      }

      msg = Exception.message(error)
      assert msg =~ "Alternatives:"
      assert msg =~ "OmQuery.raw"
      assert msg =~ "Ecto.Query"
    end

    test "uses custom suggestion when provided" do
      error = %OmQuery.WindowFunctionError{
        function: :custom,
        context: :select,
        suggestion: "Use a database view instead"
      }

      msg = Exception.message(error)
      assert msg =~ "Use a database view instead"
    end
  end

  # ============================================
  # Existing Error Types
  # ============================================

  describe "ValidationError" do
    test "has correct fields" do
      error = %OmQuery.ValidationError{
        operation: :filter,
        reason: "Invalid field",
        value: :unknown
      }

      assert error.operation == :filter
      assert error.reason == "Invalid field"
      assert error.value == :unknown
    end

    test "message includes operation and reason" do
      error = %OmQuery.ValidationError{
        operation: :filter,
        reason: "Field not found"
      }

      msg = Exception.message(error)
      assert msg =~ "Invalid filter operation"
      assert msg =~ "Field not found"
    end

    test "includes suggestion when provided" do
      error = %OmQuery.ValidationError{
        operation: :order_by,
        reason: "Invalid direction",
        value: :sideways,
        suggestion: "Use :asc or :desc"
      }

      msg = Exception.message(error)
      assert msg =~ "Suggestion:"
      assert msg =~ "Use :asc or :desc"
    end
  end

  describe "LimitExceededError" do
    test "has correct fields" do
      error = %OmQuery.LimitExceededError{
        requested: 10_000,
        max_allowed: 1_000
      }

      assert error.requested == 10_000
      assert error.max_allowed == 1_000
    end

    test "message shows limits" do
      error = %OmQuery.LimitExceededError{
        requested: 5000,
        max_allowed: 1000
      }

      msg = Exception.message(error)
      assert msg =~ "5000"
      assert msg =~ "1000"
    end

    test "message includes config hint" do
      error = %OmQuery.LimitExceededError{
        requested: 5000,
        max_allowed: 1000
      }

      msg = Exception.message(error)
      assert msg =~ "config :om_query"
      assert msg =~ "max_limit"
    end
  end

  describe "CursorError" do
    test "has correct fields" do
      error = %OmQuery.CursorError{
        cursor: "abc123",
        reason: "Invalid format"
      }

      assert error.cursor == "abc123"
      assert error.reason == "Invalid format"
    end

    test "message shows reason" do
      error = %OmQuery.CursorError{
        cursor: "xyz",
        reason: "Expired"
      }

      msg = Exception.message(error)
      assert msg =~ "Invalid cursor"
      assert msg =~ "Expired"
    end

    test "truncates long cursors" do
      long_cursor = String.duplicate("x", 100)
      error = %OmQuery.CursorError{
        cursor: long_cursor,
        reason: "Invalid"
      }

      msg = Exception.message(error)
      assert msg =~ "..."
    end
  end
end
