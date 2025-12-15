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
  alias Events.Core.Query.Builder.Pagination
  alias Events.Core.Query.Builder.Cursor
  alias Events.Core.Query.Builder.Search
  alias Events.Core.Query.Builder.Joins
  alias Events.Core.Query.Builder.Selects
  alias Events.Core.Query.Builder.Advanced

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
  defp apply_operation({:paginate, spec}, query), do: Pagination.apply(query, spec)
  defp apply_operation({:order, spec}, query), do: Advanced.apply_order(query, spec)
  defp apply_operation({:join, spec}, query), do: Joins.apply(query, spec)
  defp apply_operation({:preload, spec}, query), do: Selects.apply_preload(query, spec)
  defp apply_operation({:select, spec}, query), do: Selects.apply_select(query, spec)
  defp apply_operation({:group_by, spec}, query), do: Selects.apply_group_by(query, spec)
  defp apply_operation({:having, spec}, query), do: Selects.apply_having(query, spec)
  defp apply_operation({:limit, value}, query), do: from(q in query, limit: ^value)
  defp apply_operation({:offset, value}, query), do: from(q in query, offset: ^value)
  defp apply_operation({:distinct, spec}, query), do: Selects.apply_distinct(query, spec)
  defp apply_operation({:lock, mode}, query), do: Advanced.apply_lock(query, mode)
  defp apply_operation({:cte, spec}, query), do: Advanced.apply_cte(query, spec)
  defp apply_operation({:window, spec}, query), do: Advanced.apply_window(query, spec)
  defp apply_operation({:raw_where, spec}, query), do: Advanced.apply_raw_where(query, spec)
  defp apply_operation({:exists, spec}, query), do: Filters.apply_exists(query, spec, true)
  defp apply_operation({:not_exists, spec}, query), do: Filters.apply_exists(query, spec, false)
  defp apply_operation({:search_rank, spec}, query), do: Search.apply_rank(query, spec)

  defp apply_operation({:search_rank_limited, spec}, query),
    do: Search.apply_rank_limited(query, spec)

  defp apply_operation({:field_compare, spec}, query), do: Filters.apply_field_compare(query, spec)

  ## Public Cursor API (delegated to Cursor module)

  defdelegate decode_cursor(encoded), to: Cursor
  defdelegate cursor_field(field_spec), to: Cursor
  defdelegate cursor_direction(field_spec), to: Cursor
  defdelegate normalize_cursor_fields(fields), to: Cursor

  ## Public Window API (delegated to Advanced module)

  defdelegate get_window_sql(name, definition), to: Advanced
  defdelegate build_window_select_expr(func, window_name), to: Advanced

end
