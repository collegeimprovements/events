defmodule OmCrud.Error do
  @moduledoc """
  Rich error types for CRUD operations.

  Provides structured error information with context about what went wrong,
  including the operation type, schema, field-level details, and original errors.

  ## Error Types

  - `:not_found` - Record not found
  - `:validation_error` - Changeset validation failed
  - `:constraint_violation` - Database constraint violated
  - `:step_failed` - A step in atomic operation failed
  - `:transaction_error` - Transaction failed
  - `:stale_entry` - Optimistic locking conflict

  ## Usage

      case OmCrud.fetch(User, id) do
        {:ok, user} -> user
        {:error, %OmCrud.Error{type: :not_found}} -> handle_not_found()
        {:error, %OmCrud.Error{} = error} -> Logger.error(OmCrud.Error.message(error))
      end

  ## In Atomic Operations

      OmCrud.atomic fn ->
        with {:ok, user} <- OmCrud.fetch(User, user_id),
             {:ok, account} <- OmCrud.fetch(Account, user.account_id) do
          {:ok, %{user: user, account: account}}
        end
      end
      # Returns {:error, %OmCrud.Error{type: :not_found, ...}} on failure
  """

  @type error_type ::
          :not_found
          | :validation_error
          | :constraint_violation
          | :step_failed
          | :transaction_error
          | :stale_entry
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          schema: module() | nil,
          operation: atom() | nil,
          id: term() | nil,
          field: atom() | nil,
          value: term() | nil,
          constraint: atom() | nil,
          changeset: Ecto.Changeset.t() | nil,
          query: Ecto.Query.t() | nil,
          errors: [{atom(), {String.t(), keyword()}}] | nil,
          message: String.t() | nil,
          step: atom() | nil,
          original: term() | nil,
          metadata: map()
        }

  defstruct [
    :type,
    :schema,
    :operation,
    :id,
    :field,
    :value,
    :constraint,
    :changeset,
    :query,
    :errors,
    :message,
    :step,
    :original,
    metadata: %{}
  ]

  defimpl String.Chars do
    def to_string(error) do
      OmCrud.Error.message(error)
    end
  end

  # Smart Constructors

  @doc """
  Creates a not_found error.

  ## Examples

      OmCrud.Error.not_found(User, 123)
      #=> %OmCrud.Error{type: :not_found, schema: User, id: 123}

      OmCrud.Error.not_found(User, 123, operation: :fetch)
      #=> %OmCrud.Error{type: :not_found, schema: User, id: 123, operation: :fetch}
  """
  @spec not_found(module(), term(), keyword()) :: t()
  def not_found(schema, id, opts \\ []) do
    %__MODULE__{
      type: :not_found,
      schema: schema,
      id: id,
      operation: Keyword.get(opts, :operation, :fetch),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates an error from an Ecto changeset.

  Automatically extracts constraint violations and field errors.

  ## Examples

      changeset = User.changeset(%User{}, %{email: "invalid"})
      OmCrud.Error.from_changeset(changeset)
      #=> %OmCrud.Error{type: :validation_error, errors: [...], changeset: changeset}
  """
  @spec from_changeset(Ecto.Changeset.t(), keyword()) :: t()
  def from_changeset(%Ecto.Changeset{} = changeset, opts \\ []) do
    {type, constraint} = classify_changeset_error(changeset)

    %__MODULE__{
      type: type,
      schema: changeset.data.__struct__,
      operation: Keyword.get(opts, :operation, :create),
      changeset: changeset,
      errors: changeset.errors,
      constraint: constraint,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a constraint violation error.

  ## Examples

      OmCrud.Error.constraint_violation(:users_email_unique, User)
      #=> %OmCrud.Error{type: :constraint_violation, constraint: :users_email_unique}
  """
  @spec constraint_violation(atom(), module(), keyword()) :: t()
  def constraint_violation(constraint, schema, opts \\ []) do
    %__MODULE__{
      type: :constraint_violation,
      constraint: constraint,
      schema: schema,
      operation: Keyword.get(opts, :operation),
      field: Keyword.get(opts, :field),
      value: Keyword.get(opts, :value),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a validation error.

  ## Examples

      OmCrud.Error.validation_error(:email, "is invalid", schema: User)
      #=> %OmCrud.Error{type: :validation_error, field: :email, ...}
  """
  @spec validation_error(atom(), String.t(), keyword()) :: t()
  def validation_error(field, message, opts \\ []) do
    %__MODULE__{
      type: :validation_error,
      field: field,
      message: message,
      schema: Keyword.get(opts, :schema),
      operation: Keyword.get(opts, :operation),
      value: Keyword.get(opts, :value),
      errors: [{field, {message, []}}],
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a step_failed error for atomic operations.

  ## Examples

      OmCrud.Error.step_failed(:create_user, {:error, changeset})
      #=> %OmCrud.Error{type: :step_failed, step: :create_user, original: {:error, changeset}}
  """
  @spec step_failed(atom(), term(), keyword()) :: t()
  def step_failed(step, original_error, opts \\ []) do
    base = %__MODULE__{
      type: :step_failed,
      step: step,
      original: original_error,
      operation: Keyword.get(opts, :operation),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    # Extract details from original error if it's a changeset
    case original_error do
      {:error, %Ecto.Changeset{} = changeset} ->
        inner = from_changeset(changeset, opts)

        %{
          base
          | schema: inner.schema,
            changeset: changeset,
            errors: inner.errors,
            constraint: inner.constraint
        }

      {:error, %__MODULE__{} = inner} ->
        %{
          base
          | schema: inner.schema,
            changeset: inner.changeset,
            errors: inner.errors,
            constraint: inner.constraint,
            original: inner
        }

      _ ->
        base
    end
  end

  @doc """
  Creates a transaction error.

  ## Examples

      OmCrud.Error.transaction_error(:rollback, step: :create_account)
      #=> %OmCrud.Error{type: :transaction_error, original: :rollback, step: :create_account}
  """
  @spec transaction_error(term(), keyword()) :: t()
  def transaction_error(reason, opts \\ []) do
    %__MODULE__{
      type: :transaction_error,
      original: reason,
      step: Keyword.get(opts, :step),
      operation: Keyword.get(opts, :operation, :transaction),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a stale entry error for optimistic locking conflicts.

  ## Examples

      OmCrud.Error.stale_entry(User, 123)
      #=> %OmCrud.Error{type: :stale_entry, schema: User, id: 123}
  """
  @spec stale_entry(module(), term(), keyword()) :: t()
  def stale_entry(schema, id, opts \\ []) do
    %__MODULE__{
      type: :stale_entry,
      schema: schema,
      id: id,
      operation: Keyword.get(opts, :operation, :update),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Wraps any error into an OmCrud.Error struct.

  If already an OmCrud.Error, returns it unchanged.

  ## Examples

      OmCrud.Error.wrap(:not_found)
      #=> %OmCrud.Error{type: :unknown, original: :not_found}

      OmCrud.Error.wrap(%OmCrud.Error{type: :not_found})
      #=> %OmCrud.Error{type: :not_found}  # unchanged
  """
  @spec wrap(term(), keyword()) :: t()
  def wrap(%__MODULE__{} = error, _opts), do: error

  def wrap(%Ecto.Changeset{} = changeset, opts), do: from_changeset(changeset, opts)

  def wrap(error, opts) do
    %__MODULE__{
      type: :unknown,
      original: error,
      operation: Keyword.get(opts, :operation),
      schema: Keyword.get(opts, :schema),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  # Message Generation

  @doc """
  Generates a human-readable error message.

  ## Examples

      error = OmCrud.Error.not_found(User, 123)
      OmCrud.Error.message(error)
      #=> "User with id 123 not found"
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: msg}) when is_binary(msg), do: msg

  def message(%__MODULE__{type: :not_found, schema: schema, id: id}) do
    schema_name = schema_name(schema)
    "#{schema_name} with id #{inspect(id)} not found"
  end

  def message(%__MODULE__{type: :validation_error, changeset: %Ecto.Changeset{} = cs}) do
    errors =
      Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    "Validation failed: #{inspect(errors)}"
  end

  def message(%__MODULE__{type: :validation_error, field: field, errors: errors})
      when is_list(errors) do
    formatted =
      Enum.map_join(errors, ", ", fn {f, {msg, _}} ->
        "#{f} #{msg}"
      end)

    if field do
      "Validation failed on #{field}: #{formatted}"
    else
      "Validation failed: #{formatted}"
    end
  end

  def message(%__MODULE__{type: :constraint_violation, constraint: constraint, schema: schema}) do
    schema_name = schema_name(schema)
    "Constraint violation on #{schema_name}: #{constraint}"
  end

  def message(%__MODULE__{type: :step_failed, step: step, original: original}) do
    "Step #{inspect(step)} failed: #{format_original(original)}"
  end

  def message(%__MODULE__{type: :transaction_error, original: reason, step: step}) do
    if step do
      "Transaction failed at step #{inspect(step)}: #{inspect(reason)}"
    else
      "Transaction failed: #{inspect(reason)}"
    end
  end

  def message(%__MODULE__{type: :stale_entry, schema: schema, id: id}) do
    schema_name = schema_name(schema)
    "#{schema_name} with id #{inspect(id)} has been modified by another process"
  end

  def message(%__MODULE__{type: type, original: original}) do
    "#{type}: #{format_original(original)}"
  end

  # Conversion Helpers

  @doc """
  Converts an error to a map suitable for JSON encoding.

  ## Examples

      error = OmCrud.Error.not_found(User, 123)
      OmCrud.Error.to_map(error)
      #=> %{type: :not_found, schema: "User", id: 123, message: "User with id 123 not found"}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      type: error.type,
      message: message(error)
    }
    |> maybe_put(:schema, schema_name(error.schema))
    |> maybe_put(:id, error.id)
    |> maybe_put(:field, error.field)
    |> maybe_put(:constraint, error.constraint)
    |> maybe_put(:step, error.step)
    |> maybe_put(:errors, format_errors_for_json(error.errors))
  end

  @doc """
  Returns an appropriate HTTP status code for the error.

  ## Examples

      OmCrud.Error.to_http_status(%OmCrud.Error{type: :not_found})
      #=> 404

      OmCrud.Error.to_http_status(%OmCrud.Error{type: :validation_error})
      #=> 422
  """
  @spec to_http_status(t()) :: pos_integer()
  def to_http_status(%__MODULE__{type: :not_found}), do: 404
  def to_http_status(%__MODULE__{type: :validation_error}), do: 422
  def to_http_status(%__MODULE__{type: :constraint_violation}), do: 409
  def to_http_status(%__MODULE__{type: :stale_entry}), do: 409
  def to_http_status(%__MODULE__{type: _}), do: 500

  # Query Helpers

  @doc """
  Checks if the error is of a specific type.

  ## Examples

      error = OmCrud.Error.not_found(User, 123)
      OmCrud.Error.is_type?(error, :not_found)
      #=> true
  """
  @spec is_type?(t(), error_type()) :: boolean()
  def is_type?(%__MODULE__{type: type}, expected_type), do: type == expected_type

  @doc """
  Checks if error is related to a specific field.

  ## Examples

      error = OmCrud.Error.validation_error(:email, "is invalid")
      OmCrud.Error.on_field?(error, :email)
      #=> true
  """
  @spec on_field?(t(), atom()) :: boolean()
  def on_field?(%__MODULE__{field: field}, expected_field) when field == expected_field do
    true
  end

  def on_field?(%__MODULE__{errors: errors}, expected_field) when is_list(errors) do
    Enum.any?(errors, fn {field, _} -> field == expected_field end)
  end

  def on_field?(%__MODULE__{}, _expected_field), do: false

  # Private Helpers

  defp classify_changeset_error(%Ecto.Changeset{} = changeset) do
    # Check for constraint errors
    constraint_error =
      Enum.find(changeset.errors, fn
        {_field, {_msg, [constraint: _, constraint_name: name]}} -> name
        {_field, {_msg, [constraint: _]}} -> true
        _ -> false
      end)

    case constraint_error do
      {_field, {_msg, opts}} ->
        constraint_name = Keyword.get(opts, :constraint_name)
        {:constraint_violation, constraint_name}

      nil ->
        {:validation_error, nil}
    end
  end

  defp schema_name(nil), do: nil
  defp schema_name(schema) when is_atom(schema), do: schema |> Module.split() |> List.last()

  defp format_original({:error, %Ecto.Changeset{} = cs}) do
    "changeset errors: #{inspect(cs.errors)}"
  end

  defp format_original({:error, %__MODULE__{} = error}), do: message(error)
  defp format_original({:error, reason}), do: inspect(reason)
  defp format_original(other), do: inspect(other)

  defp format_errors_for_json(nil), do: nil

  defp format_errors_for_json(errors) when is_list(errors) do
    Map.new(errors, fn {field, {msg, _opts}} -> {field, msg} end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
