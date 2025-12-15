defmodule Events.Core.Query.Api.Filtering do
  @moduledoc false
  # Internal module for Query - filtering operations
  #
  # Handles all filter-related operations including:
  # - Basic filters (filter, where)
  # - Filter groups (where_any, where_all, where_none, where_not)
  # - Field comparisons (where_field)
  # - Join filters (on, maybe_on)
  # - Conditional filters (maybe)
  # - Raw SQL filters (raw)

  alias Events.Core.Query.{Token, Cast, Predicates}

  @doc """
  Add a filter condition with optional type casting.

  This is the primary filtering function. Use `filter/5` as a semantic alias.
  """
  @spec where(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def where(token, field, op, value, opts \\ []) do
    {cast_type, filter_opts} = Keyword.pop(opts, :cast)
    casted_value = Cast.cast(value, cast_type)
    Token.add_operation(token, {:filter, {field, op, casted_value, filter_opts}})
  end

  @doc """
  Alias for `where/5`. Semantic alternative name.

  ## Shorthand Syntax

  When operator is `:eq`, you can omit it:

      # These are equivalent:
      Query.filter(token, :status, :eq, "active")
      Query.filter(token, :status, "active")

  For keyword-based equality filters:

      # These are equivalent:
      token
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:verified, :eq, true)

      Query.filter(token, status: "active", verified: true)
  """
  @spec filter(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def filter(token, field, op, value, opts \\ []) do
    where(token, field, op, value, opts)
  end

  @doc """
  Shorthand filter for equality (`:eq` operator).

  ## Examples

      # These are equivalent:
      Query.filter(token, :status, :eq, "active")
      Query.filter(token, :status, "active")
  """
  @spec filter(Token.t(), atom(), term()) :: Token.t()
  def filter(token, field, value) when is_atom(field) do
    where(token, field, :eq, value, [])
  end

  @doc """
  Filter with keyword list for multiple equality conditions.

  ## Examples

      # These are equivalent:
      token
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:verified, :eq, true)
      |> Query.filter(:role, :eq, "admin")

      Query.filter(token, status: "active", verified: true, role: "admin")
  """
  @spec filter(Token.t(), keyword()) :: Token.t()
  def filter(token, filters) when is_list(filters) and length(filters) > 0 do
    Enum.reduce(filters, token, fn {field, value}, acc ->
      Token.add_operation(acc, {:filter, {field, :eq, value, []}})
    end)
  end

  @doc """
  Filter on a joined table using its binding name.

  This is a shorthand for `filter/5` with the `binding:` option.
  """
  @spec on(Token.t(), atom(), atom(), term()) :: Token.t()
  def on(token, binding, field, value) when is_atom(binding) and is_atom(field) do
    Token.add_operation(token, {:filter, {field, :eq, value, [binding: binding]}})
  end

  @doc """
  Filter on a joined table with explicit operator.
  """
  @spec on(Token.t(), atom(), atom(), atom(), term()) :: Token.t()
  def on(token, binding, field, op, value)
      when is_atom(binding) and is_atom(field) and is_atom(op) do
    Token.add_operation(token, {:filter, {field, op, value, [binding: binding]}})
  end

  @doc """
  Conditionally apply a filter only if the value is truthy.

  This is extremely useful when building queries from optional parameters.
  If value is `nil`, `false`, or empty string, the filter is skipped entirely.
  """
  @spec maybe(Token.t(), atom(), term()) :: Token.t()
  def maybe(token, field, value) do
    maybe(token, field, value, :eq, [])
  end

  @spec maybe(Token.t(), atom(), term(), atom()) :: Token.t()
  def maybe(token, field, value, op) when is_atom(op) and op not in [:when] do
    maybe(token, field, value, op, [])
  end

  @spec maybe(Token.t(), atom(), term(), keyword()) :: Token.t()
  def maybe(token, field, value, opts) when is_list(opts) do
    maybe(token, field, value, :eq, opts)
  end

  @spec maybe(Token.t(), atom(), term(), atom(), keyword()) :: Token.t()
  def maybe(token, field, value, op, opts) when is_atom(op) do
    {predicate, filter_opts} = Keyword.pop(opts, :when, :present)

    if Predicates.check(predicate, value) do
      where(token, field, op, value, filter_opts)
    else
      token
    end
  end

  @doc """
  Conditionally apply a filter on a joined table.

  Like `maybe/4` but for joined tables using their binding name.
  Supports the same `:when` option for custom predicates.
  """
  @spec maybe_on(Token.t(), atom(), atom(), term()) :: Token.t()
  def maybe_on(token, binding, field, value) do
    maybe_on(token, binding, field, value, :eq, [])
  end

  @spec maybe_on(Token.t(), atom(), atom(), term(), atom()) :: Token.t()
  def maybe_on(token, binding, field, value, op) when is_atom(op) do
    maybe_on(token, binding, field, value, op, [])
  end

  @spec maybe_on(Token.t(), atom(), atom(), term(), atom(), keyword()) :: Token.t()
  def maybe_on(token, binding, field, value, op, opts)
      when is_atom(binding) and is_atom(op) do
    {predicate, filter_opts} = Keyword.pop(opts, :when, :present)

    if Predicates.check(predicate, value) do
      full_opts = Keyword.put(filter_opts, :binding, binding)
      where(token, field, op, value, full_opts)
    else
      token
    end
  end

  @doc """
  Add an OR filter group - matches if ANY condition is true.
  """
  @spec where_any(Token.t(), list(), keyword()) :: Token.t()
  def where_any(token, filter_list, opts \\ [])

  def where_any(token, filter_list, opts)
      when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:or, normalized}})
  end

  @doc """
  Add an AND filter group - matches only if ALL conditions are true.
  """
  @spec where_all(Token.t(), list(), keyword()) :: Token.t()
  def where_all(token, filter_list, opts \\ [])

  def where_all(token, filter_list, opts)
      when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:and, normalized}})
  end

  @doc """
  Add a NONE filter group - matches if NONE of the conditions are true.
  """
  @spec where_none(Token.t(), list(), keyword()) :: Token.t()
  def where_none(token, filter_list, opts \\ [])

  def where_none(token, filter_list, opts)
      when is_list(filter_list) and length(filter_list) >= 2 do
    normalized = normalize_filter_specs(filter_list, opts)
    Token.add_operation(token, {:filter_group, {:not_or, normalized}})
  end

  @doc """
  Add a negated filter condition.

  Inverts the operator to create the opposite condition.
  """
  @spec where_not(Token.t(), atom(), atom(), term(), keyword()) :: Token.t()
  def where_not(token, field, op, value, opts \\ []) do
    negated_op = negate_operator(op)
    where(token, field, negated_op, value, opts)
  end

  # Private helpers

  defp normalize_filter_specs(filter_list, global_opts) do
    Enum.map(filter_list, fn spec ->
      {field, op, value, filter_opts} = normalize_filter_spec(spec)
      # Per-filter opts take precedence over global opts
      merged_opts = Keyword.merge(global_opts, filter_opts)
      {field, op, value, merged_opts}
    end)
  end

  defp normalize_filter_spec({field, op, value}), do: {field, op, value, []}
  defp normalize_filter_spec({field, op, value, opts}), do: {field, op, value, opts}

  # Operator negation mapping
  defp negate_operator(:eq), do: :neq
  defp negate_operator(:neq), do: :eq
  defp negate_operator(:gt), do: :lte
  defp negate_operator(:gte), do: :lt
  defp negate_operator(:lt), do: :gte
  defp negate_operator(:lte), do: :gt
  defp negate_operator(:in), do: :not_in
  defp negate_operator(:not_in), do: :in
  defp negate_operator(:is_nil), do: :not_nil
  defp negate_operator(:not_nil), do: :is_nil
  defp negate_operator(:like), do: :not_like
  defp negate_operator(:ilike), do: :not_ilike
  defp negate_operator(:not_like), do: :like
  defp negate_operator(:not_ilike), do: :ilike

  defp negate_operator(op) do
    raise ArgumentError, """
    Unknown operator for negation: #{inspect(op)}

    Supported operators: :eq, :neq, :gt, :gte, :lt, :lte, :in, :not_in,
    :is_nil, :not_nil, :like, :ilike, :not_like, :not_ilike
    """
  end
end
