defmodule Events.CRUD.Validation do
  @moduledoc """
  Comprehensive validation for tokens and operations.

  This module validates entire tokens and delegates operation-specific validation
  to individual operation modules.
  """

  alias Events.CRUD.Token

  @doc """
  Validates a token and all its operations.

  Returns `{:ok, validated_token}` if all operations are valid,
  or `{:error, reason}` if any operation fails validation.
  """
  @spec validate(Token.t()) :: {:ok, Token.t()} | {:error, String.t()}
  def validate(%Token{operations: operations} = token) do
    case validate_operations(operations) do
      :ok -> {:ok, %{token | validated: true}}
      error -> error
    end
  end

  @doc """
  Validates a single operation spec.

  This is useful for validating operations before adding them to a token.
  """
  @spec validate_operation(atom(), term()) :: :ok | {:error, String.t()}
  def validate_operation(op_type, spec) do
    case operation_module(op_type) do
      {:error, reason} ->
        {:error, reason}

      operation_module ->
        if Code.ensure_loaded?(operation_module) do
          operation_module.validate_spec(spec)
        else
          {:error, "Operation module not loaded: #{inspect(operation_module)}"}
        end
    end
  end

  # Private functions

  defp validate_operations([]), do: :ok

  defp validate_operations([{op_type, spec} | rest]) do
    case validate_operation(op_type, spec) do
      :ok -> validate_operations(rest)
      error -> error
    end
  end

  # Operation module mapping
  # TODO: Consider using a registry or dynamic loading for better extensibility
  defp operation_module(:where), do: Events.CRUD.Operations.Where
  defp operation_module(:join), do: Events.CRUD.Operations.Join
  defp operation_module(:order), do: Events.CRUD.Operations.Order
  defp operation_module(:preload), do: Events.CRUD.Operations.Preload
  defp operation_module(:paginate), do: Events.CRUD.Operations.Paginate
  defp operation_module(:select), do: Events.CRUD.Operations.Select
  defp operation_module(:group), do: Events.CRUD.Operations.Group
  defp operation_module(:having), do: Events.CRUD.Operations.Having
  defp operation_module(:window), do: Events.CRUD.Operations.Window
  defp operation_module(:raw), do: Events.CRUD.Operations.Raw
  defp operation_module(:debug), do: Events.CRUD.Operations.Debug
  defp operation_module(:create), do: Events.CRUD.Operations.Create
  defp operation_module(:update), do: Events.CRUD.Operations.Update
  defp operation_module(:delete), do: Events.CRUD.Operations.Delete
  defp operation_module(:get), do: Events.CRUD.Operations.Get
  defp operation_module(:list), do: Events.CRUD.Operations.List
  defp operation_module(op_type), do: {:error, "Unknown operation type: #{op_type}"}
end
