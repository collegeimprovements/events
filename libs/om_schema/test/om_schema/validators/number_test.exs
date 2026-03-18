defmodule OmSchema.Validators.NumberTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.Number, as: NumberValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :age, :integer
      field :price, :float
      field :amount, :decimal
      field :score, :integer
      field :rating, :float
    end

    @fields [:age, :price, :amount, :score, :rating]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns numeric types" do
      assert NumberValidator.field_types() == [:integer, :float, :decimal]
    end
  end

  describe "supported_options/0" do
    test "returns all supported option keys" do
      opts = NumberValidator.supported_options()

      assert :min in opts
      assert :max in opts
      assert :positive in opts
      assert :non_negative in opts
      assert :negative in opts
      assert :non_positive in opts
      assert :greater_than in opts
      assert :gt in opts
      assert :greater_than_or_equal_to in opts
      assert :gte in opts
      assert :less_than in opts
      assert :lt in opts
      assert :less_than_or_equal_to in opts
      assert :lte in opts
      assert :equal_to in opts
      assert :eq in opts
      assert :in in opts
    end
  end

  # ============================================
  # min / max validation
  # ============================================

  describe "validate/3 with min" do
    test "passes when value equals min" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, min: 18)

      assert cs.valid?
    end

    test "passes when value exceeds min" do
      cs = changeset(%{age: 25}) |> NumberValidator.validate(:age, min: 18)

      assert cs.valid?
    end

    test "fails when value is below min" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, min: 18)

      refute cs.valid?
      assert cs.errors[:age] != nil
    end

    test "passes when field has no change" do
      cs = changeset(%{}) |> NumberValidator.validate(:age, min: 18)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, min: {18, message: "too young"})

      refute cs.valid?
      {msg, _} = cs.errors[:age]
      assert msg == "too young"
    end
  end

  describe "validate/3 with max" do
    test "passes when value equals max" do
      cs = changeset(%{age: 150}) |> NumberValidator.validate(:age, max: 150)

      assert cs.valid?
    end

    test "passes when value is below max" do
      cs = changeset(%{age: 100}) |> NumberValidator.validate(:age, max: 150)

      assert cs.valid?
    end

    test "fails when value exceeds max" do
      cs = changeset(%{age: 200}) |> NumberValidator.validate(:age, max: 150)

      refute cs.valid?
      assert cs.errors[:age] != nil
    end

    test "accepts tuple format with custom message" do
      cs = changeset(%{age: 200}) |> NumberValidator.validate(:age, max: {150, message: "too old"})

      refute cs.valid?
      {msg, _} = cs.errors[:age]
      assert msg == "too old"
    end
  end

  describe "validate/3 with min and max combined" do
    test "passes when value is within range" do
      cs = changeset(%{age: 25}) |> NumberValidator.validate(:age, min: 18, max: 100)

      assert cs.valid?
    end

    test "fails when below min" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, min: 18, max: 100)

      refute cs.valid?
    end

    test "fails when above max" do
      cs = changeset(%{age: 150}) |> NumberValidator.validate(:age, min: 18, max: 100)

      refute cs.valid?
    end
  end

  # ============================================
  # positive / non_negative / negative / non_positive
  # ============================================

  describe "validate/3 with positive" do
    test "passes for positive value" do
      cs = changeset(%{age: 1}) |> NumberValidator.validate(:age, positive: true)

      assert cs.valid?
    end

    test "fails for zero" do
      cs = changeset(%{age: 0}) |> NumberValidator.validate(:age, positive: true)

      refute cs.valid?
    end

    test "fails for negative value" do
      cs = changeset(%{age: -1}) |> NumberValidator.validate(:age, positive: true)

      refute cs.valid?
    end
  end

  describe "validate/3 with non_negative" do
    test "passes for positive value" do
      cs = changeset(%{age: 1}) |> NumberValidator.validate(:age, non_negative: true)

      assert cs.valid?
    end

    test "passes for zero" do
      cs = changeset(%{age: 0}) |> NumberValidator.validate(:age, non_negative: true)

      assert cs.valid?
    end

    test "fails for negative value" do
      cs = changeset(%{age: -1}) |> NumberValidator.validate(:age, non_negative: true)

      refute cs.valid?
    end
  end

  describe "validate/3 with negative" do
    test "passes for negative value" do
      cs = changeset(%{score: -5}) |> NumberValidator.validate(:score, negative: true)

      assert cs.valid?
    end

    test "fails for zero" do
      cs = changeset(%{score: 0}) |> NumberValidator.validate(:score, negative: true)

      refute cs.valid?
    end

    test "fails for positive value" do
      cs = changeset(%{score: 1}) |> NumberValidator.validate(:score, negative: true)

      refute cs.valid?
    end
  end

  describe "validate/3 with non_positive" do
    test "passes for negative value" do
      cs = changeset(%{score: -5}) |> NumberValidator.validate(:score, non_positive: true)

      assert cs.valid?
    end

    test "passes for zero" do
      cs = changeset(%{score: 0}) |> NumberValidator.validate(:score, non_positive: true)

      assert cs.valid?
    end

    test "fails for positive value" do
      cs = changeset(%{score: 1}) |> NumberValidator.validate(:score, non_positive: true)

      refute cs.valid?
    end
  end

  # ============================================
  # greater_than / gt
  # ============================================

  describe "validate/3 with greater_than" do
    test "passes when value is greater" do
      cs = changeset(%{age: 20}) |> NumberValidator.validate(:age, greater_than: 18)

      assert cs.valid?
    end

    test "fails when value equals threshold" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, greater_than: 18)

      refute cs.valid?
    end

    test "fails when value is less" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, greater_than: 18)

      refute cs.valid?
    end

    test "accepts tuple with custom message" do
      cs =
        changeset(%{age: 10})
        |> NumberValidator.validate(:age, greater_than: {18, message: "must be over 18"})

      refute cs.valid?
      {msg, _} = cs.errors[:age]
      assert msg == "must be over 18"
    end
  end

  describe "validate/3 with gt (alias)" do
    test "passes when value is greater" do
      cs = changeset(%{age: 20}) |> NumberValidator.validate(:age, gt: 18)

      assert cs.valid?
    end

    test "fails when value is not greater" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, gt: 18)

      refute cs.valid?
    end
  end

  # ============================================
  # greater_than_or_equal_to / gte
  # ============================================

  describe "validate/3 with greater_than_or_equal_to" do
    test "passes when value equals threshold" do
      cs =
        changeset(%{age: 18})
        |> NumberValidator.validate(:age, greater_than_or_equal_to: 18)

      assert cs.valid?
    end

    test "passes when value exceeds threshold" do
      cs =
        changeset(%{age: 20})
        |> NumberValidator.validate(:age, greater_than_or_equal_to: 18)

      assert cs.valid?
    end

    test "fails when value is below threshold" do
      cs =
        changeset(%{age: 10})
        |> NumberValidator.validate(:age, greater_than_or_equal_to: 18)

      refute cs.valid?
    end
  end

  describe "validate/3 with gte (alias)" do
    test "passes when value equals threshold" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, gte: 18)

      assert cs.valid?
    end

    test "fails when value is below threshold" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, gte: 18)

      refute cs.valid?
    end
  end

  # ============================================
  # less_than / lt
  # ============================================

  describe "validate/3 with less_than" do
    test "passes when value is less" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, less_than: 18)

      assert cs.valid?
    end

    test "fails when value equals threshold" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, less_than: 18)

      refute cs.valid?
    end

    test "fails when value exceeds threshold" do
      cs = changeset(%{age: 20}) |> NumberValidator.validate(:age, less_than: 18)

      refute cs.valid?
    end
  end

  describe "validate/3 with lt (alias)" do
    test "passes when value is less" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, lt: 18)

      assert cs.valid?
    end

    test "fails when value is not less" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, lt: 18)

      refute cs.valid?
    end
  end

  # ============================================
  # less_than_or_equal_to / lte
  # ============================================

  describe "validate/3 with less_than_or_equal_to" do
    test "passes when value equals threshold" do
      cs =
        changeset(%{age: 100})
        |> NumberValidator.validate(:age, less_than_or_equal_to: 100)

      assert cs.valid?
    end

    test "passes when value is below threshold" do
      cs =
        changeset(%{age: 50})
        |> NumberValidator.validate(:age, less_than_or_equal_to: 100)

      assert cs.valid?
    end

    test "fails when value exceeds threshold" do
      cs =
        changeset(%{age: 101})
        |> NumberValidator.validate(:age, less_than_or_equal_to: 100)

      refute cs.valid?
    end
  end

  describe "validate/3 with lte (alias)" do
    test "passes when value equals threshold" do
      cs = changeset(%{age: 100}) |> NumberValidator.validate(:age, lte: 100)

      assert cs.valid?
    end

    test "fails when value exceeds threshold" do
      cs = changeset(%{age: 101}) |> NumberValidator.validate(:age, lte: 100)

      refute cs.valid?
    end
  end

  # ============================================
  # equal_to / eq
  # ============================================

  describe "validate/3 with equal_to" do
    test "passes when value equals target" do
      cs = changeset(%{score: 100}) |> NumberValidator.validate(:score, equal_to: 100)

      assert cs.valid?
    end

    test "fails when value does not equal target" do
      cs = changeset(%{score: 99}) |> NumberValidator.validate(:score, equal_to: 100)

      refute cs.valid?
    end
  end

  describe "validate/3 with eq (alias)" do
    test "passes when value equals target" do
      cs = changeset(%{score: 42}) |> NumberValidator.validate(:score, eq: 42)

      assert cs.valid?
    end

    test "fails when value does not equal target" do
      cs = changeset(%{score: 41}) |> NumberValidator.validate(:score, eq: 42)

      refute cs.valid?
    end

    test "accepts tuple with custom message" do
      cs =
        changeset(%{score: 41})
        |> NumberValidator.validate(:score, eq: {42, message: "must be 42"})

      refute cs.valid?
      {msg, _} = cs.errors[:score]
      assert msg == "must be 42"
    end
  end

  # ============================================
  # :in with Range
  # ============================================

  describe "validate/3 with in: Range" do
    test "passes when value is within range" do
      cs = changeset(%{age: 25}) |> NumberValidator.validate(:age, in: 18..65)

      assert cs.valid?
    end

    test "passes at range start boundary" do
      cs = changeset(%{age: 18}) |> NumberValidator.validate(:age, in: 18..65)

      assert cs.valid?
    end

    test "passes at range end boundary" do
      cs = changeset(%{age: 65}) |> NumberValidator.validate(:age, in: 18..65)

      assert cs.valid?
    end

    test "fails when value is below range" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, in: 18..65)

      refute cs.valid?
    end

    test "fails when value is above range" do
      cs = changeset(%{age: 70}) |> NumberValidator.validate(:age, in: 18..65)

      refute cs.valid?
    end
  end

  describe "validate/3 with in: [Range]" do
    test "passes when value is within range wrapped in list" do
      cs = changeset(%{age: 25}) |> NumberValidator.validate(:age, in: [18..65])

      assert cs.valid?
    end

    test "fails when value is outside range wrapped in list" do
      cs = changeset(%{age: 10}) |> NumberValidator.validate(:age, in: [18..65])

      refute cs.valid?
    end
  end

  # ============================================
  # :in with list of values
  # ============================================

  describe "validate/3 with in: list" do
    test "passes when value is in list" do
      cs = changeset(%{score: 1}) |> NumberValidator.validate(:score, in: [1, 2, 3, 5, 8])

      assert cs.valid?
    end

    test "fails when value is not in list" do
      cs = changeset(%{score: 4}) |> NumberValidator.validate(:score, in: [1, 2, 3, 5, 8])

      refute cs.valid?
    end
  end

  # ============================================
  # Float values
  # ============================================

  describe "validate/3 with float fields" do
    test "passes float within range" do
      cs = changeset(%{price: 9.99}) |> NumberValidator.validate(:price, min: 0.01, max: 100.0)

      assert cs.valid?
    end

    test "fails float below min" do
      cs = changeset(%{price: 0.001}) |> NumberValidator.validate(:price, min: 0.01)

      refute cs.valid?
    end

    test "positive validates float" do
      cs = changeset(%{price: 0.5}) |> NumberValidator.validate(:price, positive: true)

      assert cs.valid?
    end

    test "positive fails for zero float" do
      cs = changeset(%{price: 0.0}) |> NumberValidator.validate(:price, positive: true)

      refute cs.valid?
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no options" do
    test "returns changeset unchanged" do
      cs = changeset(%{age: 25}) |> NumberValidator.validate(:age, [])

      assert cs.valid?
    end
  end

  # ============================================
  # Nil field (no change)
  # ============================================

  describe "validate/3 with nil field" do
    test "passes all validations when field has no change" do
      cs =
        changeset(%{})
        |> NumberValidator.validate(:age, min: 1, max: 100, positive: true)

      assert cs.valid?
    end
  end
end
