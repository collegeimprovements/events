defmodule Events.Errors.Mappers.Ecto do
  @moduledoc """
  Error mapper for Ecto-related errors.

  Handles normalization of:
  - Ecto.Changeset errors
  - Ecto.Query errors
  - Ecto.NoResultsError
  - Ecto.MultipleResultsError
  - Database constraint errors
  """

  alias Events.Errors.Error

  @doc """
  Normalizes an Ecto.Changeset into an Error struct.
  """
  @spec normalize(Ecto.Changeset.t()) :: Error.t()
  def normalize(%Ecto.Changeset{valid?: false} = changeset) do
    errors = extract_errors(changeset)

    Error.new(:validation, :changeset_invalid,
      message: "Validation failed",
      details: %{errors: errors},
      source: Ecto.Changeset
    )
  end

  def normalize(%Ecto.Changeset{valid?: true}) do
    Error.new(:internal, :invalid_changeset,
      message: "Attempted to normalize a valid changeset",
      source: Ecto.Changeset
    )
  end

  @doc """
  Extracts errors from an Ecto.Changeset into a structured format.

  ## Examples

      iex> changeset = %Ecto.Changeset{
      ...>   errors: [
      ...>     email: {"is invalid", [validation: :format]},
      ...>     age: {"must be greater than %{number}", [validation: :number, number: 0]}
      ...>   ]
      ...> }
      iex> Mappers.Ecto.extract_errors(changeset)
      [
        %{field: :email, message: "is invalid", code: :format, metadata: %{}},
        %{field: :age, message: "must be greater than 0", code: :number, metadata: %{number: 0}}
      ]
  """
  @spec extract_errors(Ecto.Changeset.t()) :: [map()]
  def extract_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      messages
      |> List.wrap()
      |> Enum.map(fn message ->
        # Extract validation type from original error
        {_msg, opts} =
          changeset.errors
          |> Keyword.get_values(field)
          |> List.first()

        code = Keyword.get(opts, :validation, :invalid)
        metadata = Keyword.delete(opts, :validation) |> Map.new()

        %{
          field: field,
          message: message,
          code: code,
          metadata: metadata
        }
      end)
    end)
  end

  @doc """
  Normalizes Ecto.NoResultsError.
  """
  @spec normalize_no_results(Ecto.NoResultsError.t()) :: Error.t()
  def normalize_no_results(%Ecto.NoResultsError{} = exception) do
    Error.new(:not_found, :no_results,
      message: Exception.message(exception),
      source: Ecto.NoResultsError
    )
  end

  @doc """
  Normalizes Ecto.MultipleResultsError.
  """
  @spec normalize_multiple_results(Ecto.MultipleResultsError.t()) :: Error.t()
  def normalize_multiple_results(%Ecto.MultipleResultsError{} = exception) do
    Error.new(:conflict, :multiple_results,
      message: Exception.message(exception),
      source: Ecto.MultipleResultsError
    )
  end

  @doc """
  Normalizes database constraint errors.
  """
  @spec normalize_constraint(atom(), map()) :: Error.t()
  def normalize_constraint(constraint_type, details \\ %{})

  def normalize_constraint(:unique, details) do
    Error.new(:conflict, :unique_constraint,
      message: "Value must be unique",
      details: details,
      source: :database
    )
  end

  def normalize_constraint(:foreign_key, details) do
    Error.new(:unprocessable, :foreign_key_constraint,
      message: "Referenced record does not exist",
      details: details,
      source: :database
    )
  end

  def normalize_constraint(:check, details) do
    Error.new(:validation, :check_constraint,
      message: "Check constraint violation",
      details: details,
      source: :database
    )
  end

  def normalize_constraint(:exclusion, details) do
    Error.new(:conflict, :exclusion_constraint,
      message: "Exclusion constraint violation",
      details: details,
      source: :database
    )
  end

  def normalize_constraint(type, details) do
    Error.new(:unprocessable, :constraint_violation,
      message: "Database constraint violation",
      details: Map.put(details, :constraint_type, type),
      source: :database
    )
  end
end
