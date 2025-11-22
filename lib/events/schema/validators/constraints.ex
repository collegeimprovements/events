defmodule Events.Schema.Validators.Constraints do
  @moduledoc """
  Database constraint validations for enhanced schema fields.

  Adds Ecto constraint validations that catch database-level errors:
  - Unique constraints
  - Foreign key constraints
  - Check constraints
  """

  @doc """
  Apply all database constraint validations to a changeset.
  """
  def validate(changeset, field_name, opts) do
    changeset
    |> maybe_add_unique_constraint(field_name, opts)
    |> maybe_add_foreign_key_constraint(field_name, opts)
    |> maybe_add_check_constraint(field_name, opts)
  end

  defp maybe_add_unique_constraint(changeset, field_name, opts) do
    case opts[:unique] do
      true ->
        Ecto.Changeset.unique_constraint(changeset, field_name)

      fields when is_list(fields) ->
        # Composite unique constraint
        Ecto.Changeset.unique_constraint(changeset, field_name,
          name: constraint_name(fields, :unique)
        )

      _ ->
        changeset
    end
  end

  defp maybe_add_foreign_key_constraint(changeset, field_name, opts) do
    if opts[:foreign_key] do
      Ecto.Changeset.foreign_key_constraint(changeset, field_name)
    else
      changeset
    end
  end

  defp maybe_add_check_constraint(changeset, field_name, opts) do
    if constraint = opts[:check] do
      Ecto.Changeset.check_constraint(changeset, field_name,
        name: constraint_name([field_name], :check),
        message: constraint
      )
    else
      changeset
    end
  end

  defp constraint_name(fields, type) do
    fields_str = fields |> Enum.map(&to_string/1) |> Enum.join("_")
    "#{fields_str}_#{type}"
  end
end
