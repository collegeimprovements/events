defmodule Events.Query.Error do
  @moduledoc """
  Structured error types for query operations.

  Provides domain-specific errors with detailed context for better
  error handling and debugging.
  """

  defexception [:type, :message, :details]

  @type error_type ::
          :validation
          | :timeout
          | :pagination
          | :limit_exceeded
          | :execution
          | :database

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map()
        }

  @doc "Create a validation error"
  @spec validation(String.t(), map()) :: t()
  def validation(message, details \\ %{}) do
    %__MODULE__{
      type: :validation,
      message: message,
      details: details
    }
  end

  @doc "Create a timeout error"
  @spec timeout(String.t(), map()) :: t()
  def timeout(message, details \\ %{}) do
    %__MODULE__{
      type: :timeout,
      message: message,
      details: details
    }
  end

  @doc "Create a pagination error"
  @spec pagination(String.t(), map()) :: t()
  def pagination(message, details \\ %{}) do
    %__MODULE__{
      type: :pagination,
      message: message,
      details: details
    }
  end

  @doc "Create a limit exceeded error"
  @spec limit_exceeded(pos_integer(), pos_integer(), String.t()) :: t()
  def limit_exceeded(requested, max_allowed, suggestion \\ nil) do
    message = """
    Limit of #{requested} exceeds max_limit of #{max_allowed}.

    #{suggestion || "Increase :max_limit config or use streaming for large datasets."}
    """

    %__MODULE__{
      type: :limit_exceeded,
      message: String.trim(message),
      details: %{
        requested: requested,
        max_allowed: max_allowed,
        suggestion: suggestion
      }
    }
  end

  @doc "Create an execution error"
  @spec execution(String.t(), map()) :: t()
  def execution(message, details \\ %{}) do
    %__MODULE__{
      type: :execution,
      message: message,
      details: details
    }
  end

  @doc "Create a database error"
  @spec database(String.t(), map()) :: t()
  def database(message, details \\ %{}) do
    %__MODULE__{
      type: :database,
      message: message,
      details: details
    }
  end

  @impl Exception
  def message(%__MODULE__{message: msg}), do: msg
end

defmodule Events.Query.ValidationError do
  @moduledoc """
  Error raised when a query operation fails validation.
  """

  defexception [:operation, :reason, :value, :suggestion]

  @type t :: %__MODULE__{
          operation: atom(),
          reason: String.t(),
          value: term(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    base = "Invalid #{error.operation} operation: #{error.reason}"

    if error.suggestion do
      """
      #{base}

      Value: #{inspect(error.value)}

      Suggestion: #{error.suggestion}
      """
      |> String.trim()
    else
      base
    end
  end
end

defmodule Events.Query.LimitExceededError do
  @moduledoc """
  Error raised when a query limit exceeds the configured maximum.
  """

  defexception [:requested, :max_allowed, :suggestion]

  @type t :: %__MODULE__{
          requested: pos_integer(),
          max_allowed: pos_integer(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    suggestion =
      error.suggestion ||
        "Increase :max_limit config or use streaming for large datasets."

    """
    Limit of #{error.requested} exceeds max_limit of #{error.max_allowed}.

    #{suggestion}

    To increase max_limit, add to config.exs:

        config :events, Events.Query.Token,
          max_limit: #{error.requested}
    """
    |> String.trim()
  end
end

defmodule Events.Query.PaginationError do
  @moduledoc """
  Error raised when pagination configuration is invalid.
  """

  defexception [:type, :reason, :order_by, :cursor_fields, :suggestion]

  @type t :: %__MODULE__{
          type: :offset | :cursor,
          reason: String.t(),
          order_by: list() | nil,
          cursor_fields: list() | nil,
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    base = "Invalid #{error.type} pagination: #{error.reason}"

    details =
      []
      |> maybe_add("order_by: #{inspect(error.order_by)}", error.order_by)
      |> maybe_add("cursor_fields: #{inspect(error.cursor_fields)}", error.cursor_fields)
      |> maybe_add("Suggestion: #{error.suggestion}", error.suggestion)

    if Enum.empty?(details) do
      base
    else
      """
      #{base}

      #{Enum.join(details, "\n")}
      """
      |> String.trim()
    end
  end

  defp maybe_add(list, _text, nil), do: list
  defp maybe_add(list, text, _), do: list ++ [text]
end
