defmodule Events.Repo.SqlScope.Scope do
  @moduledoc """
  Chainable scope builder for SQL WHERE clauses.

  This module provides a fluent API for building complex WHERE conditions
  that can be used in migrations (partial indexes, constraints) or converted
  to Ecto queries.

  ## Features

  - Type-safe SQL generation with parameterized queries
  - Chainable API for complex conditions
  - Support for JSONB operations
  - Predefined scopes (active, deleted, recent, etc.)
  - Converts to SQL strings or Ecto.Query fragments

  ## Examples

      # Build a simple scope
      Scope.new()
      |> Scope.eq(:status, "published")
      |> Scope.not_null(:deleted_at)
      |> Scope.to_sql()
      #=> {"status = $1 AND deleted_at IS NOT NULL", ["published"]}

      # Use predefined scopes
      Scope.new()
      |> Scope.active()
      |> Scope.recent(days: 7)
      |> Scope.to_sql()
      #=> {"status = $1 AND deleted_at IS NULL AND inserted_at > NOW() - INTERVAL '7 days'", ["active"]}

      # JSONB operations
      Scope.new()
      |> Scope.jsonb_contains(:metadata, %{category: "electronics"})
      |> Scope.to_sql()

      # Complex conditions
      Scope.new()
      |> Scope.or_where([
          Scope.eq(:type, "premium"),
          Scope.and_where([
            Scope.eq(:type, "standard"),
            Scope.gt(:price, 100)
          ])
        ])
      |> Scope.to_sql()
  """

  alias Events.Repo.SqlScope.Security

  defstruct conditions: [], bindings: [], operator: :and

  @type t :: %__MODULE__{
          conditions: [String.t()],
          bindings: [any()],
          operator: :and | :or
        }

  @doc """
  Creates a new empty scope.

  ## Examples

      Scope.new()
      #=> %Scope{conditions: [], bindings: [], operator: :and}

      Scope.new(operator: :or)
      #=> %Scope{conditions: [], bindings: [], operator: :or}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      operator: Keyword.get(opts, :operator, :and)
    }
  end

  # === COMPARISON OPERATORS ===

  @doc """
  Adds equality condition: field = value

  ## Examples

      Scope.new() |> Scope.eq(:status, "active")
      #=> WHERE status = $1
  """
  @spec eq(t(), atom() | String.t(), any()) :: t()
  def eq(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} = $", [value])
  end

  @doc """
  Adds inequality condition: field != value

  ## Examples

      Scope.new() |> Scope.neq(:status, "deleted")
      #=> WHERE status != $1
  """
  @spec neq(t(), atom() | String.t(), any()) :: t()
  def neq(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} != $", [value])
  end

  @doc """
  Adds less than condition: field < value

  ## Examples

      Scope.new() |> Scope.lt(:price, 100)
      #=> WHERE price < $1
  """
  @spec lt(t(), atom() | String.t(), any()) :: t()
  def lt(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} < $", [value])
  end

  @doc """
  Adds less than or equal condition: field <= value
  """
  @spec lte(t(), atom() | String.t(), any()) :: t()
  def lte(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} <= $", [value])
  end

  @doc """
  Adds greater than condition: field > value
  """
  @spec gt(t(), atom() | String.t(), any()) :: t()
  def gt(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} > $", [value])
  end

  @doc """
  Adds greater than or equal condition: field >= value
  """
  @spec gte(t(), atom() | String.t(), any()) :: t()
  def gte(scope, field, value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} >= $", [value])
  end

  # === LIST OPERATIONS ===

  @doc """
  Adds IN condition: field IN (values)

  ## Examples

      Scope.new() |> Scope.in_list(:status, ["active", "pending"])
      #=> WHERE status IN ($1, $2)
  """
  @spec in_list(t(), atom() | String.t(), [any()]) :: t()
  def in_list(scope, field, values) when is_list(values) do
    field_str = Security.validate_identifier!(field)

    placeholders =
      Enum.map_join(1..length(values), ", ", fn i ->
        "$#{length(scope.bindings) + i}"
      end)

    add_condition(scope, "#{field_str} IN (#{placeholders})", values)
  end

  @doc """
  Adds NOT IN condition: field NOT IN (values)
  """
  @spec not_in(t(), atom() | String.t(), [any()]) :: t()
  def not_in(scope, field, values) when is_list(values) do
    field_str = Security.validate_identifier!(field)

    placeholders =
      Enum.map_join(1..length(values), ", ", fn i ->
        "$#{length(scope.bindings) + i}"
      end)

    add_condition(scope, "#{field_str} NOT IN (#{placeholders})", values)
  end

  # === RANGE OPERATIONS ===

  @doc """
  Adds BETWEEN condition: field BETWEEN min AND max

  ## Examples

      Scope.new() |> Scope.between(:price, 10, 100)
      #=> WHERE price BETWEEN $1 AND $2
  """
  @spec between(t(), atom() | String.t(), any(), any()) :: t()
  def between(scope, field, min_value, max_value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} BETWEEN $ AND $", [min_value, max_value])
  end

  @doc """
  Adds NOT BETWEEN condition: field NOT BETWEEN min AND max
  """
  @spec not_between(t(), atom() | String.t(), any(), any()) :: t()
  def not_between(scope, field, min_value, max_value) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} NOT BETWEEN $ AND $", [min_value, max_value])
  end

  # === NULL CHECKS ===

  @doc """
  Adds IS NULL condition: field IS NULL

  ## Examples

      Scope.new() |> Scope.null(:deleted_at)
      #=> WHERE deleted_at IS NULL
  """
  @spec null(t(), atom() | String.t()) :: t()
  def null(scope, field) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} IS NULL", [], raw: true)
  end

  @doc """
  Adds IS NOT NULL condition: field IS NOT NULL

  ## Examples

      Scope.new() |> Scope.not_null(:published_at)
      #=> WHERE published_at IS NOT NULL
  """
  @spec not_null(t(), atom() | String.t()) :: t()
  def not_null(scope, field) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} IS NOT NULL", [], raw: true)
  end

  # === PATTERN MATCHING ===

  @doc """
  Adds LIKE condition: field LIKE pattern

  ## Examples

      Scope.new() |> Scope.like(:name, "%electronics%")
      #=> WHERE name LIKE $1
  """
  @spec like(t(), atom() | String.t(), String.t()) :: t()
  def like(scope, field, pattern) when is_binary(pattern) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} LIKE $", [pattern])
  end

  @doc """
  Adds ILIKE condition (case-insensitive): field ILIKE pattern

  ## Examples

      Scope.new() |> Scope.ilike(:email, "%@example.com")
      #=> WHERE email ILIKE $1
  """
  @spec ilike(t(), atom() | String.t(), String.t()) :: t()
  def ilike(scope, field, pattern) when is_binary(pattern) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} ILIKE $", [pattern])
  end

  @doc """
  Adds NOT LIKE condition: field NOT LIKE pattern
  """
  @spec not_like(t(), atom() | String.t(), String.t()) :: t()
  def not_like(scope, field, pattern) when is_binary(pattern) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} NOT LIKE $", [pattern])
  end

  # === JSONB OPERATIONS ===

  @doc """
  Adds JSONB equality condition: field->path = value

  ## Examples

      Scope.new() |> Scope.jsonb_eq(:metadata, ["category"], "electronics")
      #=> WHERE metadata->'category' = $1

      Scope.new() |> Scope.jsonb_eq(:metadata, ["user", "name"], "John")
      #=> WHERE metadata->'user'->'name' = $1
  """
  @spec jsonb_eq(t(), atom() | String.t(), [String.t()], any()) :: t()
  def jsonb_eq(scope, field, path, value) when is_list(path) do
    field_str = Security.validate_identifier!(field)
    path_str = build_jsonb_path(path)
    add_condition(scope, "#{field_str}#{path_str} = $", [value])
  end

  @doc """
  Adds JSONB contains condition: field @> value

  ## Examples

      Scope.new() |> Scope.jsonb_contains(:metadata, %{status: "active"})
      #=> WHERE metadata @> $1::jsonb
  """
  @spec jsonb_contains(t(), atom() | String.t(), map()) :: t()
  def jsonb_contains(scope, field, value) when is_map(value) do
    field_str = Security.validate_identifier!(field)
    json_value = Jason.encode!(value)
    add_condition(scope, "#{field_str} @> $::jsonb", [json_value])
  end

  @doc """
  Adds JSONB contained by condition: field <@ value
  """
  @spec jsonb_contained(t(), atom() | String.t(), map()) :: t()
  def jsonb_contained(scope, field, value) when is_map(value) do
    field_str = Security.validate_identifier!(field)
    json_value = Jason.encode!(value)
    add_condition(scope, "#{field_str} <@ $::jsonb", [json_value])
  end

  @doc """
  Adds JSONB has key condition: field ? key

  ## Examples

      Scope.new() |> Scope.jsonb_has_key(:metadata, "category")
      #=> WHERE metadata ? $1
  """
  @spec jsonb_has_key(t(), atom() | String.t(), String.t()) :: t()
  def jsonb_has_key(scope, field, key) when is_binary(key) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} ? $", [key])
  end

  @doc """
  Adds JSONB has any key condition: field ?| ARRAY[keys]
  """
  @spec jsonb_has_any_key(t(), atom() | String.t(), [String.t()]) :: t()
  def jsonb_has_any_key(scope, field, keys) when is_list(keys) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} ?| $::text[]", [keys])
  end

  @doc """
  Adds JSONB has all keys condition: field ?& ARRAY[keys]
  """
  @spec jsonb_has_all_keys(t(), atom() | String.t(), [String.t()]) :: t()
  def jsonb_has_all_keys(scope, field, keys) when is_list(keys) do
    field_str = Security.validate_identifier!(field)
    add_condition(scope, "#{field_str} ?& $::text[]", [keys])
  end

  @doc """
  Adds JSONB array length condition: jsonb_array_length(field) op length

  ## Examples

      Scope.new() |> Scope.jsonb_array_length(:tags, 5, :gt)
      #=> WHERE jsonb_array_length(tags) > $1

      Scope.new() |> Scope.jsonb_array_length(:items, 0, :eq)
      #=> WHERE jsonb_array_length(items) = $1
  """
  @spec jsonb_array_length(t(), atom() | String.t(), integer(), :eq | :neq | :lt | :lte | :gt | :gte) :: t()
  def jsonb_array_length(scope, field, length, operator \\ :eq) when is_integer(length) do
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

    add_condition(scope, "jsonb_array_length(#{field_str}) #{op_str} $", [length])
  end

  # === PREDEFINED SCOPES ===

  @doc """
  Adds active scope: status = 'active' AND deleted_at IS NULL

  ## Examples

      Scope.new() |> Scope.active()
      #=> WHERE status = $1 AND deleted_at IS NULL
  """
  @spec active(t()) :: t()
  def active(scope) do
    scope
    |> eq(:status, "active")
    |> null(:deleted_at)
  end

  @doc """
  Adds deleted scope: deleted_at IS NOT NULL

  ## Examples

      Scope.new() |> Scope.deleted()
      #=> WHERE deleted_at IS NOT NULL
  """
  @spec deleted(t()) :: t()
  def deleted(scope) do
    not_null(scope, :deleted_at)
  end

  @doc """
  Adds not deleted scope: deleted_at IS NULL

  ## Examples

      Scope.new() |> Scope.not_deleted()
      #=> WHERE deleted_at IS NULL
  """
  @spec not_deleted(t()) :: t()
  def not_deleted(scope) do
    null(scope, :deleted_at)
  end

  @doc """
  Adds recent scope: inserted_at > NOW() - INTERVAL 'X days'

  ## Examples

      Scope.new() |> Scope.recent(days: 7)
      #=> WHERE inserted_at > NOW() - INTERVAL '7 days'

      Scope.new() |> Scope.recent(hours: 24)
      #=> WHERE inserted_at > NOW() - INTERVAL '24 hours'
  """
  @spec recent(t(), keyword()) :: t()
  def recent(scope, opts) do
    {value, unit} =
      cond do
        Keyword.has_key?(opts, :days) -> {Keyword.get(opts, :days), "days"}
        Keyword.has_key?(opts, :hours) -> {Keyword.get(opts, :hours), "hours"}
        Keyword.has_key?(opts, :minutes) -> {Keyword.get(opts, :minutes), "minutes"}
        true -> {7, "days"}
      end

    # Validate that value is an integer to prevent SQL injection
    unless is_integer(value) do
      raise ArgumentError, """
      Invalid interval value: #{inspect(value)}

      Expected an integer for interval value.

      Examples:
        Scope.recent(days: 7)
        Scope.recent(hours: 24)
        Scope.recent(minutes: 30)
      """
    end

    add_condition(scope, "inserted_at > NOW() - INTERVAL '#{value} #{unit}'", [], raw: true)
  end

  @doc """
  Adds status scope: status = value

  ## Examples

      Scope.new() |> Scope.status("published")
      #=> WHERE status = $1
  """
  @spec status(t(), String.t()) :: t()
  def status(scope, value) do
    eq(scope, :status, value)
  end

  @doc """
  Adds type scope: type = value

  ## Examples

      Scope.new() |> Scope.type("premium")
      #=> WHERE type = $1
  """
  @spec type(t(), String.t()) :: t()
  def type(scope, value) do
    eq(scope, :type, value)
  end

  # === LOGICAL COMBINATORS ===

  @doc """
  Combines multiple scopes with AND.

  ## Examples

      Scope.new() |> Scope.and_where([
        Scope.eq(:status, "active"),
        Scope.gt(:price, 100)
      ])
      #=> WHERE (status = $1 AND price > $2)
  """
  @spec and_where(t(), [t()]) :: t()
  def and_where(scope, scopes) when is_list(scopes) do
    combined = combine_scopes(scopes, :and)

    %{scope | conditions: scope.conditions ++ combined.conditions, bindings: scope.bindings ++ combined.bindings}
  end

  @doc """
  Combines multiple scopes with OR.

  ## Examples

      Scope.new() |> Scope.or_where([
        Scope.eq(:type, "premium"),
        Scope.eq(:type, "standard")
      ])
      #=> WHERE (type = $1 OR type = $2)
  """
  @spec or_where(t(), [t()]) :: t()
  def or_where(scope, scopes) when is_list(scopes) do
    combined = combine_scopes(scopes, :or)

    %{scope | conditions: scope.conditions ++ combined.conditions, bindings: scope.bindings ++ combined.bindings}
  end

  @doc """
  Negates a scope with NOT.

  ## Examples

      Scope.new() |> Scope.not_where(Scope.eq(:status, "deleted"))
      #=> WHERE NOT (status = $1)
  """
  @spec not_where(t(), t()) :: t()
  def not_where(scope, inner_scope) do
    {sql, bindings} = to_sql(inner_scope)

    add_condition(scope, "NOT (#{sql})", bindings, raw: true)
  end

  @doc """
  Adds a custom SQL condition.

  WARNING: Use with caution! This bypasses security checks.
  Only use for complex conditions that can't be built with other functions.

  ## Examples

      Scope.new() |> Scope.custom("EXTRACT(YEAR FROM created_at) = 2024")
      #=> WHERE EXTRACT(YEAR FROM created_at) = 2024
  """
  @spec custom(t(), String.t()) :: t()
  def custom(scope, sql_fragment) when is_binary(sql_fragment) do
    Security.validate_sql_fragment!(sql_fragment)
    add_condition(scope, sql_fragment, [], raw: true)
  end

  # === OUTPUT FUNCTIONS ===

  @doc """
  Converts scope to SQL WHERE clause with bindings.

  Returns `{sql_string, bindings}` tuple.

  ## Examples

      Scope.new()
      |> Scope.eq(:status, "active")
      |> Scope.not_null(:deleted_at)
      |> Scope.to_sql()
      #=> {"status = $1 AND deleted_at IS NOT NULL", ["active"]}
  """
  @spec to_sql(t()) :: {String.t(), [any()]}
  def to_sql(%__MODULE__{conditions: [], bindings: []}) do
    {"1=1", []}
  end

  def to_sql(%__MODULE__{conditions: conditions, bindings: bindings, operator: operator}) do
    # Replace placeholders with actual parameter numbers
    {sql_conditions, _} =
      Enum.map_reduce(conditions, 1, fn condition, param_num ->
        # Count number of parameters in this condition
        param_count = String.split(condition, "$", trim: false) |> length() |> Kernel.-(1)

        # Replace $ placeholders with $1, $2, etc.
        replaced =
          Enum.reduce(1..param_count, condition, fn i, acc ->
            String.replace(acc, "$", "$#{param_num + i - 1}", global: false)
          end)

        {replaced, param_num + param_count}
      end)

    operator_str = if operator == :and, do: " AND ", else: " OR "
    sql = Enum.join(sql_conditions, operator_str)

    {sql, bindings}
  end

  @doc """
  Converts scope to raw SQL string with interpolated values.

  WARNING: Only use for display/debugging. Never use in actual queries!

  ## Examples

      Scope.new()
      |> Scope.eq(:status, "active")
      |> Scope.to_raw_sql()
      #=> "status = 'active'"
  """
  @spec to_raw_sql(t()) :: String.t()
  def to_raw_sql(scope) do
    {sql, bindings} = to_sql(scope)

    Enum.reduce(Enum.with_index(bindings, 1), sql, fn {value, i}, acc ->
      placeholder = "$#{i}"
      replacement = inspect_value(value)
      String.replace(acc, placeholder, replacement)
    end)
  end

  @doc """
  Checks if scope is empty (no conditions).

  ## Examples

      Scope.new() |> Scope.empty?()
      #=> true

      Scope.new() |> Scope.eq(:status, "active") |> Scope.empty?()
      #=> false
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{conditions: []}), do: true
  def empty?(%__MODULE__{}), do: false

  # === PRIVATE HELPERS ===

  # Add a condition to the scope
  defp add_condition(scope, sql, bindings, opts \\ []) do
    raw = Keyword.get(opts, :raw, false)

    %{
      scope
      | conditions: scope.conditions ++ [sql],
        bindings: if(raw, do: scope.bindings, else: scope.bindings ++ bindings)
    }
  end

  # Build JSONB path accessor
  defp build_jsonb_path([]), do: ""

  defp build_jsonb_path([key | rest]) do
    "->'" <> key <> "'" <> build_jsonb_path(rest)
  end

  # Combine multiple scopes with operator
  defp combine_scopes(scopes, operator) do
    Enum.reduce(scopes, new(operator: operator), fn scope, acc ->
      {sql, bindings} = to_sql(scope)

      %{
        acc
        | conditions: acc.conditions ++ ["(#{sql})"],
          bindings: acc.bindings ++ bindings
      }
    end)
  end

  # Inspect value for raw SQL
  defp inspect_value(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
  defp inspect_value(value) when is_integer(value), do: Integer.to_string(value)
  defp inspect_value(value) when is_float(value), do: Float.to_string(value)
  defp inspect_value(value) when is_boolean(value), do: if(value, do: "TRUE", else: "FALSE")
  defp inspect_value(nil), do: "NULL"
  defp inspect_value(value), do: inspect(value)
end
