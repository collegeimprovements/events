defmodule Events.Core.QueryTest do
  use Events.TestCase, async: true

  alias OmQuery, as: Query
  alias OmQuery.{Token, Result}

  describe "token creation" do
    test "creates token from schema" do
      token = OmQuery.new(User)
      assert %Token{source: User, operations: []} = token
    end

    test "adds filter operation" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")

      assert [filter_op] = token.operations
      assert {:filter, {:status, :eq, "active", []}} = filter_op
    end

    test "chains multiple operations" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.filter(:age, :gte, 18)
        |> OmQuery.order(:name, :asc)
        |> OmQuery.limit(10)

      assert length(token.operations) == 4
    end
  end

  describe "filter operations" do
    test "validates supported operators" do
      token = OmQuery.new(User)

      # Valid operators should work
      assert %Token{} = OmQuery.filter(token, :status, :eq, "active")
      assert %Token{} = OmQuery.filter(token, :age, :gt, 18)
      assert %Token{} = OmQuery.filter(token, :name, :like, "%john%")

      # Invalid operators should raise ValidationError
      assert_raise OmQuery.ValidationError, fn ->
        OmQuery.filter(token, :status, :invalid_op, "value")
      end
    end

    test "supports filter options" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:name, :eq, "John", case_insensitive: true)

      assert [{:filter, {:name, :eq, "John", opts}}] = token.operations
      assert opts[:case_insensitive] == true
    end
  end

  describe "pagination" do
    test "offset pagination" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.paginate(:offset, limit: 20, offset: 40)

      assert [{:paginate, {:offset, opts}}] = token.operations
      assert opts[:limit] == 20
      assert opts[:offset] == 40
    end

    test "cursor pagination" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.paginate(:cursor, cursor_fields: [:id, :created_at], limit: 10)

      assert [{:paginate, {:cursor, opts}}] = token.operations
      assert opts[:cursor_fields] == [:id, :created_at]
      assert opts[:limit] == 10
    end

    test "cursor pagination allows nil cursor_fields (will be inferred)" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.paginate(:cursor, limit: 10)

      assert [{:paginate, {:cursor, opts}}] = token.operations
      assert opts[:cursor_fields] == nil
      assert opts[:limit] == 10
    end
  end

  describe "joins" do
    test "association join" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.join(:posts, :left)

      assert [{:join, {:posts, :left, []}}] = token.operations
    end

    test "join with options" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.join(:posts, :inner, as: :user_posts)

      assert [{:join, {:posts, :inner, opts}}] = token.operations
      assert opts[:as] == :user_posts
    end
  end

  describe "preloads" do
    test "simple preload" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.preload(:posts)

      assert [{:preload, :posts}] = token.operations
    end

    test "multiple preloads" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.preload([:posts, :comments])

      assert [{:preload, [:posts, :comments]}] = token.operations
    end

    test "nested preload with filters" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.preload(:posts, fn posts_token ->
          posts_token
          |> OmQuery.filter(:published, :eq, true)
          |> OmQuery.limit(5)
        end)

      assert [{:preload, {:posts, nested_token}}] = token.operations
      assert %Token{} = nested_token
      assert length(nested_token.operations) == 2
    end
  end

  describe "select and grouping" do
    test "select fields" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.select([:id, :name, :email])

      assert [{:select, [:id, :name, :email]}] = token.operations
    end

    test "select with map" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.select(%{user_id: :id, user_name: :name})

      assert [{:select, select_map}] = token.operations
      assert is_map(select_map)
    end

    test "group by and having" do
      token =
        Order
        |> OmQuery.new()
        |> OmQuery.group_by([:status])
        |> OmQuery.having(count: {:gte, 5})

      assert length(token.operations) == 2
      assert [{:group_by, [:status]}, {:having, [count: {:gte, 5}]}] = token.operations
    end
  end

  describe "CTEs and windows" do
    test "adds CTE" do
      cte_token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:active, :eq, true)

      token =
        Order
        |> OmQuery.new()
        |> OmQuery.with_cte(:active_users, cte_token)

      assert [{:cte, {:active_users, ^cte_token}}] = token.operations
    end

    test "adds recursive CTE" do
      import Ecto.Query

      # Create a simple CTE query
      base_query = from(c in "categories", select: c)

      token =
        Order
        |> OmQuery.new()
        |> OmQuery.with_cte(:category_tree, base_query, recursive: true)

      assert [{:cte, {:category_tree, %Ecto.Query{}, [recursive: true]}}] = token.operations
    end

    test "adds window definition" do
      token =
        Sale
        |> OmQuery.new()
        |> OmQuery.window(:running_total, partition_by: :product_id, order_by: [asc: :date])

      assert [{:window, {:running_total, _opts}}] = token.operations
    end

    test "adds window definition with frame" do
      token =
        Sale
        |> OmQuery.new()
        |> OmQuery.window(:moving_avg,
          order_by: [asc: :date],
          frame: {:rows, {:preceding, 1}, {:following, 1}}
        )

      [{:window, {:moving_avg, opts}}] = token.operations
      assert opts[:frame] == {:rows, {:preceding, 1}, {:following, 1}}
    end

    test "adds window definition with unbounded frame" do
      token =
        Sale
        |> OmQuery.new()
        |> OmQuery.window(:running_sum,
          partition_by: :category_id,
          order_by: [asc: :date],
          frame: {:rows, :unbounded_preceding, :current_row}
        )

      [{:window, {:running_sum, opts}}] = token.operations
      assert opts[:partition_by] == :category_id
      assert opts[:frame] == {:rows, :unbounded_preceding, :current_row}
    end
  end

  describe "raw SQL" do
    test "raw where clause" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.raw_where("age BETWEEN :min AND :max", %{min: 18, max: 65})

      assert [{:raw_where, {sql, params}}] = token.operations
      assert sql =~ ":min"
      assert params[:min] == 18
    end
  end

  describe "token operations" do
    test "get operations by type" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.filter(:age, :gt, 18)
        |> OmQuery.order(:name, :asc)

      filter_ops = Token.get_operations(token, :filter)
      assert length(filter_ops) == 2

      order_ops = Token.get_operations(token, :order)
      assert length(order_ops) == 1
    end

    test "remove operations by type" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
        |> OmQuery.order(:name, :asc)
        |> OmQuery.limit(10)

      token_without_limit = Token.remove_operations(token, :limit)
      assert length(token_without_limit.operations) == 2
      refute Enum.any?(token_without_limit.operations, fn {op, _} -> op == :limit end)
    end

    test "update metadata" do
      token =
        User
        |> OmQuery.new()
        |> Token.put_metadata(:custom_key, "custom_value")

      assert token.metadata[:custom_key] == "custom_value"
    end
  end

  describe "result structure" do
    test "creates success result" do
      result = Result.success([%{id: 1}, %{id: 2}])

      assert %Result{} = result
      assert result.data == [%{id: 1}, %{id: 2}]
      assert result.metadata.cached == false
    end

    test "creates paginated result with offset" do
      data = Enum.map(1..20, &%{id: &1})

      result =
        Result.paginated(data,
          pagination_type: :offset,
          limit: 20,
          offset: 0,
          total_count: 100
        )

      assert result.pagination.type == :offset
      assert result.pagination.limit == 20
      assert result.pagination.has_more == true
      assert result.pagination.total_count == 100
      assert result.pagination.current_page == 1
      assert result.pagination.total_pages == 5
    end

    test "creates paginated result with cursor" do
      data = [
        %{id: 1, created_at: ~N[2024-01-01 00:00:00]},
        %{id: 2, created_at: ~N[2024-01-02 00:00:00]}
      ]

      result =
        Result.paginated(data,
          pagination_type: :cursor,
          cursor_fields: [:id],
          limit: 2
        )

      assert result.pagination.type == :cursor
      assert result.pagination.start_cursor != nil
      assert result.pagination.end_cursor != nil
    end
  end

  describe "automatic safety limits" do
    test "queries without pagination have no automatic limit at token level" do
      # The automatic limit is applied at execution time, not token building time
      token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "active")

      # Token should not have limit operation yet
      assert [{:filter, _}] = token.operations
      refute Enum.any?(token.operations, fn {op, _} -> op == :limit end)
    end

    test "respects explicit pagination" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "active")
        |> OmQuery.paginate(:cursor, limit: 50)

      # Should have filter and paginate operations
      assert [{:filter, _}, {:paginate, _}] = token.operations
    end

    test "respects explicit limit" do
      token =
        User
        |> OmQuery.new()
        |> OmQuery.where(:status, :eq, "active")
        |> OmQuery.limit(100)

      # Should have filter and limit, no automatic limit needed
      assert [{:filter, _}, {:limit, 100}] = token.operations
    end

    test "limit validation enforces max_limit" do
      token = OmQuery.new(User)

      # Should raise LimitExceededError when limit exceeds max
      assert_raise OmQuery.LimitExceededError, fn ->
        OmQuery.limit(token, 10_000)
      end
    end

    test "pagination validation enforces max_limit" do
      token = OmQuery.new(User)

      # Should raise LimitExceededError when pagination limit exceeds max
      assert_raise OmQuery.LimitExceededError, fn ->
        OmQuery.paginate(token, :offset, limit: 10_000)
      end
    end
  end

  describe "safe error patterns" do
    test "Token.add_operation_safe returns {:ok, token} on success" do
      token = Token.new(User)

      assert {:ok, updated_token} =
               Token.add_operation_safe(token, {:filter, {:status, :eq, "active", []}})

      assert length(updated_token.operations) == 1
    end

    test "Token.add_operation_safe returns {:error, exception} on validation failure" do
      token = Token.new(User)

      assert {:error, %OmQuery.ValidationError{}} =
               Token.add_operation_safe(token, {:filter, {:status, :invalid_op, "value", []}})
    end

    test "Token.add_operation_safe returns {:error, LimitExceededError} for excessive limits" do
      token = Token.new(User)

      assert {:error, %OmQuery.LimitExceededError{}} =
               Token.add_operation_safe(token, {:limit, 10_000})
    end

    test "Token.add_operation! raises on validation failure" do
      token = Token.new(User)

      assert_raise OmQuery.ValidationError, fn ->
        Token.add_operation!(token, {:filter, {:status, :invalid_op, "value", []}})
      end
    end

    test "OmQuery.build_safe returns {:ok, query} on success" do
      # Use an existing Ecto query with the :root binding
      import Ecto.Query
      base_query = from(u in "users", as: :root)
      token = OmQuery.new(base_query) |> OmQuery.filter(:status, :eq, "active")

      assert {:ok, %Ecto.Query{}} = OmQuery.build_safe(token)
    end

    test "OmQuery.build! works with valid token" do
      # Use an existing Ecto query with the :root binding
      import Ecto.Query
      base_query = from(u in "users", as: :root)
      token = OmQuery.new(base_query)

      assert %Ecto.Query{} = OmQuery.build!(token)
    end
  end
end
