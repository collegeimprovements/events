defmodule Events.Schema.ValidationPipeline do
  @moduledoc """
  Main validation pipeline for enhanced schema fields.

  Orchestrates all field-level validations through a clean, composable pipeline.
  Delegates to specialized validator modules based on field type.
  """

  import Ecto.Changeset

  alias Events.Schema.Helpers.{Conditional, Normalizer}

  alias Events.Schema.Validators.{
    Array,
    Boolean,
    Constraints,
    DateTime,
    Map,
    Number,
    String
  }

  @doc """
  Apply all validations for a single field based on its type and options.

  This is the main entry point for field validation. It:
  1. Checks conditional validation (validate_if/validate_unless)
  2. Applies type-specific validations
  3. Applies normalization
  4. Applies custom validations
  5. Applies database constraints

  With telemetry enabled, emits timing and validity events.
  """
  def validate_field(changeset, field_name, field_type, opts) do
    # Use telemetry if enabled
    if Application.get_env(:events, :validation_telemetry, false) do
      Events.Schema.Telemetry.with_telemetry(changeset, field_name, field_type, opts, fn ->
        do_validate_field(changeset, field_name, field_type, opts)
      end)
    else
      do_validate_field(changeset, field_name, field_type, opts)
    end
  end

  defp do_validate_field(changeset, field_name, field_type, opts) do
    # Always normalize first, before any validations
    changeset = apply_normalization(changeset, field_name, field_type, opts)

    # Check conditional validation - if condition is false, skip validations
    if Conditional.should_validate?(changeset, opts) do
      changeset
      |> apply_type_validations(field_name, field_type, opts)
      |> apply_custom_validation(field_name, opts)
      |> Constraints.validate(field_name, opts)
    else
      changeset
    end
  end

  # Type-specific validations

  defp apply_type_validations(changeset, field_name, field_type, opts)
       when field_type in [:string, :citext] do
    String.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, field_name, field_type, opts)
       when field_type in [:integer, :float, :decimal] do
    Number.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, field_name, :boolean, opts) do
    Boolean.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, field_name, {:array, _inner_type}, opts) do
    Array.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, field_name, field_type, opts)
       when field_type in [
              :date,
              :time,
              :naive_datetime,
              :naive_datetime_usec,
              :utc_datetime,
              :utc_datetime_usec
            ] do
    DateTime.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, field_name, field_type, opts)
       when field_type in [:map, {:map, :any}] do
    Map.validate(changeset, field_name, opts)
  end

  defp apply_type_validations(changeset, _field_name, _field_type, _opts), do: changeset

  # Normalization

  defp apply_normalization(changeset, field_name, field_type, opts)
       when field_type in [:string, :citext] do
    case get_change(changeset, field_name) do
      nil ->
        changeset

      value when is_binary(value) ->
        normalized_value = Normalizer.normalize(value, opts)
        put_change(changeset, field_name, normalized_value)

      _ ->
        changeset
    end
  end

  defp apply_normalization(changeset, _field_name, _field_type, _opts), do: changeset

  # Custom validation

  defp apply_custom_validation(changeset, field_name, opts) do
    case opts[:validate] do
      nil ->
        changeset

      # Cross-field validations list
      validations when is_list(validations) ->
        Events.Schema.Validators.CrossField.validate(changeset, validations)

      validator when is_function(validator, 1) ->
        validate_change(changeset, field_name, fn _, value ->
          case validator.(value) do
            :ok -> []
            {:error, message} -> [{field_name, message}]
            errors when is_list(errors) -> errors
          end
        end)

      {module, function} ->
        validate_change(changeset, field_name, fn _, value ->
          case apply(module, function, [value]) do
            :ok -> []
            {:error, message} -> [{field_name, message}]
            errors when is_list(errors) -> errors
          end
        end)
    end
  end
end
