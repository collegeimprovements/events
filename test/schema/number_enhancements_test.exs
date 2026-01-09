defmodule Events.Core.Schema.NumberEnhancementsTest do
  use Events.TestCase, async: true

  defmodule Product do
    use OmSchema

    schema "products" do
      # Range syntax
      field :percentage, :float, required: false, in: 0..100
      field :stock_count, :integer, required: false, in: [0..1000]

      # Shortcut syntax
      field :price, :float, required: false, gt: 0
      field :quantity, :integer, required: false, gte: 0
      field :discount, :float, required: false, gte: 0, lte: 1
      field :rating, :float, required: false, gte: 0, lt: 5

      # Tuple syntax with messages
      field :age, :integer, required: false, gt: {0, message: "must be positive"}

      field :score, :integer,
        required: false,
        gte: {0, message: "cannot be negative"},
        lte: {100, message: "cannot exceed 100"}
    end

    def changeset(product, attrs) do
      product
      |> Ecto.Changeset.cast(attrs, cast_fields())
      |> Ecto.Changeset.validate_required(required_fields())
      |> apply_validations()
    end
  end

  describe "range syntax" do
    test "validates percentage in range 0..100" do
      changeset = Product.changeset(%Product{}, %{percentage: 50})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{percentage: 0})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{percentage: 100})
      assert changeset.valid?
    end

    test "rejects percentage outside range" do
      changeset = Product.changeset(%Product{}, %{percentage: -1})
      refute changeset.valid?
      assert {:percentage, _} = List.keyfind(changeset.errors, :percentage, 0)

      changeset = Product.changeset(%Product{}, %{percentage: 101})
      refute changeset.valid?
      assert {:percentage, _} = List.keyfind(changeset.errors, :percentage, 0)
    end

    test "validates stock_count with range in list" do
      changeset = Product.changeset(%Product{}, %{stock_count: 500})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{stock_count: 0})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{stock_count: 1000})
      assert changeset.valid?
    end

    test "rejects stock_count outside range" do
      changeset = Product.changeset(%Product{}, %{stock_count: -1})
      refute changeset.valid?

      changeset = Product.changeset(%Product{}, %{stock_count: 1001})
      refute changeset.valid?
    end
  end

  describe "shortcut syntax" do
    test "gt: greater than validation" do
      changeset = Product.changeset(%Product{}, %{price: 0.01})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{price: 100})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{price: 0})
      refute changeset.valid?
      assert {:price, _} = List.keyfind(changeset.errors, :price, 0)

      changeset = Product.changeset(%Product{}, %{price: -1})
      refute changeset.valid?
    end

    test "gte: greater than or equal to validation" do
      changeset = Product.changeset(%Product{}, %{quantity: 0})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{quantity: 100})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{quantity: -1})
      refute changeset.valid?
      assert {:quantity, _} = List.keyfind(changeset.errors, :quantity, 0)
    end

    test "combined gte and lte validation" do
      changeset = Product.changeset(%Product{}, %{discount: 0})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{discount: 0.5})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{discount: 1})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{discount: -0.1})
      refute changeset.valid?

      changeset = Product.changeset(%Product{}, %{discount: 1.1})
      refute changeset.valid?
    end

    test "combined gte and lt validation" do
      changeset = Product.changeset(%Product{}, %{rating: 0})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{rating: 4.9})
      assert changeset.valid?

      changeset = Product.changeset(%Product{}, %{rating: 5})
      refute changeset.valid?
      assert {:rating, _} = List.keyfind(changeset.errors, :rating, 0)

      changeset = Product.changeset(%Product{}, %{rating: -0.1})
      refute changeset.valid?
    end
  end

  describe "tuple syntax with custom messages" do
    test "gt with custom message" do
      changeset = Product.changeset(%Product{}, %{age: 0})
      refute changeset.valid?
      assert {:age, {"must be positive", _}} = List.keyfind(changeset.errors, :age, 0)
    end

    test "gte validation with custom message" do
      changeset = Product.changeset(%Product{}, %{score: -1})
      refute changeset.valid?
      # When both gte and lte have messages, Ecto will use one of them
      # Here we just verify the field has an error
      assert {:score, _} = List.keyfind(changeset.errors, :score, 0)
    end

    test "lte validation with custom message" do
      changeset = Product.changeset(%Product{}, %{score: 101})
      refute changeset.valid?
      # The last message in the chain (lte) will be used
      assert {:score, {"cannot exceed 100", _}} = List.keyfind(changeset.errors, :score, 0)
    end

    test "valid values don't trigger custom messages" do
      changeset = Product.changeset(%Product{}, %{age: 25, score: 85})
      assert changeset.valid?
    end
  end

  describe "mixed validation types" do
    test "multiple fields with different validation types" do
      attrs = %{
        percentage: 50,
        stock_count: 100,
        price: 19.99,
        quantity: 5,
        discount: 0.15,
        rating: 4.5,
        age: 18,
        score: 95
      }

      changeset = Product.changeset(%Product{}, attrs)
      assert changeset.valid?
    end

    test "multiple validation failures" do
      attrs = %{
        percentage: 101,
        price: 0,
        quantity: -1,
        rating: 5.0
      }

      changeset = Product.changeset(%Product{}, attrs)
      refute changeset.valid?

      # Should have multiple errors
      assert length(changeset.errors) >= 4
    end
  end
end
