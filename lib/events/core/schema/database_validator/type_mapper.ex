defmodule Events.Core.Schema.DatabaseValidator.TypeMapper do
  @moduledoc """
  Maps between Ecto types and PostgreSQL types for schema validation.

  Provides functions to check if an Ecto type is compatible with a PostgreSQL type,
  handling the many variations and aliases that PostgreSQL supports.

  ## Type Compatibility

  The mapper considers types compatible when:
  - The PostgreSQL type is in the list of acceptable types for the Ecto type
  - Array types match (Ecto `{:array, inner}` matches PostgreSQL `ARRAY` with matching element type)
  - Custom types like `Ecto.Enum` are handled as their underlying storage types

  ## Examples

      TypeMapper.compatible?(:string, "character varying")
      # => true

      TypeMapper.compatible?(:integer, "text")
      # => false

      TypeMapper.compatible?({:array, :string}, "ARRAY")
      # => true (element type is checked separately)
  """

  @doc """
  Maps Ecto types to lists of compatible PostgreSQL types.

  Returns a list of PostgreSQL type names that are considered compatible
  with the given Ecto type.
  """
  @spec pg_types_for(atom() | tuple()) :: [String.t()]
  def pg_types_for(:id), do: ["bigint", "integer", "int8", "int4"]
  def pg_types_for(:binary_id), do: ["uuid"]
  def pg_types_for(:integer), do: ["integer", "int4", "smallint", "int2", "bigint", "int8"]
  def pg_types_for(:float), do: ["double precision", "float8", "real", "float4", "numeric"]
  def pg_types_for(:decimal), do: ["numeric", "decimal"]
  def pg_types_for(:boolean), do: ["boolean", "bool"]

  def pg_types_for(:string),
    do: ["character varying", "varchar", "text", "char", "character", "citext"]

  def pg_types_for(:citext), do: ["citext"]
  def pg_types_for(:binary), do: ["bytea"]
  def pg_types_for(:map), do: ["jsonb", "json"]
  def pg_types_for(:date), do: ["date"]
  def pg_types_for(:time), do: ["time without time zone", "time", "timetz", "time with time zone"]

  def pg_types_for(:time_usec),
    do: ["time without time zone", "time", "timetz", "time with time zone"]

  def pg_types_for(:naive_datetime),
    do: ["timestamp without time zone", "timestamp"]

  def pg_types_for(:naive_datetime_usec),
    do: ["timestamp without time zone", "timestamp"]

  def pg_types_for(:utc_datetime),
    do: ["timestamp with time zone", "timestamptz"]

  def pg_types_for(:utc_datetime_usec),
    do: ["timestamp with time zone", "timestamptz"]

  # Ecto.Enum is stored as string/varchar by default
  def pg_types_for(Ecto.Enum), do: ["character varying", "varchar", "text"]

  # UUID type
  def pg_types_for(Ecto.UUID), do: ["uuid"]

  # Array types
  def pg_types_for({:array, _inner}), do: ["ARRAY"]

  # Map types with schema
  def pg_types_for({:map, _inner}), do: ["jsonb", "json"]

  # Embedded schemas
  def pg_types_for({:embed, _}), do: ["jsonb", "json"]

  # Parameterized types (for {:parameterized, Ecto.Enum, ...})
  def pg_types_for({:parameterized, Ecto.Enum, _}), do: ["character varying", "varchar", "text"]
  def pg_types_for({:parameterized, _, _}), do: []

  # Unknown type - return empty list (will fail validation)
  def pg_types_for(_unknown), do: []

  @doc """
  Checks if an Ecto type is compatible with a PostgreSQL type.

  ## Examples

      iex> TypeMapper.compatible?(:string, "character varying")
      true

      iex> TypeMapper.compatible?(:integer, "text")
      false

      iex> TypeMapper.compatible?(:map, "jsonb")
      true
  """
  @spec compatible?(atom() | tuple(), String.t()) :: boolean()
  def compatible?(ecto_type, pg_type) do
    pg_types = pg_types_for(ecto_type)
    Enum.any?(pg_types, &type_matches?(&1, pg_type))
  end

  defp type_matches?(expected, actual) do
    # Normalize both for comparison
    normalize_type(expected) == normalize_type(actual)
  end

  defp normalize_type(type) do
    type
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Returns a human-readable string describing expected types.

  Useful for error messages.
  """
  @spec expected_types_description(atom() | tuple()) :: String.t()
  def expected_types_description(ecto_type) do
    case pg_types_for(ecto_type) do
      [] -> "unknown"
      [single] -> single
      types -> Enum.join(types, ", ")
    end
  end

  @doc """
  Attempts to infer the Ecto type from a PostgreSQL type.

  Returns the most likely Ecto type, or `:unknown` if no match.
  """
  @spec infer_ecto_type(String.t()) :: atom() | tuple()
  def infer_ecto_type(pg_type) do
    normalized = normalize_type(pg_type)

    cond do
      normalized in ["uuid"] -> :binary_id
      normalized in ["bigint", "int8"] -> :integer
      normalized in ["integer", "int4", "smallint", "int2"] -> :integer
      normalized in ["double precision", "float8", "real", "float4"] -> :float
      normalized in ["numeric", "decimal"] -> :decimal
      normalized in ["boolean", "bool"] -> :boolean
      normalized in ["character varying", "varchar", "text", "char", "character"] -> :string
      normalized in ["citext"] -> :citext
      normalized in ["bytea"] -> :binary
      normalized in ["jsonb", "json"] -> :map
      normalized in ["date"] -> :date
      normalized in ["time without time zone", "time"] -> :time
      normalized in ["timestamp without time zone", "timestamp"] -> :naive_datetime
      normalized in ["timestamp with time zone", "timestamptz"] -> :utc_datetime
      String.starts_with?(normalized, "array") -> {:array, :unknown}
      true -> :unknown
    end
  end

  @doc """
  Checks if a PostgreSQL column can store NULL values given the Ecto field options.

  Returns true if there's a mismatch that should be warned about.
  """
  @spec nullable_mismatch?(boolean(), boolean()) :: boolean()
  def nullable_mismatch?(schema_required, db_is_nullable) do
    # If schema says required: true, but DB allows NULL, that's a mismatch
    # (validation will catch the nil, but it's better to have DB constraint too)
    schema_required && db_is_nullable
  end

  @doc """
  Returns the PostgreSQL array element type from an array type definition.

  ## Examples

      iex> TypeMapper.array_element_type("character varying[]")
      "character varying"

      iex> TypeMapper.array_element_type("integer[]")
      "integer"
  """
  @spec array_element_type(String.t()) :: String.t() | nil
  def array_element_type(pg_type) do
    case Regex.run(~r/^(.+)\[\]$/, pg_type) do
      [_, element_type] -> element_type
      _ -> nil
    end
  end

  @doc """
  Checks if Ecto array element type is compatible with PostgreSQL array element type.
  """
  @spec array_compatible?(atom(), String.t()) :: boolean()
  def array_compatible?(ecto_element_type, pg_array_type) do
    case array_element_type(pg_array_type) do
      nil -> false
      pg_element -> compatible?(ecto_element_type, pg_element)
    end
  end
end
