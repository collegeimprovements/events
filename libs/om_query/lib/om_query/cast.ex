defmodule OmQuery.Cast do
  @moduledoc """
  Value casting for query filters.

  This module converts values (typically strings from HTTP params) to
  appropriate Elixir types for database queries. It's used internally
  by OmQuery when processing filter values with type hints.

  ## Supported Types

  | Type | Casts From | Example |
  |------|------------|---------|
  | `:integer` | String, Integer | `"42"` → `42` |
  | `:float` | String, Float, Integer | `"3.14"` → `3.14` |
  | `:decimal` | String, Decimal, Integer, Float | `"99.99"` → `Decimal` |
  | `:boolean` | `"true"`, `"false"`, `"1"`, `"0"` | `"true"` → `true` |
  | `:date` | ISO8601 string, Date | `"2024-01-15"` → `~D[2024-01-15]` |
  | `:datetime` | ISO8601 string, DateTime | `"2024-01-15T10:30:00Z"` → `DateTime` |
  | `:uuid` | UUID string | Validates and normalizes UUIDs |
  | `:atom` | String (must be existing atom) | `"ok"` → `:ok` |

  ## Usage

  Casting is typically used via `OmQuery.filter/5` with the `:cast` option:

      # Cast string value to integer
      OmQuery.filter(token, :age, :gte, params["age"], cast: :integer)

      # Cast multiple values for :in operator
      OmQuery.filter(token, :status_id, :in, params["ids"], cast: :integer)

  ## Errors

  Invalid casts raise `OmQuery.CastError` with helpful messages:

      ** (OmQuery.CastError) Cannot cast "abc" to integer

      Ensure the value is a valid integer or string representation (e.g., "42")
  """

  @doc """
  Cast a value to the specified type.

  Supports casting lists of values (e.g., for :in operator).

  ## Supported Types

  - `:integer` - Parse string to integer
  - `:float` - Parse string to float
  - `:decimal` - Parse to Decimal
  - `:boolean` - Parse "true"/"false"/"1"/"0"
  - `:date` - Parse ISO8601 date
  - `:datetime` - Parse ISO8601 datetime
  - `:uuid` - Validate and normalize UUID
  - `:atom` - Convert to existing atom

  ## Examples

      Cast.cast("42", :integer)
      # => 42

      Cast.cast(["1", "2", "3"], :integer)
      # => [1, 2, 3]

      Cast.cast("true", :boolean)
      # => true
  """
  @spec cast(term(), atom() | nil) :: term()
  def cast(value, nil), do: value
  def cast(values, type) when is_list(values), do: Enum.map(values, &cast(&1, type))

  # Integer
  def cast(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise OmQuery.CastError, value: value, target_type: :integer
    end
  end

  def cast(value, :integer) when is_integer(value), do: value

  # Float
  def cast(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> raise OmQuery.CastError, value: value, target_type: :float
    end
  end

  def cast(value, :float) when is_float(value), do: value
  def cast(value, :float) when is_integer(value), do: value * 1.0

  # Decimal
  def cast(value, :decimal) when is_binary(value), do: Decimal.new(value)
  def cast(%Decimal{} = value, :decimal), do: value
  def cast(value, :decimal) when is_integer(value), do: Decimal.new(value)
  def cast(value, :decimal) when is_float(value), do: Decimal.from_float(value)

  # Boolean
  def cast("true", :boolean), do: true
  def cast("false", :boolean), do: false
  def cast("1", :boolean), do: true
  def cast("0", :boolean), do: false
  def cast(value, :boolean) when is_boolean(value), do: value

  # Date
  def cast(value, :date) when is_binary(value), do: Date.from_iso8601!(value)
  def cast(%Date{} = value, :date), do: value

  # DateTime
  def cast(value, :datetime) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      {:error, _} -> NaiveDateTime.from_iso8601!(value)
    end
  end

  def cast(%DateTime{} = value, :datetime), do: value
  def cast(%NaiveDateTime{} = value, :datetime), do: value

  # UUID
  def cast(value, :uuid) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> raise OmQuery.CastError, value: value, target_type: :uuid
    end
  end

  # Atom
  def cast(value, :atom) when is_binary(value), do: String.to_existing_atom(value)
  def cast(value, :atom) when is_atom(value), do: value

  # Unknown type
  def cast(value, type) do
    raise OmQuery.CastError,
      value: value,
      target_type: type,
      suggestion: "Unknown cast type. Supported types: :integer, :float, :decimal, :boolean, :date, :datetime, :uuid, :atom"
  end
end
