defmodule OmSchema.EmbeddedTest do
  @moduledoc """
  Tests for OmSchema.Embedded - Enhanced embedded schema support.

  Validates that:
  - `embeds_one/3` and `embeds_many/3` macros work with `propagate_validations: true`
  - `cast_embed_with_validation/3` applies embedded schema validations
  - `validate_embeds/1` recursively validates embedded schemas
  - Metadata is correctly captured in `embedded_schemas/0`
  """

  use ExUnit.Case, async: true

  alias OmSchema.Embedded

  # ============================================
  # Test Embedded Schemas
  # ============================================

  # Note: Embedded schemas use Ecto.Schema directly since they don't need
  # the enhanced OmSchema features (which are designed for database tables)

  defmodule Address do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :street, :string
      field :city, :string
      field :zip, :string
    end

    def base_changeset(struct, attrs) do
      struct
      |> cast(attrs, [:street, :city, :zip])
      |> validate_required([:street, :city])
      |> validate_length(:street, min: 5)
      |> validate_format(:zip, ~r/^\d{5}(-\d{4})?$/)
    end

    def changeset(struct, attrs), do: base_changeset(struct, attrs)
  end

  defmodule PhoneNumber do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :number, :string
      field :type, Ecto.Enum, values: [:mobile, :home, :work]
    end

    def base_changeset(struct, attrs) do
      struct
      |> cast(attrs, [:number, :type])
      |> validate_required([:number])
      |> validate_format(:number, ~r/^\+?[\d\s\-\(\)]+$/)
    end

    def changeset(struct, attrs), do: base_changeset(struct, attrs)
  end

  defmodule Tag do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:name])
      |> validate_required([:name])
    end
  end

  defmodule UserWithEmbeds do
    use OmSchema

    # Use schema with test table name
    schema "users_with_embeds_test" do
      field :name, :string, required: true

      # With validation propagation
      embeds_one :address, Address, propagate_validations: true

      # Multiple embeds with propagation
      embeds_many :phone_numbers, PhoneNumber, propagate_validations: true

      # Without propagation (for comparison)
      embeds_many :tags, Tag, propagate_validations: false
    end
  end

  defp user_changeset(attrs) do
    UserWithEmbeds.base_changeset(%UserWithEmbeds{}, attrs)
  end

  # ============================================
  # Metadata Tests
  # ============================================

  describe "embedded_schemas/0" do
    test "returns metadata for embedded schemas" do
      schemas = UserWithEmbeds.embedded_schemas()

      assert length(schemas) == 3
    end

    test "includes propagate_validations flag" do
      schemas = UserWithEmbeds.embedded_schemas()

      address_meta = Enum.find(schemas, fn {name, _, _, _} -> name == :address end)
      assert {_, :one, Address, true} = address_meta

      phones_meta = Enum.find(schemas, fn {name, _, _, _} -> name == :phone_numbers end)
      assert {_, :many, PhoneNumber, true} = phones_meta

      tags_meta = Enum.find(schemas, fn {name, _, _, _} -> name == :tags end)
      assert {_, :many, Tag, false} = tags_meta
    end

    test "records cardinality correctly" do
      schemas = UserWithEmbeds.embedded_schemas()

      assert {:address, :one, _, _} = Enum.find(schemas, &match?({:address, _, _, _}, &1))
      assert {:phone_numbers, :many, _, _} = Enum.find(schemas, &match?({:phone_numbers, _, _, _}, &1))
    end
  end

  # ============================================
  # cast_embed_with_validation/3
  # ============================================

  describe "cast_embed_with_validation/3" do
    test "casts embedded schema with base_changeset" do
      changeset =
        %UserWithEmbeds{}
        |> Ecto.Changeset.cast(%{name: "John"}, [:name])
        |> Ecto.Changeset.cast_embed(:address, with: &Address.base_changeset/2)

      # Address not present, should be valid
      assert changeset.valid?
    end

    test "applies validation from embedded schema" do
      import Ecto.Changeset

      changeset =
        %UserWithEmbeds{}
        |> cast(%{
          name: "John",
          address: %{street: "123", city: "NYC", zip: "invalid"}
        }, [:name])
        |> Embedded.cast_embed_with_validation(:address)

      # Address has invalid zip
      refute changeset.valid?
      # Check that address has errors
      address_changeset = get_change(changeset, :address)
      assert address_changeset.errors[:zip] != nil
    end
  end

  # ============================================
  # validate_embeds/2
  # ============================================

  describe "validate_embeds/2" do
    test "validates embeds with propagate_validations: true" do
      import Ecto.Changeset

      # Create a changeset with valid user but invalid address
      changeset =
        %UserWithEmbeds{}
        |> cast(%{
          name: "John",
          address: %{street: "12", city: "", zip: "12345"}  # street too short, city empty
        }, [:name])
        |> cast_embed(:address, with: fn struct, attrs -> struct |> cast(attrs, [:street, :city, :zip]) end)
        |> Embedded.validate_embeds()

      # Should have validation errors from Address
      refute changeset.valid?
    end

    test "respects :only option" do
      import Ecto.Changeset

      changeset =
        %UserWithEmbeds{}
        |> cast(%{name: "John"}, [:name])
        |> Embedded.validate_embeds(only: [:address])

      # Should still be valid since address is not present
      assert changeset.valid?
    end

    test "respects :except option" do
      import Ecto.Changeset

      changeset =
        %UserWithEmbeds{}
        |> cast(%{name: "John"}, [:name])
        |> Embedded.validate_embeds(except: [:address, :phone_numbers])

      assert changeset.valid?
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "integration with base_changeset" do
    test "base_changeset creates valid changeset with valid data" do
      cs = user_changeset(%{
        name: "John Doe",
        address: %{street: "123 Main St", city: "NYC", zip: "10001"},
        phone_numbers: [%{number: "+14155552671", type: :mobile}]
      })

      # Note: base_changeset doesn't automatically cast embeds
      # We need to manually handle embeds
      assert cs.valid?
    end

    test "tracks embedded schema metadata" do
      assert function_exported?(UserWithEmbeds, :embedded_schemas, 0)

      schemas = UserWithEmbeds.embedded_schemas()
      assert is_list(schemas)
      assert length(schemas) == 3
    end
  end

  # ============================================
  # get_embedded_schemas/1
  # ============================================

  describe "get_embedded_schemas/1" do
    test "returns embedded schemas for module with OmSchema" do
      schemas = Embedded.get_embedded_schemas(UserWithEmbeds)

      assert length(schemas) == 3
    end

    test "returns empty list for module without embedded_schemas function" do
      defmodule PlainModule do
        def foo, do: :bar
      end

      schemas = Embedded.get_embedded_schemas(PlainModule)
      assert schemas == []
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "handles nil embedded value" do
      import Ecto.Changeset

      changeset =
        %UserWithEmbeds{}
        |> cast(%{name: "John", address: nil}, [:name])
        |> Embedded.validate_embeds()

      # Should be valid since address is nil (not required)
      assert changeset.valid?
    end

    test "handles empty list for embeds_many" do
      import Ecto.Changeset

      changeset =
        %UserWithEmbeds{}
        |> cast(%{name: "John", phone_numbers: []}, [:name])
        |> Embedded.validate_embeds()

      assert changeset.valid?
    end
  end
end
