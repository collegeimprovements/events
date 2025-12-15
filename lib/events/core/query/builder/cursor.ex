defmodule Events.Core.Query.Builder.Cursor do
  @moduledoc false
  # Internal module for Builder - cursor pagination utilities
  #
  # Handles cursor encoding/decoding, filtering, ordering, and lexicographic comparisons
  # for cursor-based pagination.

  import Ecto.Query
  alias Events.Core.Query.CursorError

  ## Public API (for Builder and Pagination modules)

  @doc """
  Apply cursor ordering to a query based on cursor fields.
  """
  @spec apply_ordering(Ecto.Query.t(), list()) :: Ecto.Query.t()
  def apply_ordering(query, []), do: query

  def apply_ordering(query, cursor_fields) do
    order_by_expr =
      cursor_fields
      |> normalize_cursor_fields()
      |> Enum.map(fn {field, dir} -> {dir, field} end)

    from(q in query, order_by: ^order_by_expr)
  end

  @doc """
  Apply cursor filtering to a query.
  """
  @spec apply_filter(Ecto.Query.t(), String.t() | nil, String.t() | nil, list()) ::
          Ecto.Query.t()
  def apply_filter(query, nil, nil, _), do: query

  def apply_filter(query, after_cursor, _before, fields) when not is_nil(after_cursor) do
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

  def apply_filter(query, _, before_cursor, fields) when not is_nil(before_cursor) do
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

  ## Private Helpers

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
end
