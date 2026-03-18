defmodule OmSchema.Validators.ArrayTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.Array, as: ArrayValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :tags, {:array, :string}
      field :scores, {:array, :integer}
      field :emails, {:array, :string}
      field :categories, {:array, :string}
    end

    @fields [:tags, :scores, :emails, :categories]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns array type" do
      assert ArrayValidator.field_types() == [:array]
    end
  end

  describe "supported_options/0" do
    test "returns all supported option keys" do
      opts = ArrayValidator.supported_options()

      assert :min_length in opts
      assert :max_length in opts
      assert :length in opts
      assert :in in opts
      assert :item_format in opts
      assert :item_min in opts
      assert :item_max in opts
      assert :unique_items in opts
      assert length(opts) == 8
    end
  end

  # ============================================
  # min_length validation
  # ============================================

  describe "validate/3 with min_length" do
    test "passes when array meets minimum length" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ArrayValidator.validate(:tags, min_length: 2)

      assert cs.valid?
    end

    test "passes when array is exactly at minimum length" do
      cs =
        changeset(%{tags: ["a", "b"]})
        |> ArrayValidator.validate(:tags, min_length: 2)

      assert cs.valid?
    end

    test "fails when array is below minimum length" do
      cs =
        changeset(%{tags: ["a"]})
        |> ArrayValidator.validate(:tags, min_length: 2)

      refute cs.valid?
      assert cs.errors[:tags] != nil
    end

    test "fails when array is empty and min_length > 0" do
      cs =
        changeset(%{tags: []})
        |> ArrayValidator.validate(:tags, min_length: 1)

      refute cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> ArrayValidator.validate(:tags, min_length: 2)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{tags: ["a"]})
        |> ArrayValidator.validate(:tags, min_length: {2, message: "need more tags"})

      refute cs.valid?
      {msg, _} = cs.errors[:tags]
      assert msg =~ "need more tags"
    end
  end

  # ============================================
  # max_length validation
  # ============================================

  describe "validate/3 with max_length" do
    test "passes when array is under maximum length" do
      cs =
        changeset(%{tags: ["a", "b"]})
        |> ArrayValidator.validate(:tags, max_length: 5)

      assert cs.valid?
    end

    test "passes when array is exactly at maximum length" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ArrayValidator.validate(:tags, max_length: 3)

      assert cs.valid?
    end

    test "fails when array exceeds maximum length" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> ArrayValidator.validate(:tags, max_length: 3)

      refute cs.valid?
      assert cs.errors[:tags] != nil
    end

    test "passes for empty array with any max_length" do
      cs =
        changeset(%{tags: []})
        |> ArrayValidator.validate(:tags, max_length: 5)

      assert cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> ArrayValidator.validate(:tags, max_length: {3, message: "too many tags"})

      refute cs.valid?
      {msg, _} = cs.errors[:tags]
      assert msg =~ "too many tags"
    end
  end

  # ============================================
  # exact length validation
  # ============================================

  describe "validate/3 with length (exact)" do
    test "passes when array is exactly the required length" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ArrayValidator.validate(:tags, length: 3)

      assert cs.valid?
    end

    test "fails when array is shorter than required" do
      cs =
        changeset(%{tags: ["a", "b"]})
        |> ArrayValidator.validate(:tags, length: 3)

      refute cs.valid?
    end

    test "fails when array is longer than required" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d"]})
        |> ArrayValidator.validate(:tags, length: 3)

      refute cs.valid?
    end

    test "accepts tuple format with custom message" do
      cs =
        changeset(%{tags: ["a"]})
        |> ArrayValidator.validate(:tags, length: {3, message: "need exactly 3"})

      refute cs.valid?
      {msg, _} = cs.errors[:tags]
      assert msg =~ "need exactly 3"
    end
  end

  # ============================================
  # Combined min and max length
  # ============================================

  describe "validate/3 with combined min_length and max_length" do
    test "passes when array is within range" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ArrayValidator.validate(:tags, min_length: 2, max_length: 5)

      assert cs.valid?
    end

    test "fails when below min in combined range" do
      cs =
        changeset(%{tags: ["a"]})
        |> ArrayValidator.validate(:tags, min_length: 2, max_length: 5)

      refute cs.valid?
    end

    test "fails when above max in combined range" do
      cs =
        changeset(%{tags: ["a", "b", "c", "d", "e", "f"]})
        |> ArrayValidator.validate(:tags, min_length: 2, max_length: 5)

      refute cs.valid?
    end
  end

  # ============================================
  # :in (subset) validation
  # ============================================

  describe "validate/3 with in (subset)" do
    test "passes when all items are in allowed set" do
      cs =
        changeset(%{tags: ["elixir", "erlang"]})
        |> ArrayValidator.validate(:tags, in: ["elixir", "erlang", "rust", "go"])

      assert cs.valid?
    end

    test "fails when an item is not in allowed set" do
      cs =
        changeset(%{tags: ["elixir", "python"]})
        |> ArrayValidator.validate(:tags, in: ["elixir", "erlang", "rust", "go"])

      refute cs.valid?
      assert cs.errors[:tags] != nil
    end

    test "passes for empty array" do
      cs =
        changeset(%{tags: []})
        |> ArrayValidator.validate(:tags, in: ["elixir", "erlang"])

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> ArrayValidator.validate(:tags, in: ["elixir"])

      assert cs.valid?
    end
  end

  # ============================================
  # item_format validation
  # ============================================

  describe "validate/3 with item_format" do
    test "passes when all items match the regex" do
      cs =
        changeset(%{emails: ["a@b.com", "c@d.com"]})
        |> ArrayValidator.validate(:emails, item_format: ~r/@/)

      assert cs.valid?
    end

    test "fails when an item does not match the regex" do
      cs =
        changeset(%{emails: ["a@b.com", "invalid"]})
        |> ArrayValidator.validate(:emails, item_format: ~r/@/)

      refute cs.valid?
      {msg, _} = cs.errors[:emails]
      assert msg =~ "contains invalid items"
      assert msg =~ "invalid"
    end

    test "fails when a non-string item is in the array" do
      # item_format checks is_binary, so non-strings fail
      cs =
        changeset(%{tags: ["valid"]})
        |> ArrayValidator.validate(:tags, item_format: ~r/^[a-z]+$/)

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> ArrayValidator.validate(:emails, item_format: ~r/@/)

      assert cs.valid?
    end

    test "passes for empty array" do
      cs =
        changeset(%{emails: []})
        |> ArrayValidator.validate(:emails, item_format: ~r/@/)

      assert cs.valid?
    end
  end

  # ============================================
  # item_min / item_max validation
  # ============================================

  describe "validate/3 with item_min and item_max" do
    test "passes when all items are within range" do
      cs =
        changeset(%{scores: [5, 10, 15]})
        |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      assert cs.valid?
    end

    test "fails when an item is below item_min" do
      cs =
        changeset(%{scores: [0, 5, 10]})
        |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      refute cs.valid?
      {msg, _} = cs.errors[:scores]
      assert msg =~ "contains out of range items"
      assert msg =~ "0"
    end

    test "fails when an item exceeds item_max" do
      cs =
        changeset(%{scores: [5, 10, 25]})
        |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      refute cs.valid?
      {msg, _} = cs.errors[:scores]
      assert msg =~ "contains out of range items"
      assert msg =~ "25"
    end

    test "passes with item_min only" do
      cs =
        changeset(%{scores: [5, 10, 15]})
        |> ArrayValidator.validate(:scores, item_min: 1)

      assert cs.valid?
    end

    test "fails with item_min only when item is below" do
      cs =
        changeset(%{scores: [0, 5, 10]})
        |> ArrayValidator.validate(:scores, item_min: 1)

      refute cs.valid?
    end

    test "passes with item_max only" do
      cs =
        changeset(%{scores: [5, 10, 15]})
        |> ArrayValidator.validate(:scores, item_max: 20)

      assert cs.valid?
    end

    test "fails with item_max only when item exceeds" do
      cs =
        changeset(%{scores: [5, 10, 25]})
        |> ArrayValidator.validate(:scores, item_max: 20)

      refute cs.valid?
    end

    test "passes at boundaries" do
      cs =
        changeset(%{scores: [1, 20]})
        |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      assert cs.valid?
    end

    test "passes for empty array" do
      cs =
        changeset(%{scores: []})
        |> ArrayValidator.validate(:scores, item_min: 1, item_max: 20)

      assert cs.valid?
    end
  end

  # ============================================
  # unique_items validation
  # ============================================

  describe "validate/3 with unique_items" do
    test "passes when all items are unique" do
      cs =
        changeset(%{tags: ["a", "b", "c"]})
        |> ArrayValidator.validate(:tags, unique_items: true)

      assert cs.valid?
    end

    test "fails when items have duplicates" do
      cs =
        changeset(%{tags: ["a", "b", "a"]})
        |> ArrayValidator.validate(:tags, unique_items: true)

      refute cs.valid?
      {msg, _} = cs.errors[:tags]
      assert msg == "must have unique items"
    end

    test "passes for empty array" do
      cs =
        changeset(%{tags: []})
        |> ArrayValidator.validate(:tags, unique_items: true)

      assert cs.valid?
    end

    test "passes for single-element array" do
      cs =
        changeset(%{tags: ["only"]})
        |> ArrayValidator.validate(:tags, unique_items: true)

      assert cs.valid?
    end

    test "does not validate uniqueness when unique_items is false/nil" do
      cs =
        changeset(%{tags: ["a", "a"]})
        |> ArrayValidator.validate(:tags, unique_items: false)

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> ArrayValidator.validate(:tags, unique_items: true)

      assert cs.valid?
    end
  end

  # ============================================
  # Combined validations
  # ============================================

  describe "validate/3 with combined options" do
    test "applies all validations together" do
      cs =
        changeset(%{tags: ["elixir", "erlang"]})
        |> ArrayValidator.validate(:tags,
          min_length: 1,
          max_length: 5,
          in: ["elixir", "erlang", "rust"],
          unique_items: true
        )

      assert cs.valid?
    end

    test "reports errors from multiple failing validations" do
      cs =
        changeset(%{tags: ["a", "a", "a", "a", "a", "a"]})
        |> ArrayValidator.validate(:tags,
          max_length: 3,
          unique_items: true
        )

      refute cs.valid?
      # Both max_length and unique_items should fail
      assert length(cs.errors) >= 1
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no options" do
    test "returns changeset unchanged" do
      cs = changeset(%{tags: ["a", "b"]}) |> ArrayValidator.validate(:tags, [])

      assert cs.valid?
    end
  end
end
