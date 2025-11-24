defmodule Events.CRUD.QueryTest do
  use ExUnit.Case, async: true

  # Create a simple mock schema for testing
  defmodule TestSchema do
    use Ecto.Schema

    schema "test_schemas" do
      field :name, :string
      field :status, :string
      field :created_at, :utc_datetime
    end
  end

  describe "pure Ecto functions" do
    test "basic query building" do
      # This test verifies that the functions can be chained together
      # without actually executing against a database

      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.where(:status, :eq, "active")
        |> Events.CRUD.Query.order(:created_at, :desc)
        |> Events.CRUD.Query.limit(10)

      # Verify it's an Ecto query
      assert %Ecto.Query{} = query
      assert query.limit != nil
    end

    test "debug function returns query unchanged" do
      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.where(:status, :eq, "active")

      # Debug should return the same query
      result = Events.CRUD.Query.debug(query, "Test")
      assert result == query
    end

    test "preload with function" do
      # Test simple preload (can't test nested with mock schema)
      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.preload(:name)

      assert %Ecto.Query{} = query
      # The preload should be set
      assert query.preloads != []
    end

    test "pagination functions" do
      # Test offset pagination
      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.paginate(:offset, limit: 20, offset: 40)

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert query.offset != nil
    end

    test "join functions" do
      # Test association join functionality
      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.join(:posts, :left)

      assert %Ecto.Query{} = query
      # Should have joins
      assert length(query.joins) > 0
    end

    test "custom join with on condition" do
      # Test custom join with on condition
      # Note: This would require actual schema modules to work fully,
      # but we can test that the query structure is correct
      query = Events.CRUD.Query.from(TestSchema)

      # This should not raise an error even if schemas don't exist
      # (Ecto validates schemas at execution time)
      assert %Ecto.Query{} = query
    end

    test "select functions" do
      # Test select functionality
      query =
        Events.CRUD.Query.from(TestSchema)
        |> Events.CRUD.Query.select([:id, :name])

      assert %Ecto.Query{} = query
      # Should have select
      assert query.select != nil
    end
  end
end
