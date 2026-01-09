defmodule OmQuery.Error do
  @moduledoc """
  Structured error types for query operations.

  OmQuery provides domain-specific exception types with detailed context,
  suggestions for fixes, and structured data for programmatic handling.

  ## Available Error Types

  | Exception | When Raised |
  |-----------|-------------|
  | `OmQuery.Error` | Generic structured error with type, message, details |
  | `OmQuery.ValidationError` | Invalid query operation (field, value, etc.) |
  | `OmQuery.LimitExceededError` | Query limit exceeds configured maximum |
  | `OmQuery.PaginationError` | Invalid pagination configuration |
  | `OmQuery.CursorError` | Invalid or expired cursor |
  | `OmQuery.FilterGroupError` | Invalid OR/AND filter group |
  | `OmQuery.OperatorError` | Unknown filter operator |
  | `OmQuery.CastError` | Value casting failure |
  | `OmQuery.WindowFunctionError` | Unsupported dynamic window function |
  | `OmQuery.ParameterLimitError` | Raw SQL exceeds parameter limit |
  | `OmQuery.SearchModeError` | Unknown search mode |

  ## Usage

  All errors can be caught and inspected programmatically:

      try do
        OmQuery.filter(token, :status, :invalid_operator, "value")
      rescue
        e in OmQuery.OperatorError ->
          Logger.warning("Invalid operator: \#{e.operator}")
          # Access structured data
          supported = e.supported
      end

  ## Error Messages

  Each error type generates helpful messages with suggestions:

      ** (OmQuery.OperatorError) Unknown filter operator: :fuzzy

      Supported operators: :eq, :neq, :gt, :gte, :lt, :lte, :in, :not_in, ...

      Suggestion: For fuzzy matching, use :ilike or search modes.
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

defmodule OmQuery.ValidationError do
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

defmodule OmQuery.LimitExceededError do
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

        config :om_query, :token,
          max_limit: #{error.requested}
    """
    |> String.trim()
  end
end

defmodule OmQuery.PaginationError do
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

defmodule OmQuery.CursorError do
  @moduledoc """
  Error raised when cursor decoding or validation fails.

  Previously cursor errors were silently ignored, causing queries to return
  incorrect results. This error ensures fail-fast behavior.
  """

  defexception [:cursor, :reason, :suggestion]

  @type t :: %__MODULE__{
          cursor: String.t() | nil,
          reason: String.t(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    suggestion =
      error.suggestion ||
        "Request fresh data without a cursor, or check that the cursor hasn't expired."

    base = "Invalid cursor: #{error.reason}"

    """
    #{base}

    #{suggestion}

    Cursor value: #{inspect(truncate_cursor(error.cursor))}
    """
    |> String.trim()
  end

  defp truncate_cursor(nil), do: nil

  defp truncate_cursor(cursor) when byte_size(cursor) > 50 do
    String.slice(cursor, 0, 50) <> "..."
  end

  defp truncate_cursor(cursor), do: cursor
end

defmodule OmQuery.FilterGroupError do
  @moduledoc """
  Error raised when filter group (OR/AND) configuration is invalid.
  """

  defexception [:combinator, :filters, :reason, :suggestion]

  @type t :: %__MODULE__{
          combinator: :or | :and,
          filters: list(),
          reason: String.t(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    base = "Invalid #{error.combinator} filter group: #{error.reason}"

    if error.suggestion do
      """
      #{base}

      Suggestion: #{error.suggestion}
      """
      |> String.trim()
    else
      base
    end
  end
end

defmodule OmQuery.OperatorError do
  @moduledoc """
  Error raised when an unknown or invalid operator is used.
  """

  defexception [:operator, :context, :supported, :suggestion]

  @type t :: %__MODULE__{
          operator: atom(),
          context: :filter | :negate | :compare,
          supported: [atom()],
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    supported_str = error.supported |> Enum.map(&inspect/1) |> Enum.join(", ")

    base = """
    Unknown #{error.context} operator: #{inspect(error.operator)}

    Supported operators: #{supported_str}
    """

    if error.suggestion do
      """
      #{base}
      Suggestion: #{error.suggestion}
      """
      |> String.trim()
    else
      String.trim(base)
    end
  end
end

defmodule OmQuery.CastError do
  @moduledoc """
  Error raised when a value cannot be cast to the expected type.
  """

  defexception [:value, :target_type, :suggestion]

  @type t :: %__MODULE__{
          value: term(),
          target_type: atom(),
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    suggestion =
      error.suggestion ||
        case error.target_type do
          :integer -> "Ensure the value is a valid integer or string representation (e.g., \"42\")"
          :float -> "Ensure the value is a valid number or string representation (e.g., \"3.14\")"
          :uuid -> "Ensure the value is a valid UUID string (e.g., \"550e8400-e29b-41d4-a716-446655440000\")"
          :boolean -> "Ensure the value is true, false, \"true\", \"false\", 0, or 1"
          _ -> nil
        end

    base = "Cannot cast #{inspect(error.value)} to #{error.target_type}"

    if suggestion do
      """
      #{base}

      #{suggestion}
      """
      |> String.trim()
    else
      base
    end
  end
end

defmodule OmQuery.WindowFunctionError do
  @moduledoc """
  Error raised when window functions are used in an unsupported way.

  Window functions in Ecto require compile-time macros, so dynamic
  construction is limited.
  """

  defexception [:function, :context, :suggestion]

  @type t :: %__MODULE__{
          function: atom() | String.t(),
          context: :select | :order_by | :dynamic,
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    default_suggestion = """
    Alternatives:
    1. Use raw SQL with OmQuery.raw/4:
       |> OmQuery.raw("row_number() OVER (PARTITION BY ? ORDER BY ?)", [category, date])

    2. Build the query directly with Ecto.Query macros:
       from(r in query, select: %{row_num: over(row_number(), :my_window)})

    3. Use a database view for complex window functions
    """

    suggestion = error.suggestion || default_suggestion

    """
    Window function #{inspect(error.function)} cannot be used dynamically in #{error.context}.

    Ecto's window functions require compile-time macro expansion.

    #{suggestion}
    """
    |> String.trim()
  end
end

defmodule OmQuery.ParameterLimitError do
  @moduledoc """
  Error raised when a raw SQL fragment exceeds the parameter limit.
  """

  defexception [:count, :max_allowed, :sql_preview, :suggestion]

  @type t :: %__MODULE__{
          count: pos_integer(),
          max_allowed: pos_integer(),
          sql_preview: String.t() | nil,
          suggestion: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    default_suggestion = """
    Alternatives:
    1. Split into multiple raw/4 calls combined with AND/OR
    2. Use standard filter/4 operations where possible
    3. Use OmQuery.execute_raw/3 for complex raw SQL
    """

    suggestion = error.suggestion || default_suggestion

    sql_info =
      if error.sql_preview do
        "\nSQL fragment: #{String.slice(error.sql_preview, 0, 100)}#{if byte_size(error.sql_preview) > 100, do: "...", else: ""}"
      else
        ""
      end

    """
    Raw SQL fragment exceeds maximum #{error.max_allowed} parameters (got #{error.count}).
    #{sql_info}
    #{suggestion}
    """
    |> String.trim()
  end
end

defmodule OmQuery.SearchModeError do
  @moduledoc """
  Error raised when an unknown search mode is used.
  """

  defexception [:mode, :field, :supported]

  @supported_modes [
    :ilike,
    :like,
    :exact,
    :starts_with,
    :ends_with,
    :contains,
    :similarity,
    :word_similarity,
    :strict_word_similarity
  ]

  @type t :: %__MODULE__{
          mode: atom(),
          field: atom(),
          supported: [atom()]
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    supported = error.supported || @supported_modes
    supported_str = supported |> Enum.map(&inspect/1) |> Enum.join(", ")

    """
    Unknown search mode #{inspect(error.mode)} for field #{inspect(error.field)}

    Supported modes: #{supported_str}

    Example usage:
        OmQuery.search(token, :name, "query", mode: :ilike)
        OmQuery.search(token, :title, "query", mode: :similarity)
    """
    |> String.trim()
  end
end
