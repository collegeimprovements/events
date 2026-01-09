defmodule OmCrud.Pagination do
  @moduledoc """
  Pagination metadata for cursor-based pagination.

  This struct contains information about the current page position
  and available navigation options.

  ## Structure

      %OmCrud.Pagination{
        type: :cursor,
        has_more: true,
        has_previous: false,
        start_cursor: "eyJpbnNlcnRlZF9hdCI6...",
        end_cursor: "eyJpbnNlcnRlZF9hdCI6...",
        limit: 20
      }

  ## Cursor Encoding

  By default, uses JSON encoding for API compatibility. Can be configured
  to use binary encoding for better performance:

      # In config.exs
      config :om_crud, :pagination,
        cursor_format: :binary  # or :json (default)

  ## Navigation

      # Forward pagination
      list_users(after: pagination.end_cursor)

      # Backward pagination
      list_users(before: pagination.start_cursor)

  ## Pagination Types

  - `:cursor` - Cursor-based pagination (default, recommended)
  - `:offset` - Offset-based pagination (for legacy support)
  """

  @type pagination_type :: :cursor | :offset

  @type t :: %__MODULE__{
          type: pagination_type(),
          has_more: boolean(),
          has_previous: boolean(),
          start_cursor: String.t() | nil,
          end_cursor: String.t() | nil,
          limit: pos_integer()
        }

  defstruct [
    :type,
    :has_more,
    :has_previous,
    :start_cursor,
    :end_cursor,
    :limit
  ]

  # Default to JSON for backwards compatibility with existing APIs
  @default_cursor_format Application.compile_env(:om_crud, [:pagination, :cursor_format], :json)

  @doc """
  Create a new cursor pagination struct.

  ## Options

  - `:has_more` - Whether there are more results after (required)
  - `:has_previous` - Whether there are results before (default: false)
  - `:start_cursor` - Cursor for the first item in results
  - `:end_cursor` - Cursor for the last item in results
  - `:limit` - Page size used (required)

  ## Examples

      iex> OmCrud.Pagination.cursor(
      ...>   has_more: true,
      ...>   has_previous: false,
      ...>   start_cursor: "abc",
      ...>   end_cursor: "xyz",
      ...>   limit: 20
      ...> )
      %OmCrud.Pagination{type: :cursor, ...}
  """
  @spec cursor(keyword()) :: t()
  def cursor(opts) when is_list(opts) do
    %__MODULE__{
      type: :cursor,
      has_more: Keyword.fetch!(opts, :has_more),
      has_previous: Keyword.get(opts, :has_previous, false),
      start_cursor: Keyword.get(opts, :start_cursor),
      end_cursor: Keyword.get(opts, :end_cursor),
      limit: Keyword.fetch!(opts, :limit)
    }
  end

  @doc """
  Create pagination from a list of records and cursor fields.

  This is a convenience function that builds pagination metadata
  from actual query results.

  ## Arguments

  - `records` - The list of records returned
  - `cursor_fields` - Fields used for cursor (e.g., `[:inserted_at, :id]`)
  - `limit` - The requested limit
  - `opts` - Additional options

  ## Options

  - `:has_previous` - Whether there are previous results
  - `:fetched_extra` - If an extra record was fetched to check has_more
  - `:cursor_format` - `:json` (default) or `:binary`

  ## Examples

      iex> OmCrud.Pagination.from_records(users, [:inserted_at, :id], 20)
      %OmCrud.Pagination{...}
  """
  @spec from_records([struct()], [atom()], pos_integer(), keyword()) :: t()
  def from_records(records, cursor_fields, limit, opts \\ [])

  def from_records([], _cursor_fields, limit, opts) do
    %__MODULE__{
      type: :cursor,
      has_more: false,
      has_previous: Keyword.get(opts, :has_previous, false),
      start_cursor: nil,
      end_cursor: nil,
      limit: limit
    }
  end

  def from_records(records, cursor_fields, limit, opts) when is_list(records) do
    fetched_extra = Keyword.get(opts, :fetched_extra, false)
    has_previous = Keyword.get(opts, :has_previous, false)
    cursor_format = Keyword.get(opts, :cursor_format, @default_cursor_format)

    record_count = length(records)
    {records, has_more} = trim_records(records, record_count, limit, fetched_extra)

    first_record = List.first(records)
    last_record = List.last(records)

    %__MODULE__{
      type: :cursor,
      has_more: has_more,
      has_previous: has_previous,
      start_cursor: encode_cursor(first_record, cursor_fields, cursor_format),
      end_cursor: encode_cursor(last_record, cursor_fields, cursor_format),
      limit: limit
    }
  end

  defp trim_records(records, count, limit, true) when count > limit do
    {Enum.take(records, limit), true}
  end

  defp trim_records(records, count, limit, _fetched_extra) do
    {records, count >= limit}
  end

  @doc """
  Encode a cursor from a record and cursor fields.

  ## Options

  - `:format` - `:json` (default) or `:binary`

  ## Examples

      iex> OmCrud.Pagination.encode_cursor(user, [:inserted_at, :id])
      "eyJpbnNlcnRlZF9hdCI6IjIwMjQtMDEtMTVUMTI6MDA6MDBaIiwiaWQiOiJ1dWlkIn0="
  """
  @spec encode_cursor(struct() | nil, [atom()], atom()) :: String.t() | nil
  def encode_cursor(record, cursor_fields, format \\ @default_cursor_format)

  def encode_cursor(nil, _cursor_fields, _format), do: nil

  def encode_cursor(record, cursor_fields, format) when is_struct(record) do
    OmQuery.Cursor.encode(record, cursor_fields, format: format)
  end

  @doc """
  Decode a cursor back to field values.

  Automatically detects the encoding format.

  ## Examples

      iex> OmCrud.Pagination.decode_cursor("eyJp...")
      {:ok, %{inserted_at: "2024-01-15T12:00:00Z", id: "uuid"}}

      iex> OmCrud.Pagination.decode_cursor("invalid")
      {:error, :invalid_cursor}
  """
  @spec decode_cursor(String.t() | nil) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_cursor(cursor) do
    OmQuery.Cursor.decode(cursor, format: :auto)
  end

  @doc """
  Convert pagination to a plain map (for JSON serialization).

  ## Examples

      iex> OmCrud.Pagination.to_map(%OmCrud.Pagination{...})
      %{type: "cursor", has_more: true, ...}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = pagination) do
    %{
      type: Atom.to_string(pagination.type),
      has_more: pagination.has_more,
      has_previous: pagination.has_previous,
      start_cursor: pagination.start_cursor,
      end_cursor: pagination.end_cursor,
      limit: pagination.limit
    }
  end

  @doc """
  Get the configured default cursor format.

  Returns `:json` (default) or `:binary`.
  """
  @spec default_cursor_format() :: :json | :binary
  def default_cursor_format, do: @default_cursor_format
end
