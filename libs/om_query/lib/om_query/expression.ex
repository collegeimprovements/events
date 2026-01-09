defmodule OmQuery.Expression do
  @moduledoc """
  Expression builders for use in select, filter, and update operations.

  Provides type-safe helpers for building SQL expressions without raw SQL fragments.
  All functions return Ecto dynamic expressions that can be used throughout OmQuery.

  ## Usage in Select

      User
      |> OmQuery.select(%{
        display_name: OmQuery.Expression.coalesce(:nickname, :name),
        status: OmQuery.Expression.case_when([
          {{:verified, :eq, true}, "Verified"},
          {{:active, :eq, true}, "Active"}
        ], else: "Pending")
      })

  ## Usage in Filter

      User
      |> OmQuery.filter_dynamic(OmQuery.Expression.coalesce(:nickname, :name), :ilike, "%john%")

  ## Usage in Update (via raw)

      User
      |> OmQuery.update_all(set: [
        name: OmQuery.Expression.coalesce(:nickname, :name)
      ])
  """

  import Ecto.Query

  @doc """
  Returns the first non-NULL value from the arguments.

  SQL: `COALESCE(a, b, ...)`

  ## Examples

      # Use nickname if present, fallback to name
      OmQuery.Expression.coalesce(:nickname, :name)

      # Multiple fallbacks
      OmQuery.Expression.coalesce([:display_name, :nickname, :name])

      # With literal default
      OmQuery.Expression.coalesce(:name, "Anonymous")
  """
  @spec coalesce(atom(), atom() | String.t() | number()) :: Ecto.Query.DynamicExpr.t()
  def coalesce(field1, field2) when is_atom(field1) and is_atom(field2) do
    dynamic([q], coalesce(field(q, ^field1), field(q, ^field2)))
  end

  def coalesce(field, default) when is_atom(field) and (is_binary(default) or is_number(default)) do
    dynamic([q], coalesce(field(q, ^field), ^default))
  end

  @spec coalesce([atom() | String.t() | number()]) :: Ecto.Query.DynamicExpr.t()
  def coalesce([first | rest]) when is_list(rest) do
    Enum.reduce(rest, field_or_literal(first), fn item, acc ->
      if is_atom(item) do
        dynamic([q], coalesce(^acc, field(q, ^item)))
      else
        dynamic([q], coalesce(^acc, ^item))
      end
    end)
  end

  defp field_or_literal(item) when is_atom(item), do: dynamic([q], field(q, ^item))
  defp field_or_literal(item), do: dynamic([q], ^item)

  @doc """
  Returns NULL if the two arguments are equal, otherwise returns the first argument.

  SQL: `NULLIF(a, b)`

  ## Examples

      # Return NULL if division would be zero (prevents division by zero)
      OmQuery.Expression.nullif(:divisor, 0)

      # Nullify empty strings
      OmQuery.Expression.nullif(:name, "")

      # Compare two fields
      OmQuery.Expression.nullif(:current_value, :previous_value)
  """
  @spec nullif(atom(), atom() | term()) :: Ecto.Query.DynamicExpr.t()
  def nullif(field1, field2) when is_atom(field1) and is_atom(field2) do
    dynamic([q], fragment("NULLIF(?, ?)", field(q, ^field1), field(q, ^field2)))
  end

  def nullif(field, value) when is_atom(field) do
    dynamic([q], fragment("NULLIF(?, ?)", field(q, ^field), ^value))
  end

  @doc """
  Build a CASE WHEN expression for conditional logic.

  Due to Ecto's SQL injection protection, case_when uses pre-defined patterns
  for common use cases. For complex CASE expressions, use `fragment/1` directly.

  ## Supported Patterns

  ### Single condition CASE
      case_when({field, :op, value}, then_value, else_value)

  ### Two condition CASE
      case_when([{cond1, result1}, {cond2, result2}], else: default)

  ## Examples

      # Single condition
      OmQuery.Expression.case_when({:active, :eq, true}, "Active", "Inactive")

      # Two conditions (max supported for dynamic building)
      OmQuery.Expression.case_when([
        {{:status, :eq, "active"}, "Active User"},
        {{:status, :eq, "pending"}, "Pending"}
      ], else: "Unknown")

      # For more complex CASE expressions, use fragment directly:
      dynamic([q], fragment(
        "CASE WHEN ? THEN ? WHEN ? THEN ? ELSE ? END",
        q.status == "a", "Active",
        q.status == "b", "Beta",
        "Other"
      ))
  """
  @spec case_when(tuple(), term(), term()) :: Ecto.Query.DynamicExpr.t()
  def case_when({field, :eq, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? = ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :neq, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? != ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :gt, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? > ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :gte, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? >= ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :lt, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? < ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :lte, value}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? <= ? THEN ? ELSE ? END",
        field(q, ^field),
        ^value,
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :is_nil, true}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? IS NULL THEN ? ELSE ? END",
        field(q, ^field),
        ^then_value,
        ^else_value
      )
    )
  end

  def case_when({field, :is_nil, false}, then_value, else_value) when is_atom(field) do
    dynamic(
      [q],
      fragment(
        "CASE WHEN ? IS NOT NULL THEN ? ELSE ? END",
        field(q, ^field),
        ^then_value,
        ^else_value
      )
    )
  end

  @spec case_when([{tuple(), term()}], keyword()) :: Ecto.Query.DynamicExpr.t()
  def case_when([{{field1, :eq, val1}, result1}, {{field2, :eq, val2}, result2}], opts)
      when is_atom(field1) and is_atom(field2) do
    else_value = Keyword.get(opts, :else, nil)

    dynamic(
      [q],
      fragment(
        "CASE WHEN ? = ? THEN ? WHEN ? = ? THEN ? ELSE ? END",
        field(q, ^field1),
        ^val1,
        ^result1,
        field(q, ^field2),
        ^val2,
        ^result2,
        ^else_value
      )
    )
  end

  def case_when([{condition, result}], opts) do
    else_value = Keyword.get(opts, :else, nil)
    case_when(condition, result, else_value)
  end

  @doc """
  Build an IF expression (shorthand for 2-branch CASE).

  SQL: `CASE WHEN condition THEN then_value ELSE else_value END`

  ## Examples

      # Conditional pricing
      OmQuery.Expression.if_expr({:premium, :eq, true}, :premium_price, :base_price)

      # With literals
      OmQuery.Expression.if_expr({:active, :eq, true}, "Active", "Inactive")
  """
  @spec if_expr(tuple(), term(), term()) :: Ecto.Query.DynamicExpr.t()
  def if_expr(condition, then_value, else_value) do
    case_when([{condition, then_value}], else: else_value)
  end

  @doc """
  Create a greatest expression (returns the maximum value).

  SQL: `GREATEST(a, b, ...)`

  ## Examples

      OmQuery.Expression.greatest(:price, :min_price)
      OmQuery.Expression.greatest([:a, :b, :c])
  """
  @spec greatest(atom(), atom()) :: Ecto.Query.DynamicExpr.t()
  def greatest(field1, field2) when is_atom(field1) and is_atom(field2) do
    dynamic([q], fragment("GREATEST(?, ?)", field(q, ^field1), field(q, ^field2)))
  end

  @spec greatest([atom()]) :: Ecto.Query.DynamicExpr.t()
  def greatest([f1, f2]) when is_atom(f1) and is_atom(f2), do: greatest(f1, f2)

  def greatest([f1, f2, f3]) when is_atom(f1) and is_atom(f2) and is_atom(f3) do
    dynamic([q], fragment("GREATEST(?, ?, ?)", field(q, ^f1), field(q, ^f2), field(q, ^f3)))
  end

  @doc """
  Create a least expression (returns the minimum value).

  SQL: `LEAST(a, b, ...)`

  ## Examples

      OmQuery.Expression.least(:price, :max_price)
      OmQuery.Expression.least([:a, :b, :c])
  """
  @spec least(atom(), atom()) :: Ecto.Query.DynamicExpr.t()
  def least(field1, field2) when is_atom(field1) and is_atom(field2) do
    dynamic([q], fragment("LEAST(?, ?)", field(q, ^field1), field(q, ^field2)))
  end

  @spec least([atom()]) :: Ecto.Query.DynamicExpr.t()
  def least([f1, f2]) when is_atom(f1) and is_atom(f2), do: least(f1, f2)

  def least([f1, f2, f3]) when is_atom(f1) and is_atom(f2) and is_atom(f3) do
    dynamic([q], fragment("LEAST(?, ?, ?)", field(q, ^f1), field(q, ^f2), field(q, ^f3)))
  end

  @doc """
  Concatenate strings or fields.

  SQL: `a || b || ...` (PostgreSQL) or `CONCAT(a, b, ...)` (MySQL)

  ## Examples

      OmQuery.Expression.concat(:first_name, " ", :last_name)
      OmQuery.Expression.concat([:city, ", ", :state, " ", :zip])
  """
  @spec concat([atom() | String.t()]) :: Ecto.Query.DynamicExpr.t()
  def concat([first | rest]) do
    Enum.reduce(rest, expr_or_literal(first), fn item, acc ->
      item_expr = expr_or_literal(item)
      dynamic([q], fragment("? || ?", ^acc, ^item_expr))
    end)
  end

  @spec concat(atom() | String.t(), atom() | String.t(), atom() | String.t()) ::
          Ecto.Query.DynamicExpr.t()
  def concat(a, b, c), do: concat([a, b, c])

  defp expr_or_literal(item) when is_atom(item), do: dynamic([q], field(q, ^item))
  defp expr_or_literal(item) when is_binary(item), do: dynamic([q], ^item)

  @doc """
  Extract a date/time part from a timestamp field.

  SQL: `EXTRACT(part FROM field)`

  ## Supported Parts

  - `:year`, `:month`, `:day`
  - `:hour`, `:minute`, `:second`
  - `:dow` (day of week), `:doy` (day of year)
  - `:week`, `:quarter`
  - `:epoch` (Unix timestamp)

  ## Examples

      OmQuery.Expression.extract(:year, :created_at)
      OmQuery.Expression.extract(:month, :birth_date)
  """
  @spec extract(atom(), atom()) :: Ecto.Query.DynamicExpr.t()
  def extract(part, field) when is_atom(part) and is_atom(field) do
    part_string = Atom.to_string(part) |> String.upcase()

    dynamic(
      [q],
      fragment(
        "EXTRACT(? FROM ?)",
        literal(^part_string),
        field(q, ^field)
      )
    )
  end

  @doc """
  Truncate a timestamp to a specific precision.

  SQL: `DATE_TRUNC(precision, field)`

  ## Supported Precisions

  - `:year`, `:quarter`, `:month`, `:week`, `:day`
  - `:hour`, `:minute`, `:second`

  ## Examples

      OmQuery.Expression.date_trunc(:month, :created_at)
      OmQuery.Expression.date_trunc(:day, :event_time)
  """
  @spec date_trunc(atom(), atom()) :: Ecto.Query.DynamicExpr.t()
  def date_trunc(precision, field) when is_atom(precision) and is_atom(field) do
    precision_string = Atom.to_string(precision)
    dynamic([q], fragment("DATE_TRUNC(?, ?)", ^precision_string, field(q, ^field)))
  end

  @doc """
  Calculate age between two dates or from a date to now.

  SQL: `AGE(date)` or `AGE(date1, date2)`

  ## Examples

      OmQuery.Expression.age(:birth_date)
      OmQuery.Expression.age(:end_date, :start_date)
  """
  @spec age(atom()) :: Ecto.Query.DynamicExpr.t()
  def age(field) when is_atom(field) do
    dynamic([q], fragment("AGE(?)", field(q, ^field)))
  end

  @spec age(atom(), atom()) :: Ecto.Query.DynamicExpr.t()
  def age(field1, field2) when is_atom(field1) and is_atom(field2) do
    dynamic([q], fragment("AGE(?, ?)", field(q, ^field1), field(q, ^field2)))
  end
end
