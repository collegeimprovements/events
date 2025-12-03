defimpl Events.Core.Crud.Executable, for: Events.Core.Query.Token do
  @moduledoc """
  Executable implementation for Query.Token.

  Allows Query tokens to be executed via `Crud.run/1`:

      User
      |> Query.new()
      |> Query.where(:active, true)
      |> Crud.run()
      # => {:ok, %Query.Result{data: [%User{}, ...]}}

  ## Options

  - `:repo` - Repository to use (default: Events.Core.Repo)
  - `:timeout` - Query timeout in milliseconds (default: 15_000)
  - `:include_total_count` - Include total count for pagination (default: false)

  ## Returns

  - `{:ok, %Query.Result{}}` - Success with query result
  - `{:error, exception}` - Failure with exception
  """

  alias Events.Core.Query.Executor

  @spec execute(Events.Core.Query.Token.t(), keyword()) ::
          {:ok, Events.Core.Query.Result.t()} | {:error, Exception.t()}
  def execute(token, opts \\ []) do
    Executor.execute(token, opts)
  end
end

defimpl Events.Core.Crud.Validatable, for: Events.Core.Query.Token do
  @moduledoc """
  Validatable implementation for Query.Token.

  Query tokens are validated at operation addition time, so this
  implementation performs a basic structural check.
  """

  alias Events.Core.Query.Token

  @spec validate(Token.t()) :: :ok | {:error, [String.t()]}
  def validate(%Token{source: source, operations: ops}) do
    errors = []

    errors =
      if is_nil(source) do
        ["source is required" | errors]
      else
        errors
      end

    errors =
      if not is_list(ops) do
        ["operations must be a list" | errors]
      else
        errors
      end

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end
end

defimpl Events.Core.Crud.Debuggable, for: Events.Core.Query.Token do
  @moduledoc """
  Debuggable implementation for Query.Token.

  Provides a structured debug representation for logging and introspection.
  """

  alias Events.Core.Query.Token

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

  defp format_operation({type, config}) do
    %{type: type, config: summarize_config(config)}
  end

  defp summarize_config({field, op, _value, opts}) when is_atom(field) and is_atom(op) do
    %{field: field, op: op, opts: opts}
  end

  defp summarize_config({type, opts}) when is_atom(type) and is_list(opts) do
    %{subtype: type, opts: Keyword.keys(opts)}
  end

  defp summarize_config(value) when is_atom(value), do: value
  defp summarize_config(value) when is_integer(value), do: value
  defp summarize_config(value) when is_list(value), do: {:list, length(value)}
  defp summarize_config(_), do: :complex
end
