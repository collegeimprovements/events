defmodule Events.CRUD.Operations.Get do
  use Events.CRUD.Operation, type: :get
  import Ecto.Query

  @impl true
  def validate_spec({schema, id, opts}) do
    cond do
      not is_atom(schema) -> {:error, "Schema must be an atom"}
      not (is_integer(id) or is_binary(id)) -> {:error, "ID must be integer or binary"}
      not is_list(opts) -> {:error, "Options must be a keyword list"}
      true -> :ok
    end
  end

  @impl true
  def execute(query, {_schema, id, opts}) do
    # Build query and execute
    final_query = from(q in query, where: q.id == ^id, limit: 1)

    case Events.Repo.one(final_query) do
      nil ->
        Events.CRUD.Result.not_found()

      record ->
        record = apply_preloads(record, opts[:preload] || [])
        Events.CRUD.Result.found(record)
    end
  end

  # Simple preload application for get operations
  defp apply_preloads(record, []), do: record

  defp apply_preloads(record, preloads) do
    Events.Repo.preload(record, preloads)
  end
end
