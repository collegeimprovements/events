defmodule Events.Query.DynamicBuilderFormatsTest do
  use ExUnit.Case, async: true

  alias Events.Query.DynamicBuilder

  @moduledoc """
  Test that all filter and order formats work interchangeably.
  """

  describe "filter format normalization" do
    test "5-tuple with :filter tag normalizes correctly" do
      input = [{:filter, :status, :eq, "active", []}]
      expected = [{:filter, :status, :eq, "active", []}]

      assert DynamicBuilder.normalize_spec(input, :filter) == expected
    end

    test "4-tuple without tag normalizes correctly" do
      input = [{:status, :eq, "active", []}]
      expected = [{:filter, :status, :eq, "active", []}]

      assert DynamicBuilder.normalize_spec(input, :filter) == expected
    end

    test "3-tuple without tag normalizes correctly" do
      input = [{:status, :eq, "active"}]
      expected = [{:filter, :status, :eq, "active", []}]

      assert DynamicBuilder.normalize_spec(input, :filter) == expected
    end

    test "keyword list with 'filter:' key normalizes correctly" do
      input = [[filter: {:status, :eq, "active"}]]
      expected = [{:filter, :status, :eq, "active", []}]

      assert DynamicBuilder.normalize_spec(input, :filter) == expected
    end

    test "keyword list with 4-tuple value normalizes correctly" do
      input = [[filter: {:status, :eq, "active", []}]]
      expected = [{:filter, :status, :eq, "active", []}]

      assert DynamicBuilder.normalize_spec(input, :filter) == expected
    end

    test "multiple filters in different formats all work" do
      input = [
        {:filter, :status, :eq, "active", []},
        {:age, :gte, 18, []},
        {:verified, :eq, true},
        [filter: {:role, :in, ["admin", "editor"]}]
      ]

      result = DynamicBuilder.normalize_spec(input, :filter)

      assert length(result) == 4
      assert Enum.all?(result, fn {tag, _, _, _, _} -> tag == :filter end)
    end

    test "mixed filter formats produce same token operations" do
      # Format 1: 5-tuple
      spec1 = %{
        filters: [{:filter, :status, :eq, "active", []}, {:filter, :age, :gte, 18, []}]
      }

      # Format 2: 4-tuple
      spec2 = %{
        filters: [{:status, :eq, "active", []}, {:age, :gte, 18, []}]
      }

      # Format 3: 3-tuple
      spec3 = %{
        filters: [{:status, :eq, "active"}, {:age, :gte, 18}]
      }

      # Format 4: keyword list
      spec4 = %{
        filters: [[filter: {:status, :eq, "active"}], [filter: {:age, :gte, 18}]]
      }

      # All should produce identical normalized filters
      normalized1 = DynamicBuilder.normalize_spec(spec1.filters, :filter)
      normalized2 = DynamicBuilder.normalize_spec(spec2.filters, :filter)
      normalized3 = DynamicBuilder.normalize_spec(spec3.filters, :filter)
      normalized4 = DynamicBuilder.normalize_spec(spec4.filters, :filter)

      assert normalized1 == normalized2
      assert normalized2 == normalized3
      assert normalized3 == normalized4
    end
  end

  describe "order format normalization" do
    test "4-tuple with :order tag normalizes correctly" do
      input = [{:order, :created_at, :desc, []}]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "3-tuple without tag normalizes correctly" do
      input = [{:created_at, :desc, []}]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "2-tuple without tag normalizes correctly" do
      input = [{:created_at, :desc}]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "single atom defaults to :asc" do
      input = [:name, :email, :id]
      result = DynamicBuilder.normalize_spec(input, :order)

      assert result == [
               {:order, :name, :asc, []},
               {:order, :email, :asc, []},
               {:order, :id, :asc, []}
             ]
    end

    test "keyword list with 'order:' key normalizes correctly" do
      input = [[order: {:created_at, :desc}]]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "keyword list with 'order_by:' key normalizes correctly" do
      input = [[order_by: {:created_at, :desc}]]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "keyword list with 3-tuple value normalizes correctly" do
      input = [[order: {:created_at, :desc, []}]]
      expected = [{:order, :created_at, :desc, []}]

      assert DynamicBuilder.normalize_spec(input, :order) == expected
    end

    test "multiple orders in different formats all work" do
      input = [
        {:order, :priority, :desc, []},
        {:created_at, :desc, []},
        {:name, :asc},
        :id,
        [order_by: {:updated_at, :desc}]
      ]

      result = DynamicBuilder.normalize_spec(input, :order)

      assert length(result) == 5
      assert Enum.all?(result, fn {tag, _, _, _} -> tag == :order end)
    end

    test "mixed order formats produce same token operations" do
      # Format 1: 4-tuple
      spec1 = %{
        orders: [{:order, :created_at, :desc, []}, {:order, :id, :asc, []}]
      }

      # Format 2: 3-tuple
      spec2 = %{
        orders: [{:created_at, :desc, []}, {:id, :asc, []}]
      }

      # Format 3: 2-tuple
      spec3 = %{
        orders: [{:created_at, :desc}, {:id, :asc}]
      }

      # Format 4: keyword list with order:
      spec4 = %{
        orders: [[order: {:created_at, :desc}], [order: {:id, :asc}]]
      }

      # Format 5: keyword list with order_by:
      spec5 = %{
        orders: [[order_by: {:created_at, :desc}], [order_by: {:id, :asc}]]
      }

      # All should produce identical normalized orders
      normalized1 = DynamicBuilder.normalize_spec(spec1.orders, :order)
      normalized2 = DynamicBuilder.normalize_spec(spec2.orders, :order)
      normalized3 = DynamicBuilder.normalize_spec(spec3.orders, :order)
      normalized4 = DynamicBuilder.normalize_spec(spec4.orders, :order)
      normalized5 = DynamicBuilder.normalize_spec(spec5.orders, :order)

      assert normalized1 == normalized2
      assert normalized2 == normalized3
      assert normalized3 == normalized4
      assert normalized4 == normalized5
    end
  end

  describe "nested specs with flexible formats" do
    test "nested preloads accept flexible filter formats" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        preloads: [
          {:preload, :posts, %{
            filters: [
              {:published, :eq, true},
              [filter: {:featured, :eq, true}]
            ],
            orders: [
              {:created_at, :desc},
              [order_by: {:priority, :desc}]
            ]
          }, []}
        ]
      }

      # Should normalize without errors
      normalized_filters = DynamicBuilder.normalize_spec(spec.filters, :filter)
      assert length(normalized_filters) == 1

      # Nested filters should also normalize
      {:preload, _assoc, nested_spec, _opts} = spec.preloads |> hd()
      nested_filters = nested_spec[:filters]
      normalized_nested = DynamicBuilder.normalize_spec(nested_filters, :filter)
      assert length(normalized_nested) == 2
    end

    test "3-level nesting with mixed formats works" do
      spec = %{
        filters: [{:status, :eq, "active"}],
        preloads: [
          {:preload, :posts, %{
            filters: [[filter: {:published, :eq, true}]],
            orders: [[order: {:created_at, :desc}]],
            preloads: [
              {:preload, :comments, %{
                filters: [{:approved, :eq, true}],
                orders: [{:created_at, :asc}]
              }, []}
            ]
          }, []}
        ]
      }

      # All levels should normalize correctly
      assert length(DynamicBuilder.normalize_spec(spec.filters, :filter)) == 1

      {:preload, _assoc2, level2, _opts2} = spec.preloads |> hd()
      assert length(DynamicBuilder.normalize_spec(level2[:filters], :filter)) == 1
      assert length(DynamicBuilder.normalize_spec(level2[:orders], :order)) == 1

      {:preload, _assoc3, level3, _opts3} = level2[:preloads] |> hd()
      assert length(DynamicBuilder.normalize_spec(level3[:filters], :filter)) == 1
      assert length(DynamicBuilder.normalize_spec(level3[:orders], :order)) == 1
    end
  end

  describe "comprehensive format equivalence" do
    test "all filter formats are truly interchangeable" do
      # All these should be equivalent
      formats = [
        # Format 1: Full 5-tuple
        [{:filter, :status, :eq, "active", []}],
        # Format 2: 4-tuple without tag
        [{:status, :eq, "active", []}],
        # Format 3: 3-tuple without tag
        [{:status, :eq, "active"}],
        # Format 4: keyword with filter:
        [[filter: {:status, :eq, "active"}]],
        # Format 5: keyword with filter: and 4-tuple
        [[filter: {:status, :eq, "active", []}]]
      ]

      results = Enum.map(formats, fn format ->
        DynamicBuilder.normalize_spec(format, :filter)
      end)

      # All should normalize to the same result
      expected = [{:filter, :status, :eq, "active", []}]
      assert Enum.all?(results, fn result -> result == expected end)
    end

    test "all order formats are truly interchangeable" do
      # All these should be equivalent
      formats = [
        # Format 1: Full 4-tuple with tag
        [{:order, :created_at, :desc, []}],
        # Format 2: 3-tuple without tag
        [{:created_at, :desc, []}],
        # Format 3: 2-tuple without tag
        [{:created_at, :desc}],
        # Format 4: keyword with order:
        [[order: {:created_at, :desc}]],
        # Format 5: keyword with order_by:
        [[order_by: {:created_at, :desc}]],
        # Format 6: keyword with order: and 3-tuple
        [[order: {:created_at, :desc, []}]]
      ]

      results = Enum.map(formats, fn format ->
        DynamicBuilder.normalize_spec(format, :order)
      end)

      # All should normalize to the same result
      expected = [{:order, :created_at, :desc, []}]
      assert Enum.all?(results, fn result -> result == expected end)
    end

    test "complex real-world spec with all mixed formats" do
      spec = %{
        filters: [
          {:filter, :status, :eq, "active", []},
          {:age, :gte, 18, []},
          {:verified, :eq, true},
          [filter: {:role, :in, ["admin"]}]
        ],
        orders: [
          {:order, :priority, :desc, []},
          {:created_at, :desc, []},
          {:name, :asc},
          :id,
          [order_by: {:score, :desc}]
        ]
      }

      normalized_filters = DynamicBuilder.normalize_spec(spec.filters, :filter)
      normalized_orders = DynamicBuilder.normalize_spec(spec.orders, :order)

      # Should have all filters
      assert length(normalized_filters) == 4
      assert Enum.all?(normalized_filters, fn {tag, _, _, _, _} -> tag == :filter end)

      # Should have all orders
      assert length(normalized_orders) == 5
      assert Enum.all?(normalized_orders, fn {tag, _, _, _} -> tag == :order end)

      # Verify specific normalized values
      assert {:filter, :status, :eq, "active", []} in normalized_filters
      assert {:filter, :age, :gte, 18, []} in normalized_filters
      assert {:filter, :verified, :eq, true, []} in normalized_filters
      assert {:filter, :role, :in, ["admin"], []} in normalized_filters

      assert {:order, :priority, :desc, []} in normalized_orders
      assert {:order, :created_at, :desc, []} in normalized_orders
      assert {:order, :name, :asc, []} in normalized_orders
      assert {:order, :id, :asc, []} in normalized_orders
      assert {:order, :score, :desc, []} in normalized_orders
    end
  end

  describe "empty and edge cases" do
    test "empty list returns empty" do
      assert DynamicBuilder.normalize_spec([], :filter) == []
      assert DynamicBuilder.normalize_spec([], :order) == []
    end

    test "nested empty keyword list returns empty" do
      assert DynamicBuilder.normalize_spec([[]], :filter) == []
      assert DynamicBuilder.normalize_spec([[]], :order) == []
    end

    test "mixed valid and invalid keys in keyword list" do
      input = [[filter: {:status, :eq, "active"}], [other: {:foo, :bar}]]
      result = DynamicBuilder.normalize_spec(input, :filter)

      # Only valid filter should be included
      assert result == [{:filter, :status, :eq, "active", []}]
    end
  end
end
