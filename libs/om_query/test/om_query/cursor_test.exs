defmodule OmQuery.CursorTest do
  @moduledoc """
  Tests for OmQuery.Cursor - Cursor encoding and decoding for pagination.

  Cursor handles two encoding formats:
  - **Binary** (default): Compact, Elixir-native via :erlang.term_to_binary
  - **JSON**: Human-readable, cross-language compatible

  Both formats are Base64url-encoded for safe transport in URLs and headers.

  ## Key Behaviors

  - `encode/3` extracts field values from a record and serializes them
  - `decode/2` deserializes a cursor back to a field value map
  - `from_records/3` generates start/end cursors from a list of records
  - Direction tuples like `{:field, :desc}` are normalized to bare field names
  """

  use ExUnit.Case, async: true

  alias OmQuery.Cursor

  # ============================================
  # encode/3 - Binary format (default)
  # ============================================

  describe "encode/3 binary format" do
    test "returns nil for nil record" do
      assert Cursor.encode(nil, [:id, :name]) == nil
    end

    test "returns nil for nil record with options" do
      assert Cursor.encode(nil, [:id], format: :binary) == nil
    end

    test "encodes map with atom keys" do
      record = %{id: 42, name: "Alice", status: :active}
      cursor = Cursor.encode(record, [:id, :name])

      assert is_binary(cursor)
      assert {:ok, %{id: 42, name: "Alice"}} = Cursor.decode(cursor, format: :binary)
    end

    test "encodes map with integer values" do
      record = %{id: 1, age: 30, score: 100}
      cursor = Cursor.encode(record, [:id, :age, :score])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: 1, age: 30, score: 100}
    end

    test "encodes map with string values" do
      record = %{id: "uuid-123", email: "alice@example.com"}
      cursor = Cursor.encode(record, [:id, :email])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: "uuid-123", email: "alice@example.com"}
    end

    test "encodes DateTime values" do
      dt = ~U[2025-06-15 14:30:00Z]
      record = %{id: 1, inserted_at: dt}
      cursor = Cursor.encode(record, [:id, :inserted_at])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.inserted_at == dt
      assert decoded.id == 1
    end

    test "encodes NaiveDateTime values" do
      ndt = ~N[2025-06-15 14:30:00]
      record = %{id: 1, created_at: ndt}
      cursor = Cursor.encode(record, [:id, :created_at])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.created_at == ndt
    end

    test "encodes Date values" do
      date = ~D[2025-06-15]
      record = %{id: 1, birth_date: date}
      cursor = Cursor.encode(record, [:id, :birth_date])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.birth_date == date
    end

    test "encodes with direction tuples - direction is ignored" do
      record = %{id: 42, inserted_at: ~U[2025-01-01 00:00:00Z]}
      cursor_with_dir = Cursor.encode(record, [{:inserted_at, :desc}, {:id, :asc}])
      cursor_without_dir = Cursor.encode(record, [:inserted_at, :id])

      assert {:ok, decoded_with} = Cursor.decode(cursor_with_dir, format: :binary)
      assert {:ok, decoded_without} = Cursor.decode(cursor_without_dir, format: :binary)

      assert decoded_with == decoded_without
    end

    test "encodes nil field values" do
      record = %{id: 1, deleted_at: nil}
      cursor = Cursor.encode(record, [:id, :deleted_at])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: 1, deleted_at: nil}
    end

    test "encodes only specified fields from record" do
      record = %{id: 1, name: "Alice", email: "alice@example.com", age: 30}
      cursor = Cursor.encode(record, [:id, :name])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: 1, name: "Alice"}
      refute Map.has_key?(decoded, :email)
      refute Map.has_key?(decoded, :age)
    end
  end

  # ============================================
  # encode/3 - JSON format
  # ============================================

  describe "encode/3 JSON format" do
    test "returns nil for nil record" do
      assert Cursor.encode(nil, [:id], format: :json) == nil
    end

    test "encodes map with simple fields" do
      record = %{id: 42, name: "Alice"}
      cursor = Cursor.encode(record, [:id, :name], format: :json)

      assert is_binary(cursor)
      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:id] == 42
      assert decoded[:name] == "Alice"
    end

    test "encodes DateTime as ISO8601 string" do
      dt = ~U[2025-06-15 14:30:00Z]
      record = %{id: 1, inserted_at: dt}
      cursor = Cursor.encode(record, [:id, :inserted_at], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      # JSON decoding returns ISO8601 string, not DateTime struct
      assert decoded[:inserted_at] == "2025-06-15T14:30:00Z"
    end

    test "encodes NaiveDateTime as ISO8601 string" do
      ndt = ~N[2025-06-15 14:30:00]
      record = %{id: 1, created_at: ndt}
      cursor = Cursor.encode(record, [:id, :created_at], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:created_at] == "2025-06-15T14:30:00"
    end

    test "encodes Date as ISO8601 string" do
      date = ~D[2025-06-15]
      record = %{id: 1, birth_date: date}
      cursor = Cursor.encode(record, [:id, :birth_date], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:birth_date] == "2025-06-15"
    end

    test "encodes atom values as strings" do
      record = %{id: 1, status: :active}
      cursor = Cursor.encode(record, [:id, :status], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:status] == "active"
    end

    test "encodes with direction tuples - direction is ignored" do
      record = %{id: 42, name: "Bob"}
      cursor = Cursor.encode(record, [{:name, :desc}, {:id, :asc}], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:id] == 42
      assert decoded[:name] == "Bob"
    end
  end

  # ============================================
  # Binary vs JSON produce different outputs
  # ============================================

  describe "binary vs JSON format differences" do
    test "same record produces different encoded strings" do
      record = %{id: 1, name: "Alice"}
      binary_cursor = Cursor.encode(record, [:id, :name], format: :binary)
      json_cursor = Cursor.encode(record, [:id, :name], format: :json)

      assert is_binary(binary_cursor)
      assert is_binary(json_cursor)
      assert binary_cursor != json_cursor
    end
  end

  # ============================================
  # decode/2 - nil and empty string
  # ============================================

  describe "decode/2 nil and empty" do
    test "nil returns {:ok, empty map}" do
      assert {:ok, %{}} = Cursor.decode(nil)
    end

    test "empty string returns {:ok, empty map}" do
      assert {:ok, %{}} = Cursor.decode("")
    end

    test "nil with binary format returns {:ok, empty map}" do
      assert {:ok, %{}} = Cursor.decode(nil, format: :binary)
    end

    test "nil with json format returns {:ok, empty map}" do
      assert {:ok, %{}} = Cursor.decode(nil, format: :json)
    end

    test "empty string with auto format returns {:ok, empty map}" do
      assert {:ok, %{}} = Cursor.decode("", format: :auto)
    end
  end

  # ============================================
  # decode/2 - Binary roundtrip
  # ============================================

  describe "decode/2 binary roundtrip" do
    test "roundtrip preserves atom keys and values" do
      original = %{id: 42, status: :active, name: "Alice"}
      cursor = Cursor.encode(original, [:id, :status, :name])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: 42, status: :active, name: "Alice"}
    end

    test "roundtrip preserves DateTime" do
      dt = ~U[2025-03-18 10:00:00Z]
      original = %{id: 1, ts: dt}
      cursor = Cursor.encode(original, [:id, :ts])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.ts == dt
    end

    test "roundtrip preserves NaiveDateTime" do
      ndt = ~N[2025-03-18 10:00:00]
      original = %{id: 1, ts: ndt}
      cursor = Cursor.encode(original, [:id, :ts])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.ts == ndt
    end

    test "roundtrip preserves Date" do
      date = ~D[2025-03-18]
      original = %{id: 1, date: date}
      cursor = Cursor.encode(original, [:id, :date])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded.date == date
    end

    test "roundtrip preserves nil values" do
      original = %{id: 1, optional: nil}
      cursor = Cursor.encode(original, [:id, :optional])

      assert {:ok, decoded} = Cursor.decode(cursor, format: :binary)
      assert decoded == %{id: 1, optional: nil}
    end
  end

  # ============================================
  # decode/2 - JSON roundtrip
  # ============================================

  describe "decode/2 JSON roundtrip" do
    test "roundtrip preserves integers and strings" do
      original = %{id: 42, name: "Alice"}
      cursor = Cursor.encode(original, [:id, :name], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:id] == 42
      assert decoded[:name] == "Alice"
    end

    test "atom keys survive roundtrip for existing atoms" do
      # :id and :name are existing atoms so safe_to_atom will convert them
      original = %{id: 1, name: "Bob"}
      cursor = Cursor.encode(original, [:id, :name], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert Map.has_key?(decoded, :id)
      assert Map.has_key?(decoded, :name)
    end

    test "boolean values survive roundtrip" do
      original = %{id: 1, active: true}
      cursor = Cursor.encode(original, [:id, :active], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:active] == true
    end

    test "nil values survive roundtrip" do
      original = %{id: 1, deleted_at: nil}
      cursor = Cursor.encode(original, [:id, :deleted_at], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :json)
      assert decoded[:deleted_at] == nil
    end
  end

  # ============================================
  # decode/2 - Auto-detect format
  # ============================================

  describe "decode/2 auto-detect" do
    test "auto-detects binary cursor" do
      record = %{id: 1, name: "Alice"}
      cursor = Cursor.encode(record, [:id, :name], format: :binary)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :auto)
      assert decoded == %{id: 1, name: "Alice"}
    end

    test "auto-detects JSON cursor" do
      record = %{id: 1, name: "Alice"}
      cursor = Cursor.encode(record, [:id, :name], format: :json)

      assert {:ok, decoded} = Cursor.decode(cursor, format: :auto)
      assert decoded[:id] == 1
      assert decoded[:name] == "Alice"
    end

    test "default format is auto" do
      record = %{id: 42, name: "Bob"}

      # Binary encoded
      binary_cursor = Cursor.encode(record, [:id, :name], format: :binary)
      assert {:ok, _} = Cursor.decode(binary_cursor)

      # JSON encoded
      json_cursor = Cursor.encode(record, [:id, :name], format: :json)
      assert {:ok, _} = Cursor.decode(json_cursor)
    end
  end

  # ============================================
  # decode/2 - Error cases
  # ============================================

  describe "decode/2 error cases" do
    test "invalid base64 returns error" do
      assert {:error, :invalid_cursor} = Cursor.decode("not-valid-base64!!!")
    end

    test "tampered binary cursor returns error" do
      record = %{id: 1, name: "Alice"}
      cursor = Cursor.encode(record, [:id, :name], format: :binary)

      # Tamper with the cursor by flipping characters
      tampered = String.reverse(cursor)
      assert {:error, :invalid_cursor} = Cursor.decode(tampered, format: :binary)
    end

    test "random garbage returns error" do
      assert {:error, :invalid_cursor} = Cursor.decode("zzzzzzzzzzzz")
    end

    test "valid base64 but invalid binary term returns error" do
      # Encode something that is valid base64 but not a valid erlang term
      cursor = Base.url_encode64("this is not an erlang term", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor, format: :binary)
    end

    test "valid base64 but invalid JSON returns error" do
      cursor = Base.url_encode64("not json {{{", padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor, format: :json)
    end

    test "valid JSON but not a map returns error" do
      cursor = Base.url_encode64(JSON.encode!([1, 2, 3]), padding: false)
      assert {:error, :invalid_cursor} = Cursor.decode(cursor, format: :json)
    end

    test "binary encoded non-map term returns error" do
      # Encode a list (not a map) as binary
      cursor =
        [1, 2, 3]
        |> :erlang.term_to_binary()
        |> Base.url_encode64(padding: false)

      assert {:error, :invalid_cursor} = Cursor.decode(cursor, format: :binary)
    end
  end

  # ============================================
  # field_name/1
  # ============================================

  describe "field_name/1" do
    test "simple atom returns itself" do
      assert Cursor.field_name(:id) == :id
      assert Cursor.field_name(:inserted_at) == :inserted_at
      assert Cursor.field_name(:name) == :name
    end

    test "{field, :desc} returns field" do
      assert Cursor.field_name({:inserted_at, :desc}) == :inserted_at
    end

    test "{field, :asc} returns field" do
      assert Cursor.field_name({:id, :asc}) == :id
    end
  end

  # ============================================
  # normalize_fields/1
  # ============================================

  describe "normalize_fields/1" do
    test "normalizes list of atoms" do
      assert Cursor.normalize_fields([:id, :name, :inserted_at]) == [:id, :name, :inserted_at]
    end

    test "normalizes list of direction tuples" do
      fields = [{:inserted_at, :desc}, {:id, :asc}]
      assert Cursor.normalize_fields(fields) == [:inserted_at, :id]
    end

    test "normalizes mixed list" do
      fields = [:name, {:inserted_at, :desc}, :id]
      assert Cursor.normalize_fields(fields) == [:name, :inserted_at, :id]
    end

    test "empty list returns empty list" do
      assert Cursor.normalize_fields([]) == []
    end
  end

  # ============================================
  # from_records/3
  # ============================================

  describe "from_records/3" do
    test "empty list returns {nil, nil}" do
      assert Cursor.from_records([], [:id]) == {nil, nil}
    end

    test "single record returns same cursor for start and end" do
      records = [%{id: 1, name: "Alice"}]
      {start_cursor, end_cursor} = Cursor.from_records(records, [:id])

      assert start_cursor == end_cursor
      assert is_binary(start_cursor)
    end

    test "multiple records returns first and last cursors" do
      records = [
        %{id: 1, name: "Alice"},
        %{id: 2, name: "Bob"},
        %{id: 3, name: "Charlie"}
      ]

      {start_cursor, end_cursor} = Cursor.from_records(records, [:id, :name])

      assert is_binary(start_cursor)
      assert is_binary(end_cursor)
      assert start_cursor != end_cursor

      assert {:ok, start_decoded} = Cursor.decode(start_cursor)
      assert {:ok, end_decoded} = Cursor.decode(end_cursor)

      assert start_decoded == %{id: 1, name: "Alice"}
      assert end_decoded == %{id: 3, name: "Charlie"}
    end

    test "roundtrip: cursors decode to correct field values" do
      dt1 = ~U[2025-01-01 00:00:00Z]
      dt2 = ~U[2025-06-15 12:00:00Z]

      records = [
        %{id: "uuid-1", inserted_at: dt1},
        %{id: "uuid-2", inserted_at: dt2}
      ]

      {start_cursor, end_cursor} = Cursor.from_records(records, [{:inserted_at, :desc}, {:id, :asc}])

      assert {:ok, start_decoded} = Cursor.decode(start_cursor)
      assert start_decoded == %{id: "uuid-1", inserted_at: dt1}

      assert {:ok, end_decoded} = Cursor.decode(end_cursor)
      assert end_decoded == %{id: "uuid-2", inserted_at: dt2}
    end

    test "with JSON format option" do
      records = [
        %{id: 1, name: "First"},
        %{id: 5, name: "Last"}
      ]

      {start_cursor, end_cursor} = Cursor.from_records(records, [:id], format: :json)

      assert {:ok, start_decoded} = Cursor.decode(start_cursor, format: :json)
      assert start_decoded[:id] == 1

      assert {:ok, end_decoded} = Cursor.decode(end_cursor, format: :json)
      assert end_decoded[:id] == 5
    end

    test "with direction tuples in fields" do
      records = [
        %{id: 10, score: 95},
        %{id: 20, score: 42}
      ]

      {start_cursor, end_cursor} = Cursor.from_records(records, [{:score, :desc}, {:id, :asc}])

      assert {:ok, start_decoded} = Cursor.decode(start_cursor)
      assert start_decoded == %{id: 10, score: 95}

      assert {:ok, end_decoded} = Cursor.decode(end_cursor)
      assert end_decoded == %{id: 20, score: 42}
    end
  end
end
