defmodule Events.CRUD.Operations.Where do
  @moduledoc """
  WHERE clause operations for filtering query results.

  Supports standard SQL operators and PostgreSQL-specific operators like JSON operations.
  """

  use Events.CRUD.Operation, type: :where

  @supported_ops [
    :eq,
    :neq,
    :gt,
    :gte,
    :lt,
    :lte,
    :in,
    :not_in,
    :like,
    :ilike,
    :between,
    :is_nil,
    :not_nil,
    :contains,
    :contained_by,
    :jsonb_contains,
    :jsonb_has_key
  ]

  @impl true
  def validate_spec({field, op, _value, _opts}) do
    OperationUtils.validate_spec({field, op},
      field: &OperationUtils.validate_field/1,
      op: &validate_operator/1
    )
  end

  @impl true
  def execute(query, {field, op, value, _opts}) do
    # Use the existing Repo.Query.where for now
    # TODO: Consider migrating to direct Ecto.Query usage for consistency
    Events.Repo.Query.where(query, {field, op, value, []})
  end

  @impl true
  def optimize({field, op, value, opts}, context) do
    # TODO: Implement filter optimization based on:
    # - Index availability
    # - Selectivity estimates
    # - Query structure analysis
    {field, op, value, opts}
  end

  # Private validation helpers

  defp validate_operator({_field, op}) do
    OperationUtils.validate_enum(op, @supported_ops, "operator")
  end
end
