defmodule Events.Schema.FieldLevelValidationTest do
  use ExUnit.Case, async: true

  defmodule TestUser do
    use Events.Schema
    import Events.Schema.Presets

    schema "test_users" do
      field :email, :string, required: true, format: :email, normalize: [:trim, :downcase]
      field :age, :integer, min: 18, max: 120
      field :username, :string, preset: username()
      field :bio, :string, max_length: 500, cast: true
      field :notes, :string, cast: false
      # timestamps() already added by Events.Schema
    end

    def changeset(user, attrs) do
      user
      |> cast(attrs, __cast_fields__())
      |> validate_required(__required_fields__())
      |> __apply_field_validations__()
    end
  end

  describe "enhanced field macro" do
    test "__cast_fields__ returns fields with cast: true" do
      cast_fields = TestUser.__cast_fields__()

      assert :email in cast_fields
      assert :age in cast_fields
      assert :username in cast_fields
      assert :bio in cast_fields
      # cast: false
      refute :notes in cast_fields
    end

    test "__required_fields__ returns fields with required: true" do
      required_fields = TestUser.__required_fields__()

      assert :email in required_fields
    end

    test "__field_validations__ returns validation metadata" do
      validations = TestUser.__field_validations__()

      assert length(validations) > 0
      assert Enum.any?(validations, fn {field, _type, _opts} -> field == :email end)
    end

    test "changeset applies field validations" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "  TEST@EXAMPLE.COM  ",
          age: 25,
          username: "john_doe"
        })

      assert changeset.valid?
      # Verify normalization happened
      assert changeset.changes.email == "test@example.com"
    end

    test "changeset validates age range" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          # Too young
          age: 15,
          username: "john_doe"
        })

      refute changeset.valid?
      assert {:age, _} = List.keyfind(changeset.errors, :age, 0)
    end

    test "changeset validates email format" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "invalid-email",
          age: 25,
          username: "john_doe"
        })

      refute changeset.valid?
    end

    test "cast_fields excludes fields with cast: false" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          age: 25,
          username: "john_doe",
          notes: "should not be cast"
        })

      refute Map.has_key?(changeset.changes, :notes)
    end
  end
end
