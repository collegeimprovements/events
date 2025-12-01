defmodule Events.Core.Schema.Utils.Comparison do
  @moduledoc """
  Shared comparison utilities for schema validation.

  Provides type-safe comparison functions for values, datetimes, and fields.
  Used by Validators, ValidatorsExtended, and DateTime validator.

  ## Usage

      alias Events.Core.Schema.Utils.Comparison

      # Compare values with operator
      Comparison.compare_values(10, :>, 5)      # => true
      Comparison.compare_values("a", :==, "a")  # => true

      # Compare datetimes (supports Date, DateTime, NaiveDateTime)
      Comparison.compare_datetime(date1, date2)  # => :lt | :eq | :gt
  """

  @utc_timezone "Etc/UTC"

  # ============================================
  # Value Comparison
  # ============================================

  @doc """
  Compares two values using the given operator.

  ## Supported Operators

  - `:==` - Equal
  - `:!=` - Not equal
  - `:<` - Less than
  - `:<=` - Less than or equal
  - `:>` - Greater than
  - `:>=` - Greater than or equal

  ## Examples

      compare_values(10, :>, 5)
      # => true

      compare_values("a", :==, "b")
      # => false

      compare_values(~D[2024-01-01], :<, ~D[2024-12-31])
      # => true
  """
  @spec compare_values(any(), atom(), any()) :: boolean()
  def compare_values(v1, :==, v2), do: v1 == v2
  def compare_values(v1, :!=, v2), do: v1 != v2
  def compare_values(v1, :<, v2), do: v1 < v2
  def compare_values(v1, :<=, v2), do: v1 <= v2
  def compare_values(v1, :>, v2), do: v1 > v2
  def compare_values(v1, :>=, v2), do: v1 >= v2

  # ============================================
  # DateTime Comparison
  # ============================================

  @doc """
  Compares two datetime values, returning `:lt`, `:eq`, or `:gt`.

  Supports comparison between:
  - `Date` and `Date`
  - `DateTime` and `DateTime`
  - `NaiveDateTime` and `NaiveDateTime`
  - Mixed types (converts for comparison)

  ## Examples

      compare_datetime(~D[2024-01-01], ~D[2024-12-31])
      # => :lt

      compare_datetime(DateTime.utc_now(), DateTime.utc_now())
      # => :eq (or :lt/:gt depending on timing)
  """
  @spec compare_datetime(
          Date.t() | DateTime.t() | NaiveDateTime.t(),
          Date.t() | DateTime.t() | NaiveDateTime.t()
        ) :: :lt | :eq | :gt
  def compare_datetime(%Date{} = d1, %Date{} = d2) do
    Date.compare(d1, d2)
  end

  def compare_datetime(%DateTime{} = dt1, %DateTime{} = dt2) do
    DateTime.compare(dt1, dt2)
  end

  # NaiveDateTime comparisons (convert to DateTime)
  def compare_datetime(%NaiveDateTime{} = ndt1, %NaiveDateTime{} = ndt2) do
    compare_datetime(naive_to_datetime(ndt1), naive_to_datetime(ndt2))
  end

  def compare_datetime(%NaiveDateTime{} = ndt, %DateTime{} = dt) do
    compare_datetime(naive_to_datetime(ndt), dt)
  end

  def compare_datetime(%DateTime{} = dt, %NaiveDateTime{} = ndt) do
    compare_datetime(dt, naive_to_datetime(ndt))
  end

  # Mixed Date/DateTime comparisons
  def compare_datetime(%Date{} = d, %DateTime{} = dt) do
    compare_datetime(d, DateTime.to_date(dt))
  end

  def compare_datetime(%DateTime{} = dt, %Date{} = d) do
    compare_datetime(DateTime.to_date(dt), d)
  end

  def compare_datetime(%Date{} = d, %NaiveDateTime{} = ndt) do
    compare_datetime(d, naive_to_datetime(ndt))
  end

  def compare_datetime(%NaiveDateTime{} = ndt, %Date{} = d) do
    compare_datetime(naive_to_datetime(ndt), d)
  end

  # Fallback for incompatible types
  def compare_datetime(_, _), do: :eq

  @doc """
  Checks if a datetime is in the past relative to now.

  ## Examples

      datetime_past?(~U[2020-01-01 00:00:00Z])
      # => true
  """
  @spec datetime_past?(Date.t() | DateTime.t() | NaiveDateTime.t()) :: boolean()
  def datetime_past?(datetime) do
    compare_datetime(datetime, DateTime.utc_now()) == :lt
  end

  @doc """
  Checks if a datetime is in the future relative to now.

  ## Examples

      datetime_future?(~U[2030-01-01 00:00:00Z])
      # => true
  """
  @spec datetime_future?(Date.t() | DateTime.t() | NaiveDateTime.t()) :: boolean()
  def datetime_future?(datetime) do
    compare_datetime(datetime, DateTime.utc_now()) == :gt
  end

  @doc """
  Checks if a datetime is after a reference datetime.
  """
  @spec datetime_after?(
          Date.t() | DateTime.t() | NaiveDateTime.t(),
          Date.t() | DateTime.t() | NaiveDateTime.t()
        ) :: boolean()
  def datetime_after?(datetime, reference) do
    compare_datetime(datetime, reference) == :gt
  end

  @doc """
  Checks if a datetime is before a reference datetime.
  """
  @spec datetime_before?(
          Date.t() | DateTime.t() | NaiveDateTime.t(),
          Date.t() | DateTime.t() | NaiveDateTime.t()
        ) :: boolean()
  def datetime_before?(datetime, reference) do
    compare_datetime(datetime, reference) == :lt
  end

  # ============================================
  # Helpers
  # ============================================

  @doc false
  def naive_to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, @utc_timezone)
  end
end
