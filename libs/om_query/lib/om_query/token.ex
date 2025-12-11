defmodule OmQuery.Token do
  @moduledoc false
  # Internal module - use OmQuery public API instead.
  #
  # Composable query token using pipeline pattern.
  # Tokens are immutable and compose through a list of operations.
  # Each operation is validated and optimized before execution.
  #
  # Configuration:
  # - :default_limit - Default limit for pagination (default: 20)
  # - :max_limit - Maximum allowed limit (default: 1000)
  #
  # Configure in config.exs:
  #     config :events, OmQuery.Token,
  #       default_limit: 50,
  #       max_limit: 5000

  alias __MODULE__
  alias OmQuery.{ValidationError, LimitExceededError, PaginationError}

  @default_limit 20
  @default_max_limit 1000

  @type filter_spec :: {atom(), atom(), term(), keyword()}

  @type operation ::
          {:filter, filter_spec()}
          | {:filter_group, {:or | :and, [filter_spec()]}}
          | {:paginate, {:offset | :cursor, keyword()}}
          | {:order, {atom(), :asc | :desc, keyword()}}
          | {:join, {atom() | module(), atom(), keyword()}}
          | {:preload, term()}
          | {:select, list() | map()}
          | {:group_by, atom() | list()}
          | {:having, keyword()}
          | {:limit, pos_integer()}
          | {:offset, non_neg_integer()}
          | {:distinct, boolean() | list()}
          | {:lock, String.t() | atom()}
          | {:cte, {atom(), Token.t() | Ecto.Query.t(), keyword()}}
          | {:window, {atom(), keyword()}}
          | {:raw_where, {String.t(), map()}}
          | {:exists, Token.t() | Ecto.Query.t()}
          | {:not_exists, Token.t() | Ecto.Query.t()}
          | {:search_rank, {list(), String.t()}}
          | {:search_rank_limited, {list(), String.t()}}
          | {:field_compare, {atom(), atom(), atom(), keyword()}}

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

  @doc """
  Add an operation to the token (safe variant).

  Returns `{:ok, token}` on success or `{:error, exception}` on validation failure.
  Use this when you want to handle errors gracefully with pattern matching.

  For the raising variant, use `add_operation!/2`.

  ## Examples

      case Token.add_operation_safe(token, {:filter, {:status, :eq, "active", []}}) do
        {:ok, updated_token} -> updated_token
        {:error, %ValidationError{} = error} -> handle_error(error)
      end
  """
  @spec add_operation_safe(t(), operation()) :: {:ok, t()} | {:error, Exception.t()}
  def add_operation_safe(%Token{} = token, operation) when is_tuple(operation) do
    case validate_operation(operation) do
      :ok ->
        {:ok, %{token | operations: token.operations ++ [operation]}}

      {:error, %LimitExceededError{} = error} ->
        {:error, error}

      {:error, %PaginationError{} = error} ->
        {:error, error}

      {:error, %OmQuery.FilterGroupError{} = error} ->
        {:error, error}

      {:error, reason} when is_binary(reason) ->
        {op_type, _} = operation

        {:error,
         %ValidationError{
           operation: op_type,
           reason: reason,
           value: operation,
           suggestion: nil
         }}
    end
  end

  @doc """
  Add an operation to the token (raising variant).

  Raises an exception on validation failure. This is the same as `add_operation/2`.

  For the safe variant that returns tuples, use `add_operation_safe/2`.

  ## Examples

      token = Token.add_operation!(token, {:filter, {:status, :eq, "active", []}})
  """
  @spec add_operation!(t(), operation()) :: t()
  def add_operation!(%Token{} = token, operation) when is_tuple(operation) do
    case add_operation_safe(token, operation) do
      {:ok, token} -> token
      {:error, error} -> raise error
    end
  end

  @doc """
  Add an operation to the token.

  Raises an exception on validation failure.
  This is an alias for `add_operation!/2` kept for backwards compatibility.

  For the safe variant that returns tuples, use `add_operation_safe/2`.
  """
  @spec add_operation(t(), operation()) :: t()
  def add_operation(%Token{} = token, operation) when is_tuple(operation) do
    add_operation!(token, operation)
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

  # Configurable limits - can be overridden via application config
  # config :events, OmQuery.Token, default_limit: 50, max_limit: 5000
  @configured_default_limit Application.compile_env(:om_query, [__MODULE__, :default_limit], @default_limit)
  @configured_max_limit Application.compile_env(:om_query, [__MODULE__, :max_limit], @default_max_limit)

  @doc "Get configured default limit"
  @spec default_limit() :: pos_integer()
  def default_limit, do: @configured_default_limit

  @doc "Get configured max limit"
  @spec max_limit() :: pos_integer()
  def max_limit, do: @configured_max_limit

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
       when is_atom(field) and
              dir in [
                :asc,
                :desc,
                :asc_nulls_first,
                :asc_nulls_last,
                :desc_nulls_first,
                :desc_nulls_last
              ] and
              is_list(opts) do
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

  defp validate_operation({:limit, n}) when is_integer(n) and n > 0 do
    validate_limit_bounds(n, max_limit())
  end

  defp validate_operation({:offset, n}) when is_integer(n) and n >= 0, do: :ok
  defp validate_operation({:distinct, value}) when is_boolean(value) or is_list(value), do: :ok
  defp validate_operation({:lock, mode}) when is_atom(mode) or is_binary(mode), do: :ok

  defp validate_operation({:cte, {name, _query, opts}}) when is_atom(name) and is_list(opts),
    do: :ok

  # Backwards compatibility - CTE without opts
  defp validate_operation({:cte, {name, _query}}) when is_atom(name), do: :ok
  defp validate_operation({:window, {name, def}}) when is_atom(name) and is_list(def), do: :ok

  defp validate_operation({:raw_where, {sql, params, opts}})
       when is_binary(sql) and (is_list(params) or is_map(params)) and is_list(opts),
       do: :ok

  # Backwards compatibility
  defp validate_operation({:raw_where, {sql, params}})
       when is_binary(sql) and (is_list(params) or is_map(params)),
       do: :ok

  defp validate_operation({:filter_group, {combinator, filters}})
       when combinator in [:or, :and, :not_or] and is_list(filters) do
    validate_filter_group(combinator, filters)
  end

  defp validate_operation({:exists, subquery})
       when is_struct(subquery, Token) or is_struct(subquery, Ecto.Query),
       do: :ok

  defp validate_operation({:not_exists, subquery})
       when is_struct(subquery, Token) or is_struct(subquery, Ecto.Query),
       do: :ok

  defp validate_operation({:search_rank, {fields, term}})
       when is_list(fields) and is_binary(term),
       do: :ok

  defp validate_operation({:search_rank_limited, {fields, term}})
       when is_list(fields) and is_binary(term),
       do: :ok

  @field_compare_ops [:eq, :neq, :gt, :gte, :lt, :lte]
  defp validate_operation({:field_compare, {field1, op, field2, opts}})
       when is_atom(field1) and is_atom(op) and is_atom(field2) and is_list(opts) do
    if op in @field_compare_ops do
      :ok
    else
      {:error,
       "Invalid field comparison operator: #{inspect(op)}. Valid: #{inspect(@field_compare_ops)}"}
    end
  end

  defp validate_operation(op), do: {:error, "Unknown operation: #{inspect(op)}"}

  # Limit bounds validation (separate from validate_operation)
  defp validate_limit_bounds(n, max) when n <= max, do: :ok

  defp validate_limit_bounds(n, max) do
    {:error,
     %LimitExceededError{
       requested: n,
       max_allowed: max,
       suggestion: "Use streaming for large datasets or increase config."
     }}
  end

  # Validate filter group has at least 2 filters and all are valid
  defp validate_filter_group(combinator, filters) when length(filters) < 2 do
    {:error,
     %OmQuery.FilterGroupError{
       combinator: combinator,
       filters: filters,
       reason: "Filter group requires at least 2 filters",
       suggestion: "Use where_any([{:field1, :eq, val1}, {:field2, :eq, val2}])"
     }}
  end

  defp validate_filter_group(_combinator, filters) do
    Enum.reduce_while(filters, :ok, fn filter, :ok ->
      case validate_filter_spec(filter) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_filter_spec({field, op, _value, opts})
       when is_atom(field) and is_atom(op) and is_list(opts) do
    validate_filter_operation(op)
  end

  defp validate_filter_spec({field, op, _value})
       when is_atom(field) and is_atom(op) do
    validate_filter_operation(op)
  end

  defp validate_filter_spec(spec) do
    {:error,
     "Invalid filter spec in group: #{inspect(spec)}. Expected {field, op, value} or {field, op, value, opts}"}
  end

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
    :in_subquery,
    :not_in_subquery,
    :like,
    :ilike,
    :not_like,
    :not_ilike,
    :is_nil,
    :not_nil,
    :between,
    :contains,
    :jsonb_contains,
    :jsonb_has_key,
    # Text search operators
    :similarity,
    :word_similarity,
    :strict_word_similarity
  ]

  defp validate_filter_operation(op) when op in @valid_filter_ops, do: :ok
  defp validate_filter_operation(op), do: {:error, "Invalid filter operation: #{op}"}

  # Validate pagination options
  defp validate_pagination_opts(:offset, opts) do
    limit = opts[:limit] || default_limit()
    max = max_limit()

    cond do
      not is_integer(limit) or limit <= 0 ->
        {:error,
         %PaginationError{
           type: :offset,
           reason: ":limit must be a positive integer, got: #{inspect(limit)}",
           order_by: nil,
           cursor_fields: nil,
           suggestion: "Provide a valid limit: paginate(:offset, limit: 20)"
         }}

      limit > max ->
        {:error,
         %LimitExceededError{
           requested: limit,
           max_allowed: max,
           suggestion: "Use streaming for large datasets or increase config."
         }}

      true ->
        :ok
    end
  end

  defp validate_pagination_opts(:cursor, opts) do
    # cursor_fields can be nil - will be inferred from order_by
    cursor_fields = opts[:cursor_fields]
    limit = opts[:limit] || default_limit()
    max = max_limit()

    cond do
      cursor_fields != nil and not is_list(cursor_fields) ->
        {:error,
         %PaginationError{
           type: :cursor,
           reason:
             ":cursor_fields must be a list or nil (will be inferred), got: #{inspect(cursor_fields)}",
           order_by: nil,
           cursor_fields: cursor_fields,
           suggestion:
             "Either remove cursor_fields (will be inferred from order_by) or provide a list: cursor_fields: [:id, :created_at]"
         }}

      not is_integer(limit) or limit <= 0 ->
        {:error,
         %PaginationError{
           type: :cursor,
           reason: ":limit must be a positive integer, got: #{inspect(limit)}",
           order_by: nil,
           cursor_fields: cursor_fields,
           suggestion: "Provide a valid limit: paginate(:cursor, limit: 20)"
         }}

      limit > max ->
        {:error,
         %LimitExceededError{
           requested: limit,
           max_allowed: max,
           suggestion: "Use streaming for large datasets or increase config."
         }}

      true ->
        :ok
    end
  end
end
