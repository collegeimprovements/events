defmodule Events.Core.OmQuery.ParamsTest do
  use Events.TestCase, async: true

  alias OmQuery.Params

  describe "get/3" do
    test "gets value by atom key" do
      params = %{limit: 20, status: "active"}
      assert Params.get(params, :limit) == 20
      assert Params.get(params, :status) == "active"
    end

    test "gets value by string key" do
      params = %{"limit" => 20, "status" => "active"}
      assert Params.get(params, "limit") == 20
      assert Params.get(params, "status") == "active"
    end

    test "indifferent access - atom key finds string value" do
      params = %{"limit" => 20, "status" => "active"}
      assert Params.get(params, :limit) == 20
      assert Params.get(params, :status) == "active"
    end

    test "indifferent access - string key finds atom value" do
      params = %{limit: 20, status: "active"}
      assert Params.get(params, "limit") == 20
      assert Params.get(params, "status") == "active"
    end

    test "prefers exact key match" do
      # If both exist, atom key takes precedence when querying by atom
      params = Map.merge(%{"limit" => 20}, %{limit: 10})
      assert Params.get(params, :limit) == 10
    end

    test "returns default when key not found" do
      params = %{limit: 20}
      assert Params.get(params, :missing) == nil
      assert Params.get(params, :missing, "default") == "default"
    end

    test "handles mixed key maps" do
      params = %{:limit => 20, "status" => "active", :page => 1}
      assert Params.get(params, :limit) == 20
      assert Params.get(params, :status) == "active"
      assert Params.get(params, :page) == 1
    end
  end

  describe "fetch/2" do
    test "returns {:ok, value} when found" do
      params = %{"limit" => 20}
      assert {:ok, 20} = Params.fetch(params, :limit)
      assert {:ok, 20} = Params.fetch(params, "limit")
    end

    test "returns :error when not found" do
      params = %{limit: 20}
      assert :error = Params.fetch(params, :missing)
    end
  end

  describe "has_key?/2" do
    test "returns true for existing keys (indifferent)" do
      params = %{"limit" => 20}
      assert Params.has_key?(params, :limit) == true
      assert Params.has_key?(params, "limit") == true
    end

    test "returns false for missing keys" do
      params = %{limit: 20}
      assert Params.has_key?(params, :missing) == false
    end
  end

  describe "normalize/2" do
    test "converts string keys to atoms" do
      params = %{"limit" => 20, "status" => "active"}
      result = Params.normalize(params)
      assert result == %{limit: 20, status: "active"}
    end

    test "preserves atom keys" do
      params = %{limit: 20, status: "active"}
      result = Params.normalize(params)
      assert result == %{limit: 20, status: "active"}
    end

    test "handles mixed keys" do
      params = %{:limit => 20, "status" => "active"}
      result = Params.normalize(params)
      assert result == %{limit: 20, status: "active"}
    end

    test "only keeps allowed keys when :only option provided" do
      params = %{"limit" => 20, "status" => "active", "evil" => "drop"}
      result = Params.normalize(params, only: [:limit, :status])
      assert result == %{limit: 20, status: "active"}
      refute Map.has_key?(result, :evil)
    end

    test "excludes keys when :except option provided" do
      params = %{"limit" => 20, "internal" => "secret"}
      result = Params.normalize(params, except: [:internal])
      assert result == %{limit: 20}
    end
  end

  describe "take/2" do
    test "takes specified keys with indifferent access" do
      params = %{"limit" => 20, "status" => "active", "other" => "ignored"}
      result = Params.take(params, [:limit, :status])
      assert result == %{limit: 20, status: "active"}
    end

    test "returns only found keys" do
      params = %{"limit" => 20}
      result = Params.take(params, [:limit, :missing])
      assert result == %{limit: 20}
    end
  end

  describe "to_keyword/2" do
    test "converts to keyword list" do
      params = %{"limit" => 20, "after" => "cursor123"}
      result = Params.to_keyword(params, [:limit, :after])
      assert result == [limit: 20, after: "cursor123"]
    end

    test "omits missing keys" do
      params = %{"limit" => 20}
      result = Params.to_keyword(params, [:limit, :after])
      assert result == [limit: 20]
    end
  end

  describe "compact/1" do
    test "removes nil values from keyword list" do
      result = Params.compact(limit: nil, after: "cursor", status: nil)
      assert result == [after: "cursor"]
    end

    test "removes nil values from map" do
      result = Params.compact(%{limit: nil, after: "cursor", status: nil})
      assert result == %{after: "cursor"}
    end
  end

  describe "pagination_opts/2" do
    test "extracts pagination options with string keys" do
      params = %{"limit" => "20", "after" => "cursor123"}
      result = Params.pagination_opts(params)
      assert result == [limit: 20, after: "cursor123"]
    end

    test "extracts pagination options with atom keys" do
      params = %{limit: 20, after: "cursor123"}
      result = Params.pagination_opts(params)
      assert result == [limit: 20, after: "cursor123"]
    end

    test "parses string limit to integer" do
      params = %{"limit" => "50"}
      result = Params.pagination_opts(params)
      assert result == [limit: 50]
    end

    test "parses string offset to integer" do
      params = %{"offset" => "100"}
      result = Params.pagination_opts(params)
      assert result == [offset: 100]
    end

    test "omits nil and empty values" do
      params = %{"limit" => nil, "after" => "", "before" => "cursor"}
      result = Params.pagination_opts(params)
      assert result == [before: "cursor"]
    end

    test "supports custom key mapping" do
      params = %{"page_size" => "25", "cursor" => "abc"}
      result = Params.pagination_opts(params, limit: :page_size, after: :cursor)
      assert result == [limit: 25, after: "abc"]
    end

    test "ignores invalid numeric strings" do
      params = %{"limit" => "invalid", "after" => "cursor"}
      result = Params.pagination_opts(params)
      assert result == [after: "cursor"]
    end
  end

  describe "integration with Query" do
    alias OmQuery, as: Query

    test "params work with maybe filter" do
      params = %{"status" => "active", "role" => nil}

      token =
        OmQuery.new(User)
        |> OmQuery.maybe(:status, Params.get(params, :status))
        |> OmQuery.maybe(:role, Params.get(params, :role))

      # Only status filter added, role is nil
      assert [{:filter, {:status, :eq, "active", []}}] = token.operations
    end

    test "params work with paginate" do
      params = %{"limit" => "25", "after" => "cursor_token"}
      opts = Params.pagination_opts(params)

      token =
        OmQuery.new(User)
        |> OmQuery.paginate(:cursor, opts)

      assert [{:paginate, {:cursor, [limit: 25, after: "cursor_token"]}}] = token.operations
    end

    test "params work with nil pagination values" do
      # nil values get defaults in paginate
      params = %{"limit" => nil, "after" => nil}

      token =
        OmQuery.new(User)
        |> OmQuery.paginate(:cursor,
          limit: Params.get(params, :limit),
          after: Params.get(params, :after)
        )

      # Should create pagination with nil values (which use defaults)
      assert [{:paginate, {:cursor, [limit: nil, after: nil]}}] = token.operations
    end
  end
end
