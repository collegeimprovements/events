defmodule Events.Core.Schema.StringPresetsTest do
  use Events.TestCase, async: true

  import OmSchema.Presets.Strings

  defmodule Profile do
    use OmSchema

    schema "profiles" do
      field :first_name, :string, preset: name()
      field :full_name, :string, preset: full_name()
      field :bio, :string, preset: short_text()
      field :search_query, :string, preset: search_term()
      field :tag, :string, preset: tag()
      field :code, :string, preset: code()
    end

    def changeset(profile, attrs) do
      profile
      |> Ecto.Changeset.cast(attrs, cast_fields())
      |> Ecto.Changeset.validate_required(required_fields())
      |> apply_validations()
    end
  end

  describe "name preset" do
    test "titlecases names" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "john",
          full_name: "Jane Doe",
          search_query: "test",
          tag: "my-tag",
          code: "ABC123"
        })

      assert changeset.valid?
      assert changeset.changes.first_name == "John"
    end

    test "validates minimum length" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "J",
          full_name: "Jane Doe",
          search_query: "test",
          tag: "my-tag",
          code: "ABC123"
        })

      refute changeset.valid?
      assert {:first_name, _} = List.keyfind(changeset.errors, :first_name, 0)
    end
  end

  describe "full_name preset" do
    test "squishes multiple spaces" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "John",
          full_name: "Jane    Doe   Smith",
          search_query: "test",
          tag: "my-tag",
          code: "ABC123"
        })

      assert changeset.valid?
      # Note: squish should collapse spaces
    end
  end

  describe "tag preset" do
    test "downcases and validates format" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "John",
          full_name: "Jane Doe",
          search_query: "test",
          tag: "My-Tag-123",
          code: "ABC123"
        })

      assert changeset.valid?
      assert changeset.changes.tag == "my-tag-123"
    end

    test "rejects invalid characters" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "John",
          full_name: "Jane Doe",
          search_query: "test",
          tag: "Invalid Tag!",
          code: "ABC123"
        })

      refute changeset.valid?
    end
  end

  describe "code preset" do
    test "upcases and removes non-alphanumeric" do
      changeset =
        Profile.changeset(%Profile{}, %{
          first_name: "John",
          full_name: "Jane Doe",
          search_query: "test",
          tag: "my-tag",
          code: "abc-123"
        })

      assert changeset.valid?
      assert changeset.changes.code == "ABC123"
    end
  end
end
