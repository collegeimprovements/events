defmodule OmSchema.FieldTest do
  @moduledoc """
  Tests for OmSchema.Field - Enhanced field macro option splitting.

  Field handles the separation of validation options from Ecto field options,
  enabling rich validation declarations in schema definitions.

  ## Use Cases

  - **Inline validation**: `field :email, :string, required: true, format: :email`
  - **Behavioral options**: `field :password, :string, sensitive: true, immutable: true`
  - **Type-specific constraints**: `field :age, :integer, positive: true, max: 150`
  - **Documentation**: `field :status, :string, doc: "User status", example: "active"`

  ## Pattern: Declarative Field Options

      field :email, :string,
        required: true,
        format: :email,
        max_length: 255,
        normalize: [:trim, :downcase],
        unique: true

  Options are split: validation goes to changeset, Ecto options go to schema.
  """

  use ExUnit.Case, async: true

  alias OmSchema.Field

  # ============================================
  # __split_options__/3 - Basic Splitting
  # ============================================

  describe "__split_options__/3 basic" do
    test "splits validation options from ecto options" do
      opts = [required: true, default: "test", null: false]
      {validation, ecto} = Field.__split_options__(opts, :string)

      assert validation[:required] == true
      assert validation[:null] == false
      assert ecto[:default] == "test"
    end

    test "separates cast option" do
      opts = [cast: false, default: nil]
      {validation, ecto} = Field.__split_options__(opts, :string)

      assert validation[:cast] == false
      assert ecto[:default] == nil
    end

    test "handles empty options" do
      {validation, ecto} = Field.__split_options__([], :string)

      assert validation == []
      assert ecto == []
    end
  end

  # ============================================
  # __split_options__/3 - Validation Options
  # ============================================

  describe "__split_options__/3 validation options" do
    test "extracts string validation options" do
      opts = [
        min_length: 2,
        max_length: 100,
        format: ~r/^test/,
        trim: true,
        normalize: :downcase
      ]

      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:min_length] == 2
      assert validation[:max_length] == 100
      # Regex comparison needs to use Regex.source/1 since they're different structs
      assert Regex.source(validation[:format]) == "^test"
      assert validation[:trim] == true
      assert validation[:normalize] == :downcase
    end

    test "extracts number validation options" do
      opts = [
        min: 0,
        max: 100,
        positive: true,
        non_negative: true
      ]

      {validation, _ecto} = Field.__split_options__(opts, :integer)

      assert validation[:min] == 0
      assert validation[:max] == 100
      assert validation[:positive] == true
      assert validation[:non_negative] == true
    end

    test "extracts comparison operators" do
      opts = [
        greater_than: 0,
        greater_than_or_equal_to: 1,
        less_than: 100,
        less_than_or_equal_to: 99,
        equal_to: 50
      ]

      {validation, _ecto} = Field.__split_options__(opts, :integer)

      assert validation[:greater_than] == 0
      assert validation[:greater_than_or_equal_to] == 1
      assert validation[:less_than] == 100
      assert validation[:less_than_or_equal_to] == 99
      assert validation[:equal_to] == 50
    end

    test "extracts shorthand comparison operators" do
      opts = [gt: 0, gte: 1, lt: 100, lte: 99, eq: 50]
      {validation, _ecto} = Field.__split_options__(opts, :integer)

      assert validation[:gt] == 0
      assert validation[:gte] == 1
      assert validation[:lt] == 100
      assert validation[:lte] == 99
      assert validation[:eq] == 50
    end

    test "extracts array validation options" do
      opts = [unique_items: true, item_format: ~r/^[a-z]+$/]
      {validation, _ecto} = Field.__split_options__(opts, {:array, :string})

      assert validation[:unique_items] == true
      assert Regex.source(validation[:item_format]) == "^[a-z]+$"
    end

    test "extracts map validation options" do
      opts = [
        required_keys: [:name, :email],
        optional_keys: [:phone],
        forbidden_keys: [:password],
        min_keys: 1,
        max_keys: 10
      ]

      {validation, _ecto} = Field.__split_options__(opts, :map)

      assert validation[:required_keys] == [:name, :email]
      assert validation[:optional_keys] == [:phone]
      assert validation[:forbidden_keys] == [:password]
      assert validation[:min_keys] == 1
      assert validation[:max_keys] == 10
    end

    test "extracts datetime validation options" do
      opts = [after: ~U[2020-01-01 00:00:00Z], before: ~U[2025-01-01 00:00:00Z], past: true]
      {validation, _ecto} = Field.__split_options__(opts, :utc_datetime)

      assert validation[:after] == ~U[2020-01-01 00:00:00Z]
      assert validation[:before] == ~U[2025-01-01 00:00:00Z]
      assert validation[:past] == true
    end

    test "extracts inclusion/exclusion options" do
      opts = [in: [:a, :b, :c], not_in: [:x, :y, :z]]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:in] == [:a, :b, :c]
      assert validation[:not_in] == [:x, :y, :z]
    end
  end

  # ============================================
  # __split_options__/3 - Behavioral Options
  # ============================================

  describe "__split_options__/3 behavioral options" do
    test "extracts immutable option" do
      opts = [immutable: true]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:immutable] == true
    end

    test "extracts sensitive option and adds redact" do
      opts = [sensitive: true]
      {validation, ecto} = Field.__split_options__(opts, :string)

      assert validation[:sensitive] == true
      assert ecto[:redact] == true
    end

    test "sensitive does not override existing redact" do
      opts = [sensitive: true, redact: false]
      {_validation, ecto} = Field.__split_options__(opts, :string)

      assert ecto[:redact] == false
    end

    test "extracts required_when option" do
      opts = [required_when: [status: :active]]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:required_when] == [status: :active]
    end
  end

  # ============================================
  # __split_options__/3 - Documentation Options
  # ============================================

  describe "__split_options__/3 documentation options" do
    test "extracts doc option" do
      opts = [doc: "User's email address"]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:doc] == "User's email address"
    end

    test "extracts example option" do
      opts = [example: "user@example.com"]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:example] == "user@example.com"
    end
  end

  # ============================================
  # __split_options__/3 - Constraint Options
  # ============================================

  describe "__split_options__/3 constraint options" do
    test "extracts unique constraint option" do
      opts = [unique: true]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:unique] == true
    end

    test "extracts foreign_key constraint option" do
      opts = [foreign_key: :account_id]
      {validation, _ecto} = Field.__split_options__(opts, :binary_id)

      assert validation[:foreign_key] == :account_id
    end

    test "extracts check constraint option" do
      opts = [check: "age > 0"]
      {validation, _ecto} = Field.__split_options__(opts, :integer)

      assert validation[:check] == "age > 0"
    end
  end

  # ============================================
  # __split_options__/3 - Conditional Validation
  # ============================================

  describe "__split_options__/3 conditional validation" do
    test "extracts validate_if option" do
      opts = [validate_if: fn cs -> cs.valid? end]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert is_function(validation[:validate_if])
    end

    test "extracts validate_unless option" do
      opts = [validate_unless: fn cs -> cs.valid? end]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert is_function(validation[:validate_unless])
    end
  end

  # ============================================
  # __split_options__/3 - Messages
  # ============================================

  describe "__split_options__/3 message options" do
    test "extracts message option" do
      opts = [message: "must be valid"]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:message] == "must be valid"
    end

    test "extracts messages map option" do
      opts = [messages: [required: "is needed", format: "is invalid"]]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:messages] == [required: "is needed", format: "is invalid"]
    end
  end

  # ============================================
  # __split_options__/3 - Boolean Validation
  # ============================================

  describe "__split_options__/3 boolean options" do
    test "extracts acceptance option" do
      opts = [acceptance: true]
      {validation, _ecto} = Field.__split_options__(opts, :boolean)

      assert validation[:acceptance] == true
    end
  end

  # ============================================
  # __split_options__/3 - Mappers
  # ============================================

  describe "__split_options__/3 mappers" do
    test "extracts mappers option" do
      opts = [mappers: [:trim, :downcase]]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:mappers] == [:trim, :downcase]
    end
  end

  # ============================================
  # __split_options__/3 - Mixed Options
  # ============================================

  describe "__split_options__/3 mixed options" do
    test "correctly splits mixed validation and ecto options" do
      opts = [
        # Validation
        required: true,
        min_length: 5,
        max_length: 100,
        format: :email,
        # Ecto
        default: "default@example.com",
        source: :email_address,
        load_in_query: true
      ]

      {validation, ecto} = Field.__split_options__(opts, :string)

      # Validation options
      assert validation[:required] == true
      assert validation[:min_length] == 5
      assert validation[:max_length] == 100
      assert validation[:format] == :email

      # Ecto options
      assert ecto[:default] == "default@example.com"
      assert ecto[:source] == :email_address
      assert ecto[:load_in_query] == true
    end

    test "handles all field validation options together" do
      opts = [
        # Common
        cast: true,
        required: true,
        null: false,
        message: "invalid",
        # Behavioral
        immutable: false,
        sensitive: false,
        # Documentation
        doc: "test field",
        example: "example value",
        # String
        min_length: 1,
        max_length: 255,
        trim: true,
        # Ecto
        default: nil
      ]

      {validation, ecto} = Field.__split_options__(opts, :string)

      # All validation options extracted
      assert validation[:cast] == true
      assert validation[:required] == true
      assert validation[:null] == false
      assert validation[:immutable] == false
      assert validation[:sensitive] == false
      assert validation[:doc] == "test field"
      assert validation[:example] == "example value"
      assert validation[:min_length] == 1
      assert validation[:max_length] == 255
      assert validation[:trim] == true

      # Only ecto options remain
      assert ecto[:default] == nil
      assert Keyword.keys(ecto) == [:default]
    end
  end

  # ============================================
  # __split_options__/3 - Ecto.Enum Handling
  # ============================================

  describe "__split_options__/3 with Ecto.Enum" do
    test "handles Ecto.Enum type" do
      opts = [values: [:active, :inactive], default: :active, required: true]
      {validation, ecto} = Field.__split_options__(opts, Ecto.Enum)

      assert validation[:required] == true
      # values is an Ecto option for Ecto.Enum
      assert ecto[:values] == [:active, :inactive]
      assert ecto[:default] == :active
    end
  end

  # ============================================
  # __split_options__/3 - Field Name Parameter
  # ============================================

  describe "__split_options__/3 field name" do
    test "accepts field name for warnings" do
      opts = [required: true]
      {validation, _ecto} = Field.__split_options__(opts, :string, :email)

      assert validation[:required] == true
    end

    test "defaults to :unknown field name" do
      opts = [required: true]
      {validation, _ecto} = Field.__split_options__(opts, :string)

      assert validation[:required] == true
    end
  end
end
