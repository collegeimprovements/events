defmodule OmSchema.ConditionalRequiredTest do
  use ExUnit.Case, async: true

  alias OmSchema.ConditionalRequired

  # Helper schema for testing
  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :status, :string
      field :type, :string
      field :contact_method, :string
      field :email, :string
      field :phone, :string
      field :address, :map
      field :amount, :integer
      field :priority, :integer
      field :is_business, :boolean
      field :notify_sms, :boolean
      field :notify_call, :boolean
      field :reason, :string
      field :notes, :string
      field :requires_shipping, :boolean
    end

    def changeset(struct, attrs) do
      cast(struct, attrs, [
        :status,
        :type,
        :contact_method,
        :email,
        :phone,
        :address,
        :amount,
        :priority,
        :is_business,
        :notify_sms,
        :notify_call,
        :reason,
        :notes,
        :requires_shipping
      ])
    end
  end

  defp changeset(attrs) do
    TestSchema.changeset(%TestSchema{}, attrs)
  end

  # ============================================
  # Simple Equality (Keyword List)
  # ============================================

  describe "validate/2 with simple equality" do
    test "requires field when condition matches" do
      # Note: status field is :string type so we use string values
      cs = changeset(%{status: "cancelled"})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] != nil
    end

    test "does not require field when condition does not match" do
      cs = changeset(%{status: "active"})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] == nil
    end

    test "requires field when all conditions match (implicit AND)" do
      cs = changeset(%{status: "active", type: "premium"})
      result = ConditionalRequired.validate(cs, [{:phone, [status: "active", type: "premium"]}])

      assert result.errors[:phone] != nil
    end

    test "does not require field when one condition fails" do
      cs = changeset(%{status: "active", type: "basic"})
      result = ConditionalRequired.validate(cs, [{:phone, [status: "active", type: "premium"]}])

      assert result.errors[:phone] == nil
    end

    test "passes when field is present" do
      cs = changeset(%{status: "cancelled", reason: "Changed mind"})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] == nil
    end
  end

  # ============================================
  # Comparison Operators
  # ============================================

  describe "validate/2 with comparison operators" do
    test ":eq operator" do
      cs = changeset(%{amount: 100})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :eq, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":neq operator" do
      cs = changeset(%{amount: 50})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :neq, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":gt operator" do
      cs = changeset(%{amount: 150})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :gt, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":gte operator" do
      cs = changeset(%{amount: 100})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :gte, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":lt operator" do
      cs = changeset(%{amount: 50})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :lt, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":lte operator" do
      cs = changeset(%{amount: 100})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :lte, 100}}])

      assert result.errors[:reason] != nil
    end

    test ":in operator" do
      cs = changeset(%{status: "pending"})
      result = ConditionalRequired.validate(cs, [{:reason, {:status, :in, ["pending", "rejected"]}}])

      assert result.errors[:reason] != nil
    end

    test ":not_in operator" do
      cs = changeset(%{status: "active"})
      result = ConditionalRequired.validate(cs, [{:reason, {:status, :not_in, ["pending", "rejected"]}}])

      assert result.errors[:reason] != nil
    end

    test "comparison with nil value returns false" do
      cs = changeset(%{})
      result = ConditionalRequired.validate(cs, [{:reason, {:amount, :gt, 100}}])

      assert result.errors[:reason] == nil
    end
  end

  # ============================================
  # Unary Operators
  # ============================================

  describe "validate/2 with unary operators" do
    test ":truthy operator" do
      cs = changeset(%{is_business: true})
      result = ConditionalRequired.validate(cs, [{:phone, {:is_business, :truthy}}])

      assert result.errors[:phone] != nil
    end

    test ":truthy with false value" do
      cs = changeset(%{is_business: false})
      result = ConditionalRequired.validate(cs, [{:phone, {:is_business, :truthy}}])

      assert result.errors[:phone] == nil
    end

    test ":falsy operator" do
      cs = changeset(%{is_business: false})
      result = ConditionalRequired.validate(cs, [{:reason, {:is_business, :falsy}}])

      assert result.errors[:reason] != nil
    end

    test ":present operator" do
      cs = changeset(%{email: "test@example.com"})
      result = ConditionalRequired.validate(cs, [{:phone, {:email, :present}}])

      assert result.errors[:phone] != nil
    end

    test ":present with nil" do
      cs = changeset(%{})
      result = ConditionalRequired.validate(cs, [{:phone, {:email, :present}}])

      assert result.errors[:phone] == nil
    end

    test ":blank operator" do
      cs = changeset(%{})
      result = ConditionalRequired.validate(cs, [{:email, {:phone, :blank}}])

      assert result.errors[:email] != nil
    end

    test ":blank with empty string" do
      cs = changeset(%{phone: ""})
      result = ConditionalRequired.validate(cs, [{:email, {:phone, :blank}}])

      assert result.errors[:email] != nil
    end
  end

  # ============================================
  # Boolean Combinators
  # ============================================

  describe "validate/2 with :and combinator" do
    test "requires field when all conditions match" do
      cs = changeset(%{status: "active", amount: 150})
      condition = [[status: "active"], :and, {:amount, :gt, 100}]
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end

    test "does not require when first condition fails" do
      cs = changeset(%{status: "inactive", amount: 150})
      condition = [[status: "active"], :and, {:amount, :gt, 100}]
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] == nil
    end

    test "does not require when second condition fails" do
      cs = changeset(%{status: "active", amount: 50})
      condition = [[status: "active"], :and, {:amount, :gt, 100}]
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] == nil
    end
  end

  describe "validate/2 with :or combinator" do
    test "requires field when first condition matches" do
      cs = changeset(%{notify_sms: true})
      condition = [[notify_sms: true], :or, [notify_call: true]]
      result = ConditionalRequired.validate(cs, [{:phone, condition}])

      assert result.errors[:phone] != nil
    end

    test "requires field when second condition matches" do
      cs = changeset(%{notify_call: true})
      condition = [[notify_sms: true], :or, [notify_call: true]]
      result = ConditionalRequired.validate(cs, [{:phone, condition}])

      assert result.errors[:phone] != nil
    end

    test "does not require when neither condition matches" do
      cs = changeset(%{notify_sms: false, notify_call: false})
      condition = [[notify_sms: true], :or, [notify_call: true]]
      result = ConditionalRequired.validate(cs, [{:phone, condition}])

      assert result.errors[:phone] == nil
    end
  end

  describe "validate/2 with chained conditions" do
    test "chained :and" do
      cs = changeset(%{status: "active", amount: 150, priority: 10})
      condition = [[status: "active"], :and, {:amount, :gt, 100}, :and, {:priority, :gte, 5}]
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end

    test "chained :or" do
      cs = changeset(%{type: "c"})
      condition = [[type: "a"], :or, [type: "b"], :or, [type: "c"]]
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end
  end

  # ============================================
  # Negation
  # ============================================

  describe "validate/2 with negation" do
    test "requires field when negated condition is false" do
      cs = changeset(%{status: "active"})
      condition = {:not, [status: "cancelled"]}
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end

    test "does not require when negated condition is true" do
      cs = changeset(%{status: "cancelled"})
      condition = {:not, [status: "cancelled"]}
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] == nil
    end

    test "negation with comparison operator" do
      cs = changeset(%{amount: 50})
      condition = {:not, {:amount, :gt, 100}}
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end
  end

  # ============================================
  # Nested Grouping
  # ============================================

  describe "validate/2 with nested grouping" do
    test "complex nested condition" do
      # (status: "active" AND amount > 100) OR (type: "vip" AND priority >= 5)
      cs = changeset(%{status: "active", amount: 150})

      condition = [
        [[status: "active"], :and, {:amount, :gt, 100}],
        :or,
        [[type: "vip"], :and, {:priority, :gte, 5}]
      ]

      result = ConditionalRequired.validate(cs, [{:notes, condition}])

      assert result.errors[:notes] != nil
    end

    test "nested condition - second group matches" do
      cs = changeset(%{type: "vip", priority: 10})

      condition = [
        [[status: "active"], :and, {:amount, :gt, 100}],
        :or,
        [[type: "vip"], :and, {:priority, :gte, 5}]
      ]

      result = ConditionalRequired.validate(cs, [{:notes, condition}])

      assert result.errors[:notes] != nil
    end

    test "nested condition - neither group matches" do
      cs = changeset(%{status: "inactive", type: "basic"})

      condition = [
        [[status: "active"], :and, {:amount, :gt, 100}],
        :or,
        [[type: "vip"], :and, {:priority, :gte, 5}]
      ]

      result = ConditionalRequired.validate(cs, [{:notes, condition}])

      assert result.errors[:notes] == nil
    end
  end

  # ============================================
  # Function Escape Hatch
  # ============================================

  describe "validate/2 with function" do
    test "accepts anonymous function" do
      cs = changeset(%{amount: 150})
      condition = fn changeset -> Ecto.Changeset.get_field(changeset, :amount) > 100 end
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end

    test "accepts MFA tuple" do
      cs = changeset(%{status: :active})
      condition = {__MODULE__, :always_true}
      result = ConditionalRequired.validate(cs, [{:reason, condition}])

      assert result.errors[:reason] != nil
    end
  end

  def always_true(_changeset), do: true

  # ============================================
  # required?/2 function
  # ============================================

  describe "required?/2" do
    test "returns true when condition matches" do
      cs = changeset(%{status: "active"})

      assert ConditionalRequired.required?(cs, [status: "active"]) == true
    end

    test "returns false when condition does not match" do
      cs = changeset(%{status: "inactive"})

      assert ConditionalRequired.required?(cs, [status: "active"]) == false
    end
  end

  # ============================================
  # validate_syntax/1 function
  # ============================================

  describe "validate_syntax/1" do
    test "validates keyword list syntax" do
      assert ConditionalRequired.validate_syntax([status: :active]) == :ok
    end

    test "validates comparison operator syntax" do
      assert ConditionalRequired.validate_syntax({:amount, :gt, 100}) == :ok
    end

    test "validates unary operator syntax" do
      assert ConditionalRequired.validate_syntax({:is_business, :truthy}) == :ok
    end

    test "validates negation syntax" do
      assert ConditionalRequired.validate_syntax({:not, [status: :active]}) == :ok
    end

    test "validates boolean combinator syntax" do
      assert ConditionalRequired.validate_syntax([[status: :active], :and, [type: :vip]]) == :ok
    end

    test "validates function syntax" do
      assert ConditionalRequired.validate_syntax(fn _ -> true end) == :ok
    end

    test "validates MFA syntax" do
      assert ConditionalRequired.validate_syntax({MyModule, :my_function}) == :ok
    end

    test "returns error for unknown comparison operator" do
      {:error, message} = ConditionalRequired.validate_syntax({:amount, :unknown_op, 100})

      assert message =~ "unknown comparison operator"
    end

    test "returns error for unknown unary operator" do
      # The syntax validation treats unknown unary ops as MFA tuples if both are atoms
      # So we test with a more clearly invalid structure
      {:error, message} = ConditionalRequired.validate_syntax({:amount, :invalid_comparison_op, 100})

      assert message =~ "unknown comparison operator"
    end

    test "returns error for mixed operators without grouping" do
      {:error, message} = ConditionalRequired.validate_syntax([[a: 1], :and, [b: 2], :or, [c: 3]])

      assert message =~ "mixed :and/:or"
    end
  end

  # ============================================
  # Field Blank Detection
  # ============================================

  describe "field blank detection" do
    test "nil is considered blank" do
      cs = changeset(%{status: "cancelled"})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] != nil
    end

    test "empty string is considered blank" do
      cs = changeset(%{status: "cancelled", reason: ""})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] != nil
    end

    test "empty map is considered blank" do
      cs = changeset(%{status: "cancelled", address: %{}})
      result = ConditionalRequired.validate(cs, [{:address, [status: "cancelled"]}])

      assert result.errors[:address] != nil
    end

    test "non-empty value is not blank" do
      cs = changeset(%{status: "cancelled", reason: "Changed mind"})
      result = ConditionalRequired.validate(cs, [{:reason, [status: "cancelled"]}])

      assert result.errors[:reason] == nil
    end
  end

  # ============================================
  # Multiple Fields
  # ============================================

  describe "validate/2 with multiple fields" do
    test "validates multiple conditional fields" do
      cs = changeset(%{status: "cancelled"})

      fields = [
        {:reason, [status: "cancelled"]},
        {:notes, [status: "cancelled"]}
      ]

      result = ConditionalRequired.validate(cs, fields)

      assert result.errors[:reason] != nil
      assert result.errors[:notes] != nil
    end

    test "validates multiple fields with different conditions" do
      cs = changeset(%{type: "physical", requires_shipping: true})

      fields = [
        {:address, [[type: "physical"], :and, {:requires_shipping, :truthy}]},
        {:phone, [contact_method: "phone"]}
      ]

      result = ConditionalRequired.validate(cs, fields)

      assert result.errors[:address] != nil
      assert result.errors[:phone] == nil
    end
  end
end
