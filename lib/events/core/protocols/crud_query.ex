# ─────────────────────────────────────────────────────────────
# Query → CRUD Protocol Implementations
# ─────────────────────────────────────────────────────────────
#
# This file implements OmCrud protocols for query tokens, enabling
# query tokens to be executed via `OmCrud.run/1`.
#
# These implementations must live in Events (not in libs) because:
# - OmQuery cannot depend on OmCrud (would create circular dependency)
# - Application layer is the correct place for library integration
#
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# OmQuery.Token Protocol Implementations
# Enables OmQuery tokens to work with OmCrud.run/1
# ─────────────────────────────────────────────────────────────

defimpl OmCrud.Executable, for: OmQuery.Token do
  @moduledoc """
  Executable implementation for OmQuery.Token.

  Allows OmQuery tokens to be executed via `OmCrud.run/1`:

      User
      |> OmQuery.new()
      |> OmQuery.filter(:active, :eq, true)
      |> OmCrud.run()
      # => {:ok, %OmQuery.Result{data: [%User{}, ...]}}
  """

  alias OmQuery.Executor

  @spec execute(OmQuery.Token.t(), keyword()) ::
          {:ok, OmQuery.Result.t()} | {:error, Exception.t()}
  def execute(token, opts \\ []) do
    Executor.execute(token, opts)
  end
end

defimpl OmCrud.Validatable, for: OmQuery.Token do
  @moduledoc "Validatable implementation for OmQuery.Token."

  alias OmQuery.Token

  @spec validate(Token.t()) :: :ok | {:error, [String.t()]}
  def validate(%Token{source: source, operations: ops}) do
    errors = []
    errors = if is_nil(source), do: ["source is required" | errors], else: errors
    errors = if not is_list(ops), do: ["operations must be a list" | errors], else: errors
    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end
end

defimpl OmCrud.Debuggable, for: OmQuery.Token do
  @moduledoc "Debuggable implementation for OmQuery.Token."

  alias OmQuery.Token

  @spec to_debug(Token.t()) :: map()
  def to_debug(%Token{source: source, operations: ops, metadata: meta}) do
    %{
      type: :query,
      source: format_source(source),
      operation_count: length(ops),
      operations: Enum.map(ops, &format_operation/1),
      metadata: meta
    }
  end

  defp format_source(source) when is_atom(source), do: source
  defp format_source(%Ecto.Query{}), do: :ecto_query
  defp format_source(:nested), do: :nested
  defp format_source(_), do: :unknown

  defp format_operation({type, config}), do: %{type: type, config: summarize_config(config)}

  defp summarize_config({field, op, _value, opts}) when is_atom(field) and is_atom(op),
    do: %{field: field, op: op, opts: opts}

  defp summarize_config({type, opts}) when is_atom(type) and is_list(opts),
    do: %{subtype: type, opts: Keyword.keys(opts)}

  defp summarize_config(value) when is_atom(value), do: value
  defp summarize_config(value) when is_integer(value), do: value
  defp summarize_config(value) when is_list(value), do: {:list, length(value)}
  defp summarize_config(_), do: :complex
end
