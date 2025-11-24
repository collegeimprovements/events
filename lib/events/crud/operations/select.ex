defmodule Events.CRUD.Operations.Select do
  use Events.CRUD.Operation, type: :select
  import Ecto.Query

  @impl true
  def validate_spec({fields, _opts}) do
    cond do
      not (is_list(fields) or is_map(fields)) -> {:error, "Fields must be a list or map"}
      true -> :ok
    end
  end

  @impl true
  def execute(query, {fields, _opts}) when is_list(fields) do
    from(q in query, select: map(q, ^fields))
  end

  @impl true
  def execute(query, {field_map, _opts}) when is_map(field_map) do
    select_expr =
      Enum.reduce(field_map, %{}, fn {key, field}, acc when is_atom(field) ->
        Map.put(acc, key, dynamic([q], field(q, ^field)))
      end)

    from(q in query, select: ^select_expr)
  end
end
