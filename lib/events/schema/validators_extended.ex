defmodule Events.Schema.ValidatorsExtended do
  @moduledoc """
  Extended validators with normalizers, auto_trim, and enhanced validations.

  Provides comprehensive field validation with automatic normalization
  and trimming capabilities.
  """

  import Ecto.Changeset
  alias Events.Schema.Validators

  # ============================================
  # Enhanced Validators with Options
  # ============================================

  @doc """
  Validates a field with comprehensive options.

  ## Options

    * `:required` - Whether the field is required
    * `:min` - Minimum value (numbers) or length (strings)
    * `:max` - Maximum value (numbers) or length (strings)
    * `:gt` - Greater than value
    * `:gte` - Greater than or equal to value
    * `:lt` - Less than value
    * `:lte` - Less than or equal to value
    * `:format` - Regex pattern for validation
    * `:in` - List of allowed values
    * `:not_in` - List of forbidden values
    * `:auto_trim` - Automatically trim whitespace (default: true for strings)
    * `:normalizer` - Function to normalize the value
    * `:unique` - Whether the field must be unique

  ## Examples

      validate_field(changeset, :email,
        required: true,
        format: ~r/@/,
        auto_trim: true,
        normalizer: &String.downcase/1
      )

      validate_field(changeset, :age,
        required: true,
        gte: 18,
        lte: 120
      )

      validate_field(changeset, :status,
        in: ["active", "pending", "archived"],
        required: true
      )
  """
  def validate_field(changeset, field, opts \\ []) do
    changeset
    |> maybe_normalize_field(field, opts)
    |> maybe_trim_field(field, opts)
    |> apply_validations(field, opts)
  end

  # ============================================
  # Normalizers
  # ============================================

  defp maybe_normalize_field(changeset, field, opts) do
    if normalizer = opts[:normalizer] do
      update_change(changeset, field, normalizer)
    else
      apply_default_normalizer(changeset, field, opts)
    end
  end

  defp apply_default_normalizer(changeset, field, opts) do
    case get_field_type(changeset, field) do
      :string ->
        changeset
        |> maybe_auto_trim(field, opts)
        |> maybe_normalize_string(field, opts)

      :email ->
        update_change(changeset, field, &normalize_email/1)

      :phone ->
        update_change(changeset, field, &normalize_phone/1)

      :url ->
        update_change(changeset, field, &normalize_url/1)

      _ ->
        changeset
    end
  end

  defp maybe_auto_trim(changeset, field, opts) do
    if Keyword.get(opts, :auto_trim, true) do
      update_change(changeset, field, &String.trim/1)
    else
      changeset
    end
  end

  defp maybe_normalize_string(changeset, field, opts) do
    cond do
      opts[:lowercase] ->
        update_change(changeset, field, &String.downcase/1)

      opts[:uppercase] ->
        update_change(changeset, field, &String.upcase/1)

      opts[:capitalize] ->
        update_change(changeset, field, &String.capitalize/1)

      true ->
        changeset
    end
  end

  defp maybe_trim_field(changeset, field, opts) do
    if Keyword.get(opts, :trim_whitespace, false) do
      update_change(changeset, field, fn
        value when is_binary(value) -> String.trim(value)
        value -> value
      end)
    else
      changeset
    end
  end

  # ============================================
  # Validation Application
  # ============================================

  defp apply_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_required(field, opts)
    |> maybe_validate_format(field, opts)
    |> maybe_validate_length_or_range(field, opts)
    |> maybe_validate_comparison(field, opts)
    |> maybe_validate_inclusion(field, opts)
    |> maybe_validate_unique(field, opts)
  end

  defp maybe_validate_required(changeset, field, opts) do
    if opts[:required] do
      validate_required(changeset, [field])
    else
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

  defp maybe_validate_length_or_range(changeset, field, opts) do
    type = get_field_type(changeset, field)

    case type do
      t when t in [:string, :text] ->
        apply_string_length_validations(changeset, field, opts)

      t when t in [:integer, :float, :decimal] ->
        apply_number_range_validations(changeset, field, opts)

      :array ->
        apply_array_length_validations(changeset, field, opts)

      _ ->
        changeset
    end
  end

  defp apply_string_length_validations(changeset, field, opts) do
    length_opts = []
    length_opts = if min = opts[:min], do: [{:min, min} | length_opts], else: length_opts
    length_opts = if max = opts[:max], do: [{:max, max} | length_opts], else: length_opts

    if length_opts != [] do
      validate_length(changeset, field, length_opts)
    else
      changeset
    end
  end

  defp apply_number_range_validations(changeset, field, opts) do
    changeset
    |> maybe_validate_number(field, :greater_than, opts[:gt])
    |> maybe_validate_number(field, :greater_than_or_equal_to, opts[:gte])
    |> maybe_validate_number(field, :less_than, opts[:lt])
    |> maybe_validate_number(field, :less_than_or_equal_to, opts[:lte])
    |> maybe_validate_number(field, :greater_than_or_equal_to, opts[:min])
    |> maybe_validate_number(field, :less_than_or_equal_to, opts[:max])
  end

  defp maybe_validate_number(changeset, _field, _key, nil), do: changeset

  defp maybe_validate_number(changeset, field, key, value) do
    validate_number(changeset, field, [{key, value}])
  end

  defp apply_array_length_validations(changeset, field, opts) do
    validate_change(changeset, field, fn _, array ->
      cond do
        min = opts[:min] ->
          if length(array) < min do
            [{field, "should have at least #{min} items"}]
          else
            []
          end

        max = opts[:max] ->
          if length(array) > max do
            [{field, "should have at most #{max} items"}]
          else
            []
          end

        true ->
          []
      end
    end)
  end

  defp maybe_validate_comparison(changeset, field, opts) do
    changeset
    |> maybe_validate_positive(field, opts[:positive])
    |> maybe_validate_non_negative(field, opts[:non_negative])
    |> maybe_validate_negative(field, opts[:negative])
    |> maybe_validate_non_positive(field, opts[:non_positive])
  end

  defp maybe_validate_positive(changeset, _field, nil), do: changeset
  defp maybe_validate_positive(changeset, _field, false), do: changeset

  defp maybe_validate_positive(changeset, field, true) do
    validate_number(changeset, field, greater_than: 0)
  end

  defp maybe_validate_non_negative(changeset, _field, nil), do: changeset
  defp maybe_validate_non_negative(changeset, _field, false), do: changeset

  defp maybe_validate_non_negative(changeset, field, true) do
    validate_number(changeset, field, greater_than_or_equal_to: 0)
  end

  defp maybe_validate_negative(changeset, _field, nil), do: changeset
  defp maybe_validate_negative(changeset, _field, false), do: changeset

  defp maybe_validate_negative(changeset, field, true) do
    validate_number(changeset, field, less_than: 0)
  end

  defp maybe_validate_non_positive(changeset, _field, nil), do: changeset
  defp maybe_validate_non_positive(changeset, _field, false), do: changeset

  defp maybe_validate_non_positive(changeset, field, true) do
    validate_number(changeset, field, less_than_or_equal_to: 0)
  end

  defp maybe_validate_inclusion(changeset, field, opts) do
    cond do
      values = opts[:in] ->
        validate_inclusion(changeset, field, values)

      values = opts[:not_in] ->
        validate_exclusion(changeset, field, values)

      true ->
        changeset
    end
  end

  defp maybe_validate_unique(changeset, field, opts) do
    if opts[:unique] do
      unique_constraint(changeset, field)
    else
      changeset
    end
  end

  # ============================================
  # Type-Specific Validators
  # ============================================

  @doc """
  Validates email with normalization.

  ## Options

    * `:required` - Whether the email is required
    * `:unique` - Whether the email must be unique
    * `:auto_trim` - Automatically trim whitespace (default: true)
    * `:normalize` - Normalize to lowercase (default: true)

  ## Examples

      validate_email(changeset, :email, required: true, unique: true)
  """
  def validate_email(changeset, field, opts \\ []) do
    changeset
    |> update_change(field, fn email ->
      email
      |> String.trim()
      |> String.downcase()
    end)
    |> validate_field(
      field,
      Keyword.merge(
        [
          format: ~r/^[^\s]+@[^\s]+$/,
          auto_trim: true
        ],
        opts
      )
    )
  end

  @doc """
  Validates URL with normalization.
  """
  def validate_url(changeset, field, opts \\ []) do
    changeset
    |> update_change(field, &normalize_url/1)
    |> validate_field(
      field,
      Keyword.merge(
        [
          format: ~r/^https?:\/\//
        ],
        opts
      )
    )
  end

  @doc """
  Validates phone number with normalization.
  """
  def validate_phone(changeset, field, opts \\ []) do
    changeset
    |> update_change(field, &normalize_phone/1)
    |> validate_field(
      field,
      Keyword.merge(
        [
          format: ~r/^\+?[0-9]{10,15}$/
        ],
        opts
      )
    )
  end

  @doc """
  Validates monetary amount.

  ## Options

    * `:min` - Minimum amount (default: 0)
    * `:max` - Maximum amount
    * `:positive` - Must be positive
    * `:non_negative` - Must be non-negative (default: true)
    * `:precision` - Decimal precision
    * `:scale` - Decimal scale

  ## Examples

      validate_money(changeset, :price, min: 0, max: 999999.99)
  """
  def validate_money(changeset, field, opts \\ []) do
    opts = Keyword.put_new(opts, :non_negative, true)

    changeset
    |> validate_field(field, opts)
    |> maybe_validate_precision(field, opts)
  end

  defp maybe_validate_precision(changeset, field, opts) do
    precision = opts[:precision]
    scale = opts[:scale]

    if precision || scale do
      validate_change(changeset, field, fn _, value ->
        case validate_decimal_precision(value, precision, scale) do
          :ok -> []
          {:error, message} -> [{field, message}]
        end
      end)
    else
      changeset
    end
  end

  defp validate_decimal_precision(value, precision, scale) do
    string = Decimal.to_string(value)
    [integer_part, decimal_part] = String.split(string <> ".0", ".")

    cond do
      precision && String.length(integer_part) > precision ->
        {:error, "exceeds precision of #{precision}"}

      scale && String.length(decimal_part) > scale ->
        {:error, "exceeds scale of #{scale}"}

      true ->
        :ok
    end
  end

  @doc """
  Validates percentage (0-100).
  """
  def validate_percentage(changeset, field, opts \\ []) do
    validate_field(
      changeset,
      field,
      Keyword.merge(
        [
          gte: 0,
          lte: 100
        ],
        opts
      )
    )
  end

  @doc """
  Validates slug format.
  """
  def validate_slug(changeset, field, opts \\ []) do
    changeset
    |> update_change(field, &normalize_slug/1)
    |> validate_field(
      field,
      Keyword.merge(
        [
          format: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
          auto_trim: true
        ],
        opts
      )
    )
  end

  @doc """
  Validates UUID format.
  """
  def validate_uuid(changeset, field, opts \\ []) do
    validate_field(
      changeset,
      field,
      Keyword.merge(
        [
          format: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        ],
        opts
      )
    )
  end

  @doc """
  Validates JSON field.
  """
  def validate_json(changeset, field, opts \\ []) do
    changeset
    |> validate_change(field, fn _, value ->
      if is_map(value) do
        validate_json_structure(value, opts)
      else
        [{field, "must be a valid JSON object"}]
      end
    end)
  end

  defp validate_json_structure(value, opts) do
    []
    |> check_required_keys(value, opts[:required_keys])
    |> check_forbidden_keys(value, opts[:forbidden_keys])
    |> check_max_keys(value, opts[:max_keys])
  end

  defp check_required_keys(errors, _value, nil), do: errors

  defp check_required_keys(errors, value, required_keys) do
    missing = required_keys -- Map.keys(value)

    case missing do
      [] -> errors
      _ -> errors ++ [{:json, "missing required keys: #{Enum.join(missing, ", ")}"}]
    end
  end

  defp check_forbidden_keys(errors, _value, nil), do: errors

  defp check_forbidden_keys(errors, value, forbidden_keys) do
    present = forbidden_keys -- (forbidden_keys -- Map.keys(value))

    case present do
      [] -> errors
      _ -> errors ++ [{:json, "contains forbidden keys: #{Enum.join(present, ", ")}"}]
    end
  end

  defp check_max_keys(errors, _value, nil), do: errors

  defp check_max_keys(errors, value, max_keys) do
    case map_size(value) > max_keys do
      false -> errors
      true -> errors ++ [{:json, "exceeds maximum of #{max_keys} keys"}]
    end
  end

  @doc """
  Validates enum field.
  """
  def validate_enum(changeset, field, values, opts \\ []) do
    validate_field(
      changeset,
      field,
      Keyword.merge(
        [
          in: values
        ],
        opts
      )
    )
  end

  @doc """
  Validates array field.
  """
  def validate_array(changeset, field, opts \\ []) do
    changeset
    |> validate_change(field, fn _, value ->
      cond do
        !is_list(value) ->
          [{field, "must be an array"}]

        min = opts[:min_length] ->
          if length(value) < min do
            [{field, "should have at least #{min} items"}]
          else
            []
          end

        max = opts[:max_length] ->
          if length(value) > max do
            [{field, "should have at most #{max} items"}]
          else
            []
          end

        opts[:unique_items] ->
          if length(value) != length(Enum.uniq(value)) do
            [{field, "must have unique items"}]
          else
            []
          end

        true ->
          []
      end
    end)
  end

  @doc """
  Validates boolean with acceptance.
  """
  def validate_boolean(changeset, field, opts \\ []) do
    if opts[:acceptance] do
      validate_acceptance(changeset, field)
    else
      changeset
    end
  end

  # ============================================
  # Conditional Validators
  # ============================================

  @doc """
  Validates field only if condition is met.

  ## Examples

      validate_if(changeset, :phone, :required, fn changeset ->
        get_field(changeset, :email) == nil
      end)
  """
  def validate_if(changeset, field, validation, condition_fn, opts \\ []) do
    if condition_fn.(changeset) do
      apply_conditional_validation(changeset, field, validation, opts)
    else
      changeset
    end
  end

  @doc """
  Validates field unless condition is met.
  """
  def validate_unless(changeset, field, validation, condition_fn, opts \\ []) do
    if !condition_fn.(changeset) do
      apply_conditional_validation(changeset, field, validation, opts)
    else
      changeset
    end
  end

  defp apply_conditional_validation(changeset, field, :required, _opts) do
    validate_required(changeset, [field])
  end

  defp apply_conditional_validation(changeset, field, validation, opts) do
    Validators.apply(changeset, field, validation, opts)
  end

  # ============================================
  # Cross-Field Validators
  # ============================================

  @doc """
  Validates confirmation fields match.

  ## Examples

      validate_confirmation(changeset, :password, :password_confirmation)
  """
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

  @doc """
  Validates field comparison.

  ## Examples

      validate_comparison(changeset, :start_date, :<=, :end_date)
  """
  def validate_comparison(changeset, field1, operator, field2) do
    validate_change(changeset, field1, fn _, value1 ->
      value2 = get_field(changeset, field2)

      if compare_values(value1, operator, value2) do
        []
      else
        [{field1, "must be #{operator} #{field2}"}]
      end
    end)
  end

  defp compare_values(v1, :==, v2), do: v1 == v2
  defp compare_values(v1, :!=, v2), do: v1 != v2
  defp compare_values(v1, :<, v2), do: v1 < v2
  defp compare_values(v1, :<=, v2), do: v1 <= v2
  defp compare_values(v1, :>, v2), do: v1 > v2
  defp compare_values(v1, :>=, v2), do: v1 >= v2

  @doc """
  Validates exclusive fields.

  ## Examples

      validate_exclusive(changeset, [:email, :phone], at_least_one: true)
  """
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

  # ============================================
  # Helper Functions
  # ============================================

  defp get_field_type(changeset, field) do
    # Get the type from the changeset's schema
    changeset.data.__struct__.__schema__(:type, field)
  end

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(value), do: value

  defp normalize_phone(phone) when is_binary(phone) do
    phone
    |> String.replace(~r/[^\d+]/, "")
  end

  defp normalize_phone(value), do: value

  defp normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_url(value), do: value

  defp normalize_slug(slug) when is_binary(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^\w-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp normalize_slug(value), do: value
end
