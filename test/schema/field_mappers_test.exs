defmodule Events.Core.Schema.FieldMappersTest do
  use Events.TestCase, async: true

  defmodule TestUser do
    use OmSchema

    schema "test_users" do
      # Using mappers with atom names (recommended)
      field :email, :string, required: true, format: :email, mappers: [:trim, :downcase]
      field :name, :string, mappers: [:trim, :titlecase]

      # Auto-trim by default
      field :username, :string, required: true, min_length: 3

      # Disable auto-trim
      field :password, :string, trim: false

      # Mappers with MFA tuple (module, function, arity)
      field :code, :string, mappers: [:trim, :upcase]
    end

    def changeset(user, attrs) do
      user
      |> Ecto.Changeset.cast(attrs, cast_fields())
      |> Ecto.Changeset.validate_required(required_fields())
      |> apply_validations()
    end
  end

  describe "mappers option" do
    test "applies mappers left to right" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "  TEST@EXAMPLE.COM  ",
          username: "john_doe",
          password: "secret"
        })

      assert changeset.valid?
      # Email: trim() then downcase()
      assert changeset.changes.email == "test@example.com"
    end

    test "name with titlecase mapper" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          name: "  john doe  ",
          username: "john_doe",
          password: "secret"
        })

      assert changeset.valid?
      # Name: trim() then titlecase()
      assert changeset.changes.name == "John Doe"
    end

    test "code with custom function mapper" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          code: "  abc123  ",
          username: "john_doe",
          password: "secret"
        })

      assert changeset.valid?
      # Code: trim() then upcase
      assert changeset.changes.code == "ABC123"
    end
  end

  describe "auto-trim by default" do
    test "trims strings by default" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          username: "  john_doe  ",
          password: "secret"
        })

      assert changeset.valid?
      # Username has auto-trim (no mappers specified, no trim: false)
      assert changeset.changes.username == "john_doe"
    end
  end

  describe "trim: false option" do
    test "disables auto-trim" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "test@example.com",
          username: "john_doe",
          password: "  secret  "
        })

      assert changeset.valid?
      # Password has trim: false, so whitespace is preserved
      assert changeset.changes.password == "  secret  "
    end
  end

  describe "mappers with validation" do
    test "validation runs after mappers are applied" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          email: "INVALID-EMAIL",
          username: "john_doe",
          password: "secret"
        })

      refute changeset.valid?
      # Email is downcased before validation
      assert changeset.changes.email == "invalid-email"
      # But still fails format validation
      assert {:email, _} = List.keyfind(changeset.errors, :email, 0)
    end
  end
end
