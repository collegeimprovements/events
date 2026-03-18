defmodule OmQuery.ParamsTest do
  @moduledoc """
  Tests for OmQuery.Params - Indifferent-access parameter helpers.

  Params provides utilities for working with query parameters from
  Phoenix controllers, LiveView, and other sources where keys may
  be atoms or strings.

  ## Key Behaviors

  - **Indifferent access**: Atom keys find string values and vice versa
  - **Safe atom handling**: String keys that don't correspond to existing
    atoms won't crash (no atom table exhaustion)
  - **Normalization**: Convert string-keyed maps to atom-keyed with filtering
  - **Pagination**: Extract and parse pagination params from mixed sources
  """

  use ExUnit.Case, async: true

  alias OmQuery.Params

  # ============================================
  # get/3 - Indifferent Access
  # ============================================

  describe "get/3" do
    test "atom key in atom-keyed map" do
      params = %{status: "active", limit: 20}

      assert Params.get(params, :status) == "active"
      assert Params.get(params, :limit) == 20
    end

    test "atom key finds string-keyed value" do
      params = %{"status" => "active", "limit" => 20}

      assert Params.get(params, :status) == "active"
      assert Params.get(params, :limit) == 20
    end

    test "string key in string-keyed map" do
      params = %{"status" => "active", "limit" => 20}

      assert Params.get(params, "status") == "active"
      assert Params.get(params, "limit") == 20
    end

    test "string key finds atom-keyed value" do
      params = %{status: "active", limit: 20}

      assert Params.get(params, "status") == "active"
      assert Params.get(params, "limit") == 20
    end

    test "missing key returns nil default" do
      params = %{status: "active"}

      assert Params.get(params, :missing) == nil
      assert Params.get(params, "missing") == nil
    end

    test "missing key returns custom default" do
      params = %{status: "active"}

      assert Params.get(params, :missing, "fallback") == "fallback"
      assert Params.get(params, "missing", 42) == 42
    end

    test "non-existing atom string key returns default without crash" do
      # String key whose atom form doesn't exist in atom table
      params = %{"zzz_nonexistent_key_abc_12345" => "value"}

      assert Params.get(params, "zzz_nonexistent_key_abc_12345") == "value"
      # Reverse: atom key looking for string that won't match an atom
      assert Params.get(%{}, "zzz_totally_fake_key_99999", :default) == :default
    end
  end

  # ============================================
  # fetch/2
  # ============================================

  describe "fetch/2" do
    test "found with atom key returns {:ok, value}" do
      params = %{status: "active"}

      assert Params.fetch(params, :status) == {:ok, "active"}
    end

    test "found with string key returns {:ok, value}" do
      params = %{"status" => "active"}

      assert Params.fetch(params, "status") == {:ok, "active"}
    end

    test "cross-type lookup works (atom key, string map)" do
      params = %{"limit" => 20}

      assert Params.fetch(params, :limit) == {:ok, 20}
    end

    test "cross-type lookup works (string key, atom map)" do
      params = %{limit: 20}

      assert Params.fetch(params, "limit") == {:ok, 20}
    end

    test "missing key returns :error" do
      params = %{status: "active"}

      assert Params.fetch(params, :missing) == :error
      assert Params.fetch(params, "missing") == :error
    end

    test "non-existing atom string key returns :error without crash" do
      params = %{"known" => "value"}

      assert Params.fetch(params, "zzz_nonexistent_fetch_key_99999") == :error
    end
  end

  # ============================================
  # has_key?/2
  # ============================================

  describe "has_key?/2" do
    test "existing key returns true" do
      params = %{status: "active"}

      assert Params.has_key?(params, :status) == true
      assert Params.has_key?(params, "status") == true
    end

    test "missing key returns false" do
      params = %{status: "active"}

      assert Params.has_key?(params, :missing) == false
      assert Params.has_key?(params, "missing") == false
    end

    test "cross-type works" do
      assert Params.has_key?(%{"limit" => 20}, :limit) == true
      assert Params.has_key?(%{limit: 20}, "limit") == true
    end
  end

  # ============================================
  # normalize/2
  # ============================================

  describe "normalize/2" do
    test "basic string-to-atom conversion" do
      params = %{"status" => "active", "limit" => 20}

      result = Params.normalize(params)

      assert result == %{status: "active", limit: 20}
    end

    test "atom keys preserved" do
      params = %{status: "active", limit: 20}

      result = Params.normalize(params)

      assert result == %{status: "active", limit: 20}
    end

    test "with only: option filters to allowed keys" do
      params = %{"status" => "active", "limit" => 20, "offset" => 0}

      result = Params.normalize(params, only: [:status, :limit])

      assert result == %{status: "active", limit: 20}
      refute Map.has_key?(result, :offset)
    end

    test "with only: option drops unknown string keys without atom creation" do
      params = %{"status" => "active", "zzz_unknown_normalize_key_xyz" => "evil"}

      result = Params.normalize(params, only: [:status])

      assert result == %{status: "active"}
    end

    test "with except: option excludes keys" do
      params = %{"status" => "active", "internal" => "secret", "limit" => 20}

      result = Params.normalize(params, except: [:internal])

      assert result == %{status: "active", limit: 20}
    end

    test "empty map returns empty map" do
      assert Params.normalize(%{}) == %{}
    end

    test "mixed atom and string keys" do
      params = Map.merge(%{status: "active"}, %{"limit" => 20})

      result = Params.normalize(params)

      assert result[:status] == "active"
      assert result[:limit] == 20
    end
  end

  # ============================================
  # take/2
  # ============================================

  describe "take/2" do
    test "takes specified keys with indifferent access" do
      params = %{"status" => "active", "limit" => 20, "other" => "ignored"}

      result = Params.take(params, [:status, :limit])

      assert result == %{status: "active", limit: 20}
    end

    test "missing keys omitted" do
      params = %{"status" => "active"}

      result = Params.take(params, [:status, :limit, :offset])

      assert result == %{status: "active"}
    end

    test "returns atom-keyed map" do
      params = %{"name" => "Alice", "age" => 30}

      result = Params.take(params, [:name, :age])

      assert Map.keys(result) |> Enum.all?(&is_atom/1)
      assert result == %{name: "Alice", age: 30}
    end

    test "works with atom-keyed source map" do
      params = %{name: "Alice", age: 30, extra: "drop"}

      result = Params.take(params, [:name, :age])

      assert result == %{name: "Alice", age: 30}
    end
  end

  # ============================================
  # to_keyword/2
  # ============================================

  describe "to_keyword/2" do
    test "returns keyword list with specified keys" do
      params = %{"limit" => 20, "after" => "cursor123"}

      result = Params.to_keyword(params, [:limit, :after])

      assert result == [limit: 20, after: "cursor123"]
    end

    test "missing keys omitted" do
      params = %{"limit" => 20}

      result = Params.to_keyword(params, [:limit, :after])

      assert result == [limit: 20]
    end

    test "preserves order of requested keys" do
      params = %{"c" => 3, "a" => 1, "b" => 2}

      result = Params.to_keyword(params, [:a, :b, :c])

      assert Keyword.keys(result) == [:a, :b, :c]
    end

    test "returns keyword list type" do
      params = %{"limit" => 20}

      result = Params.to_keyword(params, [:limit])

      assert Keyword.keyword?(result)
    end
  end

  # ============================================
  # compact/1
  # ============================================

  describe "compact/1" do
    test "removes nil values from keyword list" do
      input = [limit: nil, after: "cursor", status: nil, offset: 10]

      result = Params.compact(input)

      assert result == [after: "cursor", offset: 10]
    end

    test "removes nil values from map" do
      input = %{limit: nil, after: "cursor", status: nil}

      result = Params.compact(input)

      assert result == %{after: "cursor"}
    end

    test "keeps non-nil values including falsy ones" do
      input = [active: false, count: 0, name: "", empty: nil]

      result = Params.compact(input)

      assert result == [active: false, count: 0, name: ""]
    end

    test "empty keyword list returns empty" do
      assert Params.compact([]) == []
    end

    test "empty map returns empty" do
      assert Params.compact(%{}) == %{}
    end
  end

  # ============================================
  # pagination_opts/2
  # ============================================

  describe "pagination_opts/2" do
    test "extracts limit, offset, after, before from params" do
      params = %{limit: 20, offset: 40, after: "cursor_a", before: "cursor_b"}

      result = Params.pagination_opts(params)

      assert result == [limit: 20, offset: 40, after: "cursor_a", before: "cursor_b"]
    end

    test "parses string integers for limit" do
      params = %{"limit" => "25"}

      result = Params.pagination_opts(params)

      assert result == [limit: 25]
    end

    test "parses string integers for offset" do
      params = %{"offset" => "100"}

      result = Params.pagination_opts(params)

      assert result == [offset: 100]
    end

    test "invalid integer strings are ignored" do
      params = %{"limit" => "abc", "offset" => "not_a_number"}

      result = Params.pagination_opts(params)

      assert result == []
    end

    test "partially valid integer strings are ignored" do
      params = %{"limit" => "20px", "offset" => "10.5"}

      result = Params.pagination_opts(params)

      assert result == []
    end

    test "custom key mapping works" do
      params = %{"page_size" => "10", "cursor" => "abc123"}

      result = Params.pagination_opts(params, limit: :page_size, after: :cursor)

      assert result == [limit: 10, after: "abc123"]
    end

    test "missing keys omitted from result" do
      params = %{"limit" => "20"}

      result = Params.pagination_opts(params)

      assert result == [limit: 20]
      refute Keyword.has_key?(result, :offset)
      refute Keyword.has_key?(result, :after)
      refute Keyword.has_key?(result, :before)
    end

    test "empty string values are ignored" do
      params = %{"limit" => "", "after" => ""}

      result = Params.pagination_opts(params)

      assert result == []
    end

    test "integer values pass through directly" do
      params = %{limit: 20, offset: 0}

      result = Params.pagination_opts(params)

      assert result == [limit: 20, offset: 0]
    end
  end
end
