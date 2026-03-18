defmodule OmSchema.Utils.ComparisonTest do
  @moduledoc """
  Tests for OmSchema.Utils.Comparison - type-safe comparison utilities.

  Provides:

  - `compare_values/3` - Compare any two values with operators (:==, :!=, :<, :<=, :>, :>=)
  - `compare_datetime/2` - Compare Date, DateTime, NaiveDateTime (including mixed types)
  - `datetime_past?/1` - Check if datetime is in the past
  - `datetime_future?/1` - Check if datetime is in the future
  - `datetime_after?/2` - Check if datetime is after a reference
  - `datetime_before?/2` - Check if datetime is before a reference
  """

  use ExUnit.Case, async: true

  alias OmSchema.Utils.Comparison

  # ============================================
  # compare_values/3 - Equality
  # ============================================

  describe "compare_values/3 :==" do
    test "equal integers" do
      assert Comparison.compare_values(5, :==, 5) == true
    end

    test "unequal integers" do
      assert Comparison.compare_values(5, :==, 6) == false
    end

    test "equal strings" do
      assert Comparison.compare_values("hello", :==, "hello") == true
    end

    test "unequal strings" do
      assert Comparison.compare_values("hello", :==, "world") == false
    end

    test "equal atoms" do
      assert Comparison.compare_values(:ok, :==, :ok) == true
    end

    test "nil equals nil" do
      assert Comparison.compare_values(nil, :==, nil) == true
    end

    test "equal floats" do
      assert Comparison.compare_values(3.14, :==, 3.14) == true
    end

    test "integer and float equality (Elixir ==)" do
      assert Comparison.compare_values(1, :==, 1.0) == true
    end

    test "equal dates" do
      assert Comparison.compare_values(~D[2024-01-01], :==, ~D[2024-01-01]) == true
    end

    test "equal booleans" do
      assert Comparison.compare_values(true, :==, true) == true
      assert Comparison.compare_values(false, :==, false) == true
    end
  end

  # ============================================
  # compare_values/3 - Inequality
  # ============================================

  describe "compare_values/3 :!=" do
    test "unequal integers" do
      assert Comparison.compare_values(5, :!=, 6) == true
    end

    test "equal integers" do
      assert Comparison.compare_values(5, :!=, 5) == false
    end

    test "unequal strings" do
      assert Comparison.compare_values("hello", :!=, "world") == true
    end

    test "nil not equal to a value" do
      assert Comparison.compare_values(nil, :!=, 1) == true
    end

    test "different types" do
      assert Comparison.compare_values("1", :!=, 1) == true
    end
  end

  # ============================================
  # compare_values/3 - Less Than
  # ============================================

  describe "compare_values/3 :<" do
    test "smaller integer" do
      assert Comparison.compare_values(3, :<, 5) == true
    end

    test "larger integer" do
      assert Comparison.compare_values(5, :<, 3) == false
    end

    test "equal integers" do
      assert Comparison.compare_values(5, :<, 5) == false
    end

    test "string comparison" do
      assert Comparison.compare_values("a", :<, "b") == true
      assert Comparison.compare_values("b", :<, "a") == false
    end

    test "float comparison" do
      assert Comparison.compare_values(1.5, :<, 2.5) == true
    end

    test "date comparison" do
      assert Comparison.compare_values(~D[2024-01-01], :<, ~D[2024-12-31]) == true
    end

    test "negative numbers" do
      assert Comparison.compare_values(-5, :<, -3) == true
      assert Comparison.compare_values(-3, :<, -5) == false
    end
  end

  # ============================================
  # compare_values/3 - Less Than or Equal
  # ============================================

  describe "compare_values/3 :<=" do
    test "smaller value" do
      assert Comparison.compare_values(3, :<=, 5) == true
    end

    test "equal value" do
      assert Comparison.compare_values(5, :<=, 5) == true
    end

    test "larger value" do
      assert Comparison.compare_values(6, :<=, 5) == false
    end
  end

  # ============================================
  # compare_values/3 - Greater Than
  # ============================================

  describe "compare_values/3 :>" do
    test "larger integer" do
      assert Comparison.compare_values(5, :>, 3) == true
    end

    test "smaller integer" do
      assert Comparison.compare_values(3, :>, 5) == false
    end

    test "equal integers" do
      assert Comparison.compare_values(5, :>, 5) == false
    end

    test "string comparison" do
      assert Comparison.compare_values("b", :>, "a") == true
    end

    test "float comparison" do
      assert Comparison.compare_values(2.5, :>, 1.5) == true
    end
  end

  # ============================================
  # compare_values/3 - Greater Than or Equal
  # ============================================

  describe "compare_values/3 :>=" do
    test "larger value" do
      assert Comparison.compare_values(5, :>=, 3) == true
    end

    test "equal value" do
      assert Comparison.compare_values(5, :>=, 5) == true
    end

    test "smaller value" do
      assert Comparison.compare_values(3, :>=, 5) == false
    end
  end

  # ============================================
  # compare_datetime/2 - Date vs Date
  # ============================================

  describe "compare_datetime/2 Date vs Date" do
    test "earlier date is :lt" do
      assert Comparison.compare_datetime(~D[2024-01-01], ~D[2024-12-31]) == :lt
    end

    test "later date is :gt" do
      assert Comparison.compare_datetime(~D[2024-12-31], ~D[2024-01-01]) == :gt
    end

    test "same date is :eq" do
      assert Comparison.compare_datetime(~D[2024-06-15], ~D[2024-06-15]) == :eq
    end

    test "adjacent dates" do
      assert Comparison.compare_datetime(~D[2024-01-01], ~D[2024-01-02]) == :lt
    end
  end

  # ============================================
  # compare_datetime/2 - DateTime vs DateTime
  # ============================================

  describe "compare_datetime/2 DateTime vs DateTime" do
    test "earlier datetime is :lt" do
      assert Comparison.compare_datetime(
               ~U[2024-01-01 00:00:00Z],
               ~U[2024-12-31 23:59:59Z]
             ) == :lt
    end

    test "later datetime is :gt" do
      assert Comparison.compare_datetime(
               ~U[2024-12-31 23:59:59Z],
               ~U[2024-01-01 00:00:00Z]
             ) == :gt
    end

    test "same datetime is :eq" do
      assert Comparison.compare_datetime(
               ~U[2024-06-15 12:00:00Z],
               ~U[2024-06-15 12:00:00Z]
             ) == :eq
    end

    test "datetimes differing by one second" do
      assert Comparison.compare_datetime(
               ~U[2024-06-15 12:00:00Z],
               ~U[2024-06-15 12:00:01Z]
             ) == :lt
    end

    test "datetimes with microseconds" do
      dt1 = DateTime.from_naive!(~N[2024-06-15 12:00:00.000001], "Etc/UTC")
      dt2 = DateTime.from_naive!(~N[2024-06-15 12:00:00.000002], "Etc/UTC")
      assert Comparison.compare_datetime(dt1, dt2) == :lt
    end
  end

  # ============================================
  # compare_datetime/2 - NaiveDateTime vs NaiveDateTime
  # ============================================

  describe "compare_datetime/2 NaiveDateTime vs NaiveDateTime" do
    test "earlier naive datetime is :lt" do
      assert Comparison.compare_datetime(
               ~N[2024-01-01 00:00:00],
               ~N[2024-12-31 23:59:59]
             ) == :lt
    end

    test "later naive datetime is :gt" do
      assert Comparison.compare_datetime(
               ~N[2024-12-31 23:59:59],
               ~N[2024-01-01 00:00:00]
             ) == :gt
    end

    test "same naive datetime is :eq" do
      assert Comparison.compare_datetime(
               ~N[2024-06-15 12:00:00],
               ~N[2024-06-15 12:00:00]
             ) == :eq
    end
  end

  # ============================================
  # compare_datetime/2 - Mixed Types
  # ============================================

  describe "compare_datetime/2 mixed types" do
    test "NaiveDateTime vs DateTime" do
      ndt = ~N[2024-01-01 00:00:00]
      dt = ~U[2024-12-31 00:00:00Z]
      assert Comparison.compare_datetime(ndt, dt) == :lt
    end

    test "DateTime vs NaiveDateTime" do
      dt = ~U[2024-12-31 00:00:00Z]
      ndt = ~N[2024-01-01 00:00:00]
      assert Comparison.compare_datetime(dt, ndt) == :gt
    end

    test "Date vs DateTime - same day" do
      date = ~D[2024-06-15]
      dt = ~U[2024-06-15 12:00:00Z]
      # Date is compared to DateTime.to_date(dt), so same day => :eq
      assert Comparison.compare_datetime(date, dt) == :eq
    end

    test "Date vs DateTime - different days" do
      date = ~D[2024-01-01]
      dt = ~U[2024-12-31 12:00:00Z]
      assert Comparison.compare_datetime(date, dt) == :lt
    end

    test "DateTime vs Date" do
      dt = ~U[2024-12-31 12:00:00Z]
      date = ~D[2024-01-01]
      assert Comparison.compare_datetime(dt, date) == :gt
    end

    test "Date vs NaiveDateTime" do
      date = ~D[2024-01-01]
      ndt = ~N[2024-12-31 12:00:00]
      assert Comparison.compare_datetime(date, ndt) == :lt
    end

    test "NaiveDateTime vs Date" do
      ndt = ~N[2024-12-31 12:00:00]
      date = ~D[2024-01-01]
      assert Comparison.compare_datetime(ndt, date) == :gt
    end

    test "equal NaiveDateTime and DateTime (same instant)" do
      ndt = ~N[2024-06-15 12:00:00]
      dt = ~U[2024-06-15 12:00:00Z]
      assert Comparison.compare_datetime(ndt, dt) == :eq
    end

    test "fallback for incompatible types returns :eq" do
      assert Comparison.compare_datetime("not a date", 42) == :eq
      assert Comparison.compare_datetime(nil, nil) == :eq
      assert Comparison.compare_datetime(:atom, "string") == :eq
    end
  end

  # ============================================
  # datetime_past?/1
  # ============================================

  describe "datetime_past?/1" do
    test "far past DateTime is past" do
      assert Comparison.datetime_past?(~U[2020-01-01 00:00:00Z]) == true
    end

    test "far future DateTime is not past" do
      assert Comparison.datetime_past?(~U[2099-12-31 23:59:59Z]) == false
    end

    test "far past Date is past" do
      assert Comparison.datetime_past?(~D[2020-01-01]) == true
    end

    test "far future Date is not past" do
      assert Comparison.datetime_past?(~D[2099-12-31]) == false
    end

    test "far past NaiveDateTime is past" do
      assert Comparison.datetime_past?(~N[2020-01-01 00:00:00]) == true
    end

    test "far future NaiveDateTime is not past" do
      assert Comparison.datetime_past?(~N[2099-12-31 23:59:59]) == false
    end
  end

  # ============================================
  # datetime_future?/1
  # ============================================

  describe "datetime_future?/1" do
    test "far future DateTime is future" do
      assert Comparison.datetime_future?(~U[2099-12-31 23:59:59Z]) == true
    end

    test "far past DateTime is not future" do
      assert Comparison.datetime_future?(~U[2020-01-01 00:00:00Z]) == false
    end

    test "far future Date is future" do
      assert Comparison.datetime_future?(~D[2099-12-31]) == true
    end

    test "far past Date is not future" do
      assert Comparison.datetime_future?(~D[2020-01-01]) == false
    end

    test "far future NaiveDateTime is future" do
      assert Comparison.datetime_future?(~N[2099-12-31 23:59:59]) == true
    end

    test "far past NaiveDateTime is not future" do
      assert Comparison.datetime_future?(~N[2020-01-01 00:00:00]) == false
    end
  end

  # ============================================
  # datetime_after?/2
  # ============================================

  describe "datetime_after?/2" do
    test "later datetime is after earlier" do
      assert Comparison.datetime_after?(~U[2024-12-31 00:00:00Z], ~U[2024-01-01 00:00:00Z]) ==
               true
    end

    test "earlier datetime is not after later" do
      assert Comparison.datetime_after?(~U[2024-01-01 00:00:00Z], ~U[2024-12-31 00:00:00Z]) ==
               false
    end

    test "same datetime is not after itself" do
      dt = ~U[2024-06-15 12:00:00Z]
      assert Comparison.datetime_after?(dt, dt) == false
    end

    test "works with Date types" do
      assert Comparison.datetime_after?(~D[2024-12-31], ~D[2024-01-01]) == true
      assert Comparison.datetime_after?(~D[2024-01-01], ~D[2024-12-31]) == false
    end

    test "works with NaiveDateTime types" do
      assert Comparison.datetime_after?(~N[2024-12-31 00:00:00], ~N[2024-01-01 00:00:00]) == true
    end

    test "works with mixed types" do
      assert Comparison.datetime_after?(~U[2024-12-31 00:00:00Z], ~D[2024-01-01]) == true
      assert Comparison.datetime_after?(~N[2024-12-31 00:00:00], ~U[2024-01-01 00:00:00Z]) == true
    end
  end

  # ============================================
  # datetime_before?/2
  # ============================================

  describe "datetime_before?/2" do
    test "earlier datetime is before later" do
      assert Comparison.datetime_before?(~U[2024-01-01 00:00:00Z], ~U[2024-12-31 00:00:00Z]) ==
               true
    end

    test "later datetime is not before earlier" do
      assert Comparison.datetime_before?(~U[2024-12-31 00:00:00Z], ~U[2024-01-01 00:00:00Z]) ==
               false
    end

    test "same datetime is not before itself" do
      dt = ~U[2024-06-15 12:00:00Z]
      assert Comparison.datetime_before?(dt, dt) == false
    end

    test "works with Date types" do
      assert Comparison.datetime_before?(~D[2024-01-01], ~D[2024-12-31]) == true
      assert Comparison.datetime_before?(~D[2024-12-31], ~D[2024-01-01]) == false
    end

    test "works with NaiveDateTime types" do
      assert Comparison.datetime_before?(~N[2024-01-01 00:00:00], ~N[2024-12-31 00:00:00]) ==
               true
    end

    test "works with mixed types" do
      assert Comparison.datetime_before?(~D[2024-01-01], ~U[2024-12-31 00:00:00Z]) == true
      assert Comparison.datetime_before?(~U[2024-01-01 00:00:00Z], ~N[2024-12-31 00:00:00]) ==
               true
    end
  end

  # ============================================
  # naive_to_datetime/1
  # ============================================

  describe "naive_to_datetime/1" do
    test "converts NaiveDateTime to UTC DateTime" do
      ndt = ~N[2024-06-15 12:00:00]
      result = Comparison.naive_to_datetime(ndt)

      assert %DateTime{} = result
      assert result.year == 2024
      assert result.month == 6
      assert result.day == 15
      assert result.hour == 12
      assert result.time_zone == "Etc/UTC"
    end

    test "preserves microseconds" do
      ndt = ~N[2024-06-15 12:00:00.123456]
      result = Comparison.naive_to_datetime(ndt)

      assert result.microsecond == {123_456, 6}
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "compare_values with zero" do
      assert Comparison.compare_values(0, :==, 0) == true
      assert Comparison.compare_values(0, :<, 1) == true
      assert Comparison.compare_values(0, :>, -1) == true
    end

    test "compare_values with empty strings" do
      assert Comparison.compare_values("", :==, "") == true
      assert Comparison.compare_values("", :<, "a") == true
    end

    test "compare_values with boolean" do
      assert Comparison.compare_values(true, :==, true) == true
      assert Comparison.compare_values(true, :!=, false) == true
    end

    test "compare_values with lists" do
      assert Comparison.compare_values([1, 2], :==, [1, 2]) == true
      assert Comparison.compare_values([1], :!=, [1, 2]) == true
    end

    test "compare_datetime with epoch boundary" do
      epoch = ~U[1970-01-01 00:00:00Z]
      before_epoch = ~U[1969-12-31 23:59:59Z]
      assert Comparison.compare_datetime(before_epoch, epoch) == :lt
    end

    test "compare_datetime with year boundaries" do
      new_years_eve = ~U[2024-12-31 23:59:59Z]
      new_years_day = ~U[2025-01-01 00:00:00Z]
      assert Comparison.compare_datetime(new_years_eve, new_years_day) == :lt
    end

    test "datetime_after? and datetime_before? are inverses for non-equal" do
      d1 = ~U[2024-01-01 00:00:00Z]
      d2 = ~U[2024-12-31 00:00:00Z]

      assert Comparison.datetime_after?(d1, d2) != Comparison.datetime_after?(d2, d1)
      assert Comparison.datetime_before?(d1, d2) != Comparison.datetime_before?(d2, d1)
    end

    test "datetime_after? and datetime_before? both false for equal" do
      dt = ~U[2024-06-15 12:00:00Z]
      assert Comparison.datetime_after?(dt, dt) == false
      assert Comparison.datetime_before?(dt, dt) == false
    end
  end
end
