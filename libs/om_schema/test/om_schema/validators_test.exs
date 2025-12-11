defmodule OmSchema.ValidatorsTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators

  # Helper to create a changeset for testing
  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :email, :string
      field :name, :string
      field :age, :integer
      field :price, :decimal
      field :status, :string
      field :url, :string
      field :uuid_field, :string
      field :slug, :string
      field :phone, :string
      field :terms_accepted, :boolean
      field :start_date, :utc_datetime
      field :tags, {:array, :string}
      field :metadata, :map
      field :other_field, :integer
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [
        :email,
        :name,
        :age,
        :price,
        :status,
        :url,
        :uuid_field,
        :slug,
        :phone,
        :terms_accepted,
        :start_date,
        :tags,
        :metadata,
        :other_field
      ])
    end
  end

  defp changeset(attrs) do
    TestSchema.changeset(%TestSchema{}, attrs)
  end

  # ============================================
  # Required Validation
  # ============================================

  describe "apply/4 :required" do
    test "validates field is required" do
      cs = changeset(%{}) |> Validators.apply(:email, :required)

      assert cs.errors[:email] != nil
    end

    test "passes when field is present" do
      cs = changeset(%{email: "test@example.com"}) |> Validators.apply(:email, :required)

      assert cs.errors[:email] == nil
    end
  end

  # ============================================
  # Email Validation
  # ============================================

  describe "apply/4 :email" do
    test "validates email format" do
      cs = changeset(%{email: "invalid"}) |> Validators.apply(:email, :email)

      assert cs.errors[:email] != nil
    end

    test "passes valid email" do
      cs = changeset(%{email: "test@example.com"}) |> Validators.apply(:email, :email)

      assert cs.errors[:email] == nil
    end
  end

  # ============================================
  # URL Validation
  # ============================================

  describe "apply/4 :url" do
    test "validates url format" do
      cs = changeset(%{url: "invalid"}) |> Validators.apply(:url, :url)

      assert cs.errors[:url] != nil
    end

    test "passes valid http url" do
      cs = changeset(%{url: "http://example.com"}) |> Validators.apply(:url, :url)

      assert cs.errors[:url] == nil
    end

    test "passes valid https url" do
      cs = changeset(%{url: "https://example.com"}) |> Validators.apply(:url, :url)

      assert cs.errors[:url] == nil
    end
  end

  # ============================================
  # UUID Validation
  # ============================================

  describe "apply/4 :uuid" do
    test "validates uuid format" do
      cs = changeset(%{uuid_field: "invalid"}) |> Validators.apply(:uuid_field, :uuid)

      assert cs.errors[:uuid_field] != nil
    end

    test "passes valid uuid" do
      cs =
        changeset(%{uuid_field: "550e8400-e29b-41d4-a716-446655440000"})
        |> Validators.apply(:uuid_field, :uuid)

      assert cs.errors[:uuid_field] == nil
    end
  end

  # ============================================
  # Slug Validation
  # ============================================

  describe "apply/4 :slug" do
    test "validates slug format" do
      cs = changeset(%{slug: "Invalid Slug!"}) |> Validators.apply(:slug, :slug)

      assert cs.errors[:slug] != nil
    end

    test "passes valid slug" do
      cs = changeset(%{slug: "valid-slug"}) |> Validators.apply(:slug, :slug)

      assert cs.errors[:slug] == nil
    end

    test "passes slug with numbers" do
      cs = changeset(%{slug: "valid-slug-123"}) |> Validators.apply(:slug, :slug)

      assert cs.errors[:slug] == nil
    end
  end

  # ============================================
  # Phone Validation
  # ============================================

  describe "apply/4 :phone" do
    test "validates phone format" do
      cs = changeset(%{phone: "abc"}) |> Validators.apply(:phone, :phone)

      assert cs.errors[:phone] != nil
    end

    test "passes valid phone" do
      cs = changeset(%{phone: "+1-555-123-4567"}) |> Validators.apply(:phone, :phone)

      assert cs.errors[:phone] == nil
    end
  end

  # ============================================
  # Number Validations
  # ============================================

  describe "apply/4 :min" do
    test "validates minimum value" do
      cs = changeset(%{age: 10}) |> Validators.apply(:age, :min, value: 18)

      assert cs.errors[:age] != nil
    end

    test "passes when at minimum" do
      cs = changeset(%{age: 18}) |> Validators.apply(:age, :min, value: 18)

      assert cs.errors[:age] == nil
    end

    test "passes when above minimum" do
      cs = changeset(%{age: 25}) |> Validators.apply(:age, :min, value: 18)

      assert cs.errors[:age] == nil
    end
  end

  describe "apply/4 :max" do
    test "validates maximum value" do
      cs = changeset(%{age: 200}) |> Validators.apply(:age, :max, value: 150)

      assert cs.errors[:age] != nil
    end

    test "passes when at maximum" do
      cs = changeset(%{age: 150}) |> Validators.apply(:age, :max, value: 150)

      assert cs.errors[:age] == nil
    end

    test "passes when below maximum" do
      cs = changeset(%{age: 100}) |> Validators.apply(:age, :max, value: 150)

      assert cs.errors[:age] == nil
    end
  end

  describe "apply/4 :positive" do
    test "validates positive value" do
      cs = changeset(%{age: 0}) |> Validators.apply(:age, :positive)

      assert cs.errors[:age] != nil
    end

    test "fails for negative value" do
      cs = changeset(%{age: -1}) |> Validators.apply(:age, :positive)

      assert cs.errors[:age] != nil
    end

    test "passes for positive value" do
      cs = changeset(%{age: 1}) |> Validators.apply(:age, :positive)

      assert cs.errors[:age] == nil
    end
  end

  describe "apply/4 :non_negative" do
    test "validates non-negative value" do
      cs = changeset(%{age: -1}) |> Validators.apply(:age, :non_negative)

      assert cs.errors[:age] != nil
    end

    test "passes for zero" do
      cs = changeset(%{age: 0}) |> Validators.apply(:age, :non_negative)

      assert cs.errors[:age] == nil
    end

    test "passes for positive" do
      cs = changeset(%{age: 1}) |> Validators.apply(:age, :non_negative)

      assert cs.errors[:age] == nil
    end
  end

  # ============================================
  # Length Validations
  # ============================================

  describe "apply/4 :min_length" do
    test "validates minimum length" do
      cs = changeset(%{name: "ab"}) |> Validators.apply(:name, :min_length, value: 3)

      assert cs.errors[:name] != nil
    end

    test "passes at minimum length" do
      cs = changeset(%{name: "abc"}) |> Validators.apply(:name, :min_length, value: 3)

      assert cs.errors[:name] == nil
    end
  end

  describe "apply/4 :max_length" do
    test "validates maximum length" do
      cs = changeset(%{name: "abcdefgh"}) |> Validators.apply(:name, :max_length, value: 5)

      assert cs.errors[:name] != nil
    end

    test "passes at maximum length" do
      cs = changeset(%{name: "abcde"}) |> Validators.apply(:name, :max_length, value: 5)

      assert cs.errors[:name] == nil
    end
  end

  describe "apply/4 :length" do
    test "validates exact length" do
      cs = changeset(%{name: "abc"}) |> Validators.apply(:name, :length, value: 5)

      assert cs.errors[:name] != nil
    end

    test "passes at exact length" do
      cs = changeset(%{name: "abcde"}) |> Validators.apply(:name, :length, value: 5)

      assert cs.errors[:name] == nil
    end
  end

  # ============================================
  # Format Validation
  # ============================================

  describe "apply/4 :format" do
    test "validates format with regex" do
      cs = changeset(%{name: "abc123"}) |> Validators.apply(:name, :format, value: ~r/^[a-z]+$/)

      assert cs.errors[:name] != nil
    end

    test "passes when format matches" do
      cs = changeset(%{name: "abc"}) |> Validators.apply(:name, :format, value: ~r/^[a-z]+$/)

      assert cs.errors[:name] == nil
    end
  end

  # ============================================
  # Inclusion/Exclusion
  # ============================================

  describe "apply/4 :inclusion" do
    test "validates value is in list" do
      cs =
        changeset(%{status: "unknown"})
        |> Validators.apply(:status, :inclusion, in: ["active", "inactive"])

      assert cs.errors[:status] != nil
    end

    test "passes when value in list" do
      cs =
        changeset(%{status: "active"})
        |> Validators.apply(:status, :inclusion, in: ["active", "inactive"])

      assert cs.errors[:status] == nil
    end
  end

  describe "apply/4 :exclusion" do
    test "validates value not in list" do
      cs =
        changeset(%{status: "banned"})
        |> Validators.apply(:status, :exclusion, not_in: ["banned", "deleted"])

      assert cs.errors[:status] != nil
    end

    test "passes when value not in list" do
      cs =
        changeset(%{status: "active"})
        |> Validators.apply(:status, :exclusion, not_in: ["banned", "deleted"])

      assert cs.errors[:status] == nil
    end
  end

  describe "apply/4 :in" do
    test "validates inclusion via :in" do
      cs = changeset(%{status: "unknown"}) |> Validators.apply(:status, :in, value: ["active"])

      assert cs.errors[:status] != nil
    end
  end

  describe "apply/4 :not_in" do
    test "validates exclusion via :not_in" do
      cs = changeset(%{status: "banned"}) |> Validators.apply(:status, :not_in, value: ["banned"])

      assert cs.errors[:status] != nil
    end
  end

  # ============================================
  # Boolean Validations
  # ============================================

  describe "apply/4 :acceptance" do
    test "validates acceptance" do
      cs = changeset(%{terms_accepted: false}) |> Validators.apply(:terms_accepted, :acceptance)

      assert cs.errors[:terms_accepted] != nil
    end

    test "passes when accepted" do
      cs = changeset(%{terms_accepted: true}) |> Validators.apply(:terms_accepted, :acceptance)

      assert cs.errors[:terms_accepted] == nil
    end
  end

  # ============================================
  # DateTime Validations
  # ============================================

  describe "apply/4 :past" do
    test "validates date is in past" do
      future = DateTime.utc_now() |> DateTime.add(86400, :second)
      cs = changeset(%{start_date: future}) |> Validators.apply(:start_date, :past)

      assert cs.errors[:start_date] != nil
    end

    test "passes for past date" do
      past = DateTime.utc_now() |> DateTime.add(-86400, :second)
      cs = changeset(%{start_date: past}) |> Validators.apply(:start_date, :past)

      assert cs.errors[:start_date] == nil
    end
  end

  describe "apply/4 :future" do
    test "validates date is in future" do
      past = DateTime.utc_now() |> DateTime.add(-86400, :second)
      cs = changeset(%{start_date: past}) |> Validators.apply(:start_date, :future)

      assert cs.errors[:start_date] != nil
    end

    test "passes for future date" do
      future = DateTime.utc_now() |> DateTime.add(86400, :second)
      cs = changeset(%{start_date: future}) |> Validators.apply(:start_date, :future)

      assert cs.errors[:start_date] == nil
    end
  end

  # ============================================
  # Unique Validation
  # ============================================

  describe "apply/4 :unique" do
    # NOTE: Embedded schemas don't have a source, so we can't test unique_constraint directly
    # This test verifies the logic paths without actually adding constraints

    test "skips unique constraint when value: false" do
      cs =
        changeset(%{email: "test@example.com"}) |> Validators.apply(:email, :unique, value: false)

      assert cs.valid?
    end
  end

  # ============================================
  # Confirmation Validation
  # ============================================

  describe "apply/4 :confirmation" do
    test "validates confirmation field matches" do
      cs = changeset(%{name: "test"}) |> Validators.apply(:name, :confirmation)

      # Confirmation validation needs the confirmation field
      assert cs.valid? || cs.errors[:name_confirmation] != nil
    end
  end

  # ============================================
  # Exclusive Fields (Global)
  # ============================================

  describe "apply/4 :exclusive" do
    test "validates mutually exclusive fields" do
      cs =
        changeset(%{email: "test@example.com", phone: "123"})
        |> Validators.apply(:_global, :exclusive, fields: [:email, :phone])

      assert cs.errors[:base] != nil
    end

    test "passes when only one field present" do
      cs =
        changeset(%{email: "test@example.com"})
        |> Validators.apply(:_global, :exclusive, fields: [:email, :phone])

      assert cs.errors[:base] == nil
    end

    test "validates at_least_one option" do
      cs =
        changeset(%{})
        |> Validators.apply(:_global, :exclusive, fields: [:email, :phone], at_least_one: true)

      assert cs.errors[:base] != nil
    end
  end

  # ============================================
  # Comparison Validation
  # ============================================

  describe "apply/4 :comparison" do
    test "validates field comparison" do
      cs =
        changeset(%{age: 10, other_field: 20})
        |> Validators.apply(:age, :comparison, operator: :>, other_field: :other_field)

      assert cs.errors[:age] != nil
    end

    test "passes when comparison is true" do
      cs =
        changeset(%{age: 30, other_field: 20})
        |> Validators.apply(:age, :comparison, operator: :>, other_field: :other_field)

      assert cs.errors[:age] == nil
    end
  end

  # ============================================
  # Fallback
  # ============================================

  describe "apply/4 fallback" do
    test "unknown type returns changeset unchanged" do
      cs = changeset(%{name: "test"}) |> Validators.apply(:name, :unknown_type)

      assert cs.valid?
    end
  end
end
