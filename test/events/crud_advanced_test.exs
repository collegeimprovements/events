defmodule Events.CRUDAdvancedTest do
  use ExUnit.Case, async: true

  describe "token operations" do
    test "cursor pagination with fields" do
      token =
        Events.CRUD.Token.new()
        |> Events.CRUD.Token.add({:where, {:status, :eq, "published", []}})
        |> Events.CRUD.Token.add({:order, {:published_at, :desc, []}})
        |> Events.CRUD.Token.add({:order, {:id, :asc, []}})
        |> Events.CRUD.Token.add(
          {:paginate, {:cursor, [limit: 20, cursor_fields: [published_at: :desc, id: :asc]]}}
        )

      assert length(token.operations) == 4
    end

    test "raw SQL with named placeholders" do
      token =
        Events.CRUD.Token.new()
        |> Events.CRUD.Token.add(
          {:raw,
           {:sql,
            """
            WITH user_stats AS (
              SELECT u.id, COUNT(p.id) as posts
              FROM users u LEFT JOIN posts p ON p.user_id = u.id
              WHERE u.created_at >= :start_date
              GROUP BY u.id
            )
            SELECT * FROM user_stats
            WHERE posts > :min_posts
            ORDER BY posts DESC
            LIMIT :limit
            """,
            %{
              start_date: ~U[2024-01-01 00:00:00Z],
              min_posts: 5,
              limit: 100
            }}}
        )

      assert length(token.operations) == 1
      assert {:raw, {:sql, _sql, params}} = hd(token.operations)
      assert params[:start_date] == ~U[2024-01-01 00:00:00Z]
    end

    test "operation composition" do
      # Base query
      base = Events.CRUD.Token.add(Events.CRUD.Token.new(), {:where, {:status, :eq, "active", []}})

      # Add ordering
      ordered = Events.CRUD.Token.add(base, {:order, {:created_at, :desc, []}})

      # Add pagination
      paginated = Events.CRUD.Token.add(ordered, {:paginate, {:offset, [limit: 20]}})

      assert length(paginated.operations) == 3
    end
  end

  describe "result metadata" do
    test "result includes comprehensive metadata" do
      result =
        Events.CRUD.Result.success([1, 2, 3], %{
          pagination: %{type: :offset, limit: 10, has_more: true},
          timing: %{total_time: 5000},
          optimization: %{applied: true, operations_reordered: true},
          query_info: %{operation_count: 3, has_raw_sql: false}
        })

      assert result.success == true
      assert result.data == [1, 2, 3]
      assert result.metadata.pagination.type == :offset
    end

    test "CRUD-specific result helpers" do
      created = Events.CRUD.Result.created(%{id: 1, name: "Test"})
      assert created.success == true
      assert created.metadata.operation == :create

      not_found = Events.CRUD.Result.not_found()
      assert not_found.success == false
      assert not_found.error == :not_found
    end
  end
end
