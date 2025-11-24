defmodule Events.Query.Builder do
  @moduledoc """
  Builds Ecto queries from tokens using pattern matching.

  Converts the token's operation list into an executable Ecto query.
  """

  import Ecto.Query
  alias Events.Query.Token

  @doc "Build an Ecto query from a token"
  @spec build(Token.t()) :: Ecto.Query.t()
  def build(%Token{source: source, operations: operations}) do
    base = build_base_query(source)
    Enum.reduce(operations, base, &apply_operation/2)
  end

  # Build base query from source
  defp build_base_query(:nested), do: nil
  defp build_base_query(schema) when is_atom(schema), do: from(s in schema, as: :root)
  defp build_base_query(%Ecto.Query{} = query), do: query

  # Apply operations using pattern matching
  defp apply_operation({:filter, spec}, query), do: apply_filter(query, spec)
  defp apply_operation({:paginate, spec}, query), do: apply_pagination(query, spec)
  defp apply_operation({:order, spec}, query), do: apply_order(query, spec)
  defp apply_operation({:join, spec}, query), do: apply_join(query, spec)
  defp apply_operation({:preload, spec}, query), do: apply_preload(query, spec)
  defp apply_operation({:select, spec}, query), do: apply_select(query, spec)
  defp apply_operation({:group_by, spec}, query), do: apply_group_by(query, spec)
  defp apply_operation({:having, spec}, query), do: apply_having(query, spec)
  defp apply_operation({:limit, value}, query), do: from(q in query, limit: ^value)
  defp apply_operation({:offset, value}, query), do: from(q in query, offset: ^value)
  defp apply_operation({:distinct, spec}, query), do: apply_distinct(query, spec)
  defp apply_operation({:lock, mode}, query), do: from(q in query, lock: ^mode)
  defp apply_operation({:cte, spec}, query), do: apply_cte(query, spec)
  defp apply_operation({:window, spec}, query), do: apply_window(query, spec)
  defp apply_operation({:raw_where, spec}, query), do: apply_raw_where(query, spec)

  ## Filter Operations

  defp apply_filter(query, {field, op, value, opts}) do
    binding = opts[:binding] || :root
    apply_filter_operation(query, binding, field, op, value, opts)
  end

  # Equality
  defp apply_filter_operation(query, binding, field, :eq, value, opts) do
    case_insensitive = opts[:case_insensitive] || false

    if is_binary(value) && case_insensitive do
      from([{^binding, q}] in query,
        where: fragment("lower(?)", field(q, ^field)) == fragment("lower(?)", ^value)
      )
    else
      from([{^binding, q}] in query, where: field(q, ^field) == ^value)
    end
  end

  # Not equal
  defp apply_filter_operation(query, binding, field, :neq, value, _opts) do
    from([{^binding, q}] in query, where: field(q, ^field) != ^value)
  end

  # Greater than
  defp apply_filter_operation(query, binding, field, :gt, value, _opts) do
    from([{^binding, q}] in query, where: field(q, ^field) > ^value)
  end

  # Greater than or equal
  defp apply_filter_operation(query, binding, field, :gte, value, _opts) do
    from([{^binding, q}] in query, where: field(q, ^field) >= ^value)
  end

  # Less than
  defp apply_filter_operation(query, binding, field, :lt, value, _opts) do
    from([{^binding, q}] in query, where: field(q, ^field) < ^value)
  end

  # Less than or equal
  defp apply_filter_operation(query, binding, field, :lte, value, _opts) do
    from([{^binding, q}] in query, where: field(q, ^field) <= ^value)
  end

  # In list
  defp apply_filter_operation(query, binding, field, :in, values, _opts) when is_list(values) do
    from([{^binding, q}] in query, where: field(q, ^field) in ^values)
  end

  # Not in list
  defp apply_filter_operation(query, binding, field, :not_in, values, _opts)
       when is_list(values) do
    from([{^binding, q}] in query, where: field(q, ^field) not in ^values)
  end

  # Like pattern
  defp apply_filter_operation(query, binding, field, :like, pattern, _opts) do
    from([{^binding, q}] in query, where: like(field(q, ^field), ^pattern))
  end

  # Case-insensitive like
  defp apply_filter_operation(query, binding, field, :ilike, pattern, _opts) do
    from([{^binding, q}] in query, where: ilike(field(q, ^field), ^pattern))
  end

  # Is null
  defp apply_filter_operation(query, binding, field, :is_nil, _value, _opts) do
    from([{^binding, q}] in query, where: is_nil(field(q, ^field)))
  end

  # Is not null
  defp apply_filter_operation(query, binding, field, :not_nil, _value, _opts) do
    from([{^binding, q}] in query, where: not is_nil(field(q, ^field)))
  end

  # Between range
  defp apply_filter_operation(query, binding, field, :between, {min, max}, _opts) do
    from([{^binding, q}] in query,
      where: field(q, ^field) >= ^min and field(q, ^field) <= ^max
    )
  end

  # Array contains
  defp apply_filter_operation(query, binding, field, :contains, value, _opts) do
    from([{^binding, q}] in query, where: fragment("? @> ?", field(q, ^field), ^value))
  end

  # JSONB contains
  defp apply_filter_operation(query, binding, field, :jsonb_contains, value, _opts) do
    json_value = Jason.encode!(value)

    from([{^binding, q}] in query,
      where: fragment("? @> ?::jsonb", field(q, ^field), ^json_value)
    )
  end

  # JSONB has key
  defp apply_filter_operation(query, binding, field, :jsonb_has_key, key, _opts) do
    from([{^binding, q}] in query, where: fragment("? \\? ?", field(q, ^field), ^key))
  end

  ## Pagination

  defp apply_pagination(query, {:offset, opts}) do
    limit = opts[:limit]
    offset = opts[:offset] || 0

    query
    |> then(fn q -> if limit, do: from(x in q, limit: ^limit), else: q end)
    |> then(fn q -> if offset > 0, do: from(x in q, offset: ^offset), else: q end)
  end

  defp apply_pagination(query, {:cursor, opts}) do
    limit = opts[:limit]
    cursor_fields = opts[:cursor_fields] || []
    after_cursor = opts[:after]
    before_cursor = opts[:before]

    query
    |> apply_cursor_ordering(cursor_fields)
    |> apply_cursor_filter(after_cursor, before_cursor, cursor_fields)
    |> then(fn q -> if limit, do: from(x in q, limit: ^limit), else: q end)
  end

  defp apply_cursor_ordering(query, []), do: query

  defp apply_cursor_ordering(query, cursor_fields) do
    order_by_expr =
      Enum.map(cursor_fields, fn
        {field, dir} -> {dir, field}
        field -> {:asc, field}
      end)

    from(q in query, order_by: ^order_by_expr)
  end

  defp apply_cursor_filter(query, nil, nil, _), do: query

  defp apply_cursor_filter(query, after_cursor, _before, fields) when not is_nil(after_cursor) do
    case decode_cursor(after_cursor) do
      {:ok, cursor_data} ->
        apply_cursor_condition(query, cursor_data, fields, :after)

      _ ->
        query
    end
  end

  defp apply_cursor_filter(query, _, before_cursor, fields) when not is_nil(before_cursor) do
    case decode_cursor(before_cursor) do
      {:ok, cursor_data} ->
        apply_cursor_condition(query, cursor_data, fields, :before)

      _ ->
        query
    end
  end

  defp apply_cursor_condition(query, cursor_data, [{field, _dir}], :after) do
    value = Map.get(cursor_data, field)
    from(q in query, where: field(q, ^field) > ^value)
  end

  defp apply_cursor_condition(query, cursor_data, [{field, _dir}], :before) do
    value = Map.get(cursor_data, field)
    from(q in query, where: field(q, ^field) < ^value)
  end

  defp apply_cursor_condition(query, _cursor_data, _fields, _direction) do
    # Multi-field cursor pagination requires complex lexicographic ordering
    # This is a simplified implementation
    query
  end

  defp decode_cursor(encoded) do
    try do
      decoded = Base.url_decode64!(encoded, padding: false)
      cursor_data = :erlang.binary_to_term(decoded, [:safe])
      {:ok, cursor_data}
    rescue
      _ -> {:error, :invalid_cursor}
    end
  end

  ## Order

  defp apply_order(query, {field, direction}) do
    from(q in query, order_by: [{^direction, ^field}])
  end

  ## Join

  defp apply_join(query, {association, type, opts}) when is_atom(association) do
    # Association join
    as_name = opts[:as] || association
    on_condition = opts[:on]

    case {type, on_condition} do
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

      {_, _on} ->
        # TODO: Support custom on conditions for associations
        query
    end
  end

  defp apply_join(query, {schema, type, opts}) when is_atom(schema) do
    # Schema join with custom on condition
    as_name = opts[:as] || schema
    on_condition = opts[:on]

    case {type, on_condition} do
      {:inner, on} when not is_nil(on) ->
        from(q in query, join: s in ^schema, on: ^on, as: ^as_name)

      {:left, on} when not is_nil(on) ->
        from(q in query, left_join: s in ^schema, on: ^on, as: ^as_name)

      {:right, on} when not is_nil(on) ->
        from(q in query, right_join: s in ^schema, on: ^on, as: ^as_name)

      {:full, on} when not is_nil(on) ->
        from(q in query, full_join: s in ^schema, on: ^on, as: ^as_name)

      _ ->
        query
    end
  end

  ## Preload

  defp apply_preload(query, associations) when is_atom(associations) do
    from(q in query, preload: ^associations)
  end

  defp apply_preload(query, associations) when is_list(associations) do
    # Process nested preloads
    processed = process_preload_list(associations)
    from(q in query, preload: ^processed)
  end

  defp apply_preload(query, {association, %Token{} = nested_token}) do
    # Nested preload with filters
    nested_query = build(nested_token)
    from(q in query, preload: [{^association, ^nested_query}])
  end

  defp process_preload_list(associations) do
    Enum.map(associations, fn
      {assoc, %Token{} = token} ->
        {assoc, build(token)}

      assoc when is_atom(assoc) ->
        assoc

      other ->
        other
    end)
  end

  ## Select

  defp apply_select(query, fields) when is_list(fields) do
    from(q in query, select: map(q, ^fields))
  end

  defp apply_select(query, field_map) when is_map(field_map) do
    # Build select expression from map
    select_expr =
      Enum.reduce(field_map, %{}, fn
        {key, field}, acc when is_atom(field) ->
          Map.put(acc, key, dynamic([q], field(q, ^field)))

        {key, {:window, func, field, window_name}}, acc ->
          # Window function
          window_expr = build_window_function(func, field, window_name)
          Map.put(acc, key, window_expr)

        {key, value}, acc ->
          Map.put(acc, key, value)
      end)

    from(q in query, select: ^select_expr)
  end

  defp build_window_function(:sum, field, window_name) do
    dynamic([q], sum(field(q, ^field)) |> over(^window_name))
  end

  defp build_window_function(:avg, field, window_name) do
    dynamic([q], avg(field(q, ^field)) |> over(^window_name))
  end

  defp build_window_function(:count, field, window_name) do
    dynamic([q], count(field(q, ^field)) |> over(^window_name))
  end

  defp build_window_function(func, field, window_name) do
    # Generic window function
    dynamic([q], fragment("?(?)", ^func, field(q, ^field)) |> over(^window_name))
  end

  ## Group By

  defp apply_group_by(query, field) when is_atom(field) do
    from(q in query, group_by: field(q, ^field))
  end

  defp apply_group_by(query, fields) when is_list(fields) do
    from(q in query, group_by: ^fields)
  end

  ## Having

  defp apply_having(query, conditions) do
    Enum.reduce(conditions, query, fn {aggregate, {op, value}}, q ->
      apply_having_condition(q, aggregate, op, value)
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

  ## Distinct

  defp apply_distinct(query, true) do
    from(q in query, distinct: true)
  end

  defp apply_distinct(query, fields) when is_list(fields) do
    from(q in query, distinct: ^fields)
  end

  ## CTE

  defp apply_cte(query, {name, %Token{} = cte_token}) do
    cte_query = build(cte_token)
    from(q in query, with_cte: ^name, as: ^cte_query)
  end

  defp apply_cte(query, {name, %Ecto.Query{} = cte_query}) do
    from(q in query, with_cte: ^name, as: ^cte_query)
  end

  ## Window

  defp apply_window(query, {name, definition}) do
    # Build window definition
    partition_by = definition[:partition_by]
    order_by = definition[:order_by]

    window_def =
      []
      |> then(fn def ->
        if partition_by, do: Keyword.put(def, :partition_by, partition_by), else: def
      end)
      |> then(fn def -> if order_by, do: Keyword.put(def, :order_by, order_by), else: def end)

    from(q in query, windows: [{^name, ^window_def}])
  end

  ## Raw WHERE

  defp apply_raw_where(query, {sql, params}) do
    # Replace named placeholders with positional
    {sql_with_positions, param_list} = convert_named_params(sql, params)
    from(q in query, where: fragment(sql_with_positions, ^param_list))
  end

  defp convert_named_params(sql, params) when is_map(params) do
    # Convert :param_name to positional ?
    {result_sql, param_list, _} =
      Regex.scan(~r/:(\w+)/, sql)
      |> Enum.reduce({sql, [], 1}, fn [match, param_name], {sql_acc, params_acc, idx} ->
        param_key = String.to_existing_atom(param_name)
        value = Map.get(params, param_key)

        # Replace :param_name with positional placeholder
        new_sql = String.replace(sql_acc, match, "?", global: false)
        {new_sql, params_acc ++ [value], idx + 1}
      end)

    {result_sql, param_list}
  end
end
