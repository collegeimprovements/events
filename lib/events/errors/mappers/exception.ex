defmodule Events.Errors.Mappers.Exception do
  @moduledoc """
  Mapper for Elixir exceptions to Error structs.

  Handles normalization of standard Elixir exceptions and custom exception types.
  """

  alias Events.Errors.Error

  @doc """
  Normalizes an Elixir exception into an Error struct.

  ## Examples

      iex> Exception.normalize(%RuntimeError{message: "boom"})
      %Error{type: :internal, code: :exception, message: "boom"}

      iex> Exception.normalize(%ArgumentError{}, stacktrace)
      %Error{type: :internal, code: :exception, stacktrace: [...]}
  """
  @spec normalize(Exception.t(), Exception.stacktrace() | nil) :: Error.t()
  def normalize(exception, stacktrace \\ nil)

  # Ecto exceptions
  def normalize(%Ecto.NoResultsError{} = exception, stacktrace) do
    Error.new(:not_found, :no_results,
      message: Exception.message(exception),
      source: Ecto,
      stacktrace: stacktrace
    )
  end

  def normalize(%Ecto.QueryError{} = exception, stacktrace) do
    Error.new(:internal, :query_error,
      message: Exception.message(exception),
      source: Ecto,
      stacktrace: stacktrace,
      details: Map.from_struct(exception)
    )
  end

  # Argument/Type errors
  def normalize(%ArgumentError{} = exception, stacktrace) do
    Error.new(:bad_request, :invalid_argument,
      message: Exception.message(exception),
      source: ArgumentError,
      stacktrace: stacktrace
    )
  end

  # Generic exception
  def normalize(exception, stacktrace) do
    module = exception.__struct__
    message = Exception.message(exception)

    Error.new(:internal, :exception,
      message: message,
      source: module,
      stacktrace: stacktrace,
      details: Map.from_struct(exception)
    )
  end
end
