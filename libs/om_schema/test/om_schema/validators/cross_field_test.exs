defmodule OmSchema.Validators.CrossFieldTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.CrossField

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :password, :string
      field :password_confirmation, :string
      field :email, :string
      field :email_confirmation, :string
      field :phone, :string
      field :name, :string
      field :status, :string
      field :reason, :string
      field :start_date, :integer
      field :end_date, :integer
      field :min_value, :integer
      field :max_value, :integer
      field :role, :string
      field :department, :string
    end

    @fields [
      :password, :password_confirmation, :email, :email_confirmation,
      :phone, :name, :status, :reason, :start_date, :end_date,
      :min_value, :max_value, :role, :department
    ]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # ============================================
  # confirmation validation
  # ============================================

  describe "validate/2 with :confirmation" do
    test "passes when field matches confirmation field" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "secret123"})
        |> CrossField.validate([{:confirmation, :password, []}])

      assert cs.valid?
    end

    test "fails when confirmation field does not match" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "different"})
        |> CrossField.validate([{:confirmation, :password, []}])

      refute cs.valid?
    end

    test "uses default confirmation field name (field_confirmation)" do
      cs =
        changeset(%{password: "secret123", password_confirmation: "secret123"})
        |> CrossField.validate([{:confirmation, :password, []}])

      assert cs.valid?
    end

    test "uses custom match field when specified" do
      cs =
        changeset(%{email: "test@example.com", email_confirmation: "test@example.com"})
        |> CrossField.validate([{:confirmation, :email, match: :email_confirmation}])

      assert cs.valid?
    end

    test "fails with custom match field when values differ" do
      cs =
        changeset(%{email: "test@example.com", email_confirmation: "other@example.com"})
        |> CrossField.validate([{:confirmation, :email, match: :email_confirmation}])

      refute cs.valid?
    end
  end

  # ============================================
  # require_if validation
  # ============================================

  describe "validate/2 with :require_if (equals condition)" do
    test "requires field when condition is met" do
      cs =
        changeset(%{status: "rejected"})
        |> CrossField.validate([
          {:require_if, :reason, when: {:field, :status, equals: "rejected"}}
        ])

      refute cs.valid?
      assert cs.errors[:reason] != nil
    end

    test "passes when condition is met and field is present" do
      cs =
        changeset(%{status: "rejected", reason: "Not qualified"})
        |> CrossField.validate([
          {:require_if, :reason, when: {:field, :status, equals: "rejected"}}
        ])

      assert cs.valid?
    end

    test "does not require field when condition is not met" do
      cs =
        changeset(%{status: "approved"})
        |> CrossField.validate([
          {:require_if, :reason, when: {:field, :status, equals: "rejected"}}
        ])

      assert cs.valid?
    end

    test "handles nil condition field" do
      cs =
        changeset(%{})
        |> CrossField.validate([
          {:require_if, :reason, when: {:field, :status, equals: "rejected"}}
        ])

      assert cs.valid?
    end
  end

  describe "validate/2 with :require_if (is_set condition)" do
    test "requires field when other field is set" do
      cs =
        changeset(%{phone: "1234567890"})
        |> CrossField.validate([
          {:require_if, :name, when: {:field, :phone, is_set: true}}
        ])

      refute cs.valid?
      assert cs.errors[:name] != nil
    end

    test "passes when other field is set and required field is present" do
      cs =
        changeset(%{phone: "1234567890", name: "John"})
        |> CrossField.validate([
          {:require_if, :name, when: {:field, :phone, is_set: true}}
        ])

      assert cs.valid?
    end

    test "does not require field when other field is nil" do
      cs =
        changeset(%{})
        |> CrossField.validate([
          {:require_if, :name, when: {:field, :phone, is_set: true}}
        ])

      assert cs.valid?
    end
  end

  describe "validate/2 with :require_if (unknown condition)" do
    test "ignores unknown condition format" do
      cs =
        changeset(%{status: "active"})
        |> CrossField.validate([
          {:require_if, :reason, when: :unknown_condition}
        ])

      assert cs.valid?
    end
  end

  # ============================================
  # one_of validation
  # ============================================

  describe "validate/2 with :one_of" do
    test "passes when at least one field has a value" do
      cs =
        changeset(%{email: "test@example.com"})
        |> CrossField.validate([{:one_of, [:email, :phone]}])

      assert cs.valid?
    end

    test "passes when multiple fields have values" do
      cs =
        changeset(%{email: "test@example.com", phone: "123"})
        |> CrossField.validate([{:one_of, [:email, :phone]}])

      assert cs.valid?
    end

    test "fails when no fields have a value" do
      cs =
        changeset(%{})
        |> CrossField.validate([{:one_of, [:email, :phone]}])

      refute cs.valid?
      {msg, _} = cs.errors[:email]
      assert msg =~ "at least one of"
      assert msg =~ ":email"
      assert msg =~ ":phone"
    end

    test "error is added to the first field in the list" do
      cs =
        changeset(%{})
        |> CrossField.validate([{:one_of, [:phone, :email]}])

      refute cs.valid?
      assert cs.errors[:phone] != nil
      assert cs.errors[:email] == nil
    end

    test "passes when only the second field has a value" do
      cs =
        changeset(%{phone: "1234567890"})
        |> CrossField.validate([{:one_of, [:email, :phone]}])

      assert cs.valid?
    end

    test "works with three or more fields" do
      cs =
        changeset(%{name: "John"})
        |> CrossField.validate([{:one_of, [:email, :phone, :name]}])

      assert cs.valid?
    end

    test "fails with three fields all nil" do
      cs =
        changeset(%{})
        |> CrossField.validate([{:one_of, [:email, :phone, :name]}])

      refute cs.valid?
    end
  end

  # ============================================
  # compare validation
  # ============================================

  describe "validate/2 with :compare (greater_than)" do
    test "passes when field1 is greater than field2" do
      cs =
        changeset(%{end_date: 20, start_date: 10})
        |> CrossField.validate([
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      assert cs.valid?
    end

    test "fails when field1 is not greater than field2" do
      cs =
        changeset(%{end_date: 5, start_date: 10})
        |> CrossField.validate([
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      refute cs.valid?
      {msg, _} = cs.errors[:end_date]
      assert msg =~ "must be greater_than start_date"
    end

    test "fails when fields are equal" do
      cs =
        changeset(%{end_date: 10, start_date: 10})
        |> CrossField.validate([
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      refute cs.valid?
    end

    test "passes when either field is nil (skipped)" do
      cs =
        changeset(%{end_date: 10})
        |> CrossField.validate([
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      assert cs.valid?
    end

    test "passes when first field is nil (skipped)" do
      cs =
        changeset(%{start_date: 10})
        |> CrossField.validate([
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      assert cs.valid?
    end
  end

  describe "validate/2 with :compare (greater_than_or_equal_to)" do
    test "passes when field1 equals field2" do
      cs =
        changeset(%{max_value: 10, min_value: 10})
        |> CrossField.validate([
          {:compare, :max_value, comparison: {:greater_than_or_equal_to, :min_value}}
        ])

      assert cs.valid?
    end

    test "passes when field1 is greater than field2" do
      cs =
        changeset(%{max_value: 20, min_value: 10})
        |> CrossField.validate([
          {:compare, :max_value, comparison: {:greater_than_or_equal_to, :min_value}}
        ])

      assert cs.valid?
    end

    test "fails when field1 is less than field2" do
      cs =
        changeset(%{max_value: 5, min_value: 10})
        |> CrossField.validate([
          {:compare, :max_value, comparison: {:greater_than_or_equal_to, :min_value}}
        ])

      refute cs.valid?
    end
  end

  describe "validate/2 with :compare (less_than)" do
    test "passes when field1 is less than field2" do
      cs =
        changeset(%{min_value: 5, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than, :max_value}}
        ])

      assert cs.valid?
    end

    test "fails when field1 is not less than field2" do
      cs =
        changeset(%{min_value: 15, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than, :max_value}}
        ])

      refute cs.valid?
    end

    test "fails when fields are equal" do
      cs =
        changeset(%{min_value: 10, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than, :max_value}}
        ])

      refute cs.valid?
    end
  end

  describe "validate/2 with :compare (less_than_or_equal_to)" do
    test "passes when field1 equals field2" do
      cs =
        changeset(%{min_value: 10, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than_or_equal_to, :max_value}}
        ])

      assert cs.valid?
    end

    test "passes when field1 is less" do
      cs =
        changeset(%{min_value: 5, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than_or_equal_to, :max_value}}
        ])

      assert cs.valid?
    end

    test "fails when field1 is greater" do
      cs =
        changeset(%{min_value: 15, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:less_than_or_equal_to, :max_value}}
        ])

      refute cs.valid?
    end
  end

  describe "validate/2 with :compare (equal_to)" do
    test "passes when fields are equal" do
      cs =
        changeset(%{min_value: 10, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:equal_to, :max_value}}
        ])

      assert cs.valid?
    end

    test "fails when fields are not equal" do
      cs =
        changeset(%{min_value: 5, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:equal_to, :max_value}}
        ])

      refute cs.valid?
    end
  end

  describe "validate/2 with :compare (not_equal_to)" do
    test "passes when fields are different" do
      cs =
        changeset(%{min_value: 5, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:not_equal_to, :max_value}}
        ])

      assert cs.valid?
    end

    test "fails when fields are equal" do
      cs =
        changeset(%{min_value: 10, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:not_equal_to, :max_value}}
        ])

      refute cs.valid?
    end
  end

  # ============================================
  # Multiple validations in one call
  # ============================================

  describe "validate/2 with multiple validations" do
    test "applies all validations" do
      cs =
        changeset(%{
          email: "test@example.com",
          phone: "123",
          end_date: 20,
          start_date: 10
        })
        |> CrossField.validate([
          {:one_of, [:email, :phone]},
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      assert cs.valid?
    end

    test "collects errors from multiple failing validations" do
      cs =
        changeset(%{end_date: 5, start_date: 10})
        |> CrossField.validate([
          {:one_of, [:email, :phone]},
          {:compare, :end_date, comparison: {:greater_than, :start_date}}
        ])

      refute cs.valid?
      # one_of should add error on :email (first field)
      assert cs.errors[:email] != nil
      # compare should add error on :end_date
      assert cs.errors[:end_date] != nil
    end
  end

  # ============================================
  # Edge cases
  # ============================================

  describe "validate/2 edge cases" do
    test "returns changeset unchanged for empty validation list" do
      cs = changeset(%{name: "test"}) |> CrossField.validate([])

      assert cs.valid?
    end

    test "returns changeset unchanged for non-list validations" do
      cs = changeset(%{name: "test"}) |> CrossField.validate(:not_a_list)

      assert cs.valid?
    end

    test "ignores unknown validation tuples" do
      cs =
        changeset(%{name: "test"})
        |> CrossField.validate([{:unknown_validation, :field, []}])

      assert cs.valid?
    end

    test "handles unknown comparison operator gracefully" do
      cs =
        changeset(%{min_value: 5, max_value: 10})
        |> CrossField.validate([
          {:compare, :min_value, comparison: {:unknown_op, :max_value}}
        ])

      # Unknown operator defaults to true, so should pass
      assert cs.valid?
    end
  end
end
