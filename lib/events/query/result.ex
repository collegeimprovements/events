defmodule Events.Query.Result do
  @moduledoc false
  # Internal module - use Events.Query public API instead.
  #
  # Structured result format for all query executions.
  # Provides consistent interface with data, pagination, and metadata.

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

    current_page = if limit > 0, do: div(offset, limit) + 1, else: 1
    total_pages = if total_count && limit > 0, do: ceil(total_count / limit), else: nil

    next_offset = if has_more, do: offset + limit, else: nil
    prev_offset = if has_previous, do: max(0, offset - limit), else: nil

    Map.merge(base, %{
      has_more: has_more,
      has_previous: has_previous,
      current_page: current_page,
      total_pages: total_pages,
      next_offset: next_offset,
      prev_offset: prev_offset
    })
  end

  # Build cursor pagination metadata
  defp build_cursor_pagination(data, base, opts) do
    cursor_fields = opts[:cursor_fields] || []
    limit = opts[:limit]

    has_more = if limit, do: length(data) >= limit, else: false

    start_cursor = if length(data) > 0, do: encode_cursor(List.first(data), cursor_fields)
    end_cursor = if length(data) > 0, do: encode_cursor(List.last(data), cursor_fields)

    Map.merge(base, %{
      has_more: has_more,
      start_cursor: start_cursor,
      end_cursor: end_cursor
    })
  end

  @doc """
  Encode a cursor from a record and cursor fields.

  This is the public API for encoding cursors, useful for testing
  and manual cursor generation.

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
      token = Query.new(User)
        |> Query.paginate(:cursor, after: cursor, limit: 10)
  """
  @spec encode_cursor(map() | nil, [atom() | {atom(), :asc | :desc}]) :: String.t() | nil
  def encode_cursor(nil, _fields), do: nil

  def encode_cursor(record, fields) when is_map(record) do
    alias Events.Query.Builder

    cursor_data =
      fields
      |> Enum.map(fn spec ->
        field = Builder.cursor_field(spec)
        {field, Map.get(record, field)}
      end)
      |> Enum.into(%{})

    cursor_data
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
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
