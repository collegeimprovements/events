defmodule Events.CRUD.Operations.Having do
  use Events.CRUD.Operation, type: :having
  import Ecto.Query

  @impl true
  def validate_spec({conditions, _opts}) do
    cond do
      not is_list(conditions) -> {:error, "Conditions must be a list"}
      true -> :ok
    end
  end

  @impl true
  def execute(query, {conditions, _opts}) do
    # Apply having conditions similar to where
    Enum.reduce(conditions, query, fn condition, q ->
      from(qq in q, having: ^build_having_condition(condition))
    end)
  end

  # Build having condition from filter spec
  defp build_having_condition({field, op, value, _opts}) do
    case op do
      :eq -> dynamic([q], field(q, ^field) == ^value)
      :gt -> dynamic([q], field(q, ^field) > ^value)
      :gte -> dynamic([q], field(q, ^field) >= ^value)
      :lt -> dynamic([q], field(q, ^field) < ^value)
      :lte -> dynamic([q], field(q, ^field) <= ^value)
      # Add more operators as needed
      # Default to eq
      _ -> dynamic([q], field(q, ^field) == ^value)
    end
  end
end
