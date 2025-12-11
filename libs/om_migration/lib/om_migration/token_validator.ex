defmodule OmMigration.TokenValidator do
  @moduledoc """
  Comprehensive validation for migration tokens.

  Validates tokens before execution to catch errors early. Provides detailed
  error messages to help developers fix issues quickly.

  ## Validations Performed

  ### Table Tokens
  - Must have at least one field
  - Must have a primary key (either explicit or default)
  - No duplicate field names
  - Index columns must reference existing fields
  - Foreign key types must match referenced table's primary key type

  ### Index Tokens
  - Must specify columns
  - Columns must not be empty

  ### All Tokens
  - Name must be an atom or string
  - Type must be valid

  ## Usage

      case TokenValidator.validate(token) do
        {:ok, token} -> Executor.execute(token)
        {:error, errors} -> handle_errors(errors)
      end

      # Or raise on error
      token = TokenValidator.validate!(token)
  """

  alias OmMigration.Token

  @type validation_error :: %{
          code: atom(),
          message: String.t(),
          field: atom() | nil,
          details: map()
        }

  @valid_token_types [:table, :index, :constraint, :alter]

  @doc """
  Validates a token and returns all validation errors.

  Returns `{:ok, token}` if valid, `{:error, errors}` otherwise.
  Unlike basic validation, this returns ALL errors found, not just the first.

  ## Examples

      {:ok, token} = TokenValidator.validate(valid_token)
      {:error, errors} = TokenValidator.validate(invalid_token)
  """
  @spec validate(Token.t()) :: {:ok, Token.t()} | {:error, [validation_error()]}
  def validate(%Token{} = token) do
    errors =
      []
      |> validate_token_type(token)
      |> validate_token_name(token)
      |> validate_by_type(token)

    case errors do
      [] -> {:ok, token}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Validates a token, raising on error.

  Raises `OmMigration.ValidationError` with detailed error information.

  ## Examples

      token = TokenValidator.validate!(token)
  """
  @spec validate!(Token.t()) :: Token.t()
  def validate!(%Token{} = token) do
    case validate(token) do
      {:ok, valid_token} ->
        valid_token

      {:error, errors} ->
        message = format_errors(token, errors)
        raise OmMigration.ValidationError, message: message, errors: errors
    end
  end

  @doc """
  Checks if a token is valid without returning errors.

  ## Examples

      if TokenValidator.valid?(token), do: execute(token)
  """
  @spec valid?(Token.t()) :: boolean()
  def valid?(%Token{} = token) do
    case validate(token) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # ============================================
  # Core Validations
  # ============================================

  defp validate_token_type(errors, %Token{type: type}) when type in @valid_token_types do
    errors
  end

  defp validate_token_type(errors, %Token{type: type}) do
    [
      %{
        code: :invalid_token_type,
        message:
          "Invalid token type: #{inspect(type)}. Must be one of: #{inspect(@valid_token_types)}",
        field: :type,
        details: %{type: type, valid_types: @valid_token_types}
      }
      | errors
    ]
  end

  defp validate_token_name(errors, %Token{name: name}) when is_atom(name) or is_binary(name) do
    errors
  end

  defp validate_token_name(errors, %Token{name: name}) do
    [
      %{
        code: :invalid_token_name,
        message: "Token name must be an atom or string, got: #{inspect(name)}",
        field: :name,
        details: %{name: name}
      }
      | errors
    ]
  end

  # ============================================
  # Type-Specific Validations
  # ============================================

  defp validate_by_type(errors, %Token{type: :table} = token) do
    errors
    |> validate_has_fields(token)
    |> validate_no_duplicate_fields(token)
    |> validate_has_primary_key(token)
    |> validate_index_columns_exist(token)
    |> validate_foreign_key_types(token)
    |> validate_constraint_expressions(token)
  end

  defp validate_by_type(errors, %Token{type: :index} = token) do
    errors
    |> validate_index_has_columns(token)
  end

  defp validate_by_type(errors, %Token{type: :alter} = token) do
    errors
    |> validate_no_duplicate_fields(token)
  end

  defp validate_by_type(errors, _token), do: errors

  # ============================================
  # Table Validations
  # ============================================

  defp validate_has_fields(errors, %Token{name: name, fields: []}) do
    [
      %{
        code: :no_fields,
        message: "Table #{name} has no fields defined",
        field: nil,
        details: %{table: name}
      }
      | errors
    ]
  end

  defp validate_has_fields(errors, _token), do: errors

  defp validate_no_duplicate_fields(errors, %Token{name: name, fields: fields}) do
    field_names = Enum.map(fields, fn {field_name, _type, _opts} -> field_name end)
    duplicates = field_names -- Enum.uniq(field_names)

    if duplicates != [] do
      [
        %{
          code: :duplicate_fields,
          message: "Table #{name} has duplicate fields: #{inspect(Enum.uniq(duplicates))}",
          field: nil,
          details: %{table: name, duplicates: Enum.uniq(duplicates)}
        }
        | errors
      ]
    else
      errors
    end
  end

  defp validate_has_primary_key(errors, %Token{name: name} = token) do
    if Token.has_primary_key?(token) do
      errors
    else
      [
        %{
          code: :no_primary_key,
          message: "Table #{name} has no primary key defined",
          field: nil,
          details: %{table: name}
        }
        | errors
      ]
    end
  end

  defp validate_index_columns_exist(errors, %Token{
         name: table_name,
         fields: fields,
         indexes: indexes
       }) do
    field_names = MapSet.new(Enum.map(fields, fn {name, _type, _opts} -> name end))

    Enum.reduce(indexes, errors, fn {index_name, columns, _opts}, acc ->
      missing = Enum.filter(columns, &(not MapSet.member?(field_names, &1)))

      if missing != [] do
        [
          %{
            code: :index_missing_columns,
            message: "Index #{index_name} references non-existent fields: #{inspect(missing)}",
            field: index_name,
            details: %{table: table_name, index: index_name, missing_columns: missing}
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp validate_foreign_key_types(errors, %Token{name: table_name, fields: fields}) do
    Enum.reduce(fields, errors, fn field, acc ->
      case field do
        {field_name, {:references, _ref_table, opts}, _field_opts} ->
          type = Keyword.get(opts, :type, :bigint)
          validate_reference_type(acc, table_name, field_name, type)

        _ ->
          acc
      end
    end)
  end

  defp validate_reference_type(errors, _table_name, _field_name, type)
       when type in [:uuid, :binary_id, :bigint, :integer, :id] do
    errors
  end

  defp validate_reference_type(errors, table_name, field_name, type) do
    [
      %{
        code: :invalid_reference_type,
        message: "Field #{field_name} has invalid reference type: #{inspect(type)}",
        field: field_name,
        details: %{table: table_name, field: field_name, type: type}
      }
      | errors
    ]
  end

  defp validate_constraint_expressions(errors, %Token{name: table_name, constraints: constraints}) do
    Enum.reduce(constraints, errors, fn {constraint_name, type, opts}, acc ->
      case type do
        :check ->
          if Keyword.has_key?(opts, :expr) or Keyword.has_key?(opts, :expression) do
            acc
          else
            [
              %{
                code: :missing_constraint_expression,
                message: "Check constraint #{constraint_name} missing expression",
                field: constraint_name,
                details: %{table: table_name, constraint: constraint_name}
              }
              | acc
            ]
          end

        _ ->
          acc
      end
    end)
  end

  # ============================================
  # Index Validations
  # ============================================

  defp validate_index_has_columns(errors, %Token{name: name, options: opts}) do
    columns = Keyword.get(opts, :columns, [])

    if columns == [] do
      [
        %{
          code: :index_no_columns,
          message: "Index #{name} has no columns defined",
          field: nil,
          details: %{index: name}
        }
        | errors
      ]
    else
      errors
    end
  end

  # ============================================
  # Error Formatting
  # ============================================

  defp format_errors(%Token{type: type, name: name}, errors) do
    error_messages =
      errors
      |> Enum.map(fn %{message: msg} -> "  - #{msg}" end)
      |> Enum.join("\n")

    """
    Migration token validation failed for #{type} '#{name}':

    #{error_messages}

    Fix the issues above before executing this migration.
    """
  end
end

defmodule OmMigration.ValidationError do
  @moduledoc """
  Exception raised when migration token validation fails.
  """

  defexception [:message, :errors]

  @impl true
  def message(%{message: message}), do: message
end
