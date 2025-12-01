defmodule Events.Core.Repo.SqlScope.CheckConstraint do
  @moduledoc """
  Builder for CHECK constraint conditions.

  This module provides a fluent API for building CHECK constraint expressions
  that can be used in migrations to enforce data validation at the database level.

  ## Features

  - Type-safe constraint generation
  - Chainable API for complex validations
  - Common validation patterns (positive, range, length, enum)
  - JSONB validation support
  - Composite conditions (AND/OR)

  ## Examples

      # Simple positive constraint
      CheckConstraint.new(:price_positive)
      |> CheckConstraint.positive(:price)
      |> CheckConstraint.to_sql()
      #=> "price > 0"

      # Range constraint
      CheckConstraint.new(:quantity_valid)
      |> CheckConstraint.range(:quantity, 1, 1000)
      |> CheckConstraint.to_sql()
      #=> "quantity >= 1 AND quantity <= 1000"

      # Enum constraint
      CheckConstraint.new(:status_valid)
      |> CheckConstraint.enum(:status, ["draft", "published", "archived"])
      |> CheckConstraint.to_sql()
      #=> "status IN ('draft', 'published', 'archived')"

      # String length constraint
      CheckConstraint.new(:title_length)
      |> CheckConstraint.length_between(:title, 3, 100)
      |> CheckConstraint.to_sql()
      #=> "char_length(title) >= 3 AND char_length(title) <= 100"

      # Complex composite constraint
      CheckConstraint.new(:price_and_discount)
      |> CheckConstraint.positive(:price)
      |> CheckConstraint.range(:discount_percent, 0, 100)
      |> CheckConstraint.custom("price * (1 - discount_percent/100.0) > 0")
      |> CheckConstraint.to_sql()
  """

  alias Events.Core.Repo.SqlScope.Security

  defstruct name: nil, conditions: []

  @type t :: %__MODULE__{
          name: atom() | String.t() | nil,
          conditions: [String.t()]
        }

  @doc """
  Creates a new check constraint builder.

  ## Examples

      CheckConstraint.new(:price_positive)
      #=> %CheckConstraint{name: :price_positive, conditions: []}
  """
  @spec new(atom() | String.t()) :: t()
  def new(name) do
    Security.validate_identifier!(name)
    %__MODULE__{name: name}
  end

  # === NUMERIC VALIDATIONS ===

  @doc """
  Adds positive number constraint: field > 0

  ## Examples

      CheckConstraint.new(:price_positive) |> CheckConstraint.positive(:price)
      #=> "price > 0"
  """
  @spec positive(t(), atom() | String.t()) :: t()
  def positive(constraint, field) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} > 0")
  end

  @doc """
  Adds negative number constraint: field < 0
  """
  @spec negative(t(), atom() | String.t()) :: t()
  def negative(constraint, field) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} < 0")
  end

  @doc """
  Adds non-zero constraint: field != 0
  """
  @spec non_zero(t(), atom() | String.t()) :: t()
  def non_zero(constraint, field) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} != 0")
  end

  @doc """
  Adds minimum value constraint: field >= min

  ## Examples

      CheckConstraint.new(:age_valid) |> CheckConstraint.min(:age, 18)
      #=> "age >= 18"
  """
  @spec min(t(), atom() | String.t(), number()) :: t()
  def min(constraint, field, min_value) when is_number(min_value) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} >= #{min_value}")
  end

  @doc """
  Adds maximum value constraint: field <= max

  ## Examples

      CheckConstraint.new(:age_valid) |> CheckConstraint.max(:age, 120)
      #=> "age <= 120"
  """
  @spec max(t(), atom() | String.t(), number()) :: t()
  def max(constraint, field, max_value) when is_number(max_value) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} <= #{max_value}")
  end

  @doc """
  Adds range constraint: field >= min AND field <= max

  ## Examples

      CheckConstraint.new(:percentage) |> CheckConstraint.range(:discount, 0, 100)
      #=> "discount >= 0 AND discount <= 100"
  """
  @spec range(t(), atom() | String.t(), number(), number()) :: t()
  def range(constraint, field, min_value, max_value)
      when is_number(min_value) and is_number(max_value) do
    field_str = Security.validate_identifier!(field)

    add_condition(constraint, "#{field_str} >= #{min_value} AND #{field_str} <= #{max_value}")
  end

  # === STRING VALIDATIONS ===

  @doc """
  Adds minimum string length constraint: char_length(field) >= min

  ## Examples

      CheckConstraint.new(:name_length) |> CheckConstraint.length_min(:name, 3)
      #=> "char_length(name) >= 3"
  """
  @spec length_min(t(), atom() | String.t(), integer()) :: t()
  def length_min(constraint, field, min_length) when is_integer(min_length) and min_length >= 0 do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "char_length(#{field_str}) >= #{min_length}")
  end

  @doc """
  Adds maximum string length constraint: char_length(field) <= max

  ## Examples

      CheckConstraint.new(:title_length) |> CheckConstraint.length_max(:title, 100)
      #=> "char_length(title) <= 100"
  """
  @spec length_max(t(), atom() | String.t(), integer()) :: t()
  def length_max(constraint, field, max_length) when is_integer(max_length) and max_length > 0 do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "char_length(#{field_str}) <= #{max_length}")
  end

  @doc """
  Adds string length range constraint: char_length(field) BETWEEN min AND max

  ## Examples

      CheckConstraint.new(:description_length)
      |> CheckConstraint.length_between(:description, 10, 500)
      #=> "char_length(description) >= 10 AND char_length(description) <= 500"
  """
  @spec length_between(t(), atom() | String.t(), integer(), integer()) :: t()
  def length_between(constraint, field, min_length, max_length)
      when is_integer(min_length) and is_integer(max_length) and min_length >= 0 and
             max_length > min_length do
    field_str = Security.validate_identifier!(field)

    add_condition(
      constraint,
      "char_length(#{field_str}) >= #{min_length} AND char_length(#{field_str}) <= #{max_length}"
    )
  end

  @doc """
  Adds non-empty string constraint: char_length(field) > 0

  ## Examples

      CheckConstraint.new(:name_not_empty) |> CheckConstraint.not_empty(:name)
      #=> "char_length(name) > 0"
  """
  @spec not_empty(t(), atom() | String.t()) :: t()
  def not_empty(constraint, field) do
    length_min(constraint, field, 1)
  end

  @doc """
  Adds regex pattern constraint: field ~ pattern

  ## Examples

      CheckConstraint.new(:email_format)
      |> CheckConstraint.regex(:email, "^[^@]+@[^@]+\\.[^@]+$")
      #=> "email ~ '^[^@]+@[^@]+\\.[^@]+$'"
  """
  @spec regex(t(), atom() | String.t(), String.t()) :: t()
  def regex(constraint, field, pattern) when is_binary(pattern) do
    field_str = Security.validate_identifier!(field)
    # Escape single quotes in pattern
    escaped_pattern = String.replace(pattern, "'", "''")
    add_condition(constraint, "#{field_str} ~ '#{escaped_pattern}'")
  end

  # === ENUM/LIST VALIDATIONS ===

  @doc """
  Adds enum constraint: field IN (values)

  ## Examples

      CheckConstraint.new(:status_valid)
      |> CheckConstraint.enum(:status, ["draft", "published", "archived"])
      #=> "status IN ('draft', 'published', 'archived')"
  """
  @spec enum(t(), atom() | String.t(), [String.t()]) :: t()
  def enum(constraint, field, values) when is_list(values) and length(values) > 0 do
    field_str = Security.validate_identifier!(field)

    values_str =
      values
      |> Enum.map(&escape_string_value/1)
      |> Enum.join(", ")

    add_condition(constraint, "#{field_str} IN (#{values_str})")
  end

  @doc """
  Adds not-in-list constraint: field NOT IN (values)

  ## Examples

      CheckConstraint.new(:status_not_deleted)
      |> CheckConstraint.not_in(:status, ["deleted", "archived"])
      #=> "status NOT IN ('deleted', 'archived')"
  """
  @spec not_in(t(), atom() | String.t(), [String.t()]) :: t()
  def not_in(constraint, field, values) when is_list(values) and length(values) > 0 do
    field_str = Security.validate_identifier!(field)

    values_str =
      values
      |> Enum.map(&escape_string_value/1)
      |> Enum.join(", ")

    add_condition(constraint, "#{field_str} NOT IN (#{values_str})")
  end

  # === JSONB VALIDATIONS ===

  @doc """
  Adds JSONB has key constraint: field ? 'key'

  ## Examples

      CheckConstraint.new(:metadata_has_category)
      |> CheckConstraint.jsonb_has_key(:metadata, "category")
      #=> "metadata ? 'category'"
  """
  @spec jsonb_has_key(t(), atom() | String.t(), String.t()) :: t()
  def jsonb_has_key(constraint, field, key) when is_binary(key) do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "#{field_str} ? '#{escape_string(key)}'")
  end

  @doc """
  Adds JSONB type validation: jsonb_typeof(field) = type

  Valid types: "object", "array", "string", "number", "boolean", "null"

  ## Examples

      CheckConstraint.new(:metadata_is_object)
      |> CheckConstraint.jsonb_type(:metadata, "object")
      #=> "jsonb_typeof(metadata) = 'object'"
  """
  @spec jsonb_type(t(), atom() | String.t(), String.t()) :: t()
  def jsonb_type(constraint, field, type)
      when type in ["object", "array", "string", "number", "boolean", "null"] do
    field_str = Security.validate_identifier!(field)
    add_condition(constraint, "jsonb_typeof(#{field_str}) = '#{type}'")
  end

  @doc """
  Adds JSONB path exists constraint: field->path IS NOT NULL

  ## Examples

      CheckConstraint.new(:metadata_has_user_name)
      |> CheckConstraint.jsonb_path_exists(:metadata, ["user", "name"])
      #=> "metadata->'user'->'name' IS NOT NULL"
  """
  @spec jsonb_path_exists(t(), atom() | String.t(), [String.t()]) :: t()
  def jsonb_path_exists(constraint, field, path) when is_list(path) and length(path) > 0 do
    field_str = Security.validate_identifier!(field)
    path_str = build_jsonb_path(path)
    add_condition(constraint, "#{field_str}#{path_str} IS NOT NULL")
  end

  @doc """
  Adds JSONB array length constraint: jsonb_array_length(field) op length

  ## Examples

      CheckConstraint.new(:tags_not_empty)
      |> CheckConstraint.jsonb_array_length(:tags, 1, :gte)
      #=> "jsonb_array_length(tags) >= 1"
  """
  @spec jsonb_array_length(
          t(),
          atom() | String.t(),
          integer(),
          :eq | :neq | :lt | :lte | :gt | :gte
        ) :: t()
  def jsonb_array_length(constraint, field, length, operator \\ :gte)
      when is_integer(length) and length >= 0 do
    field_str = Security.validate_identifier!(field)

    op_str =
      case operator do
        :eq -> "="
        :neq -> "!="
        :lt -> "<"
        :lte -> "<="
        :gt -> ">"
        :gte -> ">="
      end

    add_condition(constraint, "jsonb_array_length(#{field_str}) #{op_str} #{length}")
  end

  # === COMPOSITE CONDITIONS ===

  @doc """
  Adds a composite AND condition.

  ## Examples

      CheckConstraint.new(:price_and_discount)
      |> CheckConstraint.composite([
          CheckConstraint.new(:price) |> CheckConstraint.positive(:price),
          CheckConstraint.new(:discount) |> CheckConstraint.range(:discount, 0, 100)
        ])
      #=> "(price > 0) AND (discount >= 0 AND discount <= 100)"
  """
  @spec composite(t(), [t()]) :: t()
  def composite(constraint, sub_constraints) when is_list(sub_constraints) do
    conditions =
      sub_constraints
      |> Enum.map(&to_sql/1)
      |> Enum.map(&"(#{&1})")
      |> Enum.join(" AND ")

    add_condition(constraint, conditions)
  end

  @doc """
  Adds a composite OR condition.

  ## Examples

      CheckConstraint.new(:status_or_type)
      |> CheckConstraint.composite_or([
          CheckConstraint.new(:s) |> CheckConstraint.enum(:status, ["active"]),
          CheckConstraint.new(:t) |> CheckConstraint.enum(:type, ["premium"])
        ])
      #=> "(status IN ('active')) OR (type IN ('premium'))"
  """
  @spec composite_or(t(), [t()]) :: t()
  def composite_or(constraint, sub_constraints) when is_list(sub_constraints) do
    conditions =
      sub_constraints
      |> Enum.map(&to_sql/1)
      |> Enum.map(&"(#{&1})")
      |> Enum.join(" OR ")

    add_condition(constraint, conditions)
  end

  @doc """
  Adds a custom SQL condition.

  WARNING: Use with caution! This bypasses some security checks.
  Only use for complex conditions that can't be built with other functions.

  ## Examples

      CheckConstraint.new(:complex)
      |> CheckConstraint.custom("price * quantity > minimum_order_value")
      #=> "price * quantity > minimum_order_value"
  """
  @spec custom(t(), String.t()) :: t()
  def custom(constraint, sql_fragment) when is_binary(sql_fragment) do
    Security.validate_sql_fragment!(sql_fragment)
    add_condition(constraint, sql_fragment)
  end

  # === OUTPUT FUNCTIONS ===

  @doc """
  Converts constraint to SQL CHECK expression.

  Returns SQL string suitable for use in CREATE TABLE or ALTER TABLE.

  ## Examples

      CheckConstraint.new(:price_positive)
      |> CheckConstraint.positive(:price)
      |> CheckConstraint.to_sql()
      #=> "price > 0"
  """
  @spec to_sql(t()) :: String.t()
  def to_sql(%__MODULE__{conditions: []}) do
    "1=1"
  end

  def to_sql(%__MODULE__{conditions: conditions}) do
    Enum.join(conditions, " AND ")
  end

  @doc """
  Returns the constraint name.

  ## Examples

      CheckConstraint.new(:price_positive) |> CheckConstraint.name()
      #=> :price_positive
  """
  @spec name(t()) :: atom() | String.t()
  def name(%__MODULE__{name: name}), do: name

  @doc """
  Checks if constraint is empty (no conditions).

  ## Examples

      CheckConstraint.new(:test) |> CheckConstraint.empty?()
      #=> true

      CheckConstraint.new(:test) |> CheckConstraint.positive(:price) |> CheckConstraint.empty?()
      #=> false
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{conditions: []}), do: true
  def empty?(%__MODULE__{}), do: false

  # === PRIVATE HELPERS ===

  # Add a condition to the constraint
  defp add_condition(constraint, condition) do
    %{constraint | conditions: constraint.conditions ++ [condition]}
  end

  # Escape string value for SQL
  defp escape_string_value(value) when is_binary(value) do
    "'#{escape_string(value)}'"
  end

  defp escape_string_value(value), do: "'#{value}'"

  # Escape single quotes in string
  defp escape_string(str) when is_binary(str) do
    String.replace(str, "'", "''")
  end

  # Build JSONB path accessor
  defp build_jsonb_path([]), do: ""

  defp build_jsonb_path([key | rest]) do
    "->'" <> key <> "'" <> build_jsonb_path(rest)
  end
end
