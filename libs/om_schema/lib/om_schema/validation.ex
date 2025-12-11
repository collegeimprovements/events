defmodule OmSchema.Validation do
  @moduledoc """
  Unified validation entry point for Events schema system.

  This module provides a single, consistent API for all validation needs,
  orchestrating:
  - `OmSchema.ValidationPipeline` - Main pipeline orchestration
  - `OmSchema.Validators` - Basic validation functions
  - `OmSchema.ValidatorRegistry` - Type-based validator dispatch
  - `OmSchema.Helpers.Normalizer` - Normalization functions
  - `OmSchema.Helpers.Length` - Length validation helpers

  ## Quick Start

      defmodule MyApp.User do
        use Ecto.Schema
        import Ecto.Changeset
        alias OmSchema.Validation

        schema "users" do
          field :email, :string
          field :age, :integer
          timestamps()
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, [:email, :age])
          |> Validation.validate(:email, :email, required: true, unique: true)
          |> Validation.validate(:age, :number, min: 18, max: 120)
        end
      end

  ## Validation Types

  The `validate/4` function supports all standard types:
  - `:required` - Field must be present
  - `:email` - Valid email format
  - `:url` - Valid URL format
  - `:uuid` - Valid UUID format
  - `:slug` - Valid slug format
  - `:phone` - Valid phone number format
  - `:string` - String validations (length, format)
  - `:number` - Numeric validations (range, comparison)
  - `:decimal` - Decimal validations with precision
  - `:boolean` - Boolean validations
  - `:datetime` - DateTime validations (past, future, range)
  - `:array` - Array validations
  - `:map` - Map validations
  - `:inclusion` / `:in` - Value must be in list
  - `:exclusion` / `:not_in` - Value must not be in list

  ## Cross-Field Validation

      changeset
      |> Validation.validate_comparison(:start_date, :<=, :end_date)
      |> Validation.validate_exclusive([:email, :phone], at_least_one: true)
      |> Validation.validate_confirmation(:password, :password_confirmation)

  ## Architecture

  The validation system is organized into focused, composable modules:

  ```
  Validation (this module - unified API)
      │
      ├── ValidationPipeline ──── Main orchestration
      │       │
      │       ├── Helpers.Normalizer ──── Trim, downcase, slugify, etc.
      │       ├── ValidatorRegistry ───── Type → Validator mapping
      │       └── Validators.Constraints ─ Database constraints
      │
      ├── Validators ────────────── Basic validation dispatch
      │
      ├── Validators.* ──────────── Type-specific validators (behavior-based)
      │   ├── String
      │   ├── Number
      │   ├── DateTime
      │   ├── Array
      │   ├── Map
      │   └── Boolean
      │
      └── Validators.CrossField ─── Multi-field validations
  ```
  """

  import Ecto.Changeset
  alias OmSchema.{Validators, ValidatorsExtended, ValidatorRegistry, ValidationPipeline}
  alias OmSchema.Utils.Comparison

  # ============================================
  # Core Validation API
  # ============================================

  @doc """
  Validates a field with the specified validation type and options.

  This is the primary entry point for all validations. Routes to the appropriate
  validator based on type and options.

  ## Examples

      # Basic validations
      changeset
      |> validate(:email, :email, required: true)
      |> validate(:age, :number, min: 18)
      |> validate(:status, :inclusion, in: ["active", "pending"])

      # String validations
      |> validate(:name, :string, min_length: 2, max_length: 100)

      # With normalization (uses ValidationPipeline)
      |> validate(:email, :string, normalize: true)

  ## Options

  Common options supported by all validation types:
  - `:required` - Field must be present
  - `:normalize` - Apply normalization before validation (uses ValidationPipeline)
  - `:unique` - Add unique constraint

  Type-specific options are documented in the respective validator modules.
  """
  @spec validate(Ecto.Changeset.t(), atom(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate(changeset, field, type, opts \\ []) do
    # If normalize is requested, use the pipeline which handles normalization
    if Keyword.get(opts, :normalize) do
      # Get the schema field type for pipeline
      schema_type = get_field_type(changeset, field) || type
      ValidationPipeline.validate_field(changeset, field, schema_type, opts)
    else
      Validators.apply(changeset, field, type, opts)
    end
  end

  @doc """
  Apply validation for a single field based on its type and options.

  This delegates to the ValidationPipeline which orchestrates all validations.
  Used internally by generated schema code.
  """
  @spec apply_field_validation(Ecto.Changeset.t(), atom(), atom(), keyword()) :: Ecto.Changeset.t()
  def apply_field_validation(changeset, field_name, field_type, opts) do
    ValidationPipeline.validate_field(changeset, field_name, field_type, opts)
  end

  @doc """
  Validates a field using the registered validator for its schema type.

  Looks up the validator from `ValidatorRegistry` based on the field's type.

  ## Examples

      changeset
      |> validate_by_type(:name, min_length: 2)  # Uses String validator
      |> validate_by_type(:age, min: 18)         # Uses Number validator
  """
  @spec validate_by_type(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_by_type(changeset, field, opts \\ []) do
    field_type = get_field_type(changeset, field)

    case ValidatorRegistry.get(field_type) do
      nil -> changeset
      validator_module -> validator_module.validate(changeset, field, opts)
    end
  end

  # ============================================
  # Cross-Field Validations
  # ============================================

  @doc """
  Validates that two fields compare according to the operator.

  ## Operators

  - `:==` - Equal
  - `:!=` - Not equal
  - `:<` - Less than
  - `:<=` - Less than or equal
  - `:>` - Greater than
  - `:>=` - Greater than or equal

  ## Examples

      validate_comparison(changeset, :start_date, :<=, :end_date)
  """
  @spec validate_comparison(Ecto.Changeset.t(), atom(), atom(), atom()) :: Ecto.Changeset.t()
  def validate_comparison(changeset, field1, operator, field2) do
    validate_change(changeset, field1, fn _, value1 ->
      value2 = get_field(changeset, field2)

      if Comparison.compare_values(value1, operator, value2) do
        []
      else
        [{field1, "must be #{operator} #{field2}"}]
      end
    end)
  end

  @doc """
  Validates that fields are mutually exclusive.

  ## Options

  - `:at_least_one` - Require at least one field to be present (default: false)

  ## Examples

      validate_exclusive(changeset, [:email, :phone], at_least_one: true)
  """
  @spec validate_exclusive(Ecto.Changeset.t(), [atom()], keyword()) :: Ecto.Changeset.t()
  def validate_exclusive(changeset, fields, opts \\ []) do
    at_least_one = Keyword.get(opts, :at_least_one, false)
    present_fields = Enum.filter(fields, &get_field(changeset, &1))

    cond do
      at_least_one && present_fields == [] ->
        add_error(changeset, :base, "at least one of #{Enum.join(fields, ", ")} must be present")

      length(present_fields) > 1 ->
        add_error(changeset, :base, "only one of #{Enum.join(fields, ", ")} can be present")

      true ->
        changeset
    end
  end

  @doc """
  Validates that a confirmation field matches the original.

  ## Examples

      validate_confirmation(changeset, :password, :password_confirmation)
  """
  @spec validate_confirmation(Ecto.Changeset.t(), atom(), atom()) :: Ecto.Changeset.t()
  def validate_confirmation(changeset, field, confirmation_field) do
    validate_change(changeset, field, fn _, value ->
      confirmation = get_field(changeset, confirmation_field)

      if value == confirmation do
        []
      else
        [{confirmation_field, "does not match #{field}"}]
      end
    end)
  end

  # ============================================
  # Type-Specific Validators
  # ============================================

  @doc "Validates an email field with normalization."
  defdelegate validate_email(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a URL field with normalization."
  defdelegate validate_url(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a phone number field with normalization."
  defdelegate validate_phone(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a monetary amount."
  defdelegate validate_money(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a slug field with normalization."
  defdelegate validate_slug(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a UUID field."
  defdelegate validate_uuid(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates a percentage value (0-100)."
  defdelegate validate_percentage(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates an enum field against allowed values."
  defdelegate validate_enum(changeset, field, values, opts \\ []), to: ValidatorsExtended

  @doc "Validates a JSON/map field."
  defdelegate validate_json(changeset, field, opts \\ []), to: ValidatorsExtended

  @doc "Validates an array field."
  defdelegate validate_array(changeset, field, opts \\ []), to: ValidatorsExtended

  # ============================================
  # Conditional Validation
  # ============================================

  @doc "Validates a field only if the condition is met."
  defdelegate validate_if(changeset, field, validation, condition_fn, opts \\ []),
    to: ValidatorsExtended

  @doc "Validates a field unless the condition is met."
  defdelegate validate_unless(changeset, field, validation, condition_fn, opts \\ []),
    to: ValidatorsExtended

  # ============================================
  # Helpers
  # ============================================

  defp get_field_type(changeset, field) do
    schema = changeset.data.__struct__
    schema.__schema__(:type, field)
  end
end
