defmodule Events.Schema.Validation do
  @moduledoc """
  Validation application logic for enhanced schema fields.

  This module serves as the main entry point for field validation, delegating
  to the ValidationPipeline for the actual validation logic.

  ## Architecture

  The validation system is organized into focused, composable modules:

  - `Events.Schema.ValidationPipeline` - Main orchestration
  - `Events.Schema.Validators.*` - Type-specific validators
  - `Events.Schema.Helpers.*` - Shared utilities
  - `Events.Schema.Validators.CrossField` - Cross-field validations
  - `Events.Schema.Validators.Constraints` - Database constraints

  ## Usage

  This module is typically used automatically by the `__apply_field_validations__/1`
  function generated in your schema modules:

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, __cast_fields__())
        |> validate_required(__required_fields__())
        |> __apply_field_validations__()
      end

  For cross-field validations, use the CrossField validator directly:

      def changeset(schema, attrs) do
        schema
        |> cast(attrs, __cast_fields__())
        |> validate_required(__required_fields__())
        |> __apply_field_validations__()
        |> apply_cross_validations()
      end

      defp apply_cross_validations(changeset) do
        Events.Schema.Validators.CrossField.validate(changeset, [
          {:confirmation, :password, match: :password_confirmation},
          {:one_of, [:email, :phone]},
          {:compare, :max_price, comparison: {:greater_than, :min_price}}
        ])
      end
  """

  alias Events.Schema.ValidationPipeline

  @doc """
  Apply validation for a single field based on its type and options.

  This delegates to the ValidationPipeline which orchestrates all validations.
  """
  def apply_field_validation(changeset, field_name, field_type, opts) do
    ValidationPipeline.validate_field(changeset, field_name, field_type, opts)
  end
end
