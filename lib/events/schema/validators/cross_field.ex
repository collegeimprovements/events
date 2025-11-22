defmodule Events.Schema.Validators.CrossField do
  @moduledoc """
  Cross-field validations for enhanced schema fields.

  Provides validation patterns that span multiple fields:
  - Confirmation (password matching)
  - Conditional requirements (require_if)
  - At least one required (one_of)
  - Field comparisons (one field must be greater than another)
  """

  @doc """
  Apply a list of cross-field validations to a changeset.
  """
  def validate(changeset, validations) when is_list(validations) do
    Enum.reduce(validations, changeset, fn validation, acc ->
      apply_validation(acc, validation)
    end)
  end

  def validate(changeset, _), do: changeset

  # Confirmation validation
  defp apply_validation(changeset, {:confirmation, field, opts}) do
    match_field = opts[:match] || :"#{field}_confirmation"
    Ecto.Changeset.validate_confirmation(changeset, field, confirmation: match_field)
  end

  # Conditional requirement
  defp apply_validation(changeset, {:require_if, field, opts}) do
    case opts[:when] do
      {:field, other_field, equals: value} ->
        if Ecto.Changeset.get_field(changeset, other_field) == value do
          Ecto.Changeset.validate_required(changeset, [field])
        else
          changeset
        end

      {:field, other_field, is_set: true} ->
        if Ecto.Changeset.get_field(changeset, other_field) != nil do
          Ecto.Changeset.validate_required(changeset, [field])
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  # At least one field must be present
  defp apply_validation(changeset, {:one_of, fields}) do
    has_value = Enum.any?(fields, fn field -> Ecto.Changeset.get_field(changeset, field) != nil end)

    if has_value do
      changeset
    else
      Ecto.Changeset.add_error(
        changeset,
        hd(fields),
        "at least one of #{inspect(fields)} must be present"
      )
    end
  end

  # Field comparison
  defp apply_validation(changeset, {:compare, field1, comparison: {op, field2}}) do
    val1 = Ecto.Changeset.get_field(changeset, field1)
    val2 = Ecto.Changeset.get_field(changeset, field2)

    if val1 && val2 do
      valid =
        case op do
          :greater_than -> val1 > val2
          :greater_than_or_equal_to -> val1 >= val2
          :less_than -> val1 < val2
          :less_than_or_equal_to -> val1 <= val2
          :equal_to -> val1 == val2
          :not_equal_to -> val1 != val2
          _ -> true
        end

      if valid do
        changeset
      else
        Ecto.Changeset.add_error(changeset, field1, "must be #{op} #{field2}")
      end
    else
      changeset
    end
  end

  defp apply_validation(changeset, _), do: changeset
end
