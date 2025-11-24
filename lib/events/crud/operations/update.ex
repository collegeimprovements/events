defmodule Events.CRUD.Operations.Update do
  use Events.CRUD.Operation, type: :update

  @impl true
  def validate_spec({record, attrs, opts}) do
    cond do
      not is_struct(record) -> {:error, "Record must be a struct"}
      not is_map(attrs) -> {:error, "Attributes must be a map"}
      not is_list(opts) -> {:error, "Options must be a keyword list"}
      true -> :ok
    end
  end

  @impl true
  def execute(_query, {record, attrs, opts}) do
    changeset = build_changeset(record, attrs)

    case Events.Repo.update(changeset, opts) do
      {:ok, updated_record} -> Events.CRUD.Result.updated(updated_record)
      {:error, changeset} -> Events.CRUD.Result.error(changeset)
    end
  end

  defp build_changeset(record, attrs) do
    schema = record.__struct__

    if function_exported?(schema, :changeset, 2) do
      schema.changeset(record, attrs)
    else
      record |> Ecto.Changeset.cast(attrs, schema.__schema__(:fields))
    end
  end
end
