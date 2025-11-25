defmodule Events.Query.Search do
  @moduledoc false
  # Internal module - use Events.Query.search/4 instead.
  #
  # Full-text search implementation with ranking support.

  alias Events.Query.Token

  @type field_spec :: atom() | {atom(), atom()} | {atom(), atom(), keyword()}
  @type parsed_field :: {atom(), atom(), keyword(), integer(), integer() | nil}

  # Search modes that use pg_trgm similarity
  @similarity_modes [:similarity, :word_similarity, :strict_word_similarity]

  @doc """
  Apply search across multiple fields with optional ranking.
  """
  @spec search(Token.t(), String.t() | nil, [field_spec()], keyword()) :: Token.t()
  def search(token, term, fields, opts \\ [])
  def search(%Token{} = token, nil, _fields, _opts), do: token
  def search(%Token{} = token, "", _fields, _opts), do: token

  def search(%Token{} = token, term, fields, opts) when is_binary(term) and is_list(fields) do
    defaults = %{
      mode: Keyword.get(opts, :mode, :ilike),
      threshold: Keyword.get(opts, :threshold, 0.3),
      rank: Keyword.get(opts, :rank, false)
    }

    parsed_fields = parse_fields(fields, defaults)
    search_filters = build_filters(parsed_fields, term)

    token = apply_or_filters(token, search_filters)

    if defaults.rank do
      apply_ranking(token, parsed_fields, term)
    else
      token
    end
  end

  # ===========================================================================
  # Field Parsing
  # ===========================================================================

  defp parse_fields(fields, defaults) do
    fields
    |> Enum.with_index(1)
    |> Enum.map(fn {field_spec, index} ->
      parse_field(field_spec, defaults, index)
    end)
  end

  # Simple atom: :name
  defp parse_field(field, defaults, auto_rank) when is_atom(field) do
    {field, defaults.mode, [threshold: defaults.threshold], auto_rank, nil}
  end

  # 2-tuple: {:name, :similarity}
  defp parse_field({field, mode}, defaults, auto_rank) do
    {field, mode, [threshold: defaults.threshold], auto_rank, nil}
  end

  # 3-tuple with opts: {:name, :similarity, rank: 1, threshold: 0.5}
  defp parse_field({field, mode, opts}, defaults, auto_rank) do
    rank = Keyword.get(opts, :rank, auto_rank)
    threshold = Keyword.get(opts, :threshold, defaults.threshold)
    take = Keyword.get(opts, :take)
    {field, mode, Keyword.merge(opts, threshold: threshold), rank, take}
  end

  # ===========================================================================
  # Filter Building
  # ===========================================================================

  defp build_filters(parsed_fields, term) do
    Enum.map(parsed_fields, fn {field, mode, field_opts, _rank, _take} ->
      build_filter(field, mode, term, field_opts)
    end)
  end

  defp build_filter(field, mode, term, opts) do
    binding = Keyword.get(opts, :binding)
    base_opts = if binding, do: [binding: binding], else: []

    case mode do
      :ilike ->
        pattern = pattern(term, :contains)
        filter_tuple(field, :ilike, pattern, base_opts)

      :like ->
        pattern = pattern(term, :contains)
        filter_tuple(field, :like, pattern, base_opts)

      :starts_with ->
        pattern = pattern(term, :starts_with)
        op = if Keyword.get(opts, :case_sensitive, false), do: :like, else: :ilike
        filter_tuple(field, op, pattern, base_opts)

      :ends_with ->
        pattern = pattern(term, :ends_with)
        op = if Keyword.get(opts, :case_sensitive, false), do: :like, else: :ilike
        filter_tuple(field, op, pattern, base_opts)

      :contains ->
        pattern = pattern(term, :contains)
        op = if Keyword.get(opts, :case_sensitive, false), do: :like, else: :ilike
        filter_tuple(field, op, pattern, base_opts)

      :exact ->
        filter_tuple(field, :eq, term, base_opts)

      similarity_mode when similarity_mode in @similarity_modes ->
        threshold = Keyword.get(opts, :threshold, 0.3)
        merged_opts = Keyword.merge(base_opts, threshold: threshold)
        {field, similarity_mode, term, merged_opts}

      unknown ->
        raise ArgumentError, """
        Unknown search mode: #{inspect(unknown)} for field #{inspect(field)}

        Supported modes:
          :ilike, :like, :exact, :starts_with, :ends_with, :contains,
          :similarity, :word_similarity, :strict_word_similarity
        """
    end
  end

  defp filter_tuple(field, op, value, []), do: {field, op, value}
  defp filter_tuple(field, op, value, opts), do: {field, op, value, opts}

  defp pattern(term, :contains), do: "%#{term}%"
  defp pattern(term, :starts_with), do: "#{term}%"
  defp pattern(term, :ends_with), do: "%#{term}"

  # ===========================================================================
  # OR Filter Application
  # ===========================================================================

  defp apply_or_filters(token, filters) do
    normalized = Enum.map(filters, &normalize_filter/1)
    Token.add_operation(token, {:filter_group, {:or, normalized}})
  end

  defp normalize_filter({field, op, value}), do: {field, op, value, []}
  defp normalize_filter({field, op, value, opts}), do: {field, op, value, opts}

  # ===========================================================================
  # Ranking
  # ===========================================================================

  defp apply_ranking(token, parsed_fields, term) do
    sorted_fields = Enum.sort_by(parsed_fields, fn {_, _, _, rank, _} -> rank end)
    has_take_limits = Enum.any?(sorted_fields, fn {_, _, _, _, take} -> take != nil end)

    operation =
      if has_take_limits do
        {:search_rank_limited, {sorted_fields, term}}
      else
        {:search_rank, {sorted_fields, term}}
      end

    Token.add_operation(token, operation)
  end
end
