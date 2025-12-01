defimpl Events.Protocols.Normalizable, for: Ecto.Changeset do
  @moduledoc """
  Normalizable implementation for Ecto.Changeset.

  Converts invalid changesets into validation errors with detailed field information.
  """

  alias Events.Types.Error

  def normalize(%Ecto.Changeset{valid?: false} = changeset, opts) do
    errors = extract_errors(changeset)
    fields = Map.keys(errors)

    Error.new(:validation, :changeset_invalid,
      message: Keyword.get(opts, :message, "Validation failed"),
      details: %{errors: errors, fields: fields},
      source: Ecto.Changeset,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  def normalize(%Ecto.Changeset{valid?: true}, opts) do
    Error.new(:internal, :invalid_normalization,
      message: "Attempted to normalize a valid changeset",
      source: Ecto.Changeset,
      context: Keyword.get(opts, :context, %{})
    )
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, validation_opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        validation_opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.NoResultsError do
  @moduledoc """
  Normalizable implementation for Ecto.NoResultsError.

  Raised when a query returns no results but one was expected (e.g., Repo.one!).
  """

  alias Events.Types.Error

  def normalize(%Ecto.NoResultsError{} = exception, opts) do
    Error.new(:not_found, :no_results,
      message: Exception.message(exception),
      source: Ecto.NoResultsError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.MultipleResultsError do
  @moduledoc """
  Normalizable implementation for Ecto.MultipleResultsError.

  Raised when a query returns multiple results but only one was expected.
  """

  alias Events.Types.Error

  def normalize(%Ecto.MultipleResultsError{} = exception, opts) do
    Error.new(:conflict, :multiple_results,
      message: Exception.message(exception),
      source: Ecto.MultipleResultsError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.StaleEntryError do
  @moduledoc """
  Normalizable implementation for Ecto.StaleEntryError.

  Raised when an optimistic lock fails (record was modified by another process).
  This error is recoverable - retry with fresh data.
  """

  alias Events.Types.Error

  def normalize(%Ecto.StaleEntryError{}, opts) do
    Error.new(:conflict, :stale_entry,
      message: "Record was modified by another process",
      source: Ecto.StaleEntryError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step),
      recoverable: true
    )
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.ConstraintError do
  @moduledoc """
  Normalizable implementation for Ecto.ConstraintError.

  Raised when a database constraint is violated (unique, foreign key, etc.).
  Attempts to infer the specific constraint type from the constraint name.
  """

  alias Events.Types.Error

  def normalize(%Ecto.ConstraintError{} = exception, opts) do
    {type, code} = classify_constraint(exception.constraint, exception.type)

    Error.new(type, code,
      message: Exception.message(exception),
      details: %{
        constraint: exception.constraint,
        constraint_type: exception.type
      },
      source: Ecto.ConstraintError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp classify_constraint(constraint, type) do
    case type do
      :unique -> {:conflict, infer_unique_code(constraint)}
      :foreign_key -> {:unprocessable, :foreign_key_violation}
      :check -> {:validation, :check_constraint_violation}
      :exclusion -> {:conflict, :exclusion_violation}
      _ -> {:conflict, :constraint_violation}
    end
  end

  defp infer_unique_code(constraint) when is_binary(constraint) do
    cond do
      constraint =~ "email" -> :email_taken
      constraint =~ "username" -> :username_taken
      constraint =~ "slug" -> :slug_taken
      constraint =~ "phone" -> :phone_taken
      true -> :unique_violation
    end
  end

  defp infer_unique_code(_), do: :unique_violation
end

defimpl Events.Protocols.Normalizable, for: Ecto.QueryError do
  @moduledoc """
  Normalizable implementation for Ecto.QueryError.

  Raised when there's an error with the query structure.
  """

  alias Events.Types.Error

  def normalize(%Ecto.QueryError{} = exception, opts) do
    Error.new(:internal, :query_error,
      message: Exception.message(exception),
      source: Ecto.QueryError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.CastError do
  @moduledoc """
  Normalizable implementation for Ecto.CastError.

  Raised when a value cannot be cast to the expected type.
  """

  alias Events.Types.Error

  def normalize(%Ecto.CastError{} = exception, opts) do
    Error.new(:validation, :cast_error,
      message: Exception.message(exception),
      details: %{
        type: exception.type,
        value: inspect(exception.value)
      },
      source: Ecto.CastError,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end
end

defimpl Events.Protocols.Normalizable, for: Ecto.InvalidChangesetError do
  @moduledoc """
  Normalizable implementation for Ecto.InvalidChangesetError.

  Raised when trying to insert/update with an invalid changeset.
  """

  alias Events.Types.Error

  def normalize(%Ecto.InvalidChangesetError{changeset: changeset} = _exception, opts) do
    # Delegate to the changeset normalization
    Events.Protocols.Normalizable.normalize(changeset, opts)
  end
end
