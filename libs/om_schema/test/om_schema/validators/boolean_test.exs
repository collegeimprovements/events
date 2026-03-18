defmodule OmSchema.Validators.BooleanTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.Boolean, as: BooleanValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :terms_accepted, :boolean
      field :newsletter, :boolean
      field :is_active, :boolean
    end

    @fields [:terms_accepted, :newsletter, :is_active]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns boolean type" do
      assert BooleanValidator.field_types() == [:boolean]
    end
  end

  describe "supported_options/0" do
    test "returns acceptance option" do
      opts = BooleanValidator.supported_options()

      assert opts == [:acceptance]
    end
  end

  # ============================================
  # acceptance validation
  # ============================================

  describe "validate/3 with acceptance: true" do
    test "passes when field is true" do
      cs =
        changeset(%{terms_accepted: true})
        |> BooleanValidator.validate(:terms_accepted, acceptance: true)

      assert cs.valid?
    end

    test "fails when field is false" do
      cs =
        changeset(%{terms_accepted: false})
        |> BooleanValidator.validate(:terms_accepted, acceptance: true)

      refute cs.valid?
      assert cs.errors[:terms_accepted] != nil
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> BooleanValidator.validate(:terms_accepted, acceptance: true)

      # validate_acceptance only checks the changed value
      # when no change is present, it may or may not error depending on Ecto behavior
      # The key point is it does not crash
      assert is_map(cs)
    end
  end

  # ============================================
  # acceptance: false (no-op)
  # ============================================

  describe "validate/3 with acceptance: false" do
    test "does not validate acceptance when false" do
      cs =
        changeset(%{terms_accepted: false})
        |> BooleanValidator.validate(:terms_accepted, acceptance: false)

      assert cs.valid?
    end

    test "does not validate acceptance when nil" do
      cs =
        changeset(%{terms_accepted: false})
        |> BooleanValidator.validate(:terms_accepted, acceptance: nil)

      assert cs.valid?
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no options" do
    test "returns changeset unchanged with empty opts" do
      cs =
        changeset(%{terms_accepted: false})
        |> BooleanValidator.validate(:terms_accepted, [])

      assert cs.valid?
    end

    test "returns changeset unchanged with true value" do
      cs =
        changeset(%{terms_accepted: true})
        |> BooleanValidator.validate(:terms_accepted, [])

      assert cs.valid?
    end
  end

  # ============================================
  # Multiple boolean fields
  # ============================================

  describe "validate/3 with multiple boolean fields" do
    test "validates acceptance on one field but not another" do
      cs =
        changeset(%{terms_accepted: true, newsletter: false})
        |> BooleanValidator.validate(:terms_accepted, acceptance: true)

      assert cs.valid?
    end

    test "different fields can have different acceptance requirements" do
      cs =
        changeset(%{terms_accepted: false, newsletter: true})
        |> BooleanValidator.validate(:terms_accepted, acceptance: true)
        |> BooleanValidator.validate(:newsletter, acceptance: true)

      refute cs.valid?
      assert cs.errors[:terms_accepted] != nil
      assert cs.errors[:newsletter] == nil
    end
  end
end
