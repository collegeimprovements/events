defmodule Events.CRUD.Operations.Preload do
  use Events.CRUD.Operation, type: :preload

  @impl true
  def validate_spec({assoc, nested_ops}) do
    cond do
      not is_atom(assoc) -> {:error, "Association must be an atom"}
      not is_list(nested_ops) -> {:error, "Nested operations must be a list"}
      true -> validate_nested_operations(nested_ops)
    end
  end

  @impl true
  def execute(query, {_assoc, _nested_ops}) do
    # Simplified: return query unchanged for now
    # Full preload implementation with nested conditions is complex
    # and would require sophisticated query building
    query
  end

  # Validate nested operations recursively
  defp validate_nested_operations([]), do: :ok

  defp validate_nested_operations([{op_type, spec} | rest]) do
    case validate_nested_operation(op_type, spec) do
      :ok -> validate_nested_operations(rest)
      error -> error
    end
  end

  defp validate_nested_operation(:where, {field, op, _value, _opts}) do
    Events.CRUD.Operations.Where.validate_spec({field, op, nil, []})
  end

  defp validate_nested_operation(:order, {field, dir, _opts}) do
    Events.CRUD.Operations.Order.validate_spec({field, dir, []})
  end

  defp validate_nested_operation(:limit, limit) when is_integer(limit) and limit > 0 do
    :ok
  end

  defp validate_nested_operation(:offset, offset) when is_integer(offset) and offset >= 0 do
    :ok
  end

  defp validate_nested_operation(:preload, {assoc, nested_ops}) do
    validate_spec({assoc, nested_ops})
  end

  defp validate_nested_operation(op_type, _spec) do
    {:error, "Unsupported nested operation: #{op_type}"}
  end
end
