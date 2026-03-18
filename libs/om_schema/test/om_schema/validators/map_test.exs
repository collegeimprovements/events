defmodule OmSchema.Validators.MapTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.Map, as: MapValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :metadata, :map
      field :settings, :map
      field :config, :map
    end

    @fields [:metadata, :settings, :config]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns map type" do
      assert MapValidator.field_types() == [:map]
    end
  end

  describe "supported_options/0" do
    test "returns all supported option keys" do
      opts = MapValidator.supported_options()

      assert :required_keys in opts
      assert :forbidden_keys in opts
      assert :min_keys in opts
      assert :max_keys in opts
      assert length(opts) == 4
    end
  end

  # ============================================
  # required_keys validation
  # ============================================

  describe "validate/3 with required_keys" do
    test "passes when all required keys are present" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "a"}})
        |> MapValidator.validate(:metadata, required_keys: ["name", "type"])

      assert cs.valid?
    end

    test "passes when map has extra keys beyond required" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "a", "extra" => "val"}})
        |> MapValidator.validate(:metadata, required_keys: ["name", "type"])

      assert cs.valid?
    end

    test "fails when a required key is missing" do
      cs =
        changeset(%{metadata: %{"name" => "test"}})
        |> MapValidator.validate(:metadata, required_keys: ["name", "type"])

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "missing required keys"
      assert msg =~ "type"
    end

    test "fails when all required keys are missing" do
      cs =
        changeset(%{metadata: %{"unrelated" => "val"}})
        |> MapValidator.validate(:metadata, required_keys: ["name", "type"])

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "missing required keys"
    end

    test "fails when map is empty" do
      cs =
        changeset(%{metadata: %{}})
        |> MapValidator.validate(:metadata, required_keys: ["name"])

      refute cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> MapValidator.validate(:metadata, required_keys: ["name"])

      assert cs.valid?
    end

    test "works with atom keys" do
      cs =
        changeset(%{metadata: %{name: "test", type: "a"}})
        |> MapValidator.validate(:metadata, required_keys: [:name, :type])

      assert cs.valid?
    end

    test "fails with atom keys when key is missing" do
      cs =
        changeset(%{metadata: %{name: "test"}})
        |> MapValidator.validate(:metadata, required_keys: [:name, :type])

      refute cs.valid?
    end
  end

  # ============================================
  # forbidden_keys validation
  # ============================================

  describe "validate/3 with forbidden_keys" do
    test "passes when no forbidden keys are present" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "a"}})
        |> MapValidator.validate(:metadata, forbidden_keys: ["password", "secret"])

      assert cs.valid?
    end

    test "fails when a forbidden key is present" do
      cs =
        changeset(%{metadata: %{"name" => "test", "password" => "secret123"}})
        |> MapValidator.validate(:metadata, forbidden_keys: ["password", "secret"])

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "contains forbidden keys"
      assert msg =~ "password"
    end

    test "fails when multiple forbidden keys are present" do
      cs =
        changeset(%{metadata: %{"password" => "x", "secret" => "y"}})
        |> MapValidator.validate(:metadata, forbidden_keys: ["password", "secret"])

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "password"
      assert msg =~ "secret"
    end

    test "passes for empty map" do
      cs =
        changeset(%{metadata: %{}})
        |> MapValidator.validate(:metadata, forbidden_keys: ["password"])

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> MapValidator.validate(:metadata, forbidden_keys: ["password"])

      assert cs.valid?
    end

    test "works with atom keys" do
      cs =
        changeset(%{metadata: %{name: "test", password: "secret"}})
        |> MapValidator.validate(:metadata, forbidden_keys: [:password])

      refute cs.valid?
    end
  end

  # ============================================
  # Combined required_keys and forbidden_keys
  # ============================================

  describe "validate/3 with combined required_keys and forbidden_keys" do
    test "passes when required present and forbidden absent" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "a"}})
        |> MapValidator.validate(:metadata,
          required_keys: ["name", "type"],
          forbidden_keys: ["password"]
        )

      assert cs.valid?
    end

    test "fails when required key is missing even if no forbidden keys" do
      cs =
        changeset(%{metadata: %{"name" => "test"}})
        |> MapValidator.validate(:metadata,
          required_keys: ["name", "type"],
          forbidden_keys: ["password"]
        )

      refute cs.valid?
    end

    test "fails when forbidden key present even if all required present" do
      cs =
        changeset(%{metadata: %{"name" => "test", "type" => "a", "password" => "x"}})
        |> MapValidator.validate(:metadata,
          required_keys: ["name", "type"],
          forbidden_keys: ["password"]
        )

      refute cs.valid?
    end
  end

  # ============================================
  # min_keys validation
  # ============================================

  describe "validate/3 with min_keys" do
    test "passes when map has enough keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3}})
        |> MapValidator.validate(:metadata, min_keys: 2)

      assert cs.valid?
    end

    test "passes when map has exactly min_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> MapValidator.validate(:metadata, min_keys: 2)

      assert cs.valid?
    end

    test "fails when map has fewer than min_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> MapValidator.validate(:metadata, min_keys: 2)

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "must have at least 2 keys"
    end

    test "fails when map is empty and min_keys > 0" do
      cs =
        changeset(%{metadata: %{}})
        |> MapValidator.validate(:metadata, min_keys: 1)

      refute cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> MapValidator.validate(:metadata, min_keys: 2)

      assert cs.valid?
    end
  end

  # ============================================
  # max_keys validation
  # ============================================

  describe "validate/3 with max_keys" do
    test "passes when map has fewer than max keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2}})
        |> MapValidator.validate(:metadata, max_keys: 5)

      assert cs.valid?
    end

    test "passes when map has exactly max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3}})
        |> MapValidator.validate(:metadata, max_keys: 3)

      assert cs.valid?
    end

    test "fails when map exceeds max_keys" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3, "d" => 4}})
        |> MapValidator.validate(:metadata, max_keys: 3)

      refute cs.valid?
      {msg, _} = cs.errors[:metadata]
      assert msg =~ "must have at most 3 keys"
    end

    test "passes for empty map with any max_keys" do
      cs =
        changeset(%{metadata: %{}})
        |> MapValidator.validate(:metadata, max_keys: 5)

      assert cs.valid?
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> MapValidator.validate(:metadata, max_keys: 5)

      assert cs.valid?
    end
  end

  # ============================================
  # Combined min_keys and max_keys (size range)
  # ============================================

  describe "validate/3 with min_keys and max_keys" do
    test "passes when map size is within range" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3}})
        |> MapValidator.validate(:metadata, min_keys: 2, max_keys: 5)

      assert cs.valid?
    end

    test "fails when below min" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> MapValidator.validate(:metadata, min_keys: 2, max_keys: 5)

      refute cs.valid?
    end

    test "fails when above max" do
      cs =
        changeset(%{metadata: %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 5, "f" => 6}})
        |> MapValidator.validate(:metadata, min_keys: 2, max_keys: 5)

      refute cs.valid?
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no options" do
    test "returns changeset unchanged" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> MapValidator.validate(:metadata, [])

      assert cs.valid?
    end
  end

  # ============================================
  # Empty required/forbidden lists
  # ============================================

  describe "validate/3 with empty key lists" do
    test "passes with empty required_keys list" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> MapValidator.validate(:metadata, required_keys: [])

      assert cs.valid?
    end

    test "passes with empty forbidden_keys list" do
      cs =
        changeset(%{metadata: %{"a" => 1}})
        |> MapValidator.validate(:metadata, forbidden_keys: [])

      assert cs.valid?
    end
  end
end
