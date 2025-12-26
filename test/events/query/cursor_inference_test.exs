defmodule Events.Core.Query.CursorInferenceTest do
  use Events.TestCase, async: true

  alias OmQuery.DynamicBuilder

  describe "infer_cursor_fields/1" do
    test "infers from order 4-tuples" do
      orders = [
        {:order, :created_at, :desc, []},
        {:order, :id, :asc, []}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [{:created_at, :desc}, {:id, :asc}]
    end

    test "infers from order 3-tuples" do
      orders = [
        {:created_at, :desc, []},
        {:id, :asc, []}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [{:created_at, :desc}, {:id, :asc}]
    end

    test "infers from order 2-tuples" do
      orders = [
        {:created_at, :desc},
        {:name, :asc}
      ]

      assert DynamicBuilder.infer_cursor_fields(orders) == [
               {:created_at, :desc},
               {:name, :asc},
               {:id, :asc}
             ]
    end

    test "infers from atom orders" do
      orders = [:name, :email]

      assert DynamicBuilder.infer_cursor_fields(orders) == [
               {:name, :asc},
               {:email, :asc},
               {:id, :asc}
             ]
    end

    test "adds :id if not present" do
      orders = [{:created_at, :desc}, {:priority, :desc}]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert {:id, :asc} in result
      assert result == [{:created_at, :desc}, {:priority, :desc}, {:id, :asc}]
    end

    test "doesn't duplicate :id if already present" do
      orders = [{:created_at, :desc}, {:id, :asc}]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert result == [{:created_at, :desc}, {:id, :asc}]
      assert Enum.count(result, fn {field, _} -> field == :id end) == 1
    end

    test "handles empty orders" do
      assert DynamicBuilder.infer_cursor_fields([]) == [{:id, :asc}]
    end

    test "handles mixed order formats" do
      orders = [
        {:order, :priority, :desc, []},
        {:created_at, :desc, []},
        {:name, :asc},
        :email
      ]

      result = DynamicBuilder.infer_cursor_fields(orders)

      assert result == [
               {:priority, :desc},
               {:created_at, :desc},
               {:name, :asc},
               {:email, :asc},
               {:id, :asc}
             ]
    end
  end

  describe "default_pagination/1" do
    test "with no orders uses only :id" do
      pagination = DynamicBuilder.default_pagination([])

      assert {:paginate, :cursor, config, []} = pagination
      assert config.limit == 20
      assert config.cursor_fields == [{:id, :asc}]
    end

    test "with orders infers cursor_fields" do
      orders = [{:created_at, :desc}, {:id, :asc}]
      pagination = DynamicBuilder.default_pagination(orders)

      assert {:paginate, :cursor, config, []} = pagination
      assert config.limit == 20
      assert config.cursor_fields == [{:created_at, :desc}, {:id, :asc}]
    end

    test "with orders without :id adds it" do
      orders = [{:created_at, :desc}, {:priority, :desc}]
      pagination = DynamicBuilder.default_pagination(orders)

      assert {:paginate, :cursor, config, []} = pagination
      assert config.cursor_fields == [{:created_at, :desc}, {:priority, :desc}, {:id, :asc}]
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
      pagination_op =
        Enum.find(token.operations, fn
          {:paginate, _} -> true
          _ -> false
        end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [{:created_at, :desc}, {:id, :asc}]
    end

    test "respects explicit pagination over inference" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        orders: [{:created_at, :desc}, {:id, :asc}],
        pagination:
          {:paginate, :cursor,
           %{
             limit: 50,
             # Explicit (must match orders!)
             cursor_fields: [{:created_at, :desc}, {:id, :asc}]
           }, []}
      }

      token = DynamicBuilder.build(User, spec)

      pagination_op =
        Enum.find(token.operations, fn
          {:paginate, _} -> true
          _ -> false
        end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      # Uses explicit
      assert opts[:cursor_fields] == [{:created_at, :desc}, {:id, :asc}]
      assert opts[:limit] == 50
    end

    test "works with no orders - uses :id only" do
      spec = %{
        filters: [{:status, :eq, "active"}]
        # No orders, no pagination
      }

      token = DynamicBuilder.build(User, spec)

      pagination_op =
        Enum.find(token.operations, fn
          {:paginate, _} -> true
          _ -> false
        end)

      assert {:paginate, {:cursor, opts}} = pagination_op
      assert opts[:cursor_fields] == [{:id, :asc}]
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

      pagination_op =
        Enum.find(token.operations, fn
          {:paginate, _} -> true
          _ -> false
        end)

      assert {:paginate, {:cursor, opts}} = pagination_op

      assert opts[:cursor_fields] == [
               {:priority, :desc},
               {:created_at, :desc},
               {:name, :asc},
               {:email, :asc},
               {:id, :asc}
             ]
    end
  end

  describe "validation failures" do
    test "raises ArgumentError when cursor_fields don't match order_by" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        orders: [{:created_at, :desc}, {:id, :asc}],
        pagination:
          {:paginate, :cursor,
           %{
             limit: 20,
             # WRONG! Doesn't match orders
             cursor_fields: [{:priority, :desc}, {:id, :asc}]
           }, []}
      }

      assert_raise ArgumentError, ~r/Invalid cursor pagination configuration/, fn ->
        DynamicBuilder.build(User, spec)
      end
    end

    test "raises ArgumentError when cursor_fields have wrong direction" do
      spec = %{
        orders: [{:title, :asc}, {:id, :asc}],
        pagination:
          {:paginate, :cursor,
           %{
             limit: 20,
             # Wrong direction for :title!
             cursor_fields: [{:title, :desc}, {:id, :asc}]
           }, []}
      }

      assert_raise ArgumentError, ~r/direction for :title must be :asc/, fn ->
        DynamicBuilder.build(User, spec)
      end
    end

    test "raises ArgumentError when cursor_fields have wrong order" do
      spec = %{
        orders: [{:title, :asc}, {:age, :desc}],
        pagination:
          {:paginate, :cursor,
           %{
             limit: 20,
             # Wrong order!
             cursor_fields: [{:age, :desc}, {:title, :asc}]
           }, []}
      }

      assert_raise ArgumentError, ~r/field order must match/, fn ->
        DynamicBuilder.build(User, spec)
      end
    end

    test "raises ArgumentError when cursor_fields missing required fields" do
      spec = %{
        orders: [{:priority, :desc}, {:created_at, :desc}, {:id, :asc}],
        pagination:
          {:paginate, :cursor,
           %{
             limit: 20,
             # Missing :created_at!
             cursor_fields: [{:priority, :desc}, {:id, :asc}]
           }, []}
      }

      assert_raise ArgumentError, ~r/Invalid cursor pagination configuration/, fn ->
        DynamicBuilder.build(User, spec)
      end
    end
  end

  # Suppress warnings for undefined schemas
  @compile {:no_warn_undefined, [User]}
end
