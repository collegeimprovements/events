defmodule Events.Core.Query.Builder do
  @moduledoc false
  # Internal module - use Events.Core.Query public API instead.
  #
  # Builds Ecto queries from tokens using pattern matching.
  # Converts the token's operation list into an executable Ecto query.
  #
  # Architecture:
  # The builder uses a unified filter system where all filter operators are defined
  # once in `build_filter_dynamic/4` and can be used both for direct query building
  # and dynamic expression building (for OR/AND groups).
  #
  # Filter Operators:
  # All operators defined in @filter_operators are supported in both contexts:
  # - Direct filter/4 calls
  # - where_any/2 (OR groups)
  # - where_all/2 (AND groups)

  import Ecto.Query
  alias Events.Core.Query.Token
  alias Events.Core.Query.CursorError
  alias Events.Core.Query.Builder.Filters

  @doc """
  Build an Ecto query from a token (safe variant).

  Returns `{:ok, query}` on success or `{:error, exception}` on failure.
  Use this when you want to handle build errors gracefully.

  For the raising variant, use `build!/1` or `build/1`.

  ## Examples

      case Builder.build_safe(token) do
        {:ok, query} -> Repo.all(query)
        {:error, %CursorError{} = error} -> handle_cursor_error(error)
        {:error, error} -> handle_other_error(error)
      end
  """
  @spec build_safe(Token.t()) :: {:ok, Ecto.Query.t()} | {:error, Exception.t()}
  def build_safe(%Token{} = token) do
    {:ok, build!(token)}
  rescue
    e in [CursorError, ArgumentError] -> {:error, e}
  end

  @doc """
  Build an Ecto query from a token (raising variant).

  Raises an exception on failure. This is the same as `build/1`.

  For the safe variant that returns tuples, use `build_safe/1`.

  ## Possible Exceptions

  - `CursorError` - Invalid or corrupted cursor
  - `ArgumentError` - Invalid operation configuration
  """
  @spec build!(Token.t()) :: Ecto.Query.t()
  def build!(%Token{source: source, operations: operations}) do
    base = build_base_query(source)
    Enum.reduce(operations, base, &apply_operation/2)
  end

  @doc """
  Build an Ecto query from a token.

  Raises on failure. This is an alias for `build!/1` kept for backwards compatibility.

  For the safe variant that returns tuples, use `build_safe/1`.
  """
  @spec build(Token.t()) :: Ecto.Query.t()
  def build(%Token{} = token) do
    build!(token)
  end

  # Build base query from source
  defp build_base_query(:nested), do: nil
  defp build_base_query(schema) when is_atom(schema), do: from(s in schema, as: :root)
  defp build_base_query(%Ecto.Query{} = query), do: query

  # Apply operations using pattern matching
  defp apply_operation({:filter, spec}, query), do: Filters.apply_filter(query, spec)
  defp apply_operation({:filter_group, spec}, query), do: Filters.apply_filter_group(query, spec)
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
  defp apply_operation({:lock, mode}, query), do: apply_lock(query, mode)
  defp apply_operation({:cte, spec}, query), do: apply_cte(query, spec)
  defp apply_operation({:window, spec}, query), do: apply_window(query, spec)
  defp apply_operation({:raw_where, spec}, query), do: apply_raw_where(query, spec)
  defp apply_operation({:exists, spec}, query), do: Filters.apply_exists(query, spec, true)
  defp apply_operation({:not_exists, spec}, query), do: Filters.apply_exists(query, spec, false)
  defp apply_operation({:search_rank, spec}, query), do: apply_search_rank(query, spec)

  defp apply_operation({:search_rank_limited, spec}, query),
    do: apply_search_rank_limited(query, spec)

  defp apply_operation({:field_compare, spec}, query), do: Filters.apply_field_compare(query, spec)

  ## Pagination - Offset and Cursor-based

  defp apply_pagination(query, {:offset, opts}) do
    limit = opts[:limit] || Events.Core.Query.Token.default_limit()
    offset = opts[:offset] || 0

    query
    |> from(limit: ^limit)
    |> maybe_apply_offset(offset)
  end

  defp apply_pagination(query, {:cursor, opts}) do
    limit = opts[:limit] || Events.Core.Query.Token.default_limit()
    cursor_fields = opts[:cursor_fields] || []
    after_cursor = opts[:after]
    before_cursor = opts[:before]

    query
    |> apply_cursor_ordering(cursor_fields)
    |> apply_cursor_filter(after_cursor, before_cursor, cursor_fields)
    |> from(limit: ^limit)
  end

  defp maybe_apply_offset(query, 0), do: query
  defp maybe_apply_offset(query, offset), do: from(q in query, offset: ^offset)

  defp apply_cursor_ordering(query, []), do: query

  defp apply_cursor_ordering(query, cursor_fields) do
    order_by_expr =
      cursor_fields
      |> normalize_cursor_fields()
      |> Enum.map(fn {field, dir} -> {dir, field} end)

    from(q in query, order_by: ^order_by_expr)
  end

  defp apply_cursor_filter(query, nil, nil, _), do: query

  defp apply_cursor_filter(query, after_cursor, _before, fields) when not is_nil(after_cursor) do
    case decode_cursor(after_cursor) do
      {:ok, cursor_data} ->
        apply_cursor_condition(query, cursor_data, fields, :after)

      {:error, reason} ->
        raise CursorError,
          cursor: after_cursor,
          reason: reason,
          suggestion:
            "The 'after' cursor is invalid or corrupted. Request the first page without a cursor."
    end
  end

  defp apply_cursor_filter(query, _, before_cursor, fields) when not is_nil(before_cursor) do
    case decode_cursor(before_cursor) do
      {:ok, cursor_data} ->
        apply_cursor_condition(query, cursor_data, fields, :before)

      {:error, reason} ->
        raise CursorError,
          cursor: before_cursor,
          reason: reason,
          suggestion:
            "The 'before' cursor is invalid or corrupted. Request the last page without a cursor."
    end
  end

  # Single field cursor - simple comparison
  defp apply_cursor_condition(query, cursor_data, [{field, dir}], direction) do
    value = Map.get(cursor_data, field)
    op = cursor_comparison_op(dir, direction)
    apply_cursor_comparison(query, field, op, value)
  end

  # Multi-field cursor - lexicographic ordering
  # For fields [a, b, c] with cursor values [a', b', c'], we need:
  # (a > a') OR (a = a' AND b > b') OR (a = a' AND b = b' AND c > c')
  defp apply_cursor_condition(query, cursor_data, fields, direction) when length(fields) > 1 do
    conditions = build_lexicographic_conditions(cursor_data, fields, direction)
    from(q in query, where: ^conditions)
  end

  defp apply_cursor_condition(query, _cursor_data, [], _direction), do: query

  defp build_lexicographic_conditions(cursor_data, fields, direction) do
    fields
    |> Enum.with_index()
    |> Enum.map(fn {{field, dir}, idx} ->
      prefix_fields = Enum.take(fields, idx)
      build_cursor_branch(cursor_data, prefix_fields, {field, dir}, direction)
    end)
    |> combine_with_or()
  end

  # Build one branch of the lexicographic condition:
  # (prefix_field1 = val1 AND prefix_field2 = val2 AND ... AND target_field > target_val)
  defp build_cursor_branch(cursor_data, prefix_fields, {field, field_dir}, direction) do
    # Build equality conditions for all prefix fields
    prefix_condition =
      prefix_fields
      |> Enum.map(fn {f, _dir} ->
        value = Map.get(cursor_data, f)
        dynamic([q], field(q, ^f) == ^value)
      end)
      |> combine_with_and()

    # Build comparison condition for the target field
    value = Map.get(cursor_data, field)
    op = cursor_comparison_op(field_dir, direction)
    field_condition = build_dynamic_comparison(field, op, value)

    # Combine: (prefix_equals AND field_comparison)
    case prefix_condition do
      nil -> field_condition
      prefix -> dynamic([], ^prefix and ^field_condition)
    end
  end

  defp combine_with_or([]), do: dynamic([], false)
  defp combine_with_or([single]), do: single

  defp combine_with_or([first | rest]) do
    Enum.reduce(rest, first, fn cond, acc ->
      dynamic([], ^acc or ^cond)
    end)
  end

  defp combine_with_and([]), do: nil
  defp combine_with_and([single]), do: single

  defp combine_with_and([first | rest]) do
    Enum.reduce(rest, first, fn cond, acc ->
      dynamic([], ^acc and ^cond)
    end)
  end

  defp build_dynamic_comparison(field, :gt, value) do
    dynamic([q], field(q, ^field) > ^value)
  end

  defp build_dynamic_comparison(field, :lt, value) do
    dynamic([q], field(q, ^field) < ^value)
  end

  # Determine comparison operator based on field direction and cursor direction
  # For ascending order: after = >, before = <
  # For descending order: after = <, before = >
  defp cursor_comparison_op(:asc, :after), do: :gt
  defp cursor_comparison_op(:asc, :before), do: :lt
  defp cursor_comparison_op(:desc, :after), do: :lt
  defp cursor_comparison_op(:desc, :before), do: :gt
  # Handle nulls variations (treat as their base direction)
  defp cursor_comparison_op(:asc_nulls_first, dir), do: cursor_comparison_op(:asc, dir)
  defp cursor_comparison_op(:asc_nulls_last, dir), do: cursor_comparison_op(:asc, dir)
  defp cursor_comparison_op(:desc_nulls_first, dir), do: cursor_comparison_op(:desc, dir)
  defp cursor_comparison_op(:desc_nulls_last, dir), do: cursor_comparison_op(:desc, dir)

  defp apply_cursor_comparison(query, field, :gt, value) do
    from(q in query, where: field(q, ^field) > ^value)
  end

  defp apply_cursor_comparison(query, field, :lt, value) do
    from(q in query, where: field(q, ^field) < ^value)
  end

  @doc """
  Decode a cursor string back to its original data.

  This is the public API for decoding cursors, useful for testing,
  debugging, and cursor validation.

  ## Parameters

  - `encoded` - The base64-encoded cursor string

  ## Returns

  - `{:ok, cursor_data}` - Map of field values from the cursor
  - `{:error, reason}` - Error with description

  ## Examples

      # Decode a cursor
      {:ok, data} = decode_cursor(cursor_string)
      # => %{id: 123, created_at: ~U[2024-01-01 00:00:00Z]}

      # Handle invalid cursors
      {:error, reason} = decode_cursor("invalid")

      # Use in tests to verify cursor contents
      result = Query.execute!(token)
      {:ok, cursor_data} = decode_cursor(result.end_cursor)
      assert cursor_data.id == expected_last_id
  """
  @spec decode_cursor(String.t() | any()) :: {:ok, map()} | {:error, String.t()}
  def decode_cursor(encoded) when is_binary(encoded) do
    with {:ok, decoded} <- decode_base64(encoded),
         {:ok, cursor_data} <- decode_term(decoded) do
      {:ok, cursor_data}
    end
  end

  def decode_cursor(_), do: {:error, "Cursor must be a string"}

  @doc """
  Extract field name from a cursor field specification.

  Cursor fields can be either atoms or `{field, direction}` tuples.
  This helper normalizes them to just the field name.

  ## Examples

      cursor_field(:id) # => :id
      cursor_field({:created_at, :desc}) # => :created_at
  """
  @spec cursor_field(atom() | {atom(), :asc | :desc}) :: atom()
  def cursor_field({field, _dir}) when is_atom(field), do: field
  def cursor_field(field) when is_atom(field), do: field

  @doc """
  Extract direction from a cursor field specification.

  Returns `:asc` for bare atoms, extracts direction from tuples.

  ## Examples

      cursor_direction(:id) # => :asc
      cursor_direction({:created_at, :desc}) # => :desc
  """
  @spec cursor_direction(atom() | {atom(), :asc | :desc}) :: :asc | :desc
  def cursor_direction({_field, dir}) when dir in [:asc, :desc], do: dir
  def cursor_direction(_field), do: :asc

  @doc """
  Normalize cursor fields to `{field, direction}` tuple format.

  ## Examples

      normalize_cursor_fields([:id, {:created_at, :desc}])
      # => [{:id, :asc}, {:created_at, :desc}]
  """
  @spec normalize_cursor_fields([atom() | {atom(), :asc | :desc}]) :: [{atom(), :asc | :desc}]
  def normalize_cursor_fields(fields) when is_list(fields) do
    Enum.map(fields, fn
      {field, dir} when is_atom(field) and dir in [:asc, :desc] -> {field, dir}
      field when is_atom(field) -> {field, :asc}
    end)
  end

  defp decode_base64(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, "Invalid base64 encoding - cursor may be truncated or corrupted"}
    end
  end

  defp decode_term(binary) do
    binary
    |> :erlang.binary_to_term([:safe])
    |> validate_cursor_data()
  rescue
    ArgumentError -> {:error, "Cursor contains unsafe or malformed data"}
  end

  defp validate_cursor_data(data) when is_map(data), do: {:ok, data}
  defp validate_cursor_data(_data), do: {:error, "Cursor contains invalid data structure"}

  ## Order

  defp apply_order(query, {field, direction, opts}) do
    binding = opts[:binding] || :root
    from([{^binding, q}] in query, order_by: [{^direction, field(q, ^field)}])
  end

  ## Search Ranking
  ##
  ## Orders results by which search field matched, with lower rank = higher priority.
  ## For similarity modes, also uses similarity score as secondary sort.

  defp apply_search_rank(query, {parsed_fields, term}) do
    # Build CASE WHEN expression for primary ranking
    rank_expr = build_rank_case_expression(parsed_fields, term)

    # Build secondary similarity score expression (for tiebreaking within same rank)
    similarity_expr = build_similarity_score_expression(parsed_fields, term)

    # Apply ordering: rank ASC, then similarity DESC (if applicable)
    case similarity_expr do
      nil ->
        from(q in query, order_by: [asc: ^rank_expr])

      sim_expr ->
        from(q in query, order_by: [asc: ^rank_expr, desc: ^sim_expr])
    end
  end

  # Build CASE WHEN expression that returns the rank for whichever field matched
  # Handles both 4-tuple {field, mode, opts, rank} and 5-tuple {field, mode, opts, rank, take} formats
  defp build_rank_case_expression(parsed_fields, term) do
    # Build list of {condition_dynamic, rank} tuples
    conditions =
      parsed_fields
      |> Enum.map(fn
        {field, mode, opts, rank, _take} ->
          condition = build_rank_condition(field, mode, term, opts)
          {condition, rank}

        {field, mode, opts, rank} ->
          condition = build_rank_condition(field, mode, term, opts)
          {condition, rank}
      end)

    # Build the CASE WHEN as a fragment
    # This creates: CASE WHEN cond1 THEN rank1 WHEN cond2 THEN rank2 ... ELSE 999 END
    build_case_when_dynamic(conditions)
  end

  # Build condition dynamic for a single field (with binding support)
  # Uses pattern matching on function heads for flat, readable code
  defp build_rank_condition(field, mode, term, opts) do
    binding = opts[:binding] || :root
    do_build_rank_condition(field, mode, term, binding, opts)
  end

  # Exact match
  defp do_build_rank_condition(field, :exact, term, binding, _opts) do
    dynamic([{^binding, q}], field(q, ^field) == ^term)
  end

  # Case-insensitive contains
  defp do_build_rank_condition(field, :ilike, term, binding, _opts) do
    pattern = "%#{term}%"
    dynamic([{^binding, q}], ilike(field(q, ^field), ^pattern))
  end

  # Case-sensitive contains
  defp do_build_rank_condition(field, :like, term, binding, _opts) do
    pattern = "%#{term}%"
    dynamic([{^binding, q}], like(field(q, ^field), ^pattern))
  end

  # Starts with - uses helper for case sensitivity
  defp do_build_rank_condition(field, :starts_with, term, binding, opts) do
    build_like_condition(field, "#{term}%", binding, opts)
  end

  # Ends with - uses helper for case sensitivity
  defp do_build_rank_condition(field, :ends_with, term, binding, opts) do
    build_like_condition(field, "%#{term}", binding, opts)
  end

  # Contains with case sensitivity option
  defp do_build_rank_condition(field, :contains, term, binding, opts) do
    build_like_condition(field, "%#{term}%", binding, opts)
  end

  # Trigram similarity
  defp do_build_rank_condition(field, :similarity, term, binding, opts) do
    threshold = Keyword.get(opts, :threshold, 0.3)
    dynamic([{^binding, q}], fragment("similarity(?, ?) > ?", field(q, ^field), ^term, ^threshold))
  end

  # Word similarity (better for phrases)
  defp do_build_rank_condition(field, :word_similarity, term, binding, opts) do
    threshold = Keyword.get(opts, :threshold, 0.3)

    dynamic(
      [{^binding, q}],
      fragment("word_similarity(?, ?) > ?", ^term, field(q, ^field), ^threshold)
    )
  end

  # Strict word similarity
  defp do_build_rank_condition(field, :strict_word_similarity, term, binding, opts) do
    threshold = Keyword.get(opts, :threshold, 0.3)

    dynamic(
      [{^binding, q}],
      fragment("strict_word_similarity(?, ?) > ?", ^term, field(q, ^field), ^threshold)
    )
  end

  # Helper: builds like/ilike based on case_sensitive option
  defp build_like_condition(field, pattern, binding, opts) do
    case Keyword.get(opts, :case_sensitive, false) do
      true -> dynamic([{^binding, q}], like(field(q, ^field), ^pattern))
      false -> dynamic([{^binding, q}], ilike(field(q, ^field), ^pattern))
    end
  end

  # Build CASE WHEN dynamic expression
  # Returns a dynamic that evaluates to the rank of the first matching condition
  defp build_case_when_dynamic(conditions) do
    # We need to build this as a fragment since Ecto doesn't have native CASE WHEN
    # Build: CASE WHEN cond1 THEN 1 WHEN cond2 THEN 2 ... ELSE 999 END
    Enum.reduce(Enum.reverse(conditions), dynamic([q], 999), fn {condition, rank}, acc ->
      dynamic([q], fragment("CASE WHEN ? THEN ? ELSE ? END", ^condition, ^rank, ^acc))
    end)
  end

  # Build similarity score expression for secondary sorting
  # Only returns a value if there are similarity-based fields
  # Handles both 4-tuple and 5-tuple formats
  defp build_similarity_score_expression(parsed_fields, term) do
    similarity_fields =
      Enum.filter(parsed_fields, fn
        {_field, mode, _opts, _rank, _take} ->
          mode in [:similarity, :word_similarity, :strict_word_similarity]

        {_field, mode, _opts, _rank} ->
          mode in [:similarity, :word_similarity, :strict_word_similarity]
      end)

    case similarity_fields do
      [] ->
        nil

      fields ->
        # Build GREATEST of all similarity scores
        # This ensures we sort by the best similarity match
        build_greatest_similarity(fields, term)
    end
  end

  # Extract field/mode/opts from both tuple formats
  defp extract_field_info({field, mode, opts, _rank, _take}), do: {field, mode, opts}
  defp extract_field_info({field, mode, opts, _rank}), do: {field, mode, opts}

  defp build_greatest_similarity([tuple], term) do
    {field, mode, opts} = extract_field_info(tuple)
    build_similarity_expression(field, mode, term, opts)
  end

  defp build_greatest_similarity(fields, term) do
    exprs =
      Enum.map(fields, fn tuple ->
        {field, mode, opts} = extract_field_info(tuple)
        build_similarity_expression(field, mode, term, opts)
      end)

    # Combine with GREATEST
    Enum.reduce(exprs, fn expr, acc ->
      dynamic([q], fragment("GREATEST(?, ?)", ^acc, ^expr))
    end)
  end

  defp build_similarity_expression(field, :similarity, term, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], fragment("similarity(?, ?)", field(q, ^field), ^term))
  end

  defp build_similarity_expression(field, :word_similarity, term, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], fragment("word_similarity(?, ?)", ^term, field(q, ^field)))
  end

  defp build_similarity_expression(field, :strict_word_similarity, term, opts) do
    binding = opts[:binding] || :root
    dynamic([{^binding, q}], fragment("strict_word_similarity(?, ?)", ^term, field(q, ^field)))
  end

  ## Search Ranking with Per-Field Limits (Take)
  ##
  ## Applies ranking with per-field limits. Results are ordered by rank,
  ## with a total limit equal to the sum of all take values.
  ##
  ## For exact per-rank enforcement, consider using multiple queries or raw SQL.

  defp apply_search_rank_limited(query, {parsed_fields, term}) do
    # Build rank ordering expression
    rank_expr = build_rank_case_expression(parsed_fields, term)

    # Build similarity score for secondary ordering
    similarity_expr = build_similarity_score_expression(parsed_fields, term)

    # Calculate total limit from take values
    total_limit =
      parsed_fields
      |> Enum.map(fn {_field, _mode, _opts, _rank, take} -> take || 1000 end)
      |> Enum.sum()

    # Apply ordering: rank ASC (lower rank = higher priority), then similarity DESC
    query =
      case similarity_expr do
        nil ->
          from(q in query, order_by: [asc: ^rank_expr])

        sim_expr ->
          from(q in query, order_by: [asc: ^rank_expr, desc: ^sim_expr])
      end

    # Apply total limit
    from(q in query, limit: ^total_limit)
  end

  ## Join

  defp apply_join(query, {association, type, opts}) when is_atom(association) do
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
        apply_join_with_conditions(query, association, join_type, as_name, conditions)

      {join_type, %Ecto.Query.DynamicExpr{} = dynamic_on} ->
        # Dynamic expression passed directly
        apply_schema_join(query, association, join_type, as_name, dynamic_on)

      _ ->
        query
    end
  end

  defp apply_join(query, {schema, type, opts}) when is_atom(schema) do
    # Schema join with custom on condition
    as_name = opts[:as] || schema
    on_conditions = opts[:on]

    case {type, on_conditions} do
      {_type, nil} ->
        # No ON condition - can't do schema join without it
        query

      {join_type, conditions} when is_list(conditions) ->
        # Keyword list of conditions: [foreign_key: :local_key, ...]
        apply_join_with_conditions(query, schema, join_type, as_name, conditions)

      {join_type, %Ecto.Query.DynamicExpr{} = dynamic_on} ->
        apply_schema_join(query, schema, join_type, as_name, dynamic_on)

      _ ->
        query
    end
  end

  # Build join with keyword list conditions
  # e.g., on: [id: :category_id, tenant_id: :tenant_id]
  defp apply_join_with_conditions(query, schema, type, as_name, conditions) do
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

  ## Lock

  # Handle common lock modes as literals for security
  defp apply_lock(query, :update) do
    from(q in query, lock: "FOR UPDATE")
  end

  defp apply_lock(query, :share) do
    from(q in query, lock: "FOR SHARE")
  end

  defp apply_lock(query, :update_nowait) do
    from(q in query, lock: "FOR UPDATE NOWAIT")
  end

  defp apply_lock(query, :update_skip_locked) do
    from(q in query, lock: "FOR UPDATE SKIP LOCKED")
  end

  defp apply_lock(query, mode) when is_binary(mode) do
    # String lock mode - use as fragment
    from(q in query, lock: fragment(^mode))
  end

  defp apply_lock(query, _mode) do
    # Unknown mode, skip
    query
  end

  ## CTE

  # CTE with options (including recursive support)
  defp apply_cte(query, {name, cte_source, opts}) when is_list(opts) do
    query
    |> maybe_enable_recursive(Keyword.get(opts, :recursive, false))
    |> apply_cte_query(name, cte_source)
  end

  # Backwards compatible: CTE without options
  defp apply_cte(query, {name, cte_source}) do
    apply_cte_query(query, name, cte_source)
  end

  defp maybe_enable_recursive(query, true), do: recursive_ctes(query, true)
  defp maybe_enable_recursive(query, false), do: query

  defp apply_cte_query(query, name, %Token{} = cte_token) do
    # Build the CTE query from the token
    cte_query = build(cte_token)

    # Apply the CTE using Ecto.Query.with_cte/3
    query |> with_cte(^name, as: ^cte_query)
  end

  defp apply_cte_query(query, name, %Ecto.Query{} = cte_query) do
    # Use the Ecto query directly as CTE
    query |> with_cte(^name, as: ^cte_query)
  end

  defp apply_cte_query(query, name, {:fragment, sql}) when is_binary(sql) do
    # Raw SQL fragment as CTE
    query |> with_cte(^name, as: fragment(^sql))
  end

  ## Window Functions

  # Apply a named window definition to the query
  # Windows are used with window functions like row_number(), rank(), etc.
  #
  # Note: Ecto's windows/2 macro requires compile-time literal keyword lists.
  # Dynamic window support is limited - we generate the window SQL but it must be
  # used via raw SQL fragments in select clauses.
  #
  # For full window function support, use Ecto.Query macros directly:
  #   from(p in Product,
  #     windows: [w: [partition_by: :category_id, order_by: [desc: :price]]],
  #     select: %{name: p.name, rank: over(row_number(), :w)}
  #   )
  defp apply_window(query, {name, definition}) when is_atom(name) and is_list(definition) do
    # Build the window SQL for reference (can be used in raw fragments)
    window_sql = build_window_sql(name, definition)

    # Store the window definition in query metadata via select hints
    # This allows users to reference it in raw SQL fragments
    # Note: For actual window function execution, users should use Ecto's native macros
    # or embed the window SQL directly in fragments

    # Return query unchanged - window definitions are informational
    # The generated SQL can be accessed via get_window_sql/2 for raw queries
    query
    |> put_private_window(name, window_sql)
  end

  # Store window SQL in query's prefix (a safe place for metadata)
  # This is a workaround since Ecto.Query doesn't have a general metadata field
  defp put_private_window(query, _name, _sql) do
    # We can't modify Ecto.Query struct directly with arbitrary keys
    # Instead, return the query unchanged - the window definitions live in the Token
    # Users who need window functions should use Ecto's native windows or raw fragments
    query
  end

  @doc """
  Generate window SQL clause string from a definition.

  This can be used to construct raw SQL queries with window functions.

  ## Example

      window_sql = Builder.get_window_sql(:my_window, [
        partition_by: :category_id,
        order_by: [desc: :price],
        frame: {:rows, :unbounded_preceding, :current_row}
      ])
      # => "WINDOW my_window AS (PARTITION BY category_id ORDER BY price DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)"
  """
  @spec get_window_sql(atom(), keyword()) :: String.t()
  def get_window_sql(name, definition) when is_atom(name) and is_list(definition) do
    build_window_sql(name, definition)
  end

  defp build_window_sql(name, definition) do
    window_body =
      []
      |> maybe_add_partition(definition[:partition_by])
      |> maybe_add_order(definition[:order_by])
      |> maybe_add_frame(definition[:frame])
      |> Enum.reverse()
      |> Enum.join(" ")

    "WINDOW #{name} AS (#{window_body})"
  end

  # Partition by clause helpers
  defp maybe_add_partition(parts, nil), do: parts
  defp maybe_add_partition(parts, field) when is_atom(field), do: ["PARTITION BY #{field}" | parts]

  defp maybe_add_partition(parts, fields) when is_list(fields) do
    field_str = Enum.map_join(fields, ", ", &Atom.to_string/1)
    ["PARTITION BY #{field_str}" | parts]
  end

  # Order by clause helpers
  defp maybe_add_order(parts, nil), do: parts
  defp maybe_add_order(parts, field) when is_atom(field), do: ["ORDER BY #{field} ASC" | parts]

  defp maybe_add_order(parts, orders) when is_list(orders) do
    order_str = Enum.map_join(orders, ", ", &format_order_clause/1)
    ["ORDER BY #{order_str}" | parts]
  end

  defp format_order_clause({dir, field}) when dir in [:asc, :desc] do
    "#{field} #{String.upcase(Atom.to_string(dir))}"
  end

  defp format_order_clause({field, dir}) when dir in [:asc, :desc] do
    "#{field} #{String.upcase(Atom.to_string(dir))}"
  end

  defp format_order_clause(field) when is_atom(field), do: "#{field} ASC"

  # Frame clause helper
  defp maybe_add_frame(parts, nil), do: parts
  defp maybe_add_frame(parts, frame_spec), do: [build_frame_sql(frame_spec) | parts]

  # Build SQL for window frame specification
  # Supports ROWS, RANGE, and GROUPS frame types
  #
  # Examples:
  #   {:rows, :unbounded_preceding, :current_row}
  #   {:range, {:preceding, 1}, {:following, 1}}
  #   {:groups, :current_row, :unbounded_following}
  defp build_frame_sql({frame_type, start_bound, end_bound})
       when frame_type in [:rows, :range, :groups] do
    type_str = frame_type |> Atom.to_string() |> String.upcase()
    start_str = build_frame_bound(start_bound)
    end_str = build_frame_bound(end_bound)
    "#{type_str} BETWEEN #{start_str} AND #{end_str}"
  end

  # Shorthand: just start bound (implies CURRENT ROW as end for ROWS/RANGE)
  defp build_frame_sql({frame_type, start_bound})
       when frame_type in [:rows, :range, :groups] do
    type_str = frame_type |> Atom.to_string() |> String.upcase()
    start_str = build_frame_bound(start_bound)
    "#{type_str} #{start_str}"
  end

  # Frame bound specifications
  defp build_frame_bound(:unbounded_preceding), do: "UNBOUNDED PRECEDING"
  defp build_frame_bound(:unbounded_following), do: "UNBOUNDED FOLLOWING"
  defp build_frame_bound(:current_row), do: "CURRENT ROW"
  defp build_frame_bound({:preceding, n}) when is_integer(n), do: "#{n} PRECEDING"
  defp build_frame_bound({:following, n}) when is_integer(n), do: "#{n} FOLLOWING"

  @doc """
  Build a window function expression for use in select.

  Window functions return values computed across a set of rows related
  to the current row. The window is defined using `Query.window/3` and
  referenced by name in the select clause.

  ## Usage

  In select maps, use `{:window, func, over: :window_name}`:

      select(%{
        rank: {:window, :row_number, over: :w},
        running_total: {:window, {:sum, :amount}, over: :w}
      })

  ## Supported Functions

  - `:row_number` - Sequential row number
  - `:rank` - Rank with gaps for ties
  - `:dense_rank` - Rank without gaps
  - `{:sum, field}` - Sum of field over window
  - `{:avg, field}` - Average of field over window
  - `{:count, field}` - Count of field over window
  - `{:count}` - Count of all rows over window
  - `{:min, field}` - Minimum value over window
  - `{:max, field}` - Maximum value over window
  - `{:lag, field}` - Value from previous row
  - `{:lead, field}` - Value from next row
  - `{:first_value, field}` - First value in window frame
  - `{:last_value, field}` - Last value in window frame
  """
  def build_window_select_expr(func, window_name) when is_atom(window_name) do
    # Build the complete window function SQL using the window name reference
    # Since Ecto doesn't support dynamic window references, we use the
    # inline OVER clause syntax instead of named windows
    raise ArgumentError, """
    Dynamic window function references are not supported by Ecto's compile-time macros.

    For window functions, use one of these approaches:

    1. Use raw SQL with raw_where or raw select fragments:

       select(%{
         rank: fragment("ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price DESC)")
       })

    2. Build the query directly with Ecto.Query macros:

       from(p in Product,
         windows: [w: [partition_by: :category_id, order_by: [desc: :price]]],
         select: %{name: p.name, rank: over(row_number(), :w)}
       )

    Window function: #{inspect(func)}
    Window name: #{inspect(window_name)}
    """
  end

  ## Raw WHERE

  # New format with opts (positional params list)
  defp apply_raw_where(query, {sql, params, _opts}) when is_binary(sql) and is_list(params) do
    # Build fragment with positional parameters directly
    fragment_expr = build_fragment(sql, params)

    # Apply the where clause
    from(q in query, where: ^fragment_expr)
  end

  # Legacy format with named params map
  defp apply_raw_where(query, {sql, params}) when is_binary(sql) and is_map(params) do
    # Convert named parameters to positional
    {positional_sql, positional_params} = convert_named_params_to_positional(sql, params)

    # Build fragment with positional parameters
    fragment_expr = build_fragment(positional_sql, positional_params)

    # Apply the where clause
    from(q in query, where: ^fragment_expr)
  end

  # Legacy format with positional params list (no opts)
  defp apply_raw_where(query, {sql, params}) when is_binary(sql) and is_list(params) do
    fragment_expr = build_fragment(sql, params)
    from(q in query, where: ^fragment_expr)
  end

  # Convert named parameters (:name) to positional (?)
  defp convert_named_params_to_positional(sql, params) do
    # Find all named parameters in order they appear
    param_names =
      Regex.scan(~r/:(\w+)/, sql)
      |> Enum.map(fn [_full, name] -> String.to_atom(name) end)

    # Replace named params with ?
    positional_sql = Regex.replace(~r/:(\w+)/, sql, "?")

    # Build positional params list in order
    positional_params = Enum.map(param_names, &Map.get(params, &1))

    {positional_sql, positional_params}
  end

  # Build a fragment dynamically with list of parameters
  # Note: SQL string must be passed as literal for security.
  # We use Code.eval_quoted to build the fragment at runtime
  defp build_fragment(sql, params) do
    # Build the fragment AST with the literal SQL and parameter list
    # Since fragment/1 is a macro, we need to construct the call properly
    param_asts = Enum.map(params, fn param -> quote do: ^unquote(Macro.escape(param)) end)

    fragment_ast =
      case param_asts do
        [] ->
          quote do: fragment(unquote(sql))

        [p1] ->
          quote do: fragment(unquote(sql), unquote(p1))

        [p1, p2] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2))

        [p1, p2, p3] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2), unquote(p3))

        [p1, p2, p3, p4] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2), unquote(p3), unquote(p4))

        [p1, p2, p3, p4, p5] ->
          quote do:
                  fragment(
                    unquote(sql),
                    unquote(p1),
                    unquote(p2),
                    unquote(p3),
                    unquote(p4),
                    unquote(p5)
                  )

        _ ->
          raise ArgumentError,
                "raw_where supports maximum 5 parameters, got #{length(params)}. " <>
                  "Consider using multiple where clauses or a custom fragment."
      end

    # Evaluate the AST to get the actual dynamic expression
    quoted =
      quote do
        Ecto.Query.dynamic([], unquote(fragment_ast))
      end

    {result, _} = Code.eval_quoted(quoted, [], __ENV__)
    result
  end
end
