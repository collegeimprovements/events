defmodule Events.Errors.Error do
  @moduledoc """
  Core error struct representing a normalized error.

  This is the canonical error format used throughout the application.
  All errors from different sources should be normalized into this structure.

  ## Fields

  - `:type` - Error category (validation, not_found, unauthorized, etc.)
  - `:code` - Specific error code identifier
  - `:message` - Human-readable error message
  - `:details` - Additional error context and data
  - `:source` - Original error source (module, system, or service)
  - `:stacktrace` - Exception stacktrace for debugging
  - `:metadata` - Request/user/application context

  ## Examples

      # Create a simple error
      Error.new(:validation, :invalid_email)

      # Create with details
      Error.new(:validation, :invalid_email,
        message: "Email format is invalid",
        details: %{field: :email, value: "test"}
      )

      # Type checking
      Error.validation?(error)   #=> true
      Error.not_found?(error)    #=> false

      # Transformation
      Error.to_tuple(error)      #=> {:error, %Error{}}
      Error.to_map(error)        #=> %{type: :validation, ...}
  """

  @type error_type ::
          :validation
          | :not_found
          | :unauthorized
          | :forbidden
          | :conflict
          | :internal
          | :external
          | :timeout
          | :rate_limit
          | :bad_request
          | :unprocessable
          | :service_unavailable
          | :network
          | :configuration
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          code: atom() | String.t(),
          message: String.t(),
          details: map(),
          source: module() | atom() | nil,
          stacktrace: Exception.stacktrace() | nil,
          metadata: map()
        }

  @derive {Jason.Encoder, only: [:type, :code, :message, :details, :metadata]}
  defstruct [
    :type,
    :code,
    :message,
    :details,
    :source,
    :stacktrace,
    metadata: %{}
  ]

  alias Events.Errors.Registry

  ## Construction

  @doc """
  Creates a new Error struct.

  ## Examples

      iex> Error.new(:validation, :invalid_email)
      %Error{type: :validation, code: :invalid_email, message: "Invalid email format"}

      iex> Error.new(:not_found, :user_not_found, message: "User does not exist")
      %Error{type: :not_found, code: :user_not_found, message: "User does not exist"}
  """
  @spec new(error_type(), atom() | String.t(), keyword()) :: t()
  def new(type, code, opts \\ []) do
    %__MODULE__{
      type: type,
      code: code,
      message: Keyword.get(opts, :message) || Registry.message(type, code),
      details: Keyword.get(opts, :details, %{}),
      source: Keyword.get(opts, :source),
      stacktrace: Keyword.get(opts, :stacktrace),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  ## Type Checking

  @doc "Checks if error is a validation error"
  @spec validation?(t()) :: boolean()
  def validation?(%__MODULE__{type: :validation}), do: true
  def validation?(_), do: false

  @doc "Checks if error is a not_found error"
  @spec not_found?(t()) :: boolean()
  def not_found?(%__MODULE__{type: :not_found}), do: true
  def not_found?(_), do: false

  @doc "Checks if error is an authorization error (unauthorized or forbidden)"
  @spec unauthorized?(t()) :: boolean()
  def unauthorized?(%__MODULE__{type: type}) when type in [:unauthorized, :forbidden], do: true
  def unauthorized?(_), do: false

  @doc "Checks if error is a server/internal error"
  @spec internal?(t()) :: boolean()
  def internal?(%__MODULE__{type: type}) when type in [:internal, :unknown], do: true
  def internal?(_), do: false

  @doc "Checks if error is retriable (timeout, rate_limit, service_unavailable)"
  @spec retriable?(t()) :: boolean()
  def retriable?(%__MODULE__{type: type})
      when type in [:timeout, :rate_limit, :service_unavailable, :network],
      do: true

  def retriable?(_), do: false

  ## Transformation

  @doc """
  Converts error to a result tuple.

  ## Examples

      iex> error |> Error.to_tuple()
      {:error, %Error{}}
  """
  @spec to_tuple(t()) :: {:error, t()}
  def to_tuple(%__MODULE__{} = error), do: {:error, error}

  @doc """
  Converts error to a map for JSON serialization.

  ## Examples

      iex> Error.to_map(error)
      %{type: :validation, code: :invalid_email, message: "...", details: %{}, metadata: %{}}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      type: error.type,
      code: error.code,
      message: error.message,
      details: error.details,
      metadata: error.metadata
    }
  end

  @doc """
  Adds or merges metadata into an error.

  ## Examples

      iex> Error.with_metadata(error, request_id: "req_123")
      %Error{metadata: %{request_id: "req_123"}}
  """
  @spec with_metadata(t(), map() | keyword()) :: t()
  def with_metadata(%__MODULE__{} = error, metadata) when is_map(metadata) or is_list(metadata) do
    metadata = Map.new(metadata)
    %{error | metadata: Map.merge(error.metadata, metadata)}
  end

  @doc """
  Updates error message.

  ## Examples

      iex> Error.with_message(error, "New message")
      %Error{message: "New message"}
  """
  @spec with_message(t(), String.t()) :: t()
  def with_message(%__MODULE__{} = error, message) when is_binary(message) do
    %{error | message: message}
  end

  @doc """
  Adds or merges details into an error.

  ## Examples

      iex> Error.with_details(error, field: :email)
      %Error{details: %{field: :email}}
  """
  @spec with_details(t(), map() | keyword()) :: t()
  def with_details(%__MODULE__{} = error, details) when is_map(details) or is_list(details) do
    details = Map.new(details)
    %{error | details: Map.merge(error.details, details)}
  end

  ## String representation

  defimpl String.Chars do
    def to_string(%Events.Errors.Error{} = error) do
      "[#{error.type}:#{error.code}] #{error.message}"
    end
  end
end
