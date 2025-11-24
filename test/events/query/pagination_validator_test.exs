defmodule Events.Query.PaginationValidatorTest do
  use ExUnit.Case, async: true

  alias Events.Query.PaginationValidator

  describe "infer/1" do
    test "infers from empty orders" do
      assert PaginationValidator.infer([]) == [{:id, :asc}]
    end

    test "infers with directions from 2-tuples" do
      orders = [{:created_at, :desc}, {:priority, :asc}]
      result = PaginationValidator.infer(orders)

      assert result == [{:created_at, :desc}, {:priority, :asc}, {:id, :asc}]
    end

    test "infers from atoms (defaults to :asc)" do
      orders = [:name, :email]
      result = PaginationValidator.infer(orders)

      assert result == [{:name, :asc}, {:email, :asc}, {:id, :asc}]
    end

    test "infers from 3-tuples" do
      orders = [{:created_at, :desc, []}, {:name, :asc, []}]
      result = PaginationValidator.infer(orders)

      assert result == [{:created_at, :desc}, {:name, :asc}, {:id, :asc}]
    end

    test "infers from 4-tuples" do
      orders = [{:order, :created_at, :desc, []}, {:order, :name, :asc, []}]
      result = PaginationValidator.infer(orders)

      assert result == [{:created_at, :desc}, {:name, :asc}, {:id, :asc}]
    end

    test "doesn't append :id if already present" do
      orders = [{:created_at, :desc}, {:id, :asc}]
      result = PaginationValidator.infer(orders)

      assert result == [{:created_at, :desc}, {:id, :asc}]
    end

    test "preserves :id direction if already present" do
      orders = [{:created_at, :desc}, {:id, :desc}]
      result = PaginationValidator.infer(orders)

      assert result == [{:created_at, :desc}, {:id, :desc}]
    end

    test "handles mixed formats" do
      orders = [
        {:order, :priority, :desc, []},
        {:created_at, :desc, []},
        {:name, :asc},
        :email
      ]

      result = PaginationValidator.infer(orders)

      assert result == [
               {:priority, :desc},
               {:created_at, :desc},
               {:name, :asc},
               {:email, :asc},
               {:id, :asc}
             ]
    end
  end

  describe "validate/2 - valid cases" do
    test "validates exact match" do
      order_by = [{:title, :asc}, {:age, :desc}]
      cursor_fields = [{:title, :asc}, {:age, :desc}]

      assert PaginationValidator.validate(order_by, cursor_fields) == :ok
    end

    test "validates with :id appended" do
      order_by = [{:title, :asc}, {:age, :desc}]
      cursor_fields = [{:title, :asc}, {:age, :desc}, {:id, :asc}]

      assert PaginationValidator.validate(order_by, cursor_fields) == :ok
    end

    test "validates nil cursor_fields (will be inferred)" do
      order_by = [{:title, :asc}]

      assert PaginationValidator.validate(order_by, nil) == :ok
    end

    test "validates empty order_by" do
      assert PaginationValidator.validate([], [{:id, :asc}]) == :ok
    end

    test "validates mixed formats that normalize the same" do
      order_by = [:title, {:age, :desc}]
      cursor_fields = [{:title, :asc}, {:age, :desc}, {:id, :asc}]

      assert PaginationValidator.validate(order_by, cursor_fields) == :ok
    end
  end

  describe "validate/2 - invalid cases" do
    test "fails on different field order" do
      order_by = [{:title, :asc}, {:age, :desc}]
      cursor_fields = [{:age, :desc}, {:title, :asc}]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      assert msg =~ "field order must match"
    end

    test "fails on different direction" do
      order_by = [{:title, :asc}]
      cursor_fields = [{:title, :desc}]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      assert msg =~ "direction for :title must be :asc, got :desc"
    end

    test "fails on missing fields" do
      order_by = [{:title, :asc}, {:age, :desc}]
      cursor_fields = [{:title, :asc}]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      assert msg =~ "missing required fields"
    end

    test "fails on extra fields (not :id)" do
      order_by = [{:title, :asc}]
      cursor_fields = [{:title, :asc}, {:extra, :asc}, {:id, :asc}]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      # More than 1 extra field
      assert msg != :ok
    end

    test "fails on completely different fields" do
      order_by = [{:title, :asc}]
      cursor_fields = [{:name, :asc}]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      assert msg =~ "different fields" or msg =~ "missing required fields"
    end
  end

  describe "validate_or_infer/2" do
    test "infers when cursor_fields is nil" do
      order_by = [{:created_at, :desc}, {:id, :asc}]

      assert {:ok, result} = PaginationValidator.validate_or_infer(order_by, nil)
      assert result == [{:created_at, :desc}, {:id, :asc}]
    end

    test "validates and returns when cursor_fields match" do
      order_by = [{:title, :asc}]
      cursor_fields = [{:title, :asc}, {:id, :asc}]

      assert {:ok, result} = PaginationValidator.validate_or_infer(order_by, cursor_fields)
      assert result == [{:title, :asc}, {:id, :asc}]
    end

    test "returns error when cursor_fields mismatch" do
      order_by = [{:title, :asc}]
      cursor_fields = [{:title, :desc}]

      assert {:error, msg} = PaginationValidator.validate_or_infer(order_by, cursor_fields)
      assert msg =~ "direction"
    end
  end

  describe "complex validation scenarios" do
    test "validates multi-field ordering with directions" do
      order_by = [
        {:priority, :desc},
        {:created_at, :desc},
        {:name, :asc},
        {:id, :asc}
      ]

      cursor_fields = [
        {:priority, :desc},
        {:created_at, :desc},
        {:name, :asc},
        {:id, :asc}
      ]

      assert PaginationValidator.validate(order_by, cursor_fields) == :ok
    end

    test "fails on partial field match with wrong middle field" do
      order_by = [
        {:priority, :desc},
        {:created_at, :desc},
        {:name, :asc}
      ]

      cursor_fields = [
        {:priority, :desc},
        {:created_at, :asc},  # Wrong direction!
        {:name, :asc},
        {:id, :asc}
      ]

      assert {:error, msg} = PaginationValidator.validate(order_by, cursor_fields)
      assert msg =~ "direction for :created_at must be :desc, got :asc"
    end

    test "handles normalized formats correctly" do
      # Different input formats that should normalize the same
      order_by1 = [{:order, :title, :asc, []}]
      order_by2 = [{:title, :asc, []}]
      order_by3 = [{:title, :asc}]
      order_by4 = [:title]

      cursor_fields = [{:title, :asc}, {:id, :asc}]

      assert PaginationValidator.validate(order_by1, cursor_fields) == :ok
      assert PaginationValidator.validate(order_by2, cursor_fields) == :ok
      assert PaginationValidator.validate(order_by3, cursor_fields) == :ok
      assert PaginationValidator.validate(order_by4, cursor_fields) == :ok
    end
  end

  describe "inference always appends :id" do
    test "appends :id with :asc direction by default" do
      orders = [{:priority, :desc}, {:created_at, :desc}]
      result = PaginationValidator.infer(orders)

      assert List.last(result) == {:id, :asc}
    end

    test "doesn't duplicate :id if present" do
      orders = [{:priority, :desc}, {:id, :desc}]
      result = PaginationValidator.infer(orders)

      id_count = Enum.count(result, fn {field, _} -> field == :id end)
      assert id_count == 1
    end

    test "preserves user's :id direction" do
      orders = [{:priority, :desc}, {:id, :desc}]
      result = PaginationValidator.infer(orders)

      assert result == [{:priority, :desc}, {:id, :desc}]
    end
  end
end
