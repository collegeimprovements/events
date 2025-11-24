defmodule Events.CRUD.Builder do
  @moduledoc """
  Builds Ecto queries from tokens.
  """

  alias Events.CRUD.Token
  import Ecto.Query

  @spec build(Token.t()) :: Ecto.Query.t()
  def build(%Token{operations: operations}) do
    Enum.reduce(operations, base_query(), &apply_operation/2)
  end

  # Get base query - either from schema or empty
  defp base_query() do
    # This will be enhanced when we have schema operations
    %Ecto.Query{}
  end

  # Pattern matching operation application
  defp apply_operation({:schema, schema}, _query) when is_atom(schema) do
    from(_q in schema)
  end

  defp apply_operation({:where, spec}, query) do
    Events.CRUD.Operations.Where.execute(query, spec)
  end

  defp apply_operation({:join, spec}, query) do
    Events.CRUD.Operations.Join.execute(query, spec)
  end

  defp apply_operation({:order, spec}, query) do
    Events.CRUD.Operations.Order.execute(query, spec)
  end

  defp apply_operation({:preload, spec}, query) do
    Events.CRUD.Operations.Preload.execute(query, spec)
  end

  defp apply_operation({:paginate, spec}, query) do
    Events.CRUD.Operations.Paginate.execute(query, spec)
  end

  defp apply_operation({:select, spec}, query) do
    Events.CRUD.Operations.Select.execute(query, spec)
  end

  defp apply_operation({:group, spec}, query) do
    Events.CRUD.Operations.Group.execute(query, spec)
  end

  defp apply_operation({:having, spec}, query) do
    Events.CRUD.Operations.Having.execute(query, spec)
  end

  defp apply_operation({:window, spec}, query) do
    Events.CRUD.Operations.Window.execute(query, spec)
  end

  # Raw operations return special markers
  defp apply_operation({:raw, spec}, query) do
    Events.CRUD.Operations.Raw.execute(query, spec)
  end

  # CRUD operations are handled differently - they don't build queries
  defp apply_operation({operation, _spec}, _query)
       when operation in [:create, :update, :delete, :get, :list] do
    raise "CRUD operations should not be in query building pipeline"
  end

  # Unknown operations
  defp apply_operation({operation, _spec}, query) do
    # Log warning but continue
    IO.warn("Unknown operation: #{operation}")
    query
  end
end
