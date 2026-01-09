defmodule OmQuery.CastTest do
  @moduledoc """
  Tests for OmQuery.Cast - value type casting.
  """

  use ExUnit.Case, async: true

  alias OmQuery.Cast

  # ============================================
  # Passthrough
  # ============================================

  describe "cast/2 passthrough" do
    test "nil type returns value unchanged" do
      assert Cast.cast("anything", nil) == "anything"
      assert Cast.cast(123, nil) == 123
      assert Cast.cast(%{key: "value"}, nil) == %{key: "value"}
    end
  end

  # ============================================
  # Integer
  # ============================================

  describe "cast/2 integer" do
    test "casts string to integer" do
      assert Cast.cast("42", :integer) == 42
      assert Cast.cast("-10", :integer) == -10
      assert Cast.cast("0", :integer) == 0
    end

    test "passes through integer values" do
      assert Cast.cast(42, :integer) == 42
      assert Cast.cast(-10, :integer) == -10
    end

    test "casts list of strings" do
      assert Cast.cast(["1", "2", "3"], :integer) == [1, 2, 3]
    end

    test "raises CastError for invalid string" do
      assert_raise OmQuery.CastError, fn ->
        Cast.cast("not_a_number", :integer)
      end
    end

    test "raises CastError for string with trailing chars" do
      assert_raise OmQuery.CastError, fn ->
        Cast.cast("42abc", :integer)
      end
    end
  end

  # ============================================
  # Float
  # ============================================

  describe "cast/2 float" do
    test "casts string to float" do
      assert Cast.cast("3.14", :float) == 3.14
      assert Cast.cast("-2.5", :float) == -2.5
      assert Cast.cast("0.0", :float) == 0.0
    end

    test "passes through float values" do
      assert Cast.cast(3.14, :float) == 3.14
    end

    test "converts integer to float" do
      assert Cast.cast(42, :float) == 42.0
    end

    test "casts list of strings" do
      assert Cast.cast(["1.1", "2.2"], :float) == [1.1, 2.2]
    end

    test "raises CastError for invalid string" do
      assert_raise OmQuery.CastError, fn ->
        Cast.cast("not_a_float", :float)
      end
    end
  end

  # ============================================
  # Decimal
  # ============================================

  describe "cast/2 decimal" do
    test "casts string to Decimal" do
      result = Cast.cast("123.45", :decimal)
      assert Decimal.equal?(result, Decimal.new("123.45"))
    end

    test "passes through Decimal values" do
      dec = Decimal.new("99.99")
      assert Cast.cast(dec, :decimal) == dec
    end

    test "casts integer to Decimal" do
      result = Cast.cast(42, :decimal)
      assert Decimal.equal?(result, Decimal.new(42))
    end

    test "casts float to Decimal" do
      result = Cast.cast(3.14, :decimal)
      assert Decimal.equal?(result, Decimal.from_float(3.14))
    end
  end

  # ============================================
  # Boolean
  # ============================================

  describe "cast/2 boolean" do
    test "casts 'true' string" do
      assert Cast.cast("true", :boolean) == true
    end

    test "casts 'false' string" do
      assert Cast.cast("false", :boolean) == false
    end

    test "casts '1' string" do
      assert Cast.cast("1", :boolean) == true
    end

    test "casts '0' string" do
      assert Cast.cast("0", :boolean) == false
    end

    test "passes through boolean values" do
      assert Cast.cast(true, :boolean) == true
      assert Cast.cast(false, :boolean) == false
    end
  end

  # ============================================
  # Date
  # ============================================

  describe "cast/2 date" do
    test "casts ISO8601 string to Date" do
      result = Cast.cast("2024-01-15", :date)
      assert result == ~D[2024-01-15]
    end

    test "passes through Date values" do
      date = ~D[2024-01-15]
      assert Cast.cast(date, :date) == date
    end
  end

  # ============================================
  # DateTime
  # ============================================

  describe "cast/2 datetime" do
    test "casts ISO8601 string with timezone to DateTime" do
      result = Cast.cast("2024-01-15T10:30:00Z", :datetime)
      assert result.year == 2024
      assert result.month == 1
      assert result.day == 15
      assert result.hour == 10
    end

    test "casts ISO8601 string without timezone to NaiveDateTime" do
      result = Cast.cast("2024-01-15T10:30:00", :datetime)
      assert result == ~N[2024-01-15 10:30:00]
    end

    test "passes through DateTime values" do
      dt = DateTime.utc_now()
      assert Cast.cast(dt, :datetime) == dt
    end

    test "passes through NaiveDateTime values" do
      ndt = ~N[2024-01-15 10:30:00]
      assert Cast.cast(ndt, :datetime) == ndt
    end
  end

  # ============================================
  # UUID
  # ============================================

  describe "cast/2 uuid" do
    test "casts valid UUID string" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      result = Cast.cast(uuid, :uuid)
      assert result == uuid
    end

    test "normalizes UUID case" do
      uuid = "550E8400-E29B-41D4-A716-446655440000"
      result = Cast.cast(uuid, :uuid)
      assert result == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "raises CastError for invalid UUID" do
      assert_raise OmQuery.CastError, fn ->
        Cast.cast("not-a-uuid", :uuid)
      end
    end
  end

  # ============================================
  # Atom
  # ============================================

  describe "cast/2 atom" do
    test "casts string to existing atom" do
      # :ok is a known existing atom
      assert Cast.cast("ok", :atom) == :ok
    end

    test "passes through atom values" do
      assert Cast.cast(:existing, :atom) == :existing
    end

    test "raises for non-existing atom" do
      # String.to_existing_atom raises ArgumentError
      assert_raise ArgumentError, fn ->
        Cast.cast("definitely_not_an_existing_atom_xyz123", :atom)
      end
    end
  end

  # ============================================
  # Unknown Type
  # ============================================

  describe "cast/2 unknown type" do
    test "raises CastError for unknown type" do
      error = assert_raise OmQuery.CastError, fn ->
        Cast.cast("value", :unknown_type)
      end

      assert error.target_type == :unknown_type
      assert error.value == "value"
      assert error.suggestion =~ "Supported types"
    end
  end

  # ============================================
  # Lists
  # ============================================

  describe "cast/2 lists" do
    test "casts each element in a list" do
      assert Cast.cast(["1", "2", "3"], :integer) == [1, 2, 3]
      assert Cast.cast(["1.1", "2.2"], :float) == [1.1, 2.2]
      assert Cast.cast(["true", "false"], :boolean) == [true, false]
    end

    test "handles empty list" do
      assert Cast.cast([], :integer) == []
    end

    test "propagates errors from list elements" do
      assert_raise OmQuery.CastError, fn ->
        Cast.cast(["1", "invalid", "3"], :integer)
      end
    end
  end
end
