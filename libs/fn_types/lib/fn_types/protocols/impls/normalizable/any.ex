defimpl FnTypes.Protocols.Normalizable, for: Any do
  @moduledoc """
  Fallback Normalizable implementation for Any type.

  This implementation handles:
  1. Exceptions (structs with `__exception__: true`)
  2. Structs that derive Normalizable
  3. Unknown types (last resort fallback)

  ## Deriving Normalizable

  For custom structs, you can derive a simple implementation:

      defmodule MyApp.CustomError do
        @derive {FnTypes.Protocols.Normalizable, type: :business, code: :custom_error}
        defstruct [:message, :details]
      end

  ## Derive Options

  - `:type` - Error type (default: `:internal`)
  - `:code` - Error code (default: struct module name as snake_case atom)
  - `:message_field` - Field to use for message (default: `:message`)
  - `:details_field` - Field to use for details (default: `:details`)
  - `:recoverable` - Whether error is recoverable (default: `false`)
  """

  alias FnTypes.Error

  defmacro __deriving__(module, _struct, opts) do
    type = Keyword.get(opts, :type, :internal)
    code = Keyword.get(opts, :code, derive_code(module))
    message_field = Keyword.get(opts, :message_field, :message)
    details_field = Keyword.get(opts, :details_field, :details)
    recoverable = Keyword.get(opts, :recoverable, false)

    quote do
      defimpl FnTypes.Protocols.Normalizable, for: unquote(module) do
        def normalize(value, opts) do
          message =
            cond do
              function_exported?(unquote(module), :message, 1) ->
                Exception.message(value)

              Map.has_key?(value, unquote(message_field)) ->
                Map.get(value, unquote(message_field)) || default_message()

              true ->
                default_message()
            end

          details =
            if Map.has_key?(value, unquote(details_field)) do
              Map.get(value, unquote(details_field)) || %{}
            else
              %{}
            end

          FnTypes.Error.new(unquote(type), unquote(code),
            message: Keyword.get(opts, :message, message),
            details: details,
            source: unquote(module),
            recoverable: unquote(recoverable),
            stacktrace: Keyword.get(opts, :stacktrace),
            context: Keyword.get(opts, :context, %{}),
            step: Keyword.get(opts, :step)
          )
        end

        defp default_message do
          unquote("#{inspect(module)} error")
        end
      end
    end
  end

  # Derive a code from the module name (compile-time safe)
  defp derive_code(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  # Safe atom conversion - tries existing atoms first, falls back with limit
  defp safe_to_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      # Limit to reasonable error code length to prevent abuse
      if String.length(string) <= 64 and string =~ ~r/^[a-z_][a-z0-9_]*$/ do
        String.to_atom(string)
      else
        :unknown
      end
  end

  # Handle exceptions (structs with __exception__: true)
  def normalize(%{__struct__: struct_module, __exception__: true} = exception, opts) do
    message =
      try do
        Exception.message(exception)
      rescue
        _ -> "#{inspect(struct_module)} exception"
      end

    {type, code} = classify_exception(struct_module)

    Error.new(type, code,
      message: Keyword.get(opts, :message, message),
      source: struct_module,
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Handle regular structs (last resort)
  def normalize(%{__struct__: struct_module} = value, opts) do
    message = extract_message(value) || "#{inspect(struct_module)} error"

    Error.new(:internal, :unknown_struct_error,
      message: Keyword.get(opts, :message, message),
      details: %{struct: struct_module, value: safe_inspect(value)},
      source: struct_module,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Handle maps (non-structs)
  def normalize(%{} = map, opts) do
    message = Map.get(map, :message) || Map.get(map, "message") || "Unknown error"
    code = Map.get(map, :code) || Map.get(map, "code") || :unknown

    code_atom =
      case code do
        c when is_atom(c) -> c
        c when is_binary(c) -> safe_to_atom(c)
        _ -> :unknown
      end

    Error.new(:internal, code_atom,
      message: Keyword.get(opts, :message, message),
      details: Map.drop(map, [:message, :code, "message", "code"]),
      source: :map,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Handle tuples (like {:error, reason})
  def normalize({:error, reason}, opts) do
    normalize(reason, opts)
  end

  def normalize(tuple, opts) when is_tuple(tuple) do
    Error.new(:internal, :tuple_error,
      message: Keyword.get(opts, :message, "Tuple error: #{safe_inspect(tuple)}"),
      details: %{tuple: safe_inspect(tuple)},
      source: :tuple,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Handle atoms (common error reasons)
  def normalize(atom, opts) when is_atom(atom) do
    {type, code, message, recoverable} = map_atom(atom)

    Error.new(type, code,
      message: Keyword.get(opts, :message, message),
      source: :atom,
      recoverable: recoverable,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Handle binaries/strings
  def normalize(binary, opts) when is_binary(binary) do
    Error.new(:internal, :string_error,
      message: binary,
      source: :string,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Fallback for any other type
  def normalize(value, opts) do
    Error.new(:internal, :unknown_error,
      message: Keyword.get(opts, :message, "Unknown error: #{safe_inspect(value)}"),
      details: %{value: safe_inspect(value), type: type_of(value)},
      source: :unknown,
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  # Classify well-known exception types
  defp classify_exception(ArgumentError), do: {:validation, :argument_error}
  defp classify_exception(ArithmeticError), do: {:internal, :arithmetic_error}
  defp classify_exception(BadArityError), do: {:internal, :bad_arity}
  defp classify_exception(BadFunctionError), do: {:internal, :bad_function}
  defp classify_exception(BadMapError), do: {:internal, :bad_map}
  defp classify_exception(BadStructError), do: {:internal, :bad_struct}
  defp classify_exception(CaseClauseError), do: {:internal, :case_clause_error}
  defp classify_exception(CondClauseError), do: {:internal, :cond_clause_error}
  defp classify_exception(FunctionClauseError), do: {:internal, :function_clause_error}
  defp classify_exception(KeyError), do: {:internal, :key_error}
  defp classify_exception(MatchError), do: {:internal, :match_error}
  defp classify_exception(Protocol.UndefinedError), do: {:internal, :protocol_undefined}
  defp classify_exception(RuntimeError), do: {:internal, :runtime_error}
  defp classify_exception(SystemLimitError), do: {:external, :system_limit}
  defp classify_exception(UndefinedFunctionError), do: {:internal, :undefined_function}
  defp classify_exception(WithClauseError), do: {:internal, :with_clause_error}

  # Timeout-related exceptions
  defp classify_exception(module) do
    module_name = to_string(module)

    cond do
      module_name =~ ~r/Timeout/i -> {:timeout, :timeout_exception}
      module_name =~ ~r/Connection/i -> {:network, :connection_exception}
      module_name =~ ~r/Auth/i -> {:unauthorized, :auth_exception}
      module_name =~ ~r/NotFound/i -> {:not_found, :not_found_exception}
      module_name =~ ~r/Validation/i -> {:validation, :validation_exception}
      module_name =~ ~r/Permission|Forbidden/i -> {:forbidden, :permission_exception}
      true -> {:internal, :exception}
    end
  end

  # Map common atom error reasons
  defp map_atom(:not_found),
    do: {:not_found, :not_found, "Resource not found", false}

  defp map_atom(:unauthorized),
    do: {:unauthorized, :unauthorized, "Unauthorized", false}

  defp map_atom(:forbidden),
    do: {:forbidden, :forbidden, "Forbidden", false}

  defp map_atom(:timeout),
    do: {:timeout, :timeout, "Operation timed out", true}

  defp map_atom(:conflict),
    do: {:conflict, :conflict, "Resource conflict", false}

  defp map_atom(:invalid),
    do: {:validation, :invalid, "Invalid input", false}

  defp map_atom(:validation_failed),
    do: {:validation, :validation_failed, "Validation failed", false}

  defp map_atom(:bad_request),
    do: {:bad_request, :bad_request, "Bad request", false}

  defp map_atom(:rate_limited),
    do: {:rate_limited, :rate_limited, "Rate limited", true}

  defp map_atom(:service_unavailable),
    do: {:external, :service_unavailable, "Service unavailable", true}

  defp map_atom(:internal_error),
    do: {:internal, :internal_error, "Internal error", false}

  defp map_atom(:already_exists),
    do: {:conflict, :already_exists, "Resource already exists", false}

  defp map_atom(:stale),
    do: {:conflict, :stale, "Resource is stale", true}

  defp map_atom(:cancelled),
    do: {:internal, :cancelled, "Operation cancelled", false}

  defp map_atom(:network_error),
    do: {:network, :network_error, "Network error", true}

  defp map_atom(atom),
    do: {:internal, atom, "Error: #{atom}", false}

  # Extract message from struct if possible
  defp extract_message(%{message: message}) when is_binary(message), do: message
  defp extract_message(%{reason: reason}) when is_binary(reason), do: reason
  defp extract_message(%{error: error}) when is_binary(error), do: error
  defp extract_message(_), do: nil

  # Safe inspect that won't crash on weird values
  defp safe_inspect(value) do
    try do
      inspect(value, limit: 100, printable_limit: 200)
    rescue
      _ -> "<<uninspectable>>"
    end
  end

  # Get the type of a value
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(value) when is_binary(value), do: :binary
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_tuple(value), do: :tuple
  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_pid(value), do: :pid
  defp type_of(value) when is_reference(value), do: :reference
  defp type_of(value) when is_function(value), do: :function
  defp type_of(value) when is_port(value), do: :port
  defp type_of(_), do: :unknown
end
