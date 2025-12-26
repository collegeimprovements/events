defmodule Events.OrderPolymorphicTest do
  use Events.TestCase, async: true

  alias Events.Core.Query

  describe "order_by/order - Ecto keyword syntax vs tuple syntax" do
    test "Ecto keyword syntax - [asc: :field, desc: :field]" do
      token =
        User
        |> Query.new()
        |> Query.order_by(asc: :name, desc: :created_at, asc: :id)

      assert length(token.operations) == 3

      assert [
               {:order, {:name, :asc, []}},
               {:order, {:created_at, :desc, []}},
               {:order, {:id, :asc, []}}
             ] = token.operations
    end

    test "Ecto keyword syntax with null handling" do
      token =
        User
        |> Query.new()
        |> Query.order_by(desc_nulls_first: :score, asc_nulls_last: :name)

      assert length(token.operations) == 2

      assert [{:order, {:score, :desc_nulls_first, []}}, {:order, {:name, :asc_nulls_last, []}}] =
               token.operations
    end

    test "tuple syntax - [{:field, :direction}]" do
      token =
        User
        |> Query.new()
        |> Query.order_by([{:name, :asc}, {:created_at, :desc}, {:id, :asc}])

      assert length(token.operations) == 3

      assert [
               {:order, {:name, :asc, []}},
               {:order, {:created_at, :desc, []}},
               {:order, {:id, :asc, []}}
             ] = token.operations
    end

    test "both syntaxes produce same result" do
      # Ecto keyword syntax
      token1 = User |> Query.new() |> Query.order_by(asc: :name, desc: :age)

      # Tuple syntax
      token2 = User |> Query.new() |> Query.order_by([{:name, :asc}, {:age, :desc}])

      # Should be identical
      assert token1.operations == token2.operations
    end

    test "mixed syntaxes in one call" do
      token =
        User
        |> Query.new()
        |> Query.order_by([
          # Plain atom
          :status,
          # Tuple
          {:created_at, :desc},
          # Ecto keyword (must be last)
          asc: :name,
          # Ecto with nulls (must be last)
          desc_nulls_first: :score
        ])

      assert length(token.operations) == 4
    end
  end

  describe "order_by/order - polymorphic behavior" do
    test "order_by with single field" do
      token =
        User
        |> Query.new()
        |> Query.order_by(:name)

      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "order_by with single field and direction" do
      token =
        User
        |> Query.new()
        |> Query.order_by(:created_at, :desc)

      assert [{:order, {:created_at, :desc, []}}] = token.operations
    end

    test "order_by with list of fields" do
      token =
        User
        |> Query.new()
        |> Query.order_by([{:priority, :desc}, {:created_at, :desc}, :id])

      assert length(token.operations) == 3

      assert [
               {:order, {:priority, :desc, []}},
               {:order, {:created_at, :desc, []}},
               {:order, {:id, :asc, []}}
             ] = token.operations
    end

    test "order_by with list containing various formats" do
      token =
        User
        |> Query.new()
        |> Query.order_by([
          # atom (defaults to :asc)
          :name,
          # 2-tuple
          {:age, :desc},
          # 3-tuple with opts
          {:created_at, :desc, binding: :posts}
        ])

      assert length(token.operations) == 3

      assert [
               {:order, {:name, :asc, []}},
               {:order, {:age, :desc, []}},
               {:order, {:created_at, :desc, opts}}
             ] = token.operations

      assert opts[:binding] == :posts
    end

    test "order (alias) with single field" do
      token =
        User
        |> Query.new()
        |> Query.order(:name)

      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "order (alias) with list of fields" do
      token =
        User
        |> Query.new()
        |> Query.order([{:priority, :desc}, :id])

      assert length(token.operations) == 2
    end

    test "can mix single and list calls" do
      token =
        User
        |> Query.new()
        |> Query.order_by(:status)
        |> Query.order_by([{:priority, :desc}, {:created_at, :desc}])
        |> Query.order_by(:id)

      assert length(token.operations) == 4
    end

    test "list form is same as order_bys" do
      list = [{:priority, :desc}, {:created_at, :desc}, :id]

      token1 = User |> Query.new() |> Query.order_by(list)
      token2 = User |> Query.new() |> Query.order_bys(list)

      assert token1.operations == token2.operations
    end

    test "list form is same as orders" do
      list = [{:priority, :desc}, :id]

      token1 = User |> Query.new() |> Query.order(list)
      token2 = User |> Query.new() |> Query.orders(list)

      assert token1.operations == token2.operations
    end
  end

  describe "order_by/order in DSL" do
    import OmQuery.DSL

    test "DSL order with single field" do
      token =
        query User do
          order(:name, :asc)
        end

      assert [{:order, {:name, :asc, []}}] = token.operations
    end

    test "DSL order with list" do
      token =
        query User do
          order([{:priority, :desc}, {:created_at, :desc}, :id])
        end

      assert length(token.operations) == 3
    end

    test "DSL orders (plural) still works" do
      token =
        query User do
          orders([{:priority, :desc}, :id])
        end

      assert length(token.operations) == 2
    end
  end
end
