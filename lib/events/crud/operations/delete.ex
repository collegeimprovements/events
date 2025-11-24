defmodule Events.CRUD.Operations.Delete do
  use Events.CRUD.Operation, type: :delete

  @impl true
  def validate_spec({record, opts}) do
    cond do
      not is_struct(record) -> {:error, "Record must be a struct"}
      not is_list(opts) -> {:error, "Options must be a keyword list"}
      true -> :ok
    end
  end

  @impl true
  def execute(_query, {record, opts}) do
    case Events.Repo.delete(record, opts) do
      {:ok, deleted_record} -> Events.CRUD.Result.deleted(deleted_record)
      {:error, changeset} -> Events.CRUD.Result.error(changeset)
    end
  end
end
