defmodule Events.Query.Validator do
  @moduledoc false
  # Internal module - use Events.Query public API instead.
  #
  # Schema-aware validation for query operations.
  # Provides early validation with helpful error messages including
  # "did you mean?" suggestions for typos.

  alias Events.Query.ValidationError

  @doc """
  Validate that a field exists in the schema.

  Returns `:ok` if valid, or `{:error, ValidationError.t()}` with helpful
  suggestions if the field is not found.

  ## Examples

      iex> Validator.validate_field(User, :email)
      :ok

      iex> Validator.validate_field(User, :emial)
      {:error, %ValidationError{suggestion: "Did you mean :email?"}}
  """
  @spec validate_field(module(), atom()) :: :ok | {:error, ValidationError.t()}
  def validate_field(schema, field) when is_atom(schema) and is_atom(field) do
    fields = get_schema_fields(schema)

    if field in fields do
      :ok
    else
      similar = find_similar_fields(fields, field)
      {:error, field_not_found_error(field, schema, similar)}
    end
  end

  def validate_field(_schema, field) when is_atom(field), do: :ok
  def validate_field(_schema, _field), do: {:error, "Field must be an atom"}

  @doc """
  Validate that fields exist in the schema (for multi-field operations).
  """
  @spec validate_fields(module(), [atom()]) :: :ok | {:error, ValidationError.t()}
  def validate_fields(schema, fields) when is_list(fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_field(schema, field) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Validate filter value matches expected type for the operator.

  ## Examples

      iex> Validator.validate_filter_value(:between, {1, 10})
      :ok

      iex> Validator.validate_filter_value(:between, "invalid")
      {:error, %ValidationError{reason: ":between requires a {min, max} tuple"}}
  """
  @spec validate_filter_value(atom(), term()) :: :ok | {:error, ValidationError.t()}
  def validate_filter_value(:between, {_min, _max}), do: :ok

  def validate_filter_value(:between, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":between requires a {min, max} tuple",
       value: value,
       suggestion: "Use filter(:field, :between, {min, max})"
     }}
  end

  def validate_filter_value(:in, values) when is_list(values), do: :ok

  def validate_filter_value(:in, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":in requires a list of values",
       value: value,
       suggestion: "Use filter(:field, :in, [value1, value2, ...])"
     }}
  end

  def validate_filter_value(:not_in, values) when is_list(values), do: :ok

  def validate_filter_value(:not_in, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":not_in requires a list of values",
       value: value,
       suggestion: "Use filter(:field, :not_in, [value1, value2, ...])"
     }}
  end

  def validate_filter_value(:like, pattern) when is_binary(pattern), do: :ok

  def validate_filter_value(:like, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":like requires a string pattern",
       value: value,
       suggestion: "Use filter(:field, :like, \"%pattern%\")"
     }}
  end

  def validate_filter_value(:ilike, pattern) when is_binary(pattern), do: :ok

  def validate_filter_value(:ilike, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":ilike requires a string pattern",
       value: value,
       suggestion: "Use filter(:field, :ilike, \"%pattern%\")"
     }}
  end

  def validate_filter_value(:is_nil, _value), do: :ok
  def validate_filter_value(:not_nil, _value), do: :ok

  def validate_filter_value(:jsonb_contains, value) when is_map(value), do: :ok

  def validate_filter_value(:jsonb_contains, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":jsonb_contains requires a map value",
       value: value,
       suggestion: "Use filter(:field, :jsonb_contains, %{key: value})"
     }}
  end

  def validate_filter_value(:jsonb_has_key, key) when is_binary(key), do: :ok

  def validate_filter_value(:jsonb_has_key, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":jsonb_has_key requires a string key",
       value: value,
       suggestion: "Use filter(:field, :jsonb_has_key, \"key_name\")"
     }}
  end

  # Subquery operators accept Token or Ecto.Query
  def validate_filter_value(:in_subquery, %Events.Query.Token{}), do: :ok
  def validate_filter_value(:in_subquery, %Ecto.Query{}), do: :ok

  def validate_filter_value(:in_subquery, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":in_subquery requires a Token or Ecto.Query",
       value: value,
       suggestion: "Use filter(:field, :in_subquery, subquery_token)"
     }}
  end

  def validate_filter_value(:not_in_subquery, %Events.Query.Token{}), do: :ok
  def validate_filter_value(:not_in_subquery, %Ecto.Query{}), do: :ok

  def validate_filter_value(:not_in_subquery, value) do
    {:error,
     %ValidationError{
       operation: :filter,
       reason: ":not_in_subquery requires a Token or Ecto.Query",
       value: value,
       suggestion: "Use filter(:field, :not_in_subquery, subquery_token)"
     }}
  end

  # Default: accept any value for other operators
  def validate_filter_value(_op, _value), do: :ok

  @doc """
  Validate a binding name exists in the query context.

  Bindings are typically :root (default) or join aliases.
  """
  @spec validate_binding(atom(), [atom()]) :: :ok | {:error, ValidationError.t()}
  def validate_binding(binding, available_bindings) do
    if binding in available_bindings do
      :ok
    else
      {:error,
       %ValidationError{
         operation: :binding,
         reason: "Unknown binding: #{inspect(binding)}",
         value: binding,
         suggestion:
           "Available bindings: #{inspect(available_bindings)}. " <>
             "Did you forget to add a join?"
       }}
    end
  end

  @doc """
  Validate window function definition.
  """
  @spec validate_window_definition(keyword()) :: :ok | {:error, ValidationError.t()}
  def validate_window_definition(definition) when is_list(definition) do
    valid_keys = [:partition_by, :order_by, :frame]
    invalid_keys = Keyword.keys(definition) -- valid_keys

    if invalid_keys == [] do
      validate_window_parts(definition)
    else
      {:error,
       %ValidationError{
         operation: :window,
         reason: "Invalid window options: #{inspect(invalid_keys)}",
         value: definition,
         suggestion: "Valid options are: #{inspect(valid_keys)}"
       }}
    end
  end

  def validate_window_definition(value) do
    {:error,
     %ValidationError{
       operation: :window,
       reason: "Window definition must be a keyword list",
       value: value,
       suggestion: "Use window(:name, partition_by: :field, order_by: [desc: :field])"
     }}
  end

  # Private helpers

  defp get_schema_fields(schema) do
    if function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:fields)
    else
      []
    end
  rescue
    _ -> []
  end

  defp find_similar_fields(fields, target) do
    target_string = Atom.to_string(target)

    fields
    |> Enum.map(fn field ->
      {field, String.jaro_distance(Atom.to_string(field), target_string)}
    end)
    |> Enum.filter(fn {_field, distance} -> distance > 0.7 end)
    |> Enum.sort_by(fn {_field, distance} -> distance end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {field, _} -> field end)
  end

  defp field_not_found_error(field, schema, similar_fields) do
    suggestion =
      case similar_fields do
        [] ->
          fields = get_schema_fields(schema)

          if fields == [] do
            "Schema #{inspect(schema)} has no fields defined or is not an Ecto schema."
          else
            "Available fields: #{inspect(Enum.take(fields, 10))}#{if length(fields) > 10, do: "...", else: ""}"
          end

        [closest | _rest] ->
          "Did you mean :#{closest}?"
      end

    %ValidationError{
      operation: :filter,
      reason: "Field :#{field} not found in #{inspect(schema)}",
      value: field,
      suggestion: suggestion
    }
  end

  defp validate_window_parts(definition) do
    with :ok <- validate_partition_by(definition[:partition_by]),
         :ok <- validate_window_order_by(definition[:order_by]) do
      :ok
    end
  end

  defp validate_partition_by(nil), do: :ok
  defp validate_partition_by(field) when is_atom(field), do: :ok
  defp validate_partition_by(fields) when is_list(fields), do: :ok

  defp validate_partition_by(value) do
    {:error,
     %ValidationError{
       operation: :window,
       reason: ":partition_by must be an atom or list of atoms",
       value: value,
       suggestion: "Use partition_by: :field or partition_by: [:field1, :field2]"
     }}
  end

  defp validate_window_order_by(nil), do: :ok
  defp validate_window_order_by(orders) when is_list(orders), do: :ok
  defp validate_window_order_by(field) when is_atom(field), do: :ok

  defp validate_window_order_by(value) do
    {:error,
     %ValidationError{
       operation: :window,
       reason: ":order_by must be a keyword list or atom",
       value: value,
       suggestion: "Use order_by: [desc: :field] or order_by: :field"
     }}
  end
end
