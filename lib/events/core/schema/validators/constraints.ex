defmodule Events.Core.Schema.Validators.Constraints do
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
    opts[:unique]
    |> constraint_options([field_name], :unique)
    |> apply_constraint(changeset, field_name, &Ecto.Changeset.unique_constraint/3)
  end

  defp maybe_add_foreign_key_constraint(changeset, field_name, opts) do
    opts[:foreign_key]
    |> constraint_options([field_name], :foreign_key)
    |> apply_constraint(changeset, field_name, &Ecto.Changeset.foreign_key_constraint/3)
  end

  defp maybe_add_check_constraint(changeset, field_name, opts) do
    case opts[:check] do
      nil ->
        changeset

      {:constraint, name} ->
        Ecto.Changeset.check_constraint(changeset, field_name, name: name)

      {:constraint, name, constraint_opts} when is_list(constraint_opts) ->
        opts_with_name = Keyword.put(constraint_opts, :name, name)
        Ecto.Changeset.check_constraint(changeset, field_name, opts_with_name)

      keyword when is_list(keyword) ->
        Ecto.Changeset.check_constraint(changeset, field_name, keyword)

      message ->
        Ecto.Changeset.check_constraint(changeset, field_name,
          name: constraint_name([field_name], :check),
          message: message
        )
    end
  end

  defp apply_constraint(:skip, changeset, _field_name, _fun), do: changeset

  defp apply_constraint(constraint_opts, changeset, field_name, fun) do
    fun.(changeset, field_name, constraint_opts)
  end

  defp constraint_options(nil, _fields, _type), do: :skip
  defp constraint_options(false, _fields, _type), do: :skip
  defp constraint_options(true, _fields, _type), do: []

  defp constraint_options({:constraint, name}, _fields, _type) do
    [name: name]
  end

  defp constraint_options({:constraint, name, constraint_opts}, _fields, _type)
       when is_list(constraint_opts) do
    Keyword.put(constraint_opts, :name, name)
  end

  defp constraint_options(keyword, fields, type) when is_list(keyword) and keyword != [] do
    constraint_fields = Keyword.get(keyword, :fields, fields)

    keyword
    |> Keyword.delete(:fields)
    |> Keyword.put_new(:name, constraint_name(constraint_fields, type))
  end

  defp constraint_options(value, _fields, _type) when is_atom(value) or is_binary(value) do
    [name: value]
  end

  defp constraint_options(fields, _default_fields, type) when is_list(fields) do
    [name: constraint_name(fields, type)]
  end

  defp constraint_options(_other, fields, type), do: [name: constraint_name(fields, type)]

  defp constraint_name(fields, type) do
    fields_str = fields |> Enum.map(&to_string/1) |> Enum.join("_")
    "#{fields_str}_#{type}"
  end
end
