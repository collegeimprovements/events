defmodule Events.Core.Query.Builder.Selects do
  @moduledoc false
  # Internal module for Builder - select operations
  #
  # Handles select, preload, group_by, having, and distinct operations.

  import Ecto.Query
  alias Events.Core.Query.Token

  ## Public API (for Builder)

  @doc """
  Apply preload to a query.

  Supports:
  - Single atom association
  - List of associations
  - Nested preloads with Tokens
  """
  @spec apply_preload(Ecto.Query.t(), atom() | list() | {atom(), Token.t()}) :: Ecto.Query.t()
  def apply_preload(query, associations) when is_atom(associations) do
    from(q in query, preload: ^associations)
  end

  def apply_preload(query, associations) when is_list(associations) do
    # Process nested preloads
    processed = process_preload_list(associations)
    from(q in query, preload: ^processed)
  end

  def apply_preload(query, {association, %Token{} = nested_token}) do
    # Nested preload with filters - call Builder.build/1 via runtime
    nested_query = apply(Events.Core.Query.Builder, :build, [nested_token])
    from(q in query, preload: [{^association, ^nested_query}])
  end

  @doc """
  Apply select to a query.

  Supports:
  - List of fields
  - Map of field expressions
  """
  @spec apply_select(Ecto.Query.t(), list() | map()) :: Ecto.Query.t()
  def apply_select(query, fields) when is_list(fields) do
    from(q in query, select: map(q, ^fields))
  end

  def apply_select(query, field_map) when is_map(field_map) do
    # Build select expression from map
    select_expr =
      Enum.reduce(field_map, %{}, fn
        # Simple field reference from base table
        {key, field}, acc when is_atom(field) ->
          Map.put(acc, key, dynamic([q], field(q, ^field)))

        # Field from joined table: {:binding, :field}
        {key, {binding, field}}, acc when is_atom(binding) and is_atom(field) ->
          Map.put(acc, key, dynamic([{^binding, b}], field(b, ^field)))

        # Window function syntax - provide helpful error
        {key, {:window, _func, opts}}, _acc when is_list(opts) ->
          raise ArgumentError, """
          Window functions in select require compile-time Ecto macros.

          For dynamic window functions, use one of these approaches:

          1. Build the query directly with Ecto.Query:

             from(p in Product,
               windows: [w: [partition_by: :category_id, order_by: [desc: :price]]],
               select: %{name: p.name, rank: over(row_number(), :w)}
             )

          2. Use fragment in select for raw SQL:

             Query.select(token, %{
               name: :name,
               rank: fragment("ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price DESC)")
             })

          Key: #{inspect(key)}
          """

        # Fragment pass-through (for raw SQL window functions)
        {key, %Ecto.Query.DynamicExpr{} = dynamic_expr}, acc ->
          Map.put(acc, key, dynamic_expr)

        # Pass through other values (literals, etc.)
        {key, value}, acc ->
          Map.put(acc, key, value)
      end)

    from(q in query, select: ^select_expr)
  end

  @doc """
  Apply group_by to a query.
  """
  @spec apply_group_by(Ecto.Query.t(), atom() | list()) :: Ecto.Query.t()
  def apply_group_by(query, field) when is_atom(field) do
    from(q in query, group_by: field(q, ^field))
  end

  def apply_group_by(query, fields) when is_list(fields) do
    from(q in query, group_by: ^fields)
  end

  @doc """
  Apply having to a query.

  Supports aggregate conditions like:
  - count: :gt, :gte, :lt, :lte, :eq
  """
  @spec apply_having(Ecto.Query.t(), list()) :: Ecto.Query.t()
  def apply_having(query, conditions) do
    Enum.reduce(conditions, query, fn {aggregate, {op, value}}, q ->
      apply_having_condition(q, aggregate, op, value)
    end)
  end

  @doc """
  Apply distinct to a query.
  """
  @spec apply_distinct(Ecto.Query.t(), boolean() | list()) :: Ecto.Query.t()
  def apply_distinct(query, true) do
    from(q in query, distinct: true)
  end

  def apply_distinct(query, fields) when is_list(fields) do
    from(q in query, distinct: ^fields)
  end

  ## Private Helpers

  defp process_preload_list(associations) do
    Enum.map(associations, fn
      {assoc, %Token{} = token} ->
        # Call Builder.build/1 via runtime to avoid circular dependency
        {assoc, apply(Events.Core.Query.Builder, :build, [token])}

      assoc when is_atom(assoc) ->
        assoc

      other ->
        other
    end)
  end

  defp apply_having_condition(query, :count, :gt, value) do
    from(q in query, having: fragment("count(*) > ?", ^value))
  end

  defp apply_having_condition(query, :count, :gte, value) do
    from(q in query, having: fragment("count(*) >= ?", ^value))
  end

  defp apply_having_condition(query, :count, :lt, value) do
    from(q in query, having: fragment("count(*) < ?", ^value))
  end

  defp apply_having_condition(query, :count, :lte, value) do
    from(q in query, having: fragment("count(*) <= ?", ^value))
  end

  defp apply_having_condition(query, :count, :eq, value) do
    from(q in query, having: fragment("count(*) = ?", ^value))
  end

  defp apply_having_condition(query, _aggregate, _op, _value), do: query
end
