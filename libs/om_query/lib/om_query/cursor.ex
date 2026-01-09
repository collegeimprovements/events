defmodule OmQuery.Cursor do
  @moduledoc """
  Cursor encoding and decoding utilities for pagination.

  Provides two encoding formats:
  - **Binary** (default): Compact, Elixir-native, supports complex types
  - **JSON**: Human-readable, cross-language compatible, API-friendly

  ## Choosing a Format

  | Format | Size | Readability | Cross-language | Complex Types |
  |--------|------|-------------|----------------|---------------|
  | Binary | Smaller | No | No | Yes |
  | JSON | Larger | Yes | Yes | Limited |

  Use **binary** (default) for:
  - Internal Elixir/Phoenix applications
  - Best performance
  - Complex cursor field types

  Use **JSON** for:
  - Public APIs consumed by non-Elixir clients
  - Debugging (cursors are readable)
  - Interoperability requirements

  ## Usage

      # Binary encoding (default)
      cursor = OmQuery.Cursor.encode(record, [:inserted_at, :id])
      {:ok, values} = OmQuery.Cursor.decode(cursor)

      # JSON encoding
      cursor = OmQuery.Cursor.encode(record, [:inserted_at, :id], format: :json)
      {:ok, values} = OmQuery.Cursor.decode(cursor, format: :json)

      # Auto-detect format on decode
      {:ok, values} = OmQuery.Cursor.decode(cursor, format: :auto)

  ## Cursor Fields

  Cursor fields can be atoms or `{field, direction}` tuples:

      # Simple fields
      OmQuery.Cursor.encode(record, [:inserted_at, :id])

      # With direction hints (direction is ignored for encoding)
      OmQuery.Cursor.encode(record, [{:inserted_at, :desc}, {:id, :asc}])
  """

  @type format :: :binary | :json | :auto
  @type cursor_field :: atom() | {atom(), :asc | :desc}

  # ─────────────────────────────────────────────────────────────
  # Encoding
  # ─────────────────────────────────────────────────────────────

  @doc """
  Encode a cursor from a record and cursor fields.

  ## Options

  - `:format` - Encoding format: `:binary` (default) or `:json`

  ## Examples

      # Binary (default)
      cursor = OmQuery.Cursor.encode(user, [:inserted_at, :id])
      #=> "g2wAAAACaAJkAAtp..."

      # JSON
      cursor = OmQuery.Cursor.encode(user, [:inserted_at, :id], format: :json)
      #=> "eyJpbnNlcnRlZF9hdCI6..."

      # With direction tuples (direction ignored)
      cursor = OmQuery.Cursor.encode(user, [{:inserted_at, :desc}, {:id, :asc}])
  """
  @spec encode(map() | struct() | nil, [cursor_field()], keyword()) :: String.t() | nil
  def encode(record, fields, opts \\ [])

  def encode(nil, _fields, _opts), do: nil

  def encode(record, fields, opts) when is_map(record) and is_list(fields) do
    format = Keyword.get(opts, :format, :binary)
    normalized_fields = Enum.map(fields, &normalize_field/1)

    cursor_data =
      normalized_fields
      |> Enum.map(fn field -> {field, Map.get(record, field)} end)
      |> Map.new()

    case format do
      :binary -> encode_binary(cursor_data)
      :json -> encode_json(cursor_data)
    end
  end

  @doc """
  Encode using binary format (Erlang term_to_binary).

  More compact, supports all Elixir types natively.
  """
  @spec encode_binary(map()) :: String.t()
  def encode_binary(cursor_data) when is_map(cursor_data) do
    cursor_data
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Encode using JSON format.

  Human-readable, cross-language compatible.
  """
  @spec encode_json(map()) :: String.t()
  def encode_json(cursor_data) when is_map(cursor_data) do
    cursor_data
    |> Enum.map(fn {k, v} -> {to_string(k), encode_json_value(v)} end)
    |> Map.new()
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  # ─────────────────────────────────────────────────────────────
  # Decoding
  # ─────────────────────────────────────────────────────────────

  @doc """
  Decode a cursor back to field values.

  ## Options

  - `:format` - Decoding format: `:binary`, `:json`, or `:auto` (default)

  With `:auto`, attempts binary first, then JSON.

  ## Examples

      {:ok, %{inserted_at: ~U[2024-01-15 12:00:00Z], id: "uuid"}} =
        OmQuery.Cursor.decode(cursor)

      {:error, :invalid_cursor} =
        OmQuery.Cursor.decode("invalid")
  """
  @spec decode(String.t() | nil, keyword()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode(cursor, opts \\ [])

  def decode(nil, _opts), do: {:ok, %{}}
  def decode("", _opts), do: {:ok, %{}}

  def decode(cursor, opts) when is_binary(cursor) do
    format = Keyword.get(opts, :format, :auto)

    case format do
      :binary -> decode_binary(cursor)
      :json -> decode_json(cursor)
      :auto -> decode_auto(cursor)
    end
  end

  @doc """
  Decode a binary-encoded cursor.
  """
  @spec decode_binary(String.t()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_binary(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         data when is_map(data) <- safe_binary_to_term(decoded) do
      {:ok, data}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  @doc """
  Decode a JSON-encoded cursor.
  """
  @spec decode_json(String.t()) :: {:ok, map()} | {:error, :invalid_cursor}
  def decode_json(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, data} when is_map(data) <- JSON.decode(json) do
      # Convert string keys to atoms (only existing atoms for safety)
      atomized =
        data
        |> Enum.map(fn {k, v} -> {safe_to_atom(k), v} end)
        |> Map.new()

      {:ok, atomized}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp decode_auto(cursor) do
    case decode_binary(cursor) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> decode_json(cursor)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Field Extraction
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract the field name from a cursor field specification.

  Handles both simple atoms and `{field, direction}` tuples.

  ## Examples

      OmQuery.Cursor.field_name(:id)
      #=> :id

      OmQuery.Cursor.field_name({:inserted_at, :desc})
      #=> :inserted_at
  """
  @spec field_name(cursor_field()) :: atom()
  def field_name({field, _direction}) when is_atom(field), do: field
  def field_name(field) when is_atom(field), do: field

  @doc """
  Normalize cursor fields to a list of field names.

  ## Examples

      OmQuery.Cursor.normalize_fields([:id, {:inserted_at, :desc}])
      #=> [:id, :inserted_at]
  """
  @spec normalize_fields([cursor_field()]) :: [atom()]
  def normalize_fields(fields) when is_list(fields) do
    Enum.map(fields, &field_name/1)
  end

  # Alias for internal use - delegates to field_name/1
  defp normalize_field(field), do: field_name(field)

  # ─────────────────────────────────────────────────────────────
  # Cursor Generation from Records
  # ─────────────────────────────────────────────────────────────

  @doc """
  Generate start and end cursors from a list of records.

  Returns `{start_cursor, end_cursor}` tuple.

  ## Examples

      {start, end_cursor} = OmQuery.Cursor.from_records(users, [:inserted_at, :id])
  """
  @spec from_records([map()], [cursor_field()], keyword()) :: {String.t() | nil, String.t() | nil}
  def from_records(records, fields, opts \\ [])

  def from_records([], _fields, _opts), do: {nil, nil}

  def from_records(records, fields, opts) when is_list(records) do
    first = List.first(records)
    last = List.last(records)

    {encode(first, fields, opts), encode(last, fields, opts)}
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  # JSON value encoding for various types
  defp encode_json_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_json_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp encode_json_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_json_value(%Time{} = t), do: Time.to_iso8601(t)
  defp encode_json_value(value) when is_binary(value), do: value
  defp encode_json_value(value) when is_number(value), do: value
  defp encode_json_value(value) when is_boolean(value), do: value
  defp encode_json_value(nil), do: nil
  defp encode_json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_json_value(value), do: to_string(value)

  # Safe binary_to_term - only allows safe terms
  defp safe_binary_to_term(binary) do
    try do
      :erlang.binary_to_term(binary, [:safe])
    rescue
      _ -> nil
    end
  end

  # Safe string to existing atom conversion
  defp safe_to_atom(string) when is_binary(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> string
    end
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
