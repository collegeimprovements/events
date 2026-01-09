defmodule OmQuery.Result do
  @moduledoc """
  Structured result format for query executions.

  This module provides a consistent interface for query results, including:
  - The fetched data
  - Pagination information (offset or cursor-based)
  - Query metadata (timing, caching, SQL)

  ## Usage

  Query results are automatically wrapped in this struct when using
  `OmQuery.execute/2` with structured result format:

      {:ok, result} = User
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.paginate(:offset, limit: 20)
        |> OmQuery.execute(format: :result)

      # Access data
      users = result.data

      # Check pagination
      if result.pagination.has_more do
        # Fetch next page
        next_offset = result.pagination.next_offset
      end

      # Inspect query metadata
      IO.puts("Query took \#{result.metadata.query_time_μs}μs")

  ## Pagination Types

  ### Offset Pagination

      result.pagination.type          # :offset
      result.pagination.limit         # 20
      result.pagination.offset        # 0
      result.pagination.current_page  # 1
      result.pagination.total_pages   # 5 (if total_count provided)
      result.pagination.has_more      # true
      result.pagination.has_previous  # false
      result.pagination.next_offset   # 20
      result.pagination.prev_offset   # nil

  ### Cursor Pagination

      result.pagination.type          # :cursor
      result.pagination.limit         # 20
      result.pagination.has_more      # true
      result.pagination.start_cursor  # "eyJpZCI6..." (first item)
      result.pagination.end_cursor    # "eyJpZCI6..." (last item)
      result.pagination.cursor_fields # [:created_at, :id]

  ## Metadata

  The metadata field contains query execution information:

      result.metadata.query_time_μs        # Database query time in microseconds
      result.metadata.total_time_μs        # Total execution time including processing
      result.metadata.cached               # Whether result came from cache
      result.metadata.cache_key            # Cache key if applicable
      result.metadata.sql                  # Generated SQL (if debug enabled)
      result.metadata.operation_count      # Number of operations in the query
      result.metadata.optimizations_applied # List of optimizations applied

  ## Creating Results

  While results are typically created automatically, you can create them
  manually for testing or custom scenarios:

      result = OmQuery.Result.success(
        users,
        limit: 20,
        offset: 0,
        pagination_type: :offset,
        has_more: true,
        query_time_μs: 1500
      )
  """

  @type pagination :: %{
          type: :offset | :cursor | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          total_count: non_neg_integer() | nil,
          has_more: boolean(),
          has_previous: boolean(),
          # Offset pagination
          current_page: pos_integer() | nil,
          total_pages: pos_integer() | nil,
          next_offset: non_neg_integer() | nil,
          prev_offset: non_neg_integer() | nil,
          # Cursor pagination
          cursor_fields: list() | nil,
          start_cursor: String.t() | nil,
          end_cursor: String.t() | nil,
          after_cursor: String.t() | nil,
          before_cursor: String.t() | nil
        }

  @type metadata :: %{
          query_time_μs: non_neg_integer(),
          total_time_μs: non_neg_integer(),
          cached: boolean(),
          cache_key: String.t() | nil,
          sql: String.t() | nil,
          operation_count: non_neg_integer(),
          optimizations_applied: list()
        }

  @type t :: %__MODULE__{
          data: term(),
          pagination: pagination(),
          metadata: metadata()
        }

  defstruct data: nil,
            pagination: %{
              type: nil,
              limit: nil,
              offset: nil,
              total_count: nil,
              has_more: false,
              has_previous: false,
              current_page: nil,
              total_pages: nil,
              next_offset: nil,
              prev_offset: nil,
              cursor_fields: nil,
              start_cursor: nil,
              end_cursor: nil,
              after_cursor: nil,
              before_cursor: nil
            },
            metadata: %{
              query_time_μs: 0,
              total_time_μs: 0,
              cached: false,
              cache_key: nil,
              sql: nil,
              operation_count: 0,
              optimizations_applied: []
            }

  @doc "Create a successful result"
  @spec success(term(), keyword()) :: t()
  def success(data, opts \\ []) do
    %__MODULE__{
      data: data,
      pagination: build_pagination(opts),
      metadata: build_metadata(opts)
    }
  end

  @doc "Create a paginated result"
  @spec paginated(list(), keyword()) :: t()
  def paginated(data, opts) when is_list(data) do
    pagination = build_pagination_with_data(data, opts)
    metadata = build_metadata(opts)

    %__MODULE__{
      data: data,
      pagination: pagination,
      metadata: metadata
    }
  end

  # Build pagination metadata
  defp build_pagination(opts) do
    %{
      type: opts[:pagination_type],
      limit: opts[:limit],
      offset: opts[:offset],
      total_count: opts[:total_count],
      has_more: opts[:has_more] || false,
      has_previous: opts[:has_previous] || false,
      current_page: opts[:current_page],
      total_pages: opts[:total_pages],
      next_offset: opts[:next_offset],
      prev_offset: opts[:prev_offset],
      cursor_fields: opts[:cursor_fields],
      start_cursor: opts[:start_cursor],
      end_cursor: opts[:end_cursor],
      after_cursor: opts[:after_cursor],
      before_cursor: opts[:before_cursor]
    }
  end

  # Build pagination with data analysis
  defp build_pagination_with_data(data, opts) do
    base = build_pagination(opts)
    type = opts[:pagination_type]

    case type do
      :offset -> build_offset_pagination(data, base, opts)
      :cursor -> build_cursor_pagination(data, base, opts)
      _ -> base
    end
  end

  # Build offset pagination metadata
  defp build_offset_pagination(data, base, opts) do
    limit = opts[:limit] || length(data)
    offset = opts[:offset] || 0
    total_count = opts[:total_count]

    has_more = length(data) >= limit
    has_previous = offset > 0

    Map.merge(base, %{
      has_more: has_more,
      has_previous: has_previous,
      current_page: compute_current_page(offset, limit),
      total_pages: compute_total_pages(total_count, limit),
      next_offset: compute_next_offset(has_more, offset, limit),
      prev_offset: compute_prev_offset(has_previous, offset, limit)
    })
  end

  defp compute_current_page(_offset, limit) when limit <= 0, do: 1
  defp compute_current_page(offset, limit), do: div(offset, limit) + 1

  defp compute_total_pages(nil, _limit), do: nil
  defp compute_total_pages(_total_count, limit) when limit <= 0, do: nil
  defp compute_total_pages(total_count, limit), do: ceil(total_count / limit)

  defp compute_next_offset(false, _offset, _limit), do: nil
  defp compute_next_offset(true, offset, limit), do: offset + limit

  defp compute_prev_offset(false, _offset, _limit), do: nil
  defp compute_prev_offset(true, offset, limit), do: max(0, offset - limit)

  # Build cursor pagination metadata
  defp build_cursor_pagination(data, base, opts) do
    cursor_fields = opts[:cursor_fields] || []
    limit = opts[:limit]

    {start_cursor, end_cursor} = compute_cursors(data, cursor_fields)

    Map.merge(base, %{
      has_more: compute_cursor_has_more(data, limit),
      start_cursor: start_cursor,
      end_cursor: end_cursor
    })
  end

  defp compute_cursor_has_more(_data, nil), do: false
  defp compute_cursor_has_more(data, limit), do: length(data) >= limit

  defp compute_cursors([], _cursor_fields), do: {nil, nil}

  defp compute_cursors(data, cursor_fields) do
    OmQuery.Cursor.from_records(data, cursor_fields, format: :binary)
  end

  @doc """
  Encode a cursor from a record and cursor fields.

  This is the public API for encoding cursors, useful for testing
  and manual cursor generation. Uses binary encoding by default
  for compact representation.

  For JSON encoding (API-friendly), use `OmQuery.Cursor.encode/3` directly.

  ## Parameters

  - `record` - A map or struct containing the cursor field values
  - `fields` - List of field names or `{field, direction}` tuples

  ## Examples

      # Simple cursor
      cursor = encode_cursor(%{id: 123}, [:id])

      # Multi-field cursor
      cursor = encode_cursor(
        %{created_at: ~U[2024-01-01 00:00:00Z], id: 123},
        [{:created_at, :desc}, {:id, :asc}]
      )

      # Use in tests
      token = OmQuery.new(User)
        |> OmQuery.paginate(:cursor, after: cursor, limit: 10)

      # For JSON encoding (API use)
      cursor = OmQuery.Cursor.encode(record, fields, format: :json)
  """
  @spec encode_cursor(map() | nil, [atom() | {atom(), :asc | :desc}]) :: String.t() | nil
  def encode_cursor(nil, _fields), do: nil

  def encode_cursor(record, fields) when is_map(record) do
    OmQuery.Cursor.encode(record, fields, format: :binary)
  end

  # Build query metadata
  defp build_metadata(opts) do
    %{
      query_time_μs: opts[:query_time_μs] || 0,
      total_time_μs: opts[:total_time_μs] || 0,
      cached: opts[:cached] || false,
      cache_key: opts[:cache_key],
      sql: opts[:sql],
      operation_count: opts[:operation_count] || 0,
      optimizations_applied: opts[:optimizations_applied] || []
    }
  end
end
