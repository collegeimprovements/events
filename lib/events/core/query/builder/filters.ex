defmodule Events.Core.Query.Builder.Filters do
  @moduledoc false
  # Internal module for Builder - handles all filter operations
  #
  # This module provides the single source of truth for all filter operators.
  # Used by both direct filters and filter groups (OR/AND/NOT).

  import Ecto.Query
  alias Events.Core.Query.Token

  # Unified filter operator definitions
  @filter_operators ~w(eq neq gt gte lt lte in not_in like ilike not_like not_ilike is_nil not_nil between contains jsonb_contains jsonb_has_key similarity word_similarity strict_word_similarity)a

  ## Public API (for Builder)

  @doc """
  Apply a single filter to a query.

  Handles both regular operators and special subquery operators.
  """
  @spec apply_filter(Ecto.Query.t(), {atom(), atom(), term(), keyword()}) :: Ecto.Query.t()
  def apply_filter(query, filter_spec)

  # Special handling for subquery operators (can't be built with pure dynamic)
  # These MUST come before the generic handler due to pattern matching precedence
  def apply_filter(query, {field, :in_subquery, subquery, opts}) do
    binding = opts[:binding] || :root
    sq = resolve_subquery(subquery)
    from([{^binding, q}] in query, where: field(q, ^field) in subquery(sq))
  end

  def apply_filter(query, {field, :not_in_subquery, subquery, opts}) do
    binding = opts[:binding] || :root
    sq = resolve_subquery(subquery)
    from([{^binding, q}] in query, where: field(q, ^field) not in subquery(sq))
  end

  # Generic filter handler - delegates to filter_dynamic/4
  def apply_filter(query, {field, op, value, opts}) do
    dynamic_expr = filter_dynamic(field, op, value, opts)
    from(q in query, where: ^dynamic_expr)
  end

  @doc """
  Apply a filter group (OR/AND/NOT_OR) to a query.
  """
  @spec apply_filter_group(Ecto.Query.t(), {:or | :and | :not_or, list()}) :: Ecto.Query.t()
  def apply_filter_group(query, group_spec)

  def apply_filter_group(query, {:or, filters}) do
    conditions =
      filters
      |> Enum.map(&spec_to_dynamic/1)
      |> combine_with_or()

    from(q in query, where: ^conditions)
  end

  def apply_filter_group(query, {:and, filters}) do
    conditions =
      filters
      |> Enum.map(&spec_to_dynamic/1)
      |> combine_with_and()

    case conditions do
      nil -> query
      cond -> from(q in query, where: ^cond)
    end
  end

  def apply_filter_group(query, {:not_or, filters}) do
    # NOT (a OR b OR c) - matches if none of the conditions are true
    conditions =
      filters
      |> Enum.map(&spec_to_dynamic/1)
      |> combine_with_or()

    negated = dynamic(not (^conditions))
    from(q in query, where: ^negated)
  end

  @doc """
  Apply field-to-field comparison.
  """
  @spec apply_field_compare(Ecto.Query.t(), {atom(), atom(), atom(), keyword()}) :: Ecto.Query.t()
  def apply_field_compare(query, {field1, op, field2, opts}) do
    binding = opts[:binding] || :root
    condition = field_compare_dynamic(field1, op, field2, binding)
    from(q in query, where: ^condition)
  end

  @doc """
  Apply EXISTS or NOT EXISTS subquery.
  """
  @spec apply_exists(Ecto.Query.t(), Token.t() | Ecto.Query.t(), boolean()) :: Ecto.Query.t()
  def apply_exists(query, subquery_token_or_query, exists?)

  def apply_exists(query, %Token{} = subquery_token, exists?) do
    # Need to call Builder.build/1 - delegate to parent module via runtime
    sq = apply(Events.Core.Query.Builder, :build, [subquery_token])
    apply_exists_query(query, sq, exists?)
  end

  def apply_exists(query, %Ecto.Query{} = sq, exists?) do
    apply_exists_query(query, sq, exists?)
  end

  @doc """
  Build a dynamic filter expression for the given operator.

  This is the single source of truth for all filter operators.
  Used by both direct filters and filter groups (OR/AND).

  ## Supported Operators

  | Operator | Description | Example |
  |----------|-------------|---------|
  | `:eq` | Equal | `filter(:status, :eq, "active")` |
  | `:neq` | Not equal | `filter(:status, :neq, "deleted")` |
  | `:gt` | Greater than | `filter(:age, :gt, 18)` |
  | `:gte` | Greater than or equal | `filter(:age, :gte, 18)` |
  | `:lt` | Less than | `filter(:age, :lt, 65)` |
  | `:lte` | Less than or equal | `filter(:age, :lte, 65)` |
  | `:in` | In list | `filter(:status, :in, ["active", "pending"])` |
  | `:not_in` | Not in list | `filter(:status, :not_in, ["deleted"])` |
  | `:like` | SQL LIKE | `filter(:name, :like, "%john%")` |
  | `:ilike` | Case-insensitive LIKE | `filter(:name, :ilike, "%john%")` |
  | `:is_nil` | Is NULL | `filter(:deleted_at, :is_nil, true)` |
  | `:not_nil` | Is NOT NULL | `filter(:email, :not_nil, true)` |
  | `:between` | Between range | `filter(:age, :between, {18, 65})` |
  | `:contains` | Array contains | `filter(:tags, :contains, ["elixir"])` |
  | `:jsonb_contains` | JSONB @> | `filter(:meta, :jsonb_contains, %{vip: true})` |
  | `:jsonb_has_key` | JSONB ? | `filter(:meta, :jsonb_has_key, "role")` |

  ## Options

  - `:binding` - Named binding for joined tables (default: `:root`)
  - `:case_insensitive` - Case insensitive comparison for `:eq` (default: `false`)
  - `:threshold` - Similarity threshold for pg_trgm operators (default: `0.3`)
  """
  @spec filter_dynamic(atom(), atom(), term(), keyword()) :: Ecto.Query.DynamicExpr.t()
  def filter_dynamic(field, op, value, opts \\ [])

  # Equality - with case insensitive support
  def filter_dynamic(field, :eq, value, opts) do
    binding = opts[:binding] || :root
    build_eq_dynamic(field, value, binding, opts[:case_insensitive] || false)
  end

  # Not equal
  def filter_dynamic(field, :neq, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) != ^value)
  end

  # Comparison operators
  def filter_dynamic(field, :gt, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) > ^value)
  end

  def filter_dynamic(field, :gte, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) >= ^value)
  end

  def filter_dynamic(field, :lt, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) < ^value)
  end

  def filter_dynamic(field, :lte, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) <= ^value)
  end

  # List membership - with case insensitive support
  def filter_dynamic(field, :in, values, opts) when is_list(values) do
    binding = opts[:binding] || :root
    build_in_dynamic(field, values, binding, opts[:case_insensitive] || false)
  end

  def filter_dynamic(field, :not_in, values, opts) when is_list(values) do
    binding = opts[:binding] || :root
    build_not_in_dynamic(field, values, binding, opts[:case_insensitive] || false)
  end

  # Pattern matching
  def filter_dynamic(field, :like, pattern, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], like(field(q, ^field), ^pattern))
  end

  def filter_dynamic(field, :ilike, pattern, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], ilike(field(q, ^field), ^pattern))
  end

  def filter_dynamic(field, :not_like, pattern, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], not like(field(q, ^field), ^pattern))
  end

  def filter_dynamic(field, :not_ilike, pattern, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], not ilike(field(q, ^field), ^pattern))
  end

  # PostgreSQL pg_trgm similarity operators (requires pg_trgm extension)
  # similarity(a, b) returns a number between 0 and 1 indicating how similar they are
  # Default threshold is 0.3, configurable via :threshold option
  def filter_dynamic(field, :similarity, term, opts) do
    binding = opts[:binding] || :root
    threshold = opts[:threshold] || 0.3

    dynamic(
      [{^binding, q}],
      fragment("similarity(?, ?) > ?", field(q, ^field), ^term, ^threshold)
    )
  end

  # word_similarity - better for matching whole words within text
  def filter_dynamic(field, :word_similarity, term, opts) do
    binding = opts[:binding] || :root
    threshold = opts[:threshold] || 0.3

    dynamic(
      [{^binding, q}],
      fragment("word_similarity(?, ?) > ?", ^term, field(q, ^field), ^threshold)
    )
  end

  # strict_word_similarity - strictest matching for whole word boundaries
  def filter_dynamic(field, :strict_word_similarity, term, opts) do
    binding = opts[:binding] || :root
    threshold = opts[:threshold] || 0.3

    dynamic(
      [{^binding, q}],
      fragment("strict_word_similarity(?, ?) > ?", ^term, field(q, ^field), ^threshold)
    )
  end

  # Null checks
  def filter_dynamic(field, :is_nil, _value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], is_nil(field(q, ^field)))
  end

  def filter_dynamic(field, :not_nil, _value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], not is_nil(field(q, ^field)))
  end

  # Range - single tuple
  def filter_dynamic(field, :between, {min, max}, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], field(q, ^field) >= ^min and field(q, ^field) <= ^max)
  end

  # Range - list of ranges (OR of multiple BETWEEN conditions)
  def filter_dynamic(field, :between, ranges, opts) when is_list(ranges) do
    binding = opts[:binding] || :root

    ranges
    |> Enum.reduce(nil, fn {min, max}, acc ->
      range_condition =
        dynamic([{^binding, q}], field(q, ^field) >= ^min and field(q, ^field) <= ^max)

      if acc do
        dynamic(^acc or ^range_condition)
      else
        range_condition
      end
    end)
  end

  # Array/JSONB operators
  def filter_dynamic(field, :contains, value, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], fragment("? @> ?", field(q, ^field), ^value))
  end

  def filter_dynamic(field, :jsonb_contains, value, opts) do
    binding = opts[:binding] || :root
    json_value = Jason.encode!(value)
    dynamic([{^binding, q}], fragment("? @> ?::jsonb", field(q, ^field), ^json_value))
  end

  def filter_dynamic(field, :jsonb_has_key, key, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], fragment("? \\? ?", field(q, ^field), ^key))
  end

  # Fallback for unsupported operators
  def filter_dynamic(_field, op, _value, _opts) do
    supported = Enum.map_join(@filter_operators, ", ", &":#{&1}")

    raise ArgumentError, """
    Unknown filter operator: #{inspect(op)}

    Supported operators: #{supported}

    For subqueries, use :in_subquery or :not_in_subquery
    """
  end

  ## Private Helpers

  # Convert filter spec to dynamic expression using unified filter_dynamic/4
  defp spec_to_dynamic({field, op, value, opts}), do: filter_dynamic(field, op, value, opts)
  defp spec_to_dynamic({field, op, value}), do: filter_dynamic(field, op, value, [])

  # Build equality dynamic with optional case insensitivity
  defp build_eq_dynamic(field, value, binding, true) when is_binary(value) do
    dynamic([{^binding, q}], fragment("lower(?)", field(q, ^field)) == fragment("lower(?)", ^value))
  end

  defp build_eq_dynamic(field, value, binding, _case_insensitive) do
    dynamic([{^binding, q}], field(q, ^field) == ^value)
  end

  # Build IN dynamic with optional case insensitivity
  defp build_in_dynamic(field, values, binding, true) do
    # Case insensitive: lowercase field and all string values
    lower_values =
      Enum.map(values, fn
        v when is_binary(v) -> String.downcase(v)
        v -> v
      end)

    dynamic([{^binding, q}], fragment("lower(?)", field(q, ^field)) in ^lower_values)
  end

  defp build_in_dynamic(field, values, binding, _case_insensitive) do
    dynamic([{^binding, q}], field(q, ^field) in ^values)
  end

  # Build NOT IN dynamic with optional case insensitivity
  defp build_not_in_dynamic(field, values, binding, true) do
    lower_values =
      Enum.map(values, fn
        v when is_binary(v) -> String.downcase(v)
        v -> v
      end)

    dynamic([{^binding, q}], fragment("lower(?)", field(q, ^field)) not in ^lower_values)
  end

  defp build_not_in_dynamic(field, values, binding, _case_insensitive) do
    dynamic([{^binding, q}], field(q, ^field) not in ^values)
  end

  # Combine dynamic expressions with OR
  defp combine_with_or([]), do: dynamic([], false)
  defp combine_with_or([single]), do: single

  defp combine_with_or([first | rest]) do
    Enum.reduce(rest, first, fn cond, acc ->
      dynamic([], ^acc or ^cond)
    end)
  end

  # Combine dynamic expressions with AND
  defp combine_with_and([]), do: nil
  defp combine_with_and([single]), do: single

  defp combine_with_and([first | rest]) do
    Enum.reduce(rest, first, fn cond, acc ->
      dynamic([], ^acc and ^cond)
    end)
  end

  # Field-to-field comparison dynamics
  defp field_compare_dynamic(field1, :eq, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) == field(q, ^field2))
  end

  defp field_compare_dynamic(field1, :neq, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) != field(q, ^field2))
  end

  defp field_compare_dynamic(field1, :gt, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) > field(q, ^field2))
  end

  defp field_compare_dynamic(field1, :gte, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) >= field(q, ^field2))
  end

  defp field_compare_dynamic(field1, :lt, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) < field(q, ^field2))
  end

  defp field_compare_dynamic(field1, :lte, field2, binding) do
    dynamic([{^binding, q}], field(q, ^field1) <= field(q, ^field2))
  end

  # EXISTS/NOT EXISTS subquery helpers
  defp apply_exists_query(query, subquery, true) do
    from(q in query, where: exists(subquery(subquery)))
  end

  defp apply_exists_query(query, subquery, false) do
    from(q in query, where: not exists(subquery(subquery)))
  end

  # Resolve subquery from Token or Ecto.Query
  defp resolve_subquery(%Token{} = token) do
    # Call Builder.build/1 via runtime to avoid circular dependency
    apply(Events.Core.Query.Builder, :build, [token])
  end

  defp resolve_subquery(%Ecto.Query{} = query), do: query
end
