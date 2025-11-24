defmodule Events.Query.Token do
  @moduledoc """
  Composable query token using pipeline pattern.

  Tokens are immutable and compose through a list of operations.
  Each operation is validated and optimized before execution.
  """

  alias __MODULE__

  @type operation ::
          {:filter, {atom(), atom(), term(), keyword()}}
          | {:paginate, {:offset | :cursor, keyword()}}
          | {:order, {atom(), :asc | :desc}}
          | {:join, {atom() | module(), atom(), keyword()}}
          | {:preload, term()}
          | {:select, list() | map()}
          | {:group_by, atom() | list()}
          | {:having, keyword()}
          | {:limit, pos_integer()}
          | {:offset, non_neg_integer()}
          | {:distinct, boolean() | list()}
          | {:lock, String.t() | atom()}
          | {:cte, {atom(), Token.t() | Ecto.Query.t()}}
          | {:window, {atom(), keyword()}}
          | {:raw_where, {String.t(), map()}}

  @type t :: %__MODULE__{
          source: module() | Ecto.Query.t() | :nested,
          operations: [operation()],
          metadata: map()
        }

  @enforce_keys [:source]
  defstruct source: nil,
            operations: [],
            metadata: %{}

  @doc "Create a new token from a schema or query"
  @spec new(module() | Ecto.Query.t() | :nested) :: t()
  def new(source) do
    %Token{source: source}
  end

  @doc "Add an operation to the token"
  @spec add_operation(t(), operation()) :: t()
  def add_operation(%Token{} = token, operation) when is_tuple(operation) do
    # Validate operation
    case validate_operation(operation) do
      :ok ->
        %{token | operations: token.operations ++ [operation]}

      {:error, reason} ->
        raise ArgumentError, "Invalid operation: #{reason}"
    end
  end

  @doc "Get all operations of a specific type"
  @spec get_operations(t(), atom()) :: [operation()]
  def get_operations(%Token{operations: ops}, type) do
    Enum.filter(ops, fn {op_type, _} -> op_type == type end)
  end

  @doc "Remove operations of a specific type"
  @spec remove_operations(t(), atom()) :: t()
  def remove_operations(%Token{operations: ops} = token, type) do
    filtered_ops = Enum.reject(ops, fn {op_type, _} -> op_type == type end)
    %{token | operations: filtered_ops}
  end

  @doc "Update token metadata"
  @spec put_metadata(t(), atom(), term()) :: t()
  def put_metadata(%Token{metadata: meta} = token, key, value) do
    %{token | metadata: Map.put(meta, key, value)}
  end

  # Operation validation using pattern matching
  defp validate_operation({:filter, {field, op, _value, opts}})
       when is_atom(field) and is_atom(op) and is_list(opts) do
    validate_filter_operation(op)
  end

  defp validate_operation({:paginate, {type, opts}})
       when type in [:offset, :cursor] and is_list(opts) do
    validate_pagination_opts(type, opts)
  end

  defp validate_operation({:order, {field, dir, opts}})
       when is_atom(field) and dir in [:asc, :desc] and is_list(opts) do
    :ok
  end

  defp validate_operation({:join, {_assoc_or_schema, type, opts}})
       when type in [:inner, :left, :right, :full, :cross] and is_list(opts) do
    :ok
  end

  defp validate_operation({:preload, _}), do: :ok
  defp validate_operation({:select, fields}) when is_list(fields) or is_map(fields), do: :ok
  defp validate_operation({:group_by, fields}) when is_atom(fields) or is_list(fields), do: :ok
  defp validate_operation({:having, conditions}) when is_list(conditions), do: :ok
  defp validate_operation({:limit, n}) when is_integer(n) and n > 0, do: :ok
  defp validate_operation({:offset, n}) when is_integer(n) and n >= 0, do: :ok
  defp validate_operation({:distinct, value}) when is_boolean(value) or is_list(value), do: :ok
  defp validate_operation({:lock, mode}) when is_atom(mode) or is_binary(mode), do: :ok
  defp validate_operation({:cte, {name, _query}}) when is_atom(name), do: :ok
  defp validate_operation({:window, {name, def}}) when is_atom(name) and is_list(def), do: :ok

  defp validate_operation({:raw_where, {sql, params}})
       when is_binary(sql) and is_map(params),
       do: :ok

  defp validate_operation(op), do: {:error, "Unknown operation: #{inspect(op)}"}

  # Validate filter operations
  @valid_filter_ops [
    :eq,
    :neq,
    :gt,
    :gte,
    :lt,
    :lte,
    :in,
    :not_in,
    :like,
    :ilike,
    :is_nil,
    :not_nil,
    :between,
    :contains,
    :jsonb_contains,
    :jsonb_has_key
  ]

  defp validate_filter_operation(op) when op in @valid_filter_ops, do: :ok
  defp validate_filter_operation(op), do: {:error, "Invalid filter operation: #{op}"}

  # Validate pagination options
  defp validate_pagination_opts(:offset, opts) do
    cond do
      Keyword.has_key?(opts, :limit) and is_integer(opts[:limit]) and opts[:limit] > 0 -> :ok
      true -> {:error, "Offset pagination requires :limit option"}
    end
  end

  defp validate_pagination_opts(:cursor, opts) do
    cond do
      Keyword.has_key?(opts, :cursor_fields) and is_list(opts[:cursor_fields]) -> :ok
      true -> {:error, "Cursor pagination requires :cursor_fields option"}
    end
  end
end
