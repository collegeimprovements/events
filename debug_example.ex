defmodule DebugExample do
  @moduledoc """
  Example showing how to use the debug operation to inspect queries.
  """

  import Events.CRUD.DSL

  @doc """
  Example using debug in DSL query blocks
  """
  def debug_dsl_example() do
    IO.puts("\n=== DSL Debug Example ===")

    result =
      query User do
        debug("Starting query")

        where(:status, :eq, "active")
        debug("After status filter")

        order(:created_at, :desc)
        debug("After ordering")

        limit(5)
        debug("Final query")
      end

    case result do
      %Events.CRUD.Result{success: true, data: users} ->
        IO.puts("Found #{length(users)} users")

      _ ->
        IO.puts("Query failed")
    end
  end

  @doc """
  Example using debug with direct API
  """
  def debug_direct_api_example() do
    IO.puts("\n=== Direct API Debug Example ===")

    token =
      Events.CRUD.new_token()
      |> Events.CRUD.debug("Empty token")
      |> Events.CRUD.where(:status, :eq, "active")
      |> Events.CRUD.debug("After where clause")
      |> Events.CRUD.order(:created_at, :desc)
      |> Events.CRUD.debug("After order")
      |> Events.CRUD.limit(5)

    result = Events.CRUD.execute(token)

    case result do
      %Events.CRUD.Result{success: true, data: users} ->
        IO.puts("Found #{length(users)} users")

      _ ->
        IO.puts("Query failed")
    end
  end
end
