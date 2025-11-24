defmodule Events.CRUD.OperationUtils do
  @moduledoc """
  Shared utilities for CRUD operations.

  Provides common patterns and helpers to ensure consistency across all operations.
  """

  @doc """
  Standardizes operation spec validation.

  ## Examples

      # Simple enum validation
      validate_spec(spec, [
        field: &validate_field/1,
        op: &validate_enum(&1, @supported_ops, "operator")
      ])

      # Complex validation with custom logic
      validate_spec(spec, fn {field, op, value} ->
        with :ok <- validate_field(field),
             :ok <- validate_enum(op, @ops),
             :ok <- validate_value(value) do
          :ok
        end
      end)
  """
  @spec validate_spec(term(), keyword() | (term() -> :ok | {:error, String.t()})) ::
          :ok | {:error, String.t()}
  def validate_spec(spec, validators) when is_list(validators) do
    # Apply each validator in sequence
    Enum.reduce_while(validators, :ok, fn {_key, validator}, _acc ->
      case validator.(spec) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate_spec(spec, validator_fun) when is_function(validator_fun, 1) do
    validator_fun.(spec)
  end

  @doc """
  Creates standardized error messages.

  ## Examples

      error(:invalid_field, "username")
      # => {:error, "Field 'username' is invalid"}

      error(:unsupported_operator, "custom_op")
      # => {:error, "Unsupported operator: custom_op"}
  """
  @spec error(atom(), term()) :: {:error, String.t()}
  def error(:invalid_field, field), do: {:error, "Field '#{field}' is invalid"}
  def error(:unsupported_operator, op), do: {:error, "Unsupported operator: #{op}"}
  def error(:unsupported_join_type, type), do: {:error, "Unsupported join type: #{type}"}
  def error(:invalid_value, value), do: {:error, "Invalid value: #{inspect(value)}"}
  def error(:missing_required, field), do: {:error, "Required field missing: #{field}"}
  def error(:type_mismatch, {field, expected}), do: {:error, "Field '#{field}' must be #{expected}"}

  @doc """
  Validates field specifications.

  ## Examples

      validate_field(:name)  # => :ok
      validate_field({:user, :name})  # => :ok
      validate_field("name")  # => {:error, "Field must be atom or join tuple"}
  """
  @spec validate_field(term()) :: :ok | {:error, String.t()}
  def validate_field(field) do
    cond do
      is_atom(field) -> :ok
      is_tuple(field) and tuple_size(field) == 2 -> :ok
      true -> error(:invalid_field, "must be atom or join tuple")
    end
  end

  @doc """
  Validates enum values.

  ## Examples

      validate_enum(:eq, [:eq, :neq, :gt], "operator")  # => :ok
      validate_enum(:invalid, [:eq, :neq], "operator")  # => {:error, "Unsupported operator: invalid"}
  """
  @spec validate_enum(term(), [term()], String.t()) :: :ok | {:error, String.t()}
  def validate_enum(value, allowed, field_name) do
    if value in allowed do
      :ok
    else
      {:error, "Unsupported #{field_name}: #{value}"}
    end
  end

  @doc """
  Validates value types.

  ## Examples

      validate_type("string", :binary, "name")  # => :ok
      validate_type(123, :binary, "name")  # => {:error, "Field 'name' must be binary"}
  """
  @spec validate_type(term(), atom(), String.t()) :: :ok | {:error, String.t()}
  def validate_type(value, expected_type, field_name) do
    if match_type?(value, expected_type) do
      :ok
    else
      error(:type_mismatch, {field_name, expected_type})
    end
  end

  @doc """
  Validates ranges.

  ## Examples

      validate_range(5, 1..10, "limit")  # => :ok
      validate_range(15, 1..10, "limit")  # => {:error, "Invalid value: 15"}
  """
  @spec validate_range(term(), Range.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_range(value, range, field_name) do
    if is_number(value) and value in range do
      :ok
    else
      error(:invalid_value, "#{field_name} must be between #{range.first} and #{range.last}")
    end
  end

  # Private helpers

  defp match_type?(value, :atom), do: is_atom(value)
  defp match_type?(value, :binary), do: is_binary(value)
  defp match_type?(value, :integer), do: is_integer(value)
  defp match_type?(value, :float), do: is_float(value)
  defp match_type?(value, :number), do: is_number(value)
  defp match_type?(value, :boolean), do: is_boolean(value)
  defp match_type?(value, :list), do: is_list(value)
  defp match_type?(value, :tuple), do: is_tuple(value)
  defp match_type?(value, :map), do: is_map(value)
  defp match_type?(_value, _type), do: false
end
