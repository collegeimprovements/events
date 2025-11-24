defmodule Events.CRUD.Operations.Create do
  use Events.CRUD.Operation, type: :create

  @impl true
  def validate_spec({schema, attrs, opts}) do
    cond do
      not is_atom(schema) -> {:error, "Schema must be an atom"}
      not is_map(attrs) -> {:error, "Attributes must be a map"}
      not is_list(opts) -> {:error, "Options must be a keyword list"}
      true -> :ok
    end
  end

  @impl true
  def execute(_query, {schema, attrs, opts}) do
    # Direct Repo operation, not query building
    case Events.Repo.insert(build_changeset(schema, attrs), opts) do
      {:ok, record} -> Events.CRUD.Result.created(record)
      {:error, changeset} -> Events.CRUD.Result.error(changeset)
    end
  end

  defp build_changeset(schema, attrs) do
    if function_exported?(schema, :changeset, 2) do
      schema.changeset(struct(schema), attrs)
    else
      schema.__struct__() |> Ecto.Changeset.cast(attrs, schema.__schema__(:fields))
    end
  end
end
