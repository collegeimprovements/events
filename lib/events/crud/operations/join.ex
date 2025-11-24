defmodule Events.CRUD.Operations.Join do
  @moduledoc """
  JOIN operations for combining data from multiple tables.

  Supports standard SQL join types: inner, left, right, full, and cross joins.
  """

  use Events.CRUD.Operation, type: :join

  @join_types [:inner, :left, :right, :full, :cross]

  @impl true
  def validate_spec(spec) do
    case spec do
      # Association join: {assoc, type, opts}
      {assoc, type, opts} when is_atom(assoc) and is_atom(type) and is_list(opts) ->
        OperationUtils.validate_spec({assoc, type},
          assoc: &OperationUtils.validate_field/1,
          type: &validate_join_type/1
        )

      # Custom join: {schema, binding, opts} where opts contains :on
      {schema, binding, opts} when is_atom(schema) and is_atom(binding) and is_list(opts) ->
        OperationUtils.validate_spec({schema, binding, opts}, &validate_custom_join/1)

      _ ->
        OperationUtils.error(:invalid_value, "join specification")
    end
  end

  @impl true
  def execute(query, spec) do
    case spec do
      # Association join
      {assoc, type, _opts} when is_atom(assoc) ->
        case type do
          :inner -> from(q in query, join: a in assoc(q, ^assoc), as: ^assoc)
          :left -> from(q in query, left_join: a in assoc(q, ^assoc), as: ^assoc)
          :right -> from(q in query, right_join: a in assoc(q, ^assoc), as: ^assoc)
          :full -> from(q in query, full_join: a in assoc(q, ^assoc), as: ^assoc)
          :cross -> from(q in query, cross_join: a in assoc(q, ^assoc), as: ^assoc)
        end

      # Custom join with on condition
      {schema, binding, opts} ->
        on_condition = Keyword.get(opts, :on)
        join_type = Keyword.get(opts, :type, :inner)

        case join_type do
          :inner -> from(q in query, join: b in ^schema, on: ^on_condition, as: ^binding)
          :left -> from(q in query, left_join: b in ^schema, on: ^on_condition, as: ^binding)
          :right -> from(q in query, right_join: b in ^schema, on: ^on_condition, as: ^binding)
          :full -> from(q in query, full_join: b in ^schema, on: ^on_condition, as: ^binding)
        end
    end
  end

  @impl true
  def optimize(spec, context) do
    # TODO: Implement join optimization:
    # - Join order optimization
    # - Join elimination for unused joins
    # - Foreign key analysis
    spec
  end

  # Private validation helpers

  defp validate_join_type({_assoc, type}) do
    OperationUtils.validate_enum(type, @join_types, "join type")
  end

  defp validate_custom_join({_schema, _binding, opts}) do
    if Keyword.has_key?(opts, :on) do
      :ok
    else
      OperationUtils.error(:missing_required, ":on condition")
    end
  end
end
