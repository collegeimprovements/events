defmodule Events.Schema.Improved.ValidationPipeline do
  @moduledoc """
  Improved validation pipeline with better pattern matching and functional composition.

  This module demonstrates a cleaner approach to orchestrating validations.
  """

  import Ecto.Changeset

  alias Events.Schema.Helpers.{Conditional, Normalizer}
  alias Events.Schema.Validators

  # Type mapping for validators
  @type_validators %{
    string: Validators.String,
    citext: Validators.String,
    integer: Validators.Number,
    float: Validators.Number,
    decimal: Validators.Number,
    boolean: Validators.Boolean,
    date: Validators.DateTime,
    time: Validators.DateTime,
    naive_datetime: Validators.DateTime,
    naive_datetime_usec: Validators.DateTime,
    utc_datetime: Validators.DateTime,
    utc_datetime_usec: Validators.DateTime,
    map: Validators.Map
  }

  @string_types [:string, :citext]

  @doc """
  Main entry point for field validation with improved flow.
  """
  def validate_field(changeset, field_name, field_type, opts) do
    if telemetry_enabled?() do
      with_telemetry(changeset, field_name, field_type, opts)
    else
      apply_validations(changeset, field_name, field_type, opts)
    end
  end

  # Check if telemetry is enabled
  defp telemetry_enabled? do
    Application.get_env(:events, :validation_telemetry, false)
  end

  # Apply validations with telemetry
  defp with_telemetry(changeset, field_name, field_type, opts) do
    Events.Schema.Telemetry.with_telemetry(changeset, field_name, field_type, opts, fn ->
      apply_validations(changeset, field_name, field_type, opts)
    end)
  end

  # Main validation pipeline
  defp apply_validations(changeset, field_name, field_type, opts) do
    if Conditional.should_validate?(changeset, opts) do
      changeset
      |> validate_by_type(field_name, field_type, opts)
      |> normalize_field(field_name, field_type, opts)
      |> apply_custom(field_name, opts)
      |> apply_constraints(field_name, opts)
    else
      normalize_field(changeset, field_name, field_type, opts)
    end
  end

  # Type-based validation using pattern matching
  defp validate_by_type(changeset, field_name, field_type, opts) do
    case get_validator(field_type) do
      nil -> changeset
      validator -> validator.validate(changeset, field_name, opts)
    end
  end

  # Get validator module for type
  defp get_validator({:array, _}), do: Validators.Array
  defp get_validator({:map, _}), do: Validators.Map
  defp get_validator(type), do: Map.get(@type_validators, type)

  # Field normalization with better pattern matching
  defp normalize_field(changeset, field_name, field_type, opts) when field_type in @string_types do
    changeset
    |> get_change(field_name)
    |> normalize_value(opts)
    |> update_field(changeset, field_name)
  end

  defp normalize_field(changeset, _, _, _), do: changeset

  # Normalize value
  defp normalize_value(nil, _), do: nil
  defp normalize_value(value, opts) when is_binary(value), do: Normalizer.normalize(value, opts)
  defp normalize_value(value, _), do: value

  # Update field with normalized value
  defp update_field(nil, changeset, _), do: changeset
  defp update_field(value, changeset, field_name), do: put_change(changeset, field_name, value)

  # Apply custom validation with pattern matching
  defp apply_custom(changeset, field_name, opts) do
    case opts[:validate] do
      nil ->
        changeset

      validators when is_list(validators) ->
        Validators.CrossField.validate(changeset, validators)

      validator when is_function(validator, 1) ->
        validate_with_function(changeset, field_name, validator)

      {module, function} ->
        validate_with_mfa(changeset, field_name, module, function)

      {module, function, args} ->
        validate_with_mfa(changeset, field_name, module, function, args)
    end
  end

  # Validate with function
  defp validate_with_function(changeset, field_name, validator) do
    validate_change(changeset, field_name, fn _, value ->
      handle_validation_result(validator.(value), field_name)
    end)
  end

  # Validate with MFA
  defp validate_with_mfa(changeset, field_name, module, function, args \\ []) do
    validate_change(changeset, field_name, fn _, value ->
      result = apply(module, function, [value | args])
      handle_validation_result(result, field_name)
    end)
  end

  # Handle validation results with pattern matching
  defp handle_validation_result(:ok, _), do: []
  defp handle_validation_result({:ok, _}, _), do: []
  defp handle_validation_result({:error, message}, field_name), do: [{field_name, message}]
  defp handle_validation_result(errors, _) when is_list(errors), do: errors
  defp handle_validation_result(true, _), do: []
  defp handle_validation_result(false, field_name), do: [{field_name, "is invalid"}]
  defp handle_validation_result(_, _), do: []

  # Apply database constraints
  defp apply_constraints(changeset, field_name, opts) do
    Validators.Constraints.validate(changeset, field_name, opts)
  end
end
