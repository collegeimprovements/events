defmodule Events.Core.Query.Builder.Pagination do
  @moduledoc false
  # Internal module for Builder - handles cursor and offset pagination

  import Ecto.Query
  alias Events.Core.Query.Token
  alias Events.Core.Query.Builder.Cursor

  ## Public API (for Builder)

  @doc """
  Apply pagination to a query.

  Supports both offset and cursor-based pagination.
  """
  @spec apply(Ecto.Query.t(), {:offset, keyword()} | {:cursor, keyword()}) :: Ecto.Query.t()
  def apply(query, {:offset, opts}) do
    limit = opts[:limit] || Token.default_limit()
    offset = opts[:offset] || 0

    query
    |> from(limit: ^limit)
    |> maybe_apply_offset(offset)
  end

  def apply(query, {:cursor, opts}) do
    limit = opts[:limit] || Token.default_limit()
    cursor_fields = opts[:cursor_fields] || []
    after_cursor = opts[:after]
    before_cursor = opts[:before]

    query
    |> Cursor.apply_ordering(cursor_fields)
    |> Cursor.apply_filter(after_cursor, before_cursor, cursor_fields)
    |> from(limit: ^limit)
  end

  ## Private Helpers

  defp maybe_apply_offset(query, 0), do: query
  defp maybe_apply_offset(query, offset), do: from(q in query, offset: ^offset)
end
