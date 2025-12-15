defmodule Events.Core.Query.Builder.Joins do
  @moduledoc false
  # Internal module for Builder - join compilation
  #
  # Handles association and schema joins with support for custom ON conditions.

  import Ecto.Query

  ## Public API (for Builder)

  @doc """
  Apply a join to a query.

  Supports both association joins and schema joins with various join types
  (inner, left, right, full, cross).
  """
  @spec apply(Ecto.Query.t(), {atom(), atom(), keyword()}) :: Ecto.Query.t()
  def apply(query, {association, type, opts}) when is_atom(association) do
    # Association join
    as_name = opts[:as] || association
    on_conditions = opts[:on]

    # If no custom ON conditions, use association-based join
    # If custom ON conditions provided, build dynamic expression
    case {type, on_conditions} do
      {:inner, nil} ->
        from(q in query, join: a in assoc(q, ^association), as: ^as_name)

      {:left, nil} ->
        from(q in query, left_join: a in assoc(q, ^association), as: ^as_name)

      {:right, nil} ->
        from(q in query, right_join: a in assoc(q, ^association), as: ^as_name)

      {:full, nil} ->
        from(q in query, full_join: a in assoc(q, ^association), as: ^as_name)

      {:cross, nil} ->
        from(q in query, cross_join: a in assoc(q, ^association), as: ^as_name)

      {join_type, conditions} when is_list(conditions) ->
        # Custom ON conditions as keyword list
        apply_with_conditions(query, association, join_type, as_name, conditions)

      {join_type, %Ecto.Query.DynamicExpr{} = dynamic_on} ->
        # Dynamic expression passed directly
        apply_schema_join(query, association, join_type, as_name, dynamic_on)

      _ ->
        query
    end
  end

  def apply(query, {schema, type, opts}) when is_atom(schema) do
    # Schema join with custom on condition
    as_name = opts[:as] || schema
    on_conditions = opts[:on]

    case {type, on_conditions} do
      {_type, nil} ->
        # No ON condition - can't do schema join without it
        query

      {join_type, conditions} when is_list(conditions) ->
        # Keyword list of conditions: [foreign_key: :local_key, ...]
        apply_with_conditions(query, schema, join_type, as_name, conditions)

      {join_type, %Ecto.Query.DynamicExpr{} = dynamic_on} ->
        apply_schema_join(query, schema, join_type, as_name, dynamic_on)

      _ ->
        query
    end
  end

  ## Private Helpers

  # Build join with keyword list conditions
  # e.g., on: [id: :category_id, tenant_id: :tenant_id]
  defp apply_with_conditions(query, schema, type, as_name, conditions) do
    dynamic_on = build_join_conditions(conditions)
    apply_schema_join(query, schema, type, as_name, dynamic_on)
  end

  defp build_join_conditions(conditions) do
    conditions
    |> Enum.reduce(nil, fn {join_field, root_field}, acc ->
      condition = dynamic([q, j], field(j, ^join_field) == field(q, ^root_field))

      case acc do
        nil -> condition
        prev -> dynamic([q, j], ^prev and ^condition)
      end
    end)
  end

  defp apply_schema_join(query, schema, :inner, as_name, on) do
    from(q in query, join: s in ^schema, on: ^on, as: ^as_name)
  end

  defp apply_schema_join(query, schema, :left, as_name, on) do
    from(q in query, left_join: s in ^schema, on: ^on, as: ^as_name)
  end

  defp apply_schema_join(query, schema, :right, as_name, on) do
    from(q in query, right_join: s in ^schema, on: ^on, as: ^as_name)
  end

  defp apply_schema_join(query, schema, :full, as_name, on) do
    from(q in query, full_join: s in ^schema, on: ^on, as: ^as_name)
  end

  defp apply_schema_join(query, _schema, _type, _as_name, _on), do: query
end
