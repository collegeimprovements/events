defmodule Events.Schema.EnhancedFieldTest do
  use ExUnit.Case, async: true

  defmodule TestUser do
    use Events.Schema

    schema "users" do
      field :name, :string, required: true, min_length: 2, max_length: 100
      field :email, :string, required: true, format: :email
      field :age, :integer, positive: true, max: 150
      field :bio, :string, required: false, cast: true
      field :internal_notes, :string, cast: false
    end

    def changeset(user, attrs) do
      user
      |> Ecto.Changeset.cast(attrs, __cast_fields__())
      |> Ecto.Changeset.validate_required(__required_fields__())
      |> __apply_field_validations__()
    end
  end

  defmodule TestPost do
    use Events.Schema

    schema "posts" do
      field :title, :string, required: true
      field :slug, :string, normalize: {:slugify, uniquify: true}
      field :status, :string, in: ["draft", "published", "archived"], default: "draft"
      field :views, :integer, non_negative: true, default: 0
    end
  end

  describe "__cast_fields__/0" do
    test "returns fields with cast: true" do
      cast_fields = TestUser.__cast_fields__()

      assert :name in cast_fields
      assert :email in cast_fields
      assert :age in cast_fields
      assert :bio in cast_fields
      refute :internal_notes in cast_fields
    end
  end

  describe "__required_fields__/0" do
    test "returns fields with required: true" do
      required_fields = TestUser.__required_fields__()

      assert :name in required_fields
      assert :email in required_fields
      # positive: true, but not required
      refute :age in required_fields
      refute :bio in required_fields
    end
  end

  describe "__field_validations__/0" do
    test "returns all field validation metadata" do
      validations = TestUser.__field_validations__()

      assert is_list(validations)
      assert length(validations) > 0

      # Find name field validation
      {name, type, opts} = Enum.find(validations, fn {field, _, _} -> field == :name end)

      assert name == :name
      assert type == :string
      assert opts[:required] == true
      assert opts[:min_length] == 2
      assert opts[:max_length] == 100
    end
  end

  describe "changeset validation" do
    test "validates required fields" do
      changeset = TestUser.changeset(%TestUser{}, %{})

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates string length" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          name: "A",
          email: "test@example.com",
          age: 25
        })

      refute changeset.valid?
      assert %{name: [_]} = errors_on(changeset)
    end

    test "validates email format" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          name: "John Doe",
          email: "invalid-email",
          age: 25
        })

      refute changeset.valid?
      assert %{email: [_]} = errors_on(changeset)
    end

    test "validates positive numbers" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          name: "John Doe",
          email: "john@example.com",
          age: -5
        })

      refute changeset.valid?
      assert %{age: [_]} = errors_on(changeset)
    end

    test "valid changeset passes all validations" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          name: "John Doe",
          email: "john@example.com",
          age: 25,
          bio: "Software developer"
        })

      assert changeset.valid?
    end

    test "does not cast fields with cast: false" do
      changeset =
        TestUser.changeset(%TestUser{}, %{
          name: "John Doe",
          email: "john@example.com",
          internal_notes: "This should not be cast"
        })

      refute Map.has_key?(changeset.changes, :internal_notes)
    end
  end

  describe "slugify normalization" do
    test "slugifies with uniqueness suffix" do
      post = %TestPost{}

      changeset =
        Ecto.Changeset.cast(post, %{title: "Hello World", slug: "Hello World!"}, [:title, :slug])

      changeset = TestPost.__apply_field_validations__(changeset)

      slug = Ecto.Changeset.get_change(changeset, :slug)

      assert slug =~ ~r/^hello-world-[a-z0-9]{6}$/
    end
  end

  describe "enum validation" do
    test "validates inclusion in allowed values" do
      post = %TestPost{}
      changeset = Ecto.Changeset.cast(post, %{title: "Test", status: "invalid"}, [:title, :status])
      changeset = TestPost.__apply_field_validations__(changeset)

      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "accepts valid enum values" do
      post = %TestPost{}

      changeset =
        Ecto.Changeset.cast(post, %{title: "Test", status: "published"}, [:title, :status])

      changeset = TestPost.__apply_field_validations__(changeset)

      assert changeset.valid?
    end
  end

  describe "number shortcuts" do
    test "non_negative accepts zero and positive" do
      post = %TestPost{}

      changeset_zero = Ecto.Changeset.cast(post, %{views: 0}, [:views])
      changeset_zero = TestPost.__apply_field_validations__(changeset_zero)
      assert changeset_zero.valid?

      changeset_positive = Ecto.Changeset.cast(post, %{views: 100}, [:views])
      changeset_positive = TestPost.__apply_field_validations__(changeset_positive)
      assert changeset_positive.valid?

      changeset_negative = Ecto.Changeset.cast(post, %{views: -1}, [:views])
      changeset_negative = TestPost.__apply_field_validations__(changeset_negative)
      refute changeset_negative.valid?
    end
  end

  # Helper to get errors as a map
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
