defmodule Events.Errors.Mappers.Graphql do
  @moduledoc """
  Error mapper for GraphQL/Absinthe errors.

  Handles normalization of errors from GraphQL query parsing,
  validation, and execution.
  """

  alias Events.Errors.Error

  @doc """
  Normalizes Absinthe/GraphQL errors.

  ## Examples

      iex> Graphql.normalize(%{message: "Field 'email' not found", locations: [...]})
      %Error{type: :validation, code: :field_not_found}
  """
  @spec normalize(map() | String.t()) :: Error.t()
  def normalize(%{__struct__: Absinthe.Resolution} = resolution) do
    # Extract error from resolution
    errors = Map.get(resolution, :errors, [])

    case errors do
      [first | _] -> normalize(first)
      [] -> Error.new(:unknown, :resolution_error, message: "GraphQL resolution failed")
    end
  end

  def normalize(%{message: message} = error) when is_map(error) do
    {type, code} = infer_from_message(message)

    Error.new(type, code,
      message: message,
      source: :graphql,
      details: %{
        locations: Map.get(error, :locations),
        path: Map.get(error, :path),
        extensions: Map.get(error, :extensions, %{})
      }
    )
  end

  def normalize(message) when is_binary(message) do
    {type, code} = infer_from_message(message)

    Error.new(type, code,
      message: message,
      source: :graphql
    )
  end

  def normalize(error) do
    Error.new(:unknown, :graphql_error,
      message: "GraphQL error occurred",
      source: :graphql,
      details: %{original: inspect(error)}
    )
  end

  ## Message Pattern Matching

  defp infer_from_message(message) do
    message_lower = String.downcase(message)

    cond do
      # Authentication & Authorization
      String.contains?(message_lower, ["unauthenticated", "not logged in", "need to be logged"]) ->
        {:unauthorized, :unauthenticated}

      String.contains?(message_lower, ["unauthorized", "permission", "forbidden", "not allowed"]) ->
        {:forbidden, :unauthorized}

      String.contains?(message_lower, ["invalid token", "token expired", "expired token"]) ->
        {:unauthorized, :token_invalid}

      # Validation Errors
      String.contains?(message_lower, ["field", "not found", "doesn't exist"]) ->
        {:validation, :field_not_found}

      String.contains?(message_lower, ["invalid argument", "invalid input", "validation"]) ->
        {:validation, :invalid_argument}

      String.contains?(message_lower, ["required", "must be present", "can't be blank"]) ->
        {:validation, :required_field}

      String.contains?(message_lower, ["must be", "should be", "expected"]) ->
        {:validation, :constraint_violation}

      # Resource Errors
      String.contains?(message_lower, ["not found", "can't find", "cannot find", "does not exist"]) ->
        {:not_found, :not_found}

      String.contains?(message_lower, ["already exists", "duplicate", "conflict"]) ->
        {:conflict, :already_exists}

      String.contains?(message_lower, ["more than one", "multiple results"]) ->
        {:conflict, :multiple_results}

      # Syntax/Parse Errors
      String.contains?(message_lower, ["syntax error", "parse error", "parsing"]) ->
        {:bad_request, :syntax_error}

      String.contains?(message_lower, ["unknown type", "unknown field"]) ->
        {:bad_request, :unknown_field}

      # Rate Limiting
      String.contains?(message_lower, ["rate limit", "too many requests", "throttled"]) ->
        {:rate_limit, :rate_limit_exceeded}

      # Timeout
      String.contains?(message_lower, ["timeout", "timed out"]) ->
        {:timeout, :timeout}

      # Server Errors
      String.contains?(message_lower, ["internal error", "something went wrong", "server error"]) ->
        {:internal, :internal_error}

      # Fallback
      true ->
        {:unknown, :graphql_error}
    end
  end

  @doc """
  Normalizes Absinthe middleware errors.
  """
  @spec normalize_middleware_error(term()) :: Error.t()
  def normalize_middleware_error({:error, reason}) do
    normalize(reason)
  end

  def normalize_middleware_error(error) do
    normalize(error)
  end

  @doc """
  Converts Error struct to Absinthe error format.

  This is the reverse operation - taking our normalized error
  and formatting it for GraphQL responses.
  """
  @spec to_absinthe(Error.t()) :: map()
  def to_absinthe(%Error{} = error) do
    %{
      message: error.message,
      extensions: %{
        code: error.code,
        type: error.type,
        details: error.details,
        metadata: error.metadata
      }
    }
  end

  @doc """
  Batch normalizes multiple GraphQL errors.
  """
  @spec normalize_many([term()]) :: [Error.t()]
  def normalize_many(errors) when is_list(errors) do
    Enum.map(errors, &normalize/1)
  end
end
