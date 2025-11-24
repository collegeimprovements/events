defmodule Events.CRUD.Operations.Paginate do
  use Events.CRUD.Operation, type: :paginate
  import Ecto.Query

  @impl true
  def validate_spec({type, opts}) do
    cond do
      type not in [:offset, :cursor] ->
        {:error, "Pagination type must be :offset or :cursor"}

      type == :cursor and not opts[:cursor_fields] ->
        {:error, "Cursor pagination requires cursor_fields"}

      true ->
        :ok
    end
  end

  @impl true
  def execute(query, {:offset, opts}) do
    query
    |> apply_limit(opts[:limit])
    |> apply_offset(opts[:offset])
  end

  @impl true
  def execute(query, {:cursor, opts}) do
    cursor_fields = opts[:cursor_fields] || []
    direction = opts[:direction] || :forward
    cursor = opts[:cursor]

    query
    |> apply_cursor_ordering(cursor_fields)
    |> apply_cursor_filter(cursor, direction, cursor_fields)
    |> apply_limit(opts[:limit])
  end

  # Apply limit with default
  defp apply_limit(query, nil), do: query

  defp apply_limit(query, limit) do
    max_limit = Events.CRUD.Config.max_pagination_limit()
    actual_limit = min(limit || Events.CRUD.Config.default_pagination_limit(), max_limit)
    from(q in query, limit: ^actual_limit)
  end

  # Apply offset
  defp apply_offset(query, nil), do: query
  defp apply_offset(query, offset), do: from(q in query, offset: ^offset)

  # Ensure stable ordering for cursor pagination
  defp apply_cursor_ordering(query, []), do: query

  defp apply_cursor_ordering(query, cursor_fields) do
    # Add cursor field ordering to ensure stable pagination
    cursor_ordering = Enum.map(cursor_fields, fn {field, dir} -> {dir, field} end)
    # Keep existing ordering and append cursor ordering
    from(q in query, order_by: ^cursor_ordering)
  end

  # Apply cursor filter for pagination
  defp apply_cursor_filter(query, nil, _direction, _fields), do: query

  defp apply_cursor_filter(query, cursor, direction, cursor_fields) do
    # Decode cursor and build filter condition
    case decode_cursor(cursor) do
      {:ok, cursor_values} ->
        build_cursor_condition(query, cursor_values, direction, cursor_fields)

      {:error, _} ->
        # Invalid cursor, return unfiltered
        query
    end
  end

  # Build cursor condition based on direction
  defp build_cursor_condition(query, cursor_values, :forward, cursor_fields) do
    # For forward pagination: field > cursor_value (with tie-breakers)
    build_cursor_where(query, cursor_values, cursor_fields, :gt)
  end

  defp build_cursor_condition(query, cursor_values, :backward, cursor_fields) do
    # For backward pagination: field < cursor_value (with tie-breakers)
    build_cursor_where(query, cursor_values, cursor_fields, :lt)
  end

  # Build the actual WHERE condition for cursor pagination
  # Simplified implementation for single-field cursors
  defp build_cursor_where(query, [cursor_value], [{cursor_field, _dir}], operator) do
    case operator do
      :gt -> from(q in query, where: field(q, ^cursor_field) > ^cursor_value)
      :lt -> from(q in query, where: field(q, ^cursor_field) < ^cursor_value)
    end
  end

  # Multi-field cursor pagination (placeholder - needs more complex implementation)
  defp build_cursor_where(query, _cursor_values, _cursor_fields, _operator) do
    # Placeholder for multi-field cursor logic
    # This would require building complex OR conditions
    query
  end

  # Cursor encoding/decoding (simplified)
  @spec decode_cursor(String.t()) :: {:ok, map()} | {:error, term()}
  def decode_cursor(cursor_string) do
    try do
      decoded = Base.decode64!(cursor_string)
      values = Jason.decode!(decoded)
      {:ok, values}
    rescue
      _ -> {:error, :invalid_cursor}
    end
  end

  @spec encode_cursor([term()], [atom()]) :: String.t()
  def encode_cursor(values, _fields) do
    json = Jason.encode!(values)
    Base.encode64(json)
  end
end
