defmodule OmQuery.Cast do
  @moduledoc false
  # Internal module - use OmQuery public API instead.
  #
  # Value casting for query filters.
  # Converts string values from params to appropriate Elixir types.

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
      _ -> raise ArgumentError, "Cannot cast #{inspect(value)} to integer"
    end
  end

  def cast(value, :integer) when is_integer(value), do: value

  # Float
  def cast(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> raise ArgumentError, "Cannot cast #{inspect(value)} to float"
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
      :error -> raise ArgumentError, "Cannot cast #{inspect(value)} to UUID"
    end
  end

  # Atom
  def cast(value, :atom) when is_binary(value), do: String.to_existing_atom(value)
  def cast(value, :atom) when is_atom(value), do: value

  # Unknown type
  def cast(value, type) do
    raise ArgumentError, "Unknown cast type #{inspect(type)} for value #{inspect(value)}"
  end
end
