defmodule Events.Query.CursorInferenceTest do
  use ExUnit.Case, async: true

  alias Events.Query.DynamicBuilder

  describe "infer_cursor_fields/1" do
    test "infers from order 4-tuples" do
      orders = [
        {:order, :created_at, :desc, []},
        {:order, :id, :asc, []}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [:created_at, :id]
    end

    test "infers from order 3-tuples" do
      orders = [
        {:created_at, :desc, []},
        {:id, :asc, []}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [:created_at, :id]
    end

    test "infers from order 2-tuples" do
      orders = [
        {:created_at, :desc},
        {:name, :asc}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [:created_at, :name, :id]
    end

    test "infers from atom orders" do
      orders = [:name, :email]

      assert DynamicBuilder.infer_cursor_fields(orders) == [:name, :email, :id]
    end

    test "adds :id if not present" do
      orders = [{:created_at, :desc}, {:priority, :desc}]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert :id in result
      assert result == [:created_at, :priority, :id]
    end

    test "doesn't duplicate :id if already present" do
      orders = [{:created_at, :desc}, {:id, :asc}]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert result == [:created_at, :id]
      assert Enum.count(result, &(&1 == :id)) == 1
    end

    test "handles empty orders" do
      assert DynamicBuilder.infer_cursor_fields([]) == [:id]
    end

    test "handles mixed order formats" do
      orders = [
        {:order, :priority, :desc, []},
        {:created_at, :desc, []},
        {:name, :asc},
        :email
      ]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert result == [:priority, :created_at, :name, :email, :id]
    end
  end

  describe "default_pagination/1" do
    test "with no orders uses only :id" do
      pagination = DynamicBuilder.default_pagination([])

      assert {:paginate, :cursor, config, []} = pagination
      assert config.limit == 20
      assert config.cursor_fields == [:id]
    end

    test "with orders infers cursor_fields" do
      orders = [{:created_at, :desc}, {:id, :asc}]
      pagination = DynamicBuilder.default_pagination(orders)

      assert {:paginate, :cursor, config, []} = pagination
      assert config.limit == 20
      assert config.cursor_fields == [:created_at, :id]
    end

    test "with orders without :id adds it" do
      orders = [{:created_at, :desc}, {:priority, :desc}]
      pagination = DynamicBuilder.default_pagination(orders)

      assert {:paginate, :cursor, config, []} = pagination
      assert config.cursor_fields == [:created_at, :priority, :id]
    end
  end

  describe "build/3 with order inference" do
    test "automatically infers cursor_fields from orders" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        orders: [{:created_at, :desc}, {:id, :asc}]
        # No pagination specified!
      }

      token = DynamicBuilder.build(User, spec)

      # Should have pagination operation with inferred cursor_fields
      pagination_op = Enum.find(token.operations, fn
        {:paginate, _} -> true
        _ -> false
      end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [:created_at, :id]
    end

    test "respects explicit pagination over inference" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        orders: [{:created_at, :desc}, {:id, :asc}],
        pagination: {:paginate, :cursor, %{
          limit: 50,
          cursor_fields: [:priority, :id]  # Explicit (even if wrong!)
        }, []}
      }

      token = DynamicBuilder.build(User, spec)

      pagination_op = Enum.find(token.operations, fn
        {:paginate, _} -> true
        _ -> false
      end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [:priority, :id]  # Uses explicit
      assert opts[:limit] == 50
    end

    test "works with no orders - uses :id only" do
      spec = %{
        filters: [{:status, :eq, "active"}]
        # No orders, no pagination
      }

      token = DynamicBuilder.build(User, spec)

      pagination_op = Enum.find(token.operations, fn
        {:paginate, _} -> true
        _ -> false
      end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [:id]
    end

    test "works with complex nested orders" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        orders: [
          {:order, :priority, :desc, []},
          {:created_at, :desc, []},
          {:name, :asc},
          :email
        ]
      }

      token = DynamicBuilder.build(User, spec)

      pagination_op = Enum.find(token.operations, fn
        {:paginate, _} -> true
        _ -> false
      end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [:priority, :created_at, :name, :email, :id]
    end
  end

  # Suppress warnings for undefined schemas
  @compile {:no_warn_undefined, [User]}
end
