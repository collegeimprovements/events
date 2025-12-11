defmodule Events.Types.Error do
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

  # Configurable defaults - can be overridden via application config
  # config :events, Events.Types.Error, task_supervisor: MyApp.TaskSupervisor
  @task_supervisor Application.compile_env(:events, [__MODULE__, :task_supervisor], nil)

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
          occurred_at: DateTime.t(),
          recoverable: boolean(),
          step: atom() | nil,
          cause: t() | nil
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
    :occurred_at,
    recoverable: false,
    step: nil,
    cause: nil
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
      occurred_at: DateTime.utc_now(),
      recoverable: opts[:recoverable] || infer_recoverable(type, code),
      step: opts[:step],
      cause: opts[:cause]
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

  This function delegates to the `Events.Types.Normalizable` protocol for type-based
  dispatch. You can extend normalization for custom types by implementing the
  protocol.

  ## Telemetry

  Error normalization emits telemetry events for observability:

      [:events, :error, :normalized]
      - measurements: %{duration: native_time}
      - metadata: %{
          error_type: :validation,
          error_code: :invalid_email,
          source_type: Ecto.Changeset,
          recoverable: false
        }

  To attach a handler:

      :telemetry.attach("error-logger", [:events, :error, :normalized], fn _event, measurements, metadata, _config ->
        Logger.info("Error normalized: \#{metadata.error_type}/\#{metadata.error_code}")
      end, nil)

  ## Options

  - `:telemetry` - Set to `false` to disable telemetry emission (default: true)
  - `:context` - Additional context to attach to the error
  - `:step` - Pipeline step where error occurred

  ## Examples

      Error.normalize({:error, :not_found})
      Error.normalize(%Ecto.Changeset{valid?: false})
      Error.normalize(%RuntimeError{message: "boom"})

      # Without telemetry
      Error.normalize(error, telemetry: false)

  ## Extending

  Implement `Events.Types.Normalizable` for custom error types:

      defimpl Events.Types.Normalizable, for: MyApp.CustomError do
        def normalize(error, opts) do
          Events.Error.new(:business, error.code,
            message: error.message,
            context: Keyword.get(opts, :context, %{})
          )
        end
      end
  """
  @spec normalize(term(), keyword()) :: t()
  def normalize(error, opts \\ [])

  # Unwrap error tuples
  def normalize({:error, reason}, opts) do
    normalize(reason, opts)
  end

  # Delegate to Normalizable protocol with telemetry
  def normalize(error, opts) do
    emit_telemetry = Keyword.get(opts, :telemetry, true)
    start_time = if emit_telemetry, do: System.monotonic_time(), else: nil
    source_type = get_source_type(error)

    normalized = Events.Types.Normalizable.normalize(error, opts)

    if emit_telemetry do
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:events, :error, :normalized],
        %{duration: duration},
        %{
          error_type: normalized.type,
          error_code: normalized.code,
          source_type: source_type,
          recoverable: normalized.recoverable
        }
      )
    end

    normalized
  end

  # Get the source type for telemetry metadata
  defp get_source_type(%{__struct__: module}), do: module
  defp get_source_type(atom) when is_atom(atom), do: :atom
  defp get_source_type(binary) when is_binary(binary), do: :string
  defp get_source_type(tuple) when is_tuple(tuple), do: :tuple
  defp get_source_type(map) when is_map(map), do: :map
  defp get_source_type(_), do: :unknown

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
      supervisor = opts[:task_supervisor] || @task_supervisor ||
        raise "No task supervisor configured. Pass :task_supervisor option or configure in config."
      Task.Supervisor.start_child(supervisor, fn -> do_store(error) end)
      {:ok, error}
    else
      do_store(error)
      {:ok, error}
    end
  end

  ## Error Registry

  # Default error codes per type
  @default_codes %{
    validation: [:invalid_email, :required, :too_long, :too_short, :invalid_format],
    not_found: [:not_found, :resource_not_found, :file_not_found],
    unauthorized: [:unauthorized, :invalid_credentials, :token_expired],
    forbidden: [:forbidden, :insufficient_permissions],
    conflict: [:conflict, :already_exists, :duplicate],
    rate_limited: [:rate_limited, :too_many_requests],
    internal: [:internal, :exception, :unknown],
    external: [:external_service, :api_error, :integration_failed],
    timeout: [:timeout, :request_timeout, :operation_timeout],
    network: [:connection_failed, :dns_error, :ssl_error],
    business: [:business_rule_violation, :invalid_state]
  }

  @doc """
  Returns all known error codes for a type.

  Error codes can be extended via application config:

      # In config.exs
      config :events, Events.Types.Error,
        codes: %{
          validation: [:custom_validation_error],
          payment: [:card_declined, :insufficient_funds]
        }

  Or at runtime via `register_codes/2`.

  ## Examples

      Error.codes_for_type(:validation)
      #=> [:invalid_email, :required, :too_long, :too_short, :invalid_format, :custom_validation_error]
  """
  @spec codes_for_type(error_type()) :: [atom()]
  def codes_for_type(type) do
    default = Map.get(@default_codes, type, [])
    config = get_configured_codes(type)
    runtime = get_runtime_codes(type)

    Enum.uniq(default ++ config ++ runtime)
  end

  @doc """
  Registers additional error codes for a type at runtime.

  These codes are stored in a persistent term for fast access.

  ## Examples

      Error.register_codes(:payment, [:card_declined, :insufficient_funds])
      Error.codes_for_type(:payment)
      #=> [:card_declined, :insufficient_funds]
  """
  @spec register_codes(error_type(), [atom()]) :: :ok
  def register_codes(type, codes) when is_atom(type) and is_list(codes) do
    current = get_all_runtime_codes()
    existing = Map.get(current, type, [])
    updated = Map.put(current, type, Enum.uniq(existing ++ codes))
    :persistent_term.put({__MODULE__, :runtime_codes}, updated)
    :ok
  end

  @doc """
  Returns all registered error types (both default and custom).

  ## Examples

      Error.registered_types()
      #=> [:validation, :not_found, :unauthorized, :forbidden, :conflict, ...]
  """
  @spec registered_types() :: [error_type()]
  def registered_types do
    default_types = Map.keys(@default_codes)
    config_types = get_configured_codes() |> Map.keys()
    runtime_types = get_all_runtime_codes() |> Map.keys()

    Enum.uniq(default_types ++ config_types ++ runtime_types)
  end

  @doc """
  Checks if an error code is valid for a given type.

  ## Examples

      Error.valid_code?(:validation, :required)
      #=> true

      Error.valid_code?(:validation, :unknown_code)
      #=> false
  """
  @spec valid_code?(error_type(), atom()) :: boolean()
  def valid_code?(type, code) do
    code in codes_for_type(type)
  end

  # Get codes from application config
  defp get_configured_codes do
    Application.get_env(:events, __MODULE__, [])
    |> Keyword.get(:codes, %{})
  end

  defp get_configured_codes(type) do
    get_configured_codes()
    |> Map.get(type, [])
  end

  # Get runtime-registered codes
  defp get_all_runtime_codes do
    try do
      :persistent_term.get({__MODULE__, :runtime_codes})
    rescue
      ArgumentError -> %{}
    end
  end

  defp get_runtime_codes(type) do
    get_all_runtime_codes()
    |> Map.get(type, [])
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

  ## Recoverability and Step Handling

  @doc """
  Checks if an error is recoverable.

  ## Examples

      Error.recoverable?(error)
      #=> true | false
  """
  @spec recoverable?(t()) :: boolean()
  def recoverable?(%Error{recoverable: recoverable}), do: recoverable

  @doc """
  Marks error as recoverable or not.

  ## Examples

      error |> Error.recoverable(true)
  """
  @spec recoverable(t(), boolean()) :: t()
  def recoverable(%Error{} = error, is_recoverable) when is_boolean(is_recoverable) do
    %{error | recoverable: is_recoverable}
  end

  @doc """
  Sets the step on an error (for pipeline integration).

  ## Examples

      error |> Error.with_step(:fetch_user)
  """
  @spec with_step(t(), atom()) :: t()
  def with_step(%Error{} = error, step) when is_atom(step) do
    %{error | step: step}
  end

  @doc """
  Gets the step where the error occurred.

  ## Examples

      Error.step(error)
      #=> :fetch_user | nil
  """
  @spec step(t()) :: atom() | nil
  def step(%Error{step: step}), do: step

  ## Error Chaining

  @doc """
  Sets the cause of an error (for error chaining).

  ## Examples

      outer_error = Error.new(:internal, :pipeline_failed,
        cause: inner_error
      )

      # Or using pipe
      outer_error |> Error.with_cause(inner_error)
  """
  @spec with_cause(t(), t()) :: t()
  def with_cause(%Error{} = error, %Error{} = cause) do
    %{error | cause: cause}
  end

  @doc """
  Gets the root cause of an error chain.

  ## Examples

      Error.root_cause(error)
      #=> %Error{...} (the innermost error)
  """
  @spec root_cause(t()) :: t()
  def root_cause(%Error{cause: nil} = error), do: error
  def root_cause(%Error{cause: cause}), do: root_cause(cause)

  @doc """
  Returns all errors in the cause chain.

  ## Examples

      Error.cause_chain(error)
      #=> [outer_error, middle_error, root_error]
  """
  @spec cause_chain(t()) :: [t()]
  def cause_chain(%Error{cause: nil} = error), do: [error]
  def cause_chain(%Error{cause: cause} = error), do: [error | cause_chain(cause)]

  ## Category Helpers

  @doc """
  Checks if error is of a specific type.

  ## Examples

      Error.type?(error, :validation)
      #=> true | false
  """
  @spec type?(t(), error_type()) :: boolean()
  def type?(%Error{type: type}, expected_type), do: type == expected_type

  @doc """
  Checks if error is a validation error.
  """
  @spec validation?(t()) :: boolean()
  def validation?(%Error{} = error), do: type?(error, :validation)

  @doc """
  Checks if error is a not found error.
  """
  @spec not_found?(t()) :: boolean()
  def not_found?(%Error{} = error), do: type?(error, :not_found)

  @doc """
  Checks if error is an authorization error (unauthorized or forbidden).
  """
  @spec auth_error?(t()) :: boolean()
  def auth_error?(%Error{type: type}), do: type in [:unauthorized, :forbidden]

  @doc """
  Checks if error is a client error (validation, not_found, unauthorized, forbidden, conflict).
  """
  @spec client_error?(t()) :: boolean()
  def client_error?(%Error{type: type}) do
    type in [:validation, :not_found, :unauthorized, :forbidden, :conflict, :rate_limited]
  end

  @doc """
  Checks if error is a server error (internal, external, timeout, network).
  """
  @spec server_error?(t()) :: boolean()
  def server_error?(%Error{type: type}) do
    type in [:internal, :external, :timeout, :network]
  end

  ## Formatting

  @doc """
  Formats the error as a human-readable string.

  ## Examples

      Error.format(error)
      #=> "[validation] Validation failed (step: create_user)"
  """
  @spec format(t()) :: String.t()
  def format(%Error{} = error) do
    parts = ["[#{error.type}]", error.message]

    parts =
      case error.step do
        nil -> parts
        step -> parts ++ ["(step: #{step})"]
      end

    parts =
      case error.cause do
        nil -> parts
        cause -> parts ++ ["caused by:", format(cause)]
      end

    Enum.join(parts, " ")
  end

  ## Private Functions

  defp infer_recoverable(type, _code) do
    type in [:timeout, :network, :external, :rate_limited]
  end

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

  defp generate_id do
    "err_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp do_store(error) do
    # In production, this would write to a database or external service
    # For now, just log it
    Logger.info("Error stored: #{error.id}")
  end
end
