defmodule Events.Schema.Validators do
  @moduledoc """
  Pure validation functions using pattern matching and guards.

  Each validator is a pure function that takes a changeset and
  returns a modified changeset.
  """

  import Ecto.Changeset
  alias Events.Schema.Utils.Comparison

  # ============================================
  # Main Apply Function
  # ============================================

  @doc """
  Applies a validation to a changeset using pattern matching.

  ## Examples

      apply(changeset, :email, :required, [])
      apply(changeset, :email, :email, [])
      apply(changeset, :age, :min, value: 18)
  """
  def apply(changeset, field, type, opts \\ [])

  # Required validation
  def apply(changeset, field, :required, _opts) do
    validate_required(changeset, [field])
  end

  # String validations
  def apply(changeset, field, :string, opts) do
    apply_string_validations(changeset, field, opts)
  end

  def apply(changeset, field, :email, _opts) do
    validate_format(changeset, field, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  end

  def apply(changeset, field, :url, _opts) do
    validate_format(changeset, field, ~r/^https?:\/\//, message: "must be a valid URL")
  end

  def apply(changeset, field, :uuid, _opts) do
    validate_format(
      changeset,
      field,
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      message: "must be a valid UUID"
    )
  end

  def apply(changeset, field, :slug, _opts) do
    validate_format(changeset, field, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be a valid slug (lowercase letters, numbers, and hyphens)"
    )
  end

  def apply(changeset, field, :phone, _opts) do
    validate_format(
      changeset,
      field,
      ~r/^[\+]?[(]?[0-9]{1,4}[)]?[-\s\.]?[(]?[0-9]{1,4}[)]?[-\s\.]?[0-9]{1,5}[-\s\.]?[0-9]{1,5}$/,
      message: "must be a valid phone number"
    )
  end

  # Number validations
  def apply(changeset, field, :number, opts) do
    apply_number_validations(changeset, field, opts)
  end

  def apply(changeset, field, :min, opts) do
    value = Keyword.fetch!(opts, :value)
    validate_number(changeset, field, greater_than_or_equal_to: value)
  end

  def apply(changeset, field, :max, opts) do
    value = Keyword.fetch!(opts, :value)
    validate_number(changeset, field, less_than_or_equal_to: value)
  end

  def apply(changeset, field, :positive, _opts) do
    validate_number(changeset, field, greater_than: 0)
  end

  def apply(changeset, field, :non_negative, _opts) do
    validate_number(changeset, field, greater_than_or_equal_to: 0)
  end

  # Decimal validations
  def apply(changeset, field, :decimal, opts) do
    apply_decimal_validations(changeset, field, opts)
  end

  # Boolean validations
  def apply(changeset, field, :boolean, opts) do
    apply_boolean_validations(changeset, field, opts)
  end

  def apply(changeset, field, :acceptance, _opts) do
    validate_acceptance(changeset, field)
  end

  # DateTime validations
  def apply(changeset, field, :datetime, opts) do
    apply_datetime_validations(changeset, field, opts)
  end

  def apply(changeset, field, :past, _opts) do
    validate_datetime_relative(changeset, field, :past)
  end

  def apply(changeset, field, :future, _opts) do
    validate_datetime_relative(changeset, field, :future)
  end

  # Array validations
  def apply(changeset, field, :array, opts) do
    apply_array_validations(changeset, field, opts)
  end

  # Map validations
  def apply(changeset, field, :map, opts) do
    apply_map_validations(changeset, field, opts)
  end

  # Inclusion/Exclusion
  def apply(changeset, field, :inclusion, opts) do
    values = Keyword.get(opts, :in, [])
    validate_inclusion(changeset, field, values)
  end

  def apply(changeset, field, :exclusion, opts) do
    values = Keyword.get(opts, :not_in, [])
    validate_exclusion(changeset, field, values)
  end

  def apply(changeset, field, :in, opts) do
    apply(changeset, field, :inclusion, in: opts[:value])
  end

  def apply(changeset, field, :not_in, opts) do
    apply(changeset, field, :exclusion, not_in: opts[:value])
  end

  # Length validations
  def apply(changeset, field, :min_length, opts) do
    value = Keyword.fetch!(opts, :value)
    validate_length(changeset, field, min: value)
  end

  def apply(changeset, field, :max_length, opts) do
    value = Keyword.fetch!(opts, :value)
    validate_length(changeset, field, max: value)
  end

  def apply(changeset, field, :length, opts) do
    value = Keyword.fetch!(opts, :value)
    validate_length(changeset, field, is: value)
  end

  # Format validation
  def apply(changeset, field, :format, opts) do
    pattern = Keyword.fetch!(opts, :value)
    validate_format(changeset, field, pattern)
  end

  # Unique validation
  def apply(changeset, field, :unique, opts) do
    if Keyword.get(opts, :value, true) do
      unique_constraint(changeset, field)
    else
      changeset
    end
  end

  # Cross-field validations
  def apply(changeset, field, :confirmation, _opts) do
    validate_confirmation(changeset, field, required: true)
  end

  def apply(changeset, field, :comparison, opts) do
    operator = Keyword.fetch!(opts, :operator)
    other_field = Keyword.fetch!(opts, :other_field)
    validate_field_comparison(changeset, field, operator, other_field)
  end

  # Global validations
  def apply(changeset, :_global, :exclusive, opts) do
    fields = Keyword.fetch!(opts, :fields)
    at_least_one = Keyword.get(opts, :at_least_one, false)
    validate_exclusive_fields(changeset, fields, at_least_one)
  end

  # Fallback
  def apply(changeset, _field, _type, _opts), do: changeset

  # ============================================
  # Composite Validation Functions
  # ============================================

  defp apply_string_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_length(field, opts)
    |> maybe_validate_format(field, opts)
    |> maybe_validate_inclusion(field, opts)
  end

  defp apply_number_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_number_range(field, opts)
    |> maybe_validate_inclusion(field, opts)
  end

  defp apply_decimal_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_number_range(field, opts)
    |> maybe_validate_precision(field, opts)
  end

  defp apply_boolean_validations(changeset, field, opts) do
    if Keyword.get(opts, :acceptance) do
      validate_acceptance(changeset, field)
    else
      changeset
    end
  end

  defp apply_datetime_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_datetime_relative(field, opts)
    |> maybe_validate_datetime_range(field, opts)
  end

  defp apply_array_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_array_length(field, opts)
    |> maybe_validate_array_items(field, opts)
  end

  defp apply_map_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_map_keys(field, opts)
    |> maybe_validate_map_size(field, opts)
  end

  # ============================================
  # Maybe Validators (Conditional Application)
  # ============================================

  defp maybe_validate_length(changeset, field, opts) do
    cond do
      min = opts[:min_length] ->
        validate_length(changeset, field, min: min)

      max = opts[:max_length] ->
        validate_length(changeset, field, max: max)

      length = opts[:length] ->
        validate_length(changeset, field, is: length)

      true ->
        changeset
    end
  end

  defp maybe_validate_format(changeset, field, opts) do
    if format = opts[:format] do
      validate_format(changeset, field, format)
    else
      changeset
    end
  end

  defp maybe_validate_inclusion(changeset, field, opts) do
    if values = opts[:in] do
      validate_inclusion(changeset, field, values)
    else
      changeset
    end
  end

  defp maybe_validate_number_range(changeset, field, opts) do
    changeset
    |> maybe_apply_if(opts[:min], &validate_number(&1, field, greater_than_or_equal_to: &2))
    |> maybe_apply_if(opts[:max], &validate_number(&1, field, less_than_or_equal_to: &2))
    |> maybe_apply_if(opts[:greater_than], &validate_number(&1, field, greater_than: &2))
    |> maybe_apply_if(opts[:less_than], &validate_number(&1, field, less_than: &2))
    |> maybe_apply_if(opts[:positive], fn cs, _ -> validate_number(cs, field, greater_than: 0) end)
    |> maybe_apply_if(opts[:non_negative], fn cs, _ ->
      validate_number(cs, field, greater_than_or_equal_to: 0)
    end)
  end

  defp maybe_validate_precision(changeset, field, opts) do
    if precision = opts[:precision] do
      # Custom validation for decimal precision
      validate_change(changeset, field, fn _, value ->
        if Decimal.to_string(value) |> String.length() <= precision do
          []
        else
          [{field, "exceeds precision of #{precision}"}]
        end
      end)
    else
      changeset
    end
  end

  defp maybe_validate_datetime_relative(changeset, field, opts) do
    cond do
      opts[:past] -> validate_datetime_relative(changeset, field, :past)
      opts[:future] -> validate_datetime_relative(changeset, field, :future)
      true -> changeset
    end
  end

  defp maybe_validate_datetime_range(changeset, field, opts) do
    changeset
    |> maybe_apply_if(opts[:after], &validate_datetime_after(&1, field, &2))
    |> maybe_apply_if(opts[:before], &validate_datetime_before(&1, field, &2))
  end

  defp maybe_validate_array_length(changeset, field, opts) do
    cond do
      min = opts[:min_length] ->
        validate_change(changeset, field, fn _, value ->
          if length(value) >= min, do: [], else: [{field, "should have at least #{min} items"}]
        end)

      max = opts[:max_length] ->
        validate_change(changeset, field, fn _, value ->
          if length(value) <= max, do: [], else: [{field, "should have at most #{max} items"}]
        end)

      true ->
        changeset
    end
  end

  defp maybe_validate_array_items(changeset, field, opts) do
    if opts[:unique_items] do
      validate_change(changeset, field, fn _, value ->
        if length(value) == length(Enum.uniq(value)) do
          []
        else
          [{field, "must have unique items"}]
        end
      end)
    else
      changeset
    end
  end

  defp maybe_validate_map_keys(changeset, field, opts) do
    changeset
    |> maybe_validate_required_keys(field, opts[:required_keys])
    |> maybe_validate_forbidden_keys(field, opts[:forbidden_keys])
  end

  defp maybe_validate_required_keys(changeset, _field, nil), do: changeset

  defp maybe_validate_required_keys(changeset, field, required_keys) do
    validate_change(changeset, field, fn _, value ->
      missing = required_keys -- Map.keys(value)

      if missing == [] do
        []
      else
        [{field, "missing required keys: #{Enum.join(missing, ", ")}"}]
      end
    end)
  end

  defp maybe_validate_forbidden_keys(changeset, _field, nil), do: changeset

  defp maybe_validate_forbidden_keys(changeset, field, forbidden_keys) do
    validate_change(changeset, field, fn _, value ->
      present = forbidden_keys -- (forbidden_keys -- Map.keys(value))

      if present == [] do
        []
      else
        [{field, "contains forbidden keys: #{Enum.join(present, ", ")}"}]
      end
    end)
  end

  defp maybe_validate_map_size(changeset, field, opts) do
    cond do
      min = opts[:min_keys] ->
        validate_change(changeset, field, fn _, value ->
          size = map_size(value)
          if size >= min, do: [], else: [{field, "should have at least #{min} keys"}]
        end)

      max = opts[:max_keys] ->
        validate_change(changeset, field, fn _, value ->
          size = map_size(value)
          if size <= max, do: [], else: [{field, "should have at most #{max} keys"}]
        end)

      true ->
        changeset
    end
  end

  defp maybe_apply_if(changeset, nil, _fun), do: changeset
  defp maybe_apply_if(changeset, false, _fun), do: changeset
  defp maybe_apply_if(changeset, value, fun), do: fun.(changeset, value)

  # ============================================
  # Custom Validation Helpers
  # ============================================

  defp validate_datetime_relative(changeset, field, :past) do
    validate_change(changeset, field, fn _, value ->
      if DateTime.compare(value, DateTime.utc_now()) == :lt do
        []
      else
        [{field, "must be in the past"}]
      end
    end)
  end

  defp validate_datetime_relative(changeset, field, :future) do
    validate_change(changeset, field, fn _, value ->
      if DateTime.compare(value, DateTime.utc_now()) == :gt do
        []
      else
        [{field, "must be in the future"}]
      end
    end)
  end

  defp validate_datetime_after(changeset, field, reference) do
    validate_change(changeset, field, fn _, value ->
      if DateTime.compare(value, reference) == :gt do
        []
      else
        [{field, "must be after #{reference}"}]
      end
    end)
  end

  defp validate_datetime_before(changeset, field, reference) do
    validate_change(changeset, field, fn _, value ->
      if DateTime.compare(value, reference) == :lt do
        []
      else
        [{field, "must be before #{reference}"}]
      end
    end)
  end

  defp validate_field_comparison(changeset, field1, operator, field2) do
    validate_change(changeset, field1, fn _, value1 ->
      value2 = get_field(changeset, field2)

      if Comparison.compare_values(value1, operator, value2) do
        []
      else
        [{field1, "must be #{operator} #{field2}"}]
      end
    end)
  end

  defp validate_exclusive_fields(changeset, fields, at_least_one) do
    present_fields = Enum.filter(fields, &get_field(changeset, &1))

    cond do
      at_least_one and present_fields == [] ->
        add_error(changeset, :base, "at least one of #{Enum.join(fields, ", ")} must be present")

      length(present_fields) > 1 ->
        add_error(changeset, :base, "only one of #{Enum.join(fields, ", ")} can be present")

      true ->
        changeset
    end
  end
end
