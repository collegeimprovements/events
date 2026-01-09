defmodule OmQuery.TokenTest do
  @moduledoc """
  Tests for OmQuery.Token - Type-safe query building primitives.

  Token is the low-level building block for constructing database queries.
  It validates operations at build time, preventing invalid queries from
  reaching the database.

  ## Use Cases

  - **Filtering**: eq, neq, gt, gte, lt, lte, in, like, between, jsonb_*
  - **Ordering**: asc, desc, with null handling variants
  - **Pagination**: Offset-based and cursor-based pagination
  - **Joins**: inner, left, right, full joins on associations
  - **Aggregation**: group_by with having clauses
  - **Locking**: Pessimistic locking for transactions

  ## Pattern: Validated Query Building

      Token.new(User)
      |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
      |> Token.add_operation!({:order, {:created_at, :desc, []}})
      |> Token.add_operation!({:limit, 20})

  Invalid operations return descriptive errors before execution:

      {:error, %ValidationError{message: "Invalid filter operator: :bad_op"}}
      {:error, %LimitExceededError{requested: 10000, max: 1000}}

  These primitives power the higher-level OmQuery DSL.
  """

  use ExUnit.Case, async: true

  alias OmQuery.Token
  alias OmQuery.{ValidationError, LimitExceededError, PaginationError, FilterGroupError}

  # ============================================
  # Token Creation
  # ============================================

  describe "Token.new/1" do
    test "creates token from schema module" do
      token = Token.new(MyApp.User)

      assert token.source == MyApp.User
      assert token.operations == []
      assert token.metadata == %{}
    end

    test "creates token from :nested atom" do
      token = Token.new(:nested)

      assert token.source == :nested
    end
  end

  # ============================================
  # Operation Addition (Safe Variant)
  # ============================================

  describe "Token.add_operation_safe/2" do
    test "adds valid filter operation" do
      token = Token.new(MyApp.User)

      assert {:ok, updated} = Token.add_operation_safe(token, {:filter, {:status, :eq, "active", []}})
      assert length(updated.operations) == 1
    end

    test "returns error for invalid filter operation" do
      token = Token.new(MyApp.User)

      assert {:error, %ValidationError{}} =
               Token.add_operation_safe(token, {:filter, {:status, :invalid_op, "value", []}})
    end

    test "returns error for limit exceeding max" do
      token = Token.new(MyApp.User)

      assert {:error, %LimitExceededError{}} =
               Token.add_operation_safe(token, {:limit, 10_000})
    end

    test "returns error for filter group with < 2 filters" do
      token = Token.new(MyApp.User)

      assert {:error, %FilterGroupError{}} =
               Token.add_operation_safe(token, {:filter_group, {:or, [{:status, :eq, "active", []}]}})
    end
  end

  # ============================================
  # Operation Addition (Raising Variant)
  # ============================================

  describe "Token.add_operation!/2" do
    test "adds valid operation and returns token" do
      token = Token.new(MyApp.User)
      updated = Token.add_operation!(token, {:filter, {:name, :eq, "John", []}})

      assert length(updated.operations) == 1
    end

    test "raises on invalid operation" do
      token = Token.new(MyApp.User)

      assert_raise ValidationError, fn ->
        Token.add_operation!(token, {:filter, {:name, :bad_op, "value", []}})
      end
    end
  end

  describe "Token.add_operation/2" do
    test "is alias for add_operation!" do
      token = Token.new(MyApp.User)
      updated = Token.add_operation(token, {:filter, {:name, :eq, "John", []}})

      assert length(updated.operations) == 1
    end
  end

  # ============================================
  # Filter Operations
  # ============================================

  describe "filter operations" do
    test "validates :eq operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:status, :eq, "active", []}})
    end

    test "validates :neq operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:status, :neq, "deleted", []}})
    end

    test "validates :gt operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:age, :gt, 18, []}})
    end

    test "validates :gte operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:age, :gte, 18, []}})
    end

    test "validates :lt operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:age, :lt, 65, []}})
    end

    test "validates :lte operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:age, :lte, 65, []}})
    end

    test "validates :in operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:status, :in, ["active", "pending"], []}})
    end

    test "validates :not_in operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:status, :not_in, ["deleted"], []}})
    end

    test "validates :like operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:name, :like, "%John%", []}})
    end

    test "validates :ilike operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:name, :ilike, "%john%", []}})
    end

    test "validates :is_nil operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:deleted_at, :is_nil, true, []}})
    end

    test "validates :not_nil operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:email, :not_nil, true, []}})
    end

    test "validates :between operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:age, :between, {18, 65}, []}})
    end

    test "validates :contains operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:tags, :contains, "premium", []}})
    end

    test "validates :jsonb_contains operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:metadata, :jsonb_contains, %{key: "value"}, []}})
    end

    test "validates :jsonb_has_key operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:metadata, :jsonb_has_key, "key", []}})
    end

    test "validates :similarity operation" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:filter, {:name, :similarity, "John", []}})
    end
  end

  # ============================================
  # Pagination Operations
  # ============================================

  describe "pagination operations" do
    test "validates offset pagination" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:paginate, {:offset, [limit: 20, offset: 0]}})
    end

    test "validates cursor pagination" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:paginate, {:cursor, [limit: 20]}})
    end

    test "returns error for invalid limit in offset pagination" do
      token = Token.new(MyApp.User)
      assert {:error, %PaginationError{}} = Token.add_operation_safe(token, {:paginate, {:offset, [limit: -1]}})
    end

    test "returns error for limit exceeding max" do
      token = Token.new(MyApp.User)
      assert {:error, %LimitExceededError{}} = Token.add_operation_safe(token, {:paginate, {:offset, [limit: 10_000]}})
    end

    test "returns error for invalid cursor_fields type" do
      token = Token.new(MyApp.User)
      assert {:error, %PaginationError{}} = Token.add_operation_safe(token, {:paginate, {:cursor, [cursor_fields: "invalid"]}})
    end
  end

  # ============================================
  # Order Operations
  # ============================================

  describe "order operations" do
    test "validates :asc order" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:order, {:name, :asc, []}})
    end

    test "validates :desc order" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:order, {:created_at, :desc, []}})
    end

    test "validates :asc_nulls_first order" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:order, {:score, :asc_nulls_first, []}})
    end

    test "validates :desc_nulls_last order" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:order, {:score, :desc_nulls_last, []}})
    end
  end

  # ============================================
  # Join Operations
  # ============================================

  describe "join operations" do
    test "validates :inner join" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:join, {:posts, :inner, []}})
    end

    test "validates :left join" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:join, {:posts, :left, []}})
    end

    test "validates :right join" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:join, {:posts, :right, []}})
    end

    test "validates :full join" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:join, {:posts, :full, []}})
    end
  end

  # ============================================
  # Select Operations
  # ============================================

  describe "select operations" do
    test "validates select with list" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:select, [:id, :name, :email]})
    end

    test "validates select with map" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:select, %{id: :id, full_name: :name}})
    end
  end

  # ============================================
  # Group By Operations
  # ============================================

  describe "group_by operations" do
    test "validates group_by with atom" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:group_by, :status})
    end

    test "validates group_by with list" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:group_by, [:status, :role]})
    end
  end

  # ============================================
  # Limit/Offset Operations
  # ============================================

  describe "limit operations" do
    test "validates positive limit" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:limit, 50})
    end

    test "returns error for limit exceeding max" do
      token = Token.new(MyApp.User)
      assert {:error, %LimitExceededError{requested: 5000}} = Token.add_operation_safe(token, {:limit, 5000})
    end
  end

  describe "offset operations" do
    test "validates non-negative offset" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:offset, 0})
      assert {:ok, _} = Token.add_operation_safe(token, {:offset, 100})
    end
  end

  # ============================================
  # Distinct Operations
  # ============================================

  describe "distinct operations" do
    test "validates distinct with boolean" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:distinct, true})
    end

    test "validates distinct with list" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:distinct, [:name]})
    end
  end

  # ============================================
  # Lock Operations
  # ============================================

  describe "lock operations" do
    test "validates lock with atom" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:lock, :update})
    end

    test "validates lock with string" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:lock, "FOR UPDATE NOWAIT"})
    end
  end

  # ============================================
  # CTE Operations
  # ============================================

  describe "cte operations" do
    test "validates cte with opts" do
      subtoken = Token.new(MyApp.User)
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:cte, {:active_users, subtoken, []}})
    end

    test "validates cte without opts (backwards compat)" do
      subtoken = Token.new(MyApp.User)
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:cte, {:active_users, subtoken}})
    end
  end

  # ============================================
  # Raw Where Operations
  # ============================================

  describe "raw_where operations" do
    test "validates raw_where with list params" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {"status = ?", ["active"], []}})
    end

    test "validates raw_where with map params" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {"status = :status", %{status: "active"}, []}})
    end

    test "validates raw_where without opts (backwards compat)" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {"status = ?", ["active"]}})
    end

    test "validates raw_where with 6 parameters" do
      token = Token.new(MyApp.User)
      sql = "a = ? AND b = ? AND c = ? AND d = ? AND e = ? AND f = ?"
      params = ["a", "b", "c", "d", "e", "f"]
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {sql, params, []}})
    end

    test "validates raw_where with 10 parameters" do
      token = Token.new(MyApp.User)
      placeholders = Enum.map(1..10, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.map(1..10, fn i -> "val#{i}" end)
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {placeholders, params, []}})
    end

    test "validates raw_where with 20 parameters (max supported)" do
      token = Token.new(MyApp.User)
      placeholders = Enum.map(1..20, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.map(1..20, fn i -> "val#{i}" end)
      assert {:ok, _} = Token.add_operation_safe(token, {:raw_where, {placeholders, params, []}})
    end
  end

  # ============================================
  # Filter Group Operations
  # ============================================

  describe "filter_group operations" do
    test "validates :or filter group with 2+ filters" do
      token = Token.new(MyApp.User)

      filters = [
        {:status, :eq, "active", []},
        {:role, :eq, "admin", []}
      ]

      assert {:ok, _} = Token.add_operation_safe(token, {:filter_group, {:or, filters}})
    end

    test "validates :and filter group" do
      token = Token.new(MyApp.User)

      filters = [
        {:status, :eq, "active", []},
        {:verified, :eq, true, []}
      ]

      assert {:ok, _} = Token.add_operation_safe(token, {:filter_group, {:and, filters}})
    end

    test "validates :not_or filter group" do
      token = Token.new(MyApp.User)

      filters = [
        {:status, :eq, "deleted", []},
        {:status, :eq, "banned", []}
      ]

      assert {:ok, _} = Token.add_operation_safe(token, {:filter_group, {:not_or, filters}})
    end

    test "returns error for filter group with < 2 filters" do
      token = Token.new(MyApp.User)

      assert {:error, %FilterGroupError{reason: reason}} =
               Token.add_operation_safe(token, {:filter_group, {:or, [{:status, :eq, "active", []}]}})

      assert reason =~ "at least 2 filters"
    end

    test "returns error for filter group with invalid filter spec" do
      token = Token.new(MyApp.User)

      filters = [
        {:status, :invalid_op, "active", []},
        {:role, :eq, "admin", []}
      ]

      assert {:error, _} = Token.add_operation_safe(token, {:filter_group, {:or, filters}})
    end
  end

  # ============================================
  # Field Compare Operations
  # ============================================

  describe "field_compare operations" do
    test "validates :eq field comparison" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:field_compare, {:created_at, :eq, :updated_at, []}})
    end

    test "validates :gt field comparison" do
      token = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:field_compare, {:balance, :gt, :min_balance, []}})
    end

    test "returns error for invalid field comparison operator" do
      token = Token.new(MyApp.User)
      assert {:error, %ValidationError{}} = Token.add_operation_safe(token, {:field_compare, {:a, :invalid, :b, []}})
    end
  end

  # ============================================
  # Query Functions
  # ============================================

  describe "Token.get_operations/2" do
    test "returns operations of specific type" do
      token =
        Token.new(MyApp.User)
        |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
        |> Token.add_operation!({:filter, {:role, :eq, "admin", []}})
        |> Token.add_operation!({:order, {:name, :asc, []}})

      filters = Token.get_operations(token, :filter)
      assert length(filters) == 2

      orders = Token.get_operations(token, :order)
      assert length(orders) == 1
    end

    test "returns empty list when no operations of type" do
      token = Token.new(MyApp.User)
      assert Token.get_operations(token, :filter) == []
    end
  end

  describe "Token.remove_operations/2" do
    test "removes operations of specific type" do
      token =
        Token.new(MyApp.User)
        |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
        |> Token.add_operation!({:order, {:name, :asc, []}})

      updated = Token.remove_operations(token, :filter)

      assert Token.get_operations(updated, :filter) == []
      assert length(Token.get_operations(updated, :order)) == 1
    end
  end

  describe "Token.put_metadata/3" do
    test "adds metadata to token" do
      token =
        Token.new(MyApp.User)
        |> Token.put_metadata(:request_id, "abc123")

      assert token.metadata[:request_id] == "abc123"
    end
  end

  # ============================================
  # Configuration
  # ============================================

  describe "configuration" do
    test "default_limit returns configured value" do
      assert is_integer(Token.default_limit())
      assert Token.default_limit() > 0
    end

    test "max_limit returns configured value" do
      assert is_integer(Token.max_limit())
      assert Token.max_limit() > Token.default_limit()
    end
  end

  # ============================================
  # Set Operations (union, intersect, except)
  # ============================================

  describe "combination operations" do
    test "validates union with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:union, other}})
    end

    test "validates union_all with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:union_all, other}})
    end

    test "validates intersect with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:intersect, other}})
    end

    test "validates intersect_all with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:intersect_all, other}})
    end

    test "validates except with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:except, other}})
    end

    test "validates except_all with Token" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:except_all, other}})
    end

    test "validates combination with Ecto.Query" do
      import Ecto.Query
      token = Token.new(MyApp.User)
      ecto_query = from(u in "users")
      assert {:ok, _} = Token.add_operation_safe(token, {:combination, {:union, ecto_query}})
    end

    test "returns error for invalid combination type" do
      token = Token.new(MyApp.User)
      other = Token.new(MyApp.User)
      assert {:error, _} = Token.add_operation_safe(token, {:combination, {:invalid_type, other}})
    end
  end
end
