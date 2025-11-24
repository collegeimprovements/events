defmodule Events.CRUD.Operations.Order do
  @moduledoc """
  ORDER BY operations for sorting query results.

  Supports ascending and descending sort orders.
  """

  use Events.CRUD.Operation, type: :order

  @directions [:asc, :desc]

  @impl true
  def validate_spec({field, direction, _opts}) do
    OperationUtils.validate_spec({field, direction},
      field: &OperationUtils.validate_field/1,
      direction: &validate_direction/1
    )
  end

  @impl true
  def execute(query, {field, direction, _opts}) do
    from(q in query, order_by: [{^direction, field(q, ^field)}])
  end

  @impl true
  def optimize({field, direction, opts}, context) do
    # TODO: Consider index availability for ordering optimization
    {field, direction, opts}
  end

  # Private validation helpers

  defp validate_direction({_field, direction}) do
    OperationUtils.validate_enum(direction, @directions, "direction")
  end
end
