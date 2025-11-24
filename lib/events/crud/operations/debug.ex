defmodule Events.CRUD.Operations.Debug do
  @moduledoc """
  Debug operation that prints the current Ecto query and generated SQL.

  This operation can be inserted anywhere in the pipeline to inspect
  the current state of the query before execution.
  """

  use Events.CRUD.Operation, type: :debug

  @impl true
  def validate_spec(spec) do
    # Accept optional label for identifying debug points
    case spec do
      nil -> :ok
      label when is_binary(label) -> :ok
      _ -> {:error, "Debug spec must be a string label or nil"}
    end
  end

  @impl true
  def execute(query, spec) do
    label = spec || "Debug"

    IO.puts("\n=== #{label} ===")
    IO.puts("Ecto Query: #{inspect(query, pretty: true)}")

    # Generate and print SQL
    case Events.Repo.to_sql(:all, query) do
      {sql, params} ->
        IO.puts("Raw SQL: #{sql}")
        IO.puts("Parameters: #{inspect(params)}")

      {:error, error} ->
        IO.puts("SQL Generation Error: #{inspect(error)}")
    end

    IO.puts("=== End #{label} ===\n")

    # Return query unchanged
    query
  end

  @impl true
  def optimize(spec, _context) do
    # Debug operations should never be optimized away
    spec
  end
end
