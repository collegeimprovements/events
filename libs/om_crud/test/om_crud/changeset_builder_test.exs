defmodule OmCrud.ChangesetBuilderTest do
  use ExUnit.Case, async: true

  alias OmCrud.ChangesetBuilder

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    schema "test_table" do
      field :name, :string
      field :email, :string
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:name, :email])
      |> validate_required([:name])
    end

    def custom_changeset(struct, attrs) do
      struct
      |> cast(attrs, [:name, :email])
      |> validate_required([:name, :email])
    end
  end

  describe "build/3" do
    test "builds changeset from schema module" do
      attrs = %{name: "Alice", email: "alice@test.com"}

      changeset = ChangesetBuilder.build(TestSchema, attrs)

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "builds changeset from existing struct" do
      struct = %TestSchema{name: "Alice", email: "alice@test.com"}
      attrs = %{name: "Bob"}

      changeset = ChangesetBuilder.build(struct, attrs)

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "uses custom changeset function when specified" do
      attrs = %{name: "Alice"}

      changeset = ChangesetBuilder.build(TestSchema, attrs, changeset: :custom_changeset)

      # custom_changeset requires email, so this should be invalid
      refute changeset.valid?
    end

    test "uses default changeset function when not specified" do
      attrs = %{name: "Alice"}

      changeset = ChangesetBuilder.build(TestSchema, attrs)

      # default changeset only requires name, so this should be valid
      assert changeset.valid?
    end
  end

  describe "resolve/3" do
    test "returns explicit changeset option when provided" do
      result = ChangesetBuilder.resolve(TestSchema, :create, changeset: :custom_changeset)

      assert result == :custom_changeset
    end

    test "returns action-specific changeset when provided" do
      result = ChangesetBuilder.resolve(TestSchema, :create, create_changeset: :registration_changeset)

      assert result == :registration_changeset
    end

    test "returns default :changeset when nothing specified" do
      result = ChangesetBuilder.resolve(TestSchema, :create, [])

      assert result == :changeset
    end
  end
end
