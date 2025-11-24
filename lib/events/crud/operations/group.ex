defmodule Events.CRUD.Operations.Group do
  use Events.CRUD.Operation, type: :group
  import Ecto.Query

  @impl true
  def validate_spec({fields, _opts}) do
    cond do
      not is_list(fields) -> {:error, "Fields must be a list"}
      true -> :ok
    end
  end

  @impl true
  def execute(query, {fields, _opts}) do
    from(q in query, group_by: ^fields)
  end
end
