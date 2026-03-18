defmodule OmQuery.ValidatorTest.TestSchema do
  @moduledoc false
  use Ecto.Schema

  schema "test_items" do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :status, :string
    field :metadata, :map
  end
end

defmodule OmQuery.ValidatorTest do
  @moduledoc """
  Tests for OmQuery.Validator - Schema-aware query validation.

  Validator provides early validation of query operations with helpful
  error messages, including "did you mean?" suggestions for typos
  using Jaro distance.

  ## Key Behaviors

  - **Field validation**: Checks fields exist in Ecto schemas
  - **Operator validation**: Ensures filter values match operator expectations
  - **Binding validation**: Verifies join bindings are available
  - **Window validation**: Validates window function definitions
  """

  use ExUnit.Case, async: true

  alias OmQuery.Validator
  alias OmQuery.ValidationError

  @schema OmQuery.ValidatorTest.TestSchema

  # ============================================
  # validate_field/2
  # ============================================

  describe "validate_field/2" do
    test "valid field returns :ok" do
      assert Validator.validate_field(@schema, :name) == :ok
      assert Validator.validate_field(@schema, :email) == :ok
      assert Validator.validate_field(@schema, :age) == :ok
      assert Validator.validate_field(@schema, :status) == :ok
      assert Validator.validate_field(@schema, :metadata) == :ok
    end

    test "invalid field returns error with suggestion" do
      assert {:error, %ValidationError{suggestion: suggestion}} =
               Validator.validate_field(@schema, :emial)

      assert suggestion =~ "email"
    end

    test "invalid field error includes field name in reason" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_field(@schema, :nonexistent_field)

      assert reason =~ "nonexistent_field"
      assert reason =~ inspect(@schema)
    end

    test "non-schema module returns error with helpful message" do
      # A module without __schema__/1 still gets checked as an atom schema
      # and returns an error indicating it's not an Ecto schema
      assert {:error, %ValidationError{suggestion: suggestion}} =
               Validator.validate_field(Enum, :name)

      assert suggestion =~ "not an Ecto schema"
    end

    test "non-atom schema passes through (second clause)" do
      # When schema is not an atom, validate_field returns :ok for atom fields
      assert Validator.validate_field("not_a_module", :name) == :ok
    end

    test "non-atom field returns error" do
      assert {:error, "Field must be an atom"} = Validator.validate_field(@schema, "name")
      assert {:error, "Field must be an atom"} = Validator.validate_field(@schema, 123)
    end
  end

  # ============================================
  # validate_fields/2
  # ============================================

  describe "validate_fields/2" do
    test "all valid returns :ok" do
      assert Validator.validate_fields(@schema, [:name, :email, :age]) == :ok
    end

    test "first invalid stops and returns error" do
      assert {:error, %ValidationError{} = error} =
               Validator.validate_fields(@schema, [:name, :emial, :nonexistent])

      # Should report the first invalid field (:emial)
      assert error.reason =~ "emial"
    end

    test "empty list returns :ok" do
      assert Validator.validate_fields(@schema, []) == :ok
    end
  end

  # ============================================
  # validate_filter_value/2
  # ============================================

  describe "validate_filter_value/2 - :between" do
    test "with {min, max} tuple is valid" do
      assert Validator.validate_filter_value(:between, {1, 10}) == :ok
      assert Validator.validate_filter_value(:between, {~D[2024-01-01], ~D[2024-12-31]}) == :ok
    end

    test "with list of tuples is valid" do
      assert Validator.validate_filter_value(:between, [{1, 10}, {20, 30}]) == :ok
    end

    test "with invalid value returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:between, "invalid")

      assert reason =~ "between"
      assert reason =~ "tuple"
    end

    test "with list containing non-tuples returns error" do
      assert {:error, %ValidationError{}} =
               Validator.validate_filter_value(:between, [1, 2, 3])
    end
  end

  describe "validate_filter_value/2 - :in" do
    test "with list is valid" do
      assert Validator.validate_filter_value(:in, ["active", "pending"]) == :ok
      assert Validator.validate_filter_value(:in, [1, 2, 3]) == :ok
      assert Validator.validate_filter_value(:in, []) == :ok
    end

    test "with non-list returns error with suggestion" do
      assert {:error, %ValidationError{reason: reason, suggestion: suggestion}} =
               Validator.validate_filter_value(:in, "active")

      assert reason =~ ":in requires a list"
      assert suggestion =~ "filter"
    end
  end

  describe "validate_filter_value/2 - :not_in" do
    test "with list is valid" do
      assert Validator.validate_filter_value(:not_in, ["deleted", "banned"]) == :ok
    end

    test "with non-list returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:not_in, "deleted")

      assert reason =~ ":not_in requires a list"
    end
  end

  describe "validate_filter_value/2 - :like" do
    test "with string is valid" do
      assert Validator.validate_filter_value(:like, "%pattern%") == :ok
      assert Validator.validate_filter_value(:like, "exact") == :ok
    end

    test "with non-string returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:like, 123)

      assert reason =~ ":like requires a string"
    end
  end

  describe "validate_filter_value/2 - :ilike" do
    test "with string is valid" do
      assert Validator.validate_filter_value(:ilike, "%Pattern%") == :ok
    end

    test "with non-string returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:ilike, :not_a_string)

      assert reason =~ ":ilike requires a string"
    end
  end

  describe "validate_filter_value/2 - :is_nil and :not_nil" do
    test ":is_nil accepts any value" do
      assert Validator.validate_filter_value(:is_nil, true) == :ok
      assert Validator.validate_filter_value(:is_nil, false) == :ok
      assert Validator.validate_filter_value(:is_nil, nil) == :ok
      assert Validator.validate_filter_value(:is_nil, "anything") == :ok
    end

    test ":not_nil accepts any value" do
      assert Validator.validate_filter_value(:not_nil, true) == :ok
      assert Validator.validate_filter_value(:not_nil, false) == :ok
      assert Validator.validate_filter_value(:not_nil, 42) == :ok
    end
  end

  describe "validate_filter_value/2 - :jsonb_contains" do
    test "with map is valid" do
      assert Validator.validate_filter_value(:jsonb_contains, %{key: "value"}) == :ok
      assert Validator.validate_filter_value(:jsonb_contains, %{"nested" => %{"a" => 1}}) == :ok
    end

    test "with non-map returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:jsonb_contains, "not_a_map")

      assert reason =~ ":jsonb_contains requires a map"
    end
  end

  describe "validate_filter_value/2 - :jsonb_has_key" do
    test "with string is valid" do
      assert Validator.validate_filter_value(:jsonb_has_key, "key_name") == :ok
    end

    test "with non-string returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_filter_value(:jsonb_has_key, :not_a_string)

      assert reason =~ ":jsonb_has_key requires a string"
    end
  end

  describe "validate_filter_value/2 - unknown operators" do
    test "unknown operator accepts any value (default case)" do
      assert Validator.validate_filter_value(:eq, "anything") == :ok
      assert Validator.validate_filter_value(:gt, 42) == :ok
      assert Validator.validate_filter_value(:custom_op, %{data: true}) == :ok
    end
  end

  # ============================================
  # validate_binding/2
  # ============================================

  describe "validate_binding/2" do
    test "known binding returns :ok" do
      available = [:root, :posts, :comments]

      assert Validator.validate_binding(:root, available) == :ok
      assert Validator.validate_binding(:posts, available) == :ok
      assert Validator.validate_binding(:comments, available) == :ok
    end

    test "unknown binding returns error with available bindings" do
      available = [:root, :posts, :comments]

      assert {:error, %ValidationError{reason: reason, suggestion: suggestion}} =
               Validator.validate_binding(:users, available)

      assert reason =~ "Unknown binding"
      assert reason =~ ":users"
      assert suggestion =~ inspect(available)
    end

    test "error suggests adding a join" do
      assert {:error, %ValidationError{suggestion: suggestion}} =
               Validator.validate_binding(:missing, [:root])

      assert suggestion =~ "join"
    end
  end

  # ============================================
  # validate_window_definition/1
  # ============================================

  describe "validate_window_definition/1" do
    test "valid keyword list returns :ok" do
      assert Validator.validate_window_definition(partition_by: :status) == :ok

      assert Validator.validate_window_definition(
               partition_by: :status,
               order_by: [desc: :created_at]
             ) == :ok

      assert Validator.validate_window_definition(
               partition_by: [:status, :role],
               order_by: [asc: :name],
               frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
             ) == :ok
    end

    test "empty keyword list returns :ok" do
      assert Validator.validate_window_definition([]) == :ok
    end

    test "invalid keys return error" do
      assert {:error, %ValidationError{reason: reason, suggestion: suggestion}} =
               Validator.validate_window_definition(partition_by: :status, bad_key: :value)

      assert reason =~ "Invalid window options"
      assert reason =~ "bad_key"
      assert suggestion =~ "partition_by"
    end

    test "non-keyword-list returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_window_definition("not a keyword list")

      assert reason =~ "keyword list"
    end

    test "non-keyword-list map returns error" do
      assert {:error, %ValidationError{}} =
               Validator.validate_window_definition(%{partition_by: :status})
    end

    test "invalid partition_by returns error" do
      assert {:error, %ValidationError{reason: reason}} =
               Validator.validate_window_definition(partition_by: 123)

      assert reason =~ "partition_by"
    end

    test "atom partition_by is valid" do
      assert Validator.validate_window_definition(partition_by: :status) == :ok
    end

    test "list partition_by is valid" do
      assert Validator.validate_window_definition(partition_by: [:status, :role]) == :ok
    end

    test "order_by as atom is valid" do
      assert Validator.validate_window_definition(order_by: :created_at) == :ok
    end

    test "order_by as keyword list is valid" do
      assert Validator.validate_window_definition(order_by: [desc: :created_at, asc: :id]) == :ok
    end
  end
end
