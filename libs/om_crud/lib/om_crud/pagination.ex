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

  ## Cursor Format

  Cursors are Base64-encoded JSON containing the values of the cursor fields:

      %{"inserted_at" => "2024-01-15T...", "id" => "uuid-here"}

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

    # If we fetched an extra record to check has_more, trim it
    {records, has_more} =
      if fetched_extra and length(records) > limit do
        {Enum.take(records, limit), true}
      else
        {records, length(records) >= limit}
      end

    first_record = List.first(records)
    last_record = List.last(records)

    %__MODULE__{
      type: :cursor,
      has_more: has_more,
      has_previous: has_previous,
      start_cursor: encode_cursor(first_record, cursor_fields),
      end_cursor: encode_cursor(last_record, cursor_fields),
      limit: limit
    }
  end

  @doc """
  Encode a cursor from a record and cursor fields.

  ## Examples

      iex> OmCrud.Pagination.encode_cursor(user, [:inserted_at, :id])
      "eyJpbnNlcnRlZF9hdCI6IjIwMjQtMDEtMTVUMTI6MDA6MDBaIiwiaWQiOiJ1dWlkIn0="
  """
  @spec encode_cursor(struct() | nil, [atom()]) :: String.t() | nil
  def encode_cursor(nil, _cursor_fields), do: nil

  def encode_cursor(record, cursor_fields) when is_struct(record) do
    cursor_data =
      cursor_fields
      |> Enum.map(fn field ->
        value = Map.get(record, field)
        {Atom.to_string(field), encode_cursor_value(value)}
      end)
      |> Map.new()

    cursor_data
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decode a cursor back to field values.

  ## Examples

      iex> OmCrud.Pagination.decode_cursor("eyJp...")
      {:ok, %{"inserted_at" => "2024-01-15T12:00:00Z", "id" => "uuid"}}

      iex> OmCrud.Pagination.decode_cursor("invalid")
      {:error, :invalid_cursor}
  """
  @spec decode_cursor(String.t() | nil) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_cursor(nil), do: {:ok, %{}}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, data} <- JSON.decode(json) do
      {:ok, data}
    else
      _ -> {:error, :invalid_cursor}
    end
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

  # Private helpers

  defp encode_cursor_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_cursor_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp encode_cursor_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_cursor_value(%Time{} = t), do: Time.to_iso8601(t)
  defp encode_cursor_value(value) when is_binary(value), do: value
  defp encode_cursor_value(value) when is_number(value), do: value
  defp encode_cursor_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_cursor_value(value), do: to_string(value)
end
