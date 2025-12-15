defmodule Events.Core.Query.Builder.Search do
  @moduledoc false
  # Internal module for Builder - search ranking and similarity
  #
  # Orders results by which search field matched, with lower rank = higher priority.
  # For similarity modes, also uses similarity score as secondary sort.

  import Ecto.Query

  ## Public API (for Builder)

  @doc """
  Apply search ranking to a query.

  Orders results by rank (lower = higher priority) with optional similarity scoring.
  """
  @spec apply_rank(Ecto.Query.t(), {list(), String.t()}) :: Ecto.Query.t()
  def apply_rank(query, {parsed_fields, term}) do
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

  @doc """
  Apply search ranking with per-field limits.

  Results are ordered by rank with a total limit equal to the sum of all take values.
  For exact per-rank enforcement, consider using multiple queries or raw SQL.
  """
  @spec apply_rank_limited(Ecto.Query.t(), {list(), String.t()}) :: Ecto.Query.t()
  def apply_rank_limited(query, {parsed_fields, term}) do
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

  ## Private Helpers

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
end
