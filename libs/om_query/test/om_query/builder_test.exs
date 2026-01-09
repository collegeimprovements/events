defmodule OmQuery.BuilderTest do
  @moduledoc """
  Tests for OmQuery.Builder - Query building from tokens.

  These tests verify that tokens are correctly converted to Ecto queries,
  particularly for complex operations like raw_where with many parameters.
  """

  use ExUnit.Case, async: true

  alias OmQuery
  alias OmQuery.Builder

  # Mock schema for testing
  defmodule TestUser do
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :email, :string
      field :status, :string
      field :age, :integer
    end
  end

  # ============================================
  # Raw Where Building
  # ============================================

  describe "build_fragment with raw_where" do
    test "builds query with 1 parameter" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("status = ?", ["active"])

      # Should not raise
      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with 5 parameters (original limit)" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("a = ? AND b = ? AND c = ? AND d = ? AND e = ?", [1, 2, 3, 4, 5])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with 6 parameters (exceeds original limit)" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("a = ? AND b = ? AND c = ? AND d = ? AND e = ? AND f = ?", [1, 2, 3, 4, 5, 6])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with 10 parameters" do
      placeholders = Enum.map(1..10, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.to_list(1..10)

      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw(placeholders, params)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with 15 parameters" do
      placeholders = Enum.map(1..15, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.to_list(1..15)

      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw(placeholders, params)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with 20 parameters (max supported)" do
      placeholders = Enum.map(1..20, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.to_list(1..20)

      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw(placeholders, params)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "raises with helpful error for 21+ parameters" do
      placeholders = Enum.map(1..21, fn i -> "col#{i} = ?" end) |> Enum.join(" AND ")
      params = Enum.to_list(1..21)

      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw(placeholders, params)

      error = assert_raise OmQuery.ParameterLimitError, fn ->
        Builder.build(token)
      end

      assert error.count == 21
      assert error.max_allowed == 20
      assert error.sql_preview =~ "col1 = ?"
      # Verify the message includes helpful alternatives
      msg = Exception.message(error)
      assert msg =~ "maximum 20 parameters"
      assert msg =~ "got 21"
      assert msg =~ "Alternatives"
    end

    test "builds query with 0 parameters" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("status IS NOT NULL", [])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with mixed types in parameters" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw(
          "name = ? AND age > ? AND status IN (?, ?) AND email LIKE ?",
          ["John", 18, "active", "pending", "%@example.com"]
        )

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "combines multiple raw clauses" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("status = ?", ["active"])
        |> OmQuery.raw("age > ?", [18])
        |> OmQuery.raw("name LIKE ?", ["%John%"])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "works with named parameters via raw" do
      token =
        TestUser
        |> OmQuery.raw(
          "status = :status AND age > :min_age",
          %{status: "active", min_age: 18}
        )

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end
  end

  # ============================================
  # Integration with other operations
  # ============================================

  describe "raw_where with other operations" do
    test "combines with standard filters" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.raw("age BETWEEN ? AND ?", [18, 65])
        |> OmQuery.order(:name, :asc)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "combines with pagination" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("status = ?", ["active"])
        |> OmQuery.paginate(:offset, limit: 20, offset: 0)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end
  end

  # ============================================
  # Batch Operations (update_all, delete_all)
  # ============================================

  describe "batch operations query building" do
    test "builds update_all query with filters only" do
      # update_all strips non-filter operations (order, pagination, etc.)
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "inactive")
        |> OmQuery.filter(:age, :gte, 18)
        |> OmQuery.order(:name, :asc)  # Should be stripped
        |> OmQuery.paginate(:offset, limit: 10)  # Should be stripped

      # The Executor.clean_token_for_bulk should strip non-filter ops
      # We test this indirectly by ensuring the token can be built
      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds delete_all query with filters only" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "deleted")
        |> OmQuery.filter(:age, :lt, 18)

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with raw_where for batch operations" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.raw("status = ? AND age > ?", ["inactive", 30])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end

    test "builds query with filter groups for batch operations" do
      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.where_any([
          {:status, :eq, "inactive"},
          {:status, :eq, "deleted"}
        ])

      query = Builder.build(token)
      assert %Ecto.Query{} = query
    end
  end

  # ============================================
  # Set Operations (union, intersect, except)
  # ============================================

  describe "set operations" do
    test "builds union query" do
      t1 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active")
      t2 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "vip")

      token = OmQuery.union(t1, t2)
      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 1
      assert {:union, _} = hd(query.combinations)
    end

    test "builds union_all query" do
      t1 = TestUser |> OmQuery.new() |> OmQuery.filter(:age, :gte, 18)
      t2 = TestUser |> OmQuery.new() |> OmQuery.filter(:age, :lt, 18)

      token = OmQuery.union_all(t1, t2)
      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 1
      assert {:union_all, _} = hd(query.combinations)
    end

    test "builds intersect query" do
      t1 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active")
      t2 = TestUser |> OmQuery.new() |> OmQuery.filter(:age, :gte, 21)

      token = OmQuery.intersect(t1, t2)
      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 1
      assert {:intersect, _} = hd(query.combinations)
    end

    test "builds except query" do
      t1 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active")
      t2 = TestUser |> OmQuery.new() |> OmQuery.filter(:age, :lt, 18)

      token = OmQuery.except(t1, t2)
      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 1
      assert {:except, _} = hd(query.combinations)
    end

    test "builds multiple set operations" do
      t1 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "active")
      t2 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "vip")
      t3 = TestUser |> OmQuery.new() |> OmQuery.filter(:status, :eq, "premium")

      token =
        t1
        |> OmQuery.union(t2)
        |> OmQuery.union(t3)

      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 2
    end

    test "set operations with Ecto.Query" do
      import Ecto.Query
      ecto_query = from(u in "users", where: u.status == "archived")

      token =
        TestUser
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.union(ecto_query)

      query = Builder.build(token)

      assert %Ecto.Query{} = query
      assert length(query.combinations) == 1
    end
  end
end
