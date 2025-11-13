defmodule Events.Error do
  @moduledoc """
  Unified error handling system for the Events application.

  This module consolidates all error handling functionality into a single,
  easy-to-use interface. It combines error normalization, enrichment,
  storage, and handling in one place.

  ## Quick Start

      # Normalize any error
      Events.Error.normalize({:error, :not_found})
      Events.Error.normalize(%Ecto.Changeset{valid?: false})

      # Create a new error
      Events.Error.new(:validation, :invalid_email,
        message: "Email format is invalid",
        details: %{email: "not-an-email"}
      )

      # Enrich with context
      error
      |> Events.Error.with_context(user_id: 123, request_id: "req_123")

      # Store for analysis
      Events.Error.store(error)

      # Handle in different contexts
      Events.Error.handle(error, :http)  # Returns HTTP status and body
      Events.Error.handle(error, :graphql)  # Returns GraphQL format

  ## Error Types

  - `:validation` - Input validation errors
  - `:not_found` - Resource not found
  - `:unauthorized` - Authentication required
  - `:forbidden` - Insufficient permissions
  - `:conflict` - Resource conflict
  - `:rate_limited` - Too many requests
  - `:internal` - Server errors
  - `:external` - Third-party service errors
  - `:timeout` - Operation timeout
  - `:network` - Network errors
  """

  require Logger

  alias __MODULE__

  @type error_type ::
          :validation
          | :not_found
          | :unauthorized
          | :forbidden
          | :conflict
          | :rate_limited
          | :internal
          | :external
          | :timeout
          | :network
          | :business

  @type t :: %__MODULE__{
          type: error_type(),
          code: atom(),
          message: String.t(),
          details: map(),
          context: map(),
          source: term(),
          stacktrace: list() | nil,
          id: String.t(),
          occurred_at: DateTime.t()
        }

  defstruct [
    :type,
    :code,
    :message,
    :details,
    :context,
    :source,
    :stacktrace,
    :id,
    :occurred_at
  ]

  ## Error Creation

  @doc """
  Creates a new error.

  ## Examples

      Error.new(:validation, :invalid_email,
        message: "Email format is invalid",
        details: %{email: "not-an-email"}
      )
  """
  @spec new(error_type(), atom(), keyword()) :: t()
  def new(type, code, opts \\ []) do
    %Error{
      type: type,
      code: code,
      message: opts[:message] || default_message(type, code),
      details: opts[:details] || %{},
      context: opts[:context] || %{},
      source: opts[:source],
      stacktrace: opts[:stacktrace],
      id: generate_id(),
      occurred_at: DateTime.utc_now()
    }
  end

  @doc """
  Normalizes any error into a standard Error struct.

  Handles:
  - Error tuples: `{:error, reason}`
  - Ecto changesets
  - HTTP status codes
  - Exceptions
  - Existing Error structs
  - Custom error maps

  ## Examples

      Error.normalize({:error, :not_found})
      Error.normalize(%Ecto.Changeset{valid?: false})
      Error.normalize(%RuntimeError{message: "boom"})
  """
  @spec normalize(term(), keyword()) :: t()
  def normalize(%Error{} = error, _opts), do: error

  def normalize({:error, %Error{} = error}, _opts), do: error

  def normalize({:error, reason}, opts) do
    normalize(reason, opts)
  end

  def normalize(:not_found, opts) do
    new(:not_found, :not_found, opts)
  end

  def normalize(:unauthorized, opts) do
    new(:unauthorized, :unauthorized, opts)
  end

  def normalize(:forbidden, opts) do
    new(:forbidden, :forbidden, opts)
  end

  def normalize(%Ecto.Changeset{} = changeset, opts) do
    errors = transform_changeset_errors(changeset)

    new(
      :validation,
      :validation_failed,
      Keyword.merge(
        [
          message: "Validation failed",
          details: errors,
          source: changeset
        ],
        opts
      )
    )
  end

  def normalize(%{__exception__: true} = exception, opts) do
    new(
      :internal,
      :exception,
      Keyword.merge(
        [
          message: Exception.message(exception),
          source: exception,
          stacktrace: opts[:stacktrace] || Exception.format_stacktrace()
        ],
        opts
      )
    )
  end

  def normalize(error, opts) when is_atom(error) do
    new(:internal, error, Keyword.put(opts, :source, error))
  end

  def normalize(error, opts) when is_binary(error) do
    new(:internal, :error, Keyword.merge([message: error, source: error], opts))
  end

  def normalize(error, opts) do
    new(
      :internal,
      :unknown,
      Keyword.merge(
        [
          message: "An unknown error occurred",
          source: error
        ],
        opts
      )
    )
  end

  @doc """
  Normalizes a result tuple.

  ## Examples

      User.create(params)
      |> Error.normalize_result()
      |> case do
        {:ok, user} -> {:ok, user}
        {:error, %Error{} = error} -> handle_error(error)
      end
  """
  @spec normalize_result({:ok, term()} | {:error, term()}, keyword()) ::
          {:ok, term()} | {:error, t()}
  def normalize_result({:ok, value}, _opts), do: {:ok, value}
  def normalize_result({:error, reason}, opts), do: {:error, normalize(reason, opts)}

  @doc """
  Wraps a function call and normalizes any errors.

  ## Examples

      Error.wrap(fn ->
        dangerous_operation()
      end)
      #=> {:ok, result} | {:error, %Error{}}
  """
  @spec wrap(fun(), keyword()) :: {:ok, term()} | {:error, t()}
  def wrap(fun, opts \\ []) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    exception ->
      {:error, normalize(exception, Keyword.put(opts, :stacktrace, __STACKTRACE__))}
  catch
    :exit, reason ->
      {:error, new(:internal, :exit, Keyword.merge([source: reason], opts))}

    kind, reason ->
      {:error, new(:internal, kind, Keyword.merge([source: reason], opts))}
  end

  ## Context and Enrichment

  @doc """
  Adds context to an error.

  ## Examples

      error
      |> Error.with_context(user_id: 123, request_id: "req_123")
  """
  @spec with_context(t(), map() | keyword()) :: t()
  def with_context(%Error{} = error, context) when is_list(context) do
    with_context(error, Map.new(context))
  end

  def with_context(%Error{context: existing} = error, new_context) when is_map(new_context) do
    %{error | context: Map.merge(existing, new_context)}
  end

  @doc """
  Adds metadata to error details.

  ## Examples

      error
      |> Error.with_details(field: "email", value: "invalid")
  """
  @spec with_details(t(), map() | keyword()) :: t()
  def with_details(%Error{} = error, details) when is_list(details) do
    with_details(error, Map.new(details))
  end

  def with_details(%Error{details: existing} = error, new_details) when is_map(new_details) do
    %{error | details: Map.merge(existing, new_details)}
  end

  ## Error Handling

  @doc """
  Handles an error for different contexts.

  ## Contexts

  - `:http` - Returns HTTP status and JSON body
  - `:graphql` - Returns GraphQL error format
  - `:log` - Logs the error and returns it

  ## Examples

      Error.handle(error, :http)
      #=> {422, %{error: %{type: "validation", ...}}}
  """
  @spec handle(t(), atom(), keyword()) :: term()
  def handle(error, context, opts \\ [])

  def handle(%Error{} = error, :http, _opts) do
    status = error_to_http_status(error.type)

    body = %{
      error: %{
        type: error.type,
        code: error.code,
        message: error.message,
        details: error.details,
        id: error.id
      }
    }

    {status, body}
  end

  def handle(%Error{} = error, :graphql, _opts) do
    %{
      message: error.message,
      extensions: %{
        type: error.type,
        code: error.code,
        details: error.details,
        id: error.id
      }
    }
  end

  def handle(%Error{} = error, :log, opts) do
    level = opts[:level] || :error

    Logger.log(level, "Error occurred",
      type: error.type,
      code: error.code,
      message: error.message,
      details: error.details,
      context: error.context,
      id: error.id
    )

    error
  end

  ## Storage (simplified)

  @doc """
  Stores an error for later analysis.

  This is a simplified version. In production, you might want to
  store in a database or error tracking service.
  """
  @spec store(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def store(%Error{} = error, opts \\ []) do
    if opts[:async] do
      Task.start(fn -> do_store(error) end)
      {:ok, error}
    else
      do_store(error)
      {:ok, error}
    end
  end

  ## Error Registry

  @doc """
  Returns all known error codes for a type.
  """
  @spec codes_for_type(error_type()) :: [atom()]
  def codes_for_type(type) do
    case type do
      :validation -> [:invalid_email, :required, :too_long, :too_short, :invalid_format]
      :not_found -> [:not_found, :resource_not_found, :file_not_found]
      :unauthorized -> [:unauthorized, :invalid_credentials, :token_expired]
      :forbidden -> [:forbidden, :insufficient_permissions]
      :conflict -> [:conflict, :already_exists, :duplicate]
      :rate_limited -> [:rate_limited, :too_many_requests]
      :internal -> [:internal, :exception, :unknown]
      :external -> [:external_service, :api_error, :integration_failed]
      :timeout -> [:timeout, :request_timeout, :operation_timeout]
      :network -> [:connection_failed, :dns_error, :ssl_error]
      :business -> [:business_rule_violation, :invalid_state]
      _ -> []
    end
  end

  ## JSON Serialization

  @doc """
  Converts error to JSON-safe map.
  """
  @spec to_map(t()) :: map()
  def to_map(%Error{} = error) do
    %{
      type: error.type,
      code: error.code,
      message: error.message,
      details: error.details,
      context: error.context,
      id: error.id,
      occurred_at: DateTime.to_iso8601(error.occurred_at)
    }
  end

  ## Private Functions

  defp default_message(type, code) do
    case {type, code} do
      {:validation, :invalid_email} -> "Email format is invalid"
      {:validation, :required} -> "This field is required"
      {:validation, _} -> "Validation failed"
      {:not_found, _} -> "Resource not found"
      {:unauthorized, _} -> "Authentication required"
      {:forbidden, _} -> "You don't have permission to perform this action"
      {:conflict, :already_exists} -> "Resource already exists"
      {:conflict, _} -> "Resource conflict"
      {:rate_limited, _} -> "Too many requests, please try again later"
      {:internal, _} -> "An internal error occurred"
      {:external, _} -> "External service error"
      {:timeout, _} -> "Operation timed out"
      {:network, _} -> "Network error occurred"
      {:business, _} -> "Business rule violation"
      _ -> "An error occurred"
    end
  end

  defp error_to_http_status(type) do
    case type do
      :validation -> 422
      :not_found -> 404
      :unauthorized -> 401
      :forbidden -> 403
      :conflict -> 409
      :rate_limited -> 429
      :timeout -> 408
      :internal -> 500
      :external -> 502
      :network -> 503
      _ -> 500
    end
  end

  defp transform_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp generate_id do
    "err_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp do_store(error) do
    # In production, this would write to a database or external service
    # For now, just log it
    Logger.info("Error stored: #{error.id}")
  end
end
