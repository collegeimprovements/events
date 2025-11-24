defmodule Events.CRUD.ValidationHelpers do
  @moduledoc """
  Shared validation helpers for CRUD operations.

  Provides consistent validation patterns and error messages.
  """

  @doc """
  Validates that a field is an atom or a join tuple (for joined fields).

  ## Examples

      validate_field(:name, "field_name")  # => :ok
      validate_field({:user, :name}, "field_name")  # => :ok
      validate_field("name", "field_name")  # => {:error, "field_name must be atom or join tuple"}
  """
  @spec validate_field(term(), String.t()) :: :ok | {:error, String.t()}
  def validate_field(field, field_name) do
    if is_atom(field) or (is_tuple(field) and tuple_size(field) == 2) do
      :ok
    else
      {:error, "#{field_name} must be atom or join tuple"}
    end
  end

  @doc """
  Validates that a value is in the allowed list.

  ## Examples

      validate_enum(:inner, [:inner, :left, :right], "join_type")  # => :ok
      validate_enum(:invalid, [:inner, :left, :right], "join_type")  # => {:error, "Unsupported join_type: invalid"}
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
  Validates that a value is of the expected type.

  ## Examples

      validate_type("hello", :binary, "name")  # => :ok
      validate_type(123, :binary, "name")  # => {:error, "name must be binary"}
  """
  @spec validate_type(term(), atom(), String.t()) :: :ok | {:error, String.t()}
  def validate_type(value, expected_type, field_name) do
    if is_type?(value, expected_type) do
      :ok
    else
      {:error, "#{field_name} must be #{expected_type}"}
    end
  end

  @doc """
  Validates that a value is within a range.

  ## Examples

      validate_range(5, 1..10, "limit")  # => :ok
      validate_range(15, 1..10, "limit")  # => {:error, "limit must be between 1 and 10"}
  """
  @spec validate_range(term(), Range.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_range(value, range, field_name) do
    if is_number(value) and value in range do
      :ok
    else
      {:error, "#{field_name} must be between #{range.first} and #{range.last}"}
    end
  end

  @doc """
  Validates that a value is not nil.

  ## Examples

      validate_required("value", "field")  # => :ok
      validate_required(nil, "field")  # => {:error, "field is required"}
  """
  @spec validate_required(term(), String.t()) :: :ok | {:error, String.t()}
  def validate_required(value, field_name) do
    if value != nil do
      :ok
    else
      {:error, "#{field_name} is required"}
    end
  end

  # Helper function for type checking
  defp is_type?(value, :atom), do: is_atom(value)
  defp is_type?(value, :binary), do: is_binary(value)
  defp is_type?(value, :integer), do: is_integer(value)
  defp is_type?(value, :float), do: is_float(value)
  defp is_type?(value, :number), do: is_number(value)
  defp is_type?(value, :boolean), do: is_boolean(value)
  defp is_type?(value, :list), do: is_list(value)
  defp is_type?(value, :tuple), do: is_tuple(value)
  defp is_type?(value, :map), do: is_map(value)
end
