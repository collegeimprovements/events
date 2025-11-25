defmodule Events.Query.SyntaxConverter do
  @moduledoc false
  # Utility module for debugging/tooling - not part of primary public API.
  #
  # Convert between Pipeline and DSL syntax styles.
  # Useful for tooling, debugging, and code generation.

  alias Events.Query.Token

  @doc """
  Convert a query token to DSL macro syntax.

  Returns a formatted string containing the equivalent DSL code.

  ## Examples

      token = User
        |> Query.new()
        |> Query.filter(:status, :eq, "active")
        |> Query.filter(:age, :gte, 18)
        |> Query.order(:name, :asc)
        |> Query.limit(10)

      SyntaxConverter.token_to_dsl(token, User)
      # =>
      # query User do
      #   filter(:status, :eq, "active")
      #   filter(:age, :gte, 18)
      #   order(:name, :asc)
      #   limit(10)
      # end
  """
  @spec token_to_dsl(Token.t(), module() | atom()) :: String.t()
  def token_to_dsl(%Token{operations: operations}, schema_name) do
    body =
      operations
      |> Enum.map(&operation_to_dsl/1)
      |> Enum.join("\n")
      |> indent(2)

    """
    query #{inspect(schema_name)} do
    #{body}
    end
    """
  end

  @doc """
  Convert a query token to pipeline syntax.

  Returns a formatted string containing the equivalent pipeline code.

  ## Examples

      token = query User do
        filter(:status, :eq, "active")
        filter(:age, :gte, 18)
        order(:name, :asc)
        limit(10)
      end

      SyntaxConverter.token_to_pipeline(token, User)
      # =>
      # User
      # |> Query.new()
      # |> Query.filter(:status, :eq, "active")
      # |> Query.filter(:age, :gte, 18)
      # |> Query.order(:name, :asc)
      # |> Query.limit(10)
  """
  @spec token_to_pipeline(Token.t(), module() | atom()) :: String.t()
  def token_to_pipeline(%Token{operations: operations}, schema_name) do
    pipeline_ops =
      operations
      |> Enum.map(&operation_to_pipeline/1)
      |> Enum.join("\n")

    """
    #{inspect(schema_name)}
    |> Query.new()
    #{pipeline_ops}
    """
  end

  @doc """
  Convert a dynamic builder spec to DSL syntax.

  ## Examples

      spec = %{
        filters: [
          {:filter, :status, :eq, "active", []},
          {:filter, :age, :gte, 18, []}
        ],
        orders: [
          {:order, :created_at, :desc, []}
        ],
        pagination: {:paginate, :offset, %{limit: 20, offset: 0}, []}
      }

      SyntaxConverter.spec_to_dsl(spec, User)
  """
  @spec spec_to_dsl(map(), module() | atom()) :: String.t()
  def spec_to_dsl(spec, schema_name) do
    body =
      []
      |> add_spec_filters(spec[:filters])
      |> add_spec_orders(spec[:orders])
      |> add_spec_joins(spec[:joins])
      |> add_spec_preloads(spec[:preloads])
      |> add_spec_select(spec[:select])
      |> add_spec_group_by(spec[:group_by])
      |> add_spec_having(spec[:having])
      |> add_spec_distinct(spec[:distinct])
      |> add_spec_limit(spec[:limit])
      |> add_spec_offset(spec[:offset])
      |> add_spec_pagination(spec[:pagination])
      |> Enum.join("\n")
      |> indent(2)

    """
    query #{inspect(schema_name)} do
    #{body}
    end
    """
  end

  @doc """
  Convert a dynamic builder spec to pipeline syntax.
  """
  @spec spec_to_pipeline(map(), module() | atom()) :: String.t()
  def spec_to_pipeline(spec, schema_name) do
    pipeline =
      []
      |> add_spec_filters_pipeline(spec[:filters])
      |> add_spec_orders_pipeline(spec[:orders])
      |> add_spec_joins_pipeline(spec[:joins])
      |> add_spec_preloads_pipeline(spec[:preloads])
      |> add_spec_select_pipeline(spec[:select])
      |> add_spec_group_by_pipeline(spec[:group_by])
      |> add_spec_having_pipeline(spec[:having])
      |> add_spec_distinct_pipeline(spec[:distinct])
      |> add_spec_limit_pipeline(spec[:limit])
      |> add_spec_offset_pipeline(spec[:offset])
      |> add_spec_pagination_pipeline(spec[:pagination])
      |> Enum.join("\n")

    """
    #{inspect(schema_name)}
    |> Query.new()
    #{pipeline}
    """
  end

  # Convert individual operations to DSL syntax
  defp operation_to_dsl({:filter, {field, op, value, opts}}) do
    if opts == [] do
      "filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)})"
    else
      "filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)}, #{inspect(opts)})"
    end
  end

  defp operation_to_dsl({:order, {field, direction, opts}}) do
    if opts == [] do
      "order(#{inspect(field)}, #{inspect(direction)})"
    else
      "order(#{inspect(field)}, #{inspect(direction)}, #{inspect(opts)})"
    end
  end

  defp operation_to_dsl({:limit, value}) do
    "limit(#{value})"
  end

  defp operation_to_dsl({:offset, value}) do
    "offset(#{value})"
  end

  defp operation_to_dsl({:paginate, {type, opts}}) do
    "paginate(#{inspect(type)}, #{format_keyword_list(opts)})"
  end

  defp operation_to_dsl({:join, {assoc, type, opts}}) do
    if opts == [] do
      "join(#{inspect(assoc)}, #{inspect(type)})"
    else
      "join(#{inspect(assoc)}, #{inspect(type)}, #{inspect(opts)})"
    end
  end

  defp operation_to_dsl({:preload, {assoc, nil}}) do
    "preload(#{inspect(assoc)})"
  end

  defp operation_to_dsl({:preload, {assoc, fun}}) when is_function(fun) do
    "preload(#{inspect(assoc)}) do\n  # Nested query operations\nend"
  end

  defp operation_to_dsl({:preload, assoc}) when is_atom(assoc) do
    "preload(#{inspect(assoc)})"
  end

  defp operation_to_dsl({:preload, list}) when is_list(list) do
    "preload(#{inspect(list)})"
  end

  defp operation_to_dsl({:select, fields}) do
    "select(#{inspect(fields)})"
  end

  defp operation_to_dsl({:group_by, fields}) do
    "group_by(#{inspect(fields)})"
  end

  defp operation_to_dsl({:having, conditions}) do
    "having(#{inspect(conditions)})"
  end

  defp operation_to_dsl({:distinct, value}) do
    "distinct(#{inspect(value)})"
  end

  defp operation_to_dsl({:lock, mode}) do
    "lock(#{inspect(mode)})"
  end

  defp operation_to_dsl(op) do
    "# Unsupported operation: #{inspect(op)}"
  end

  # Convert individual operations to pipeline syntax
  defp operation_to_pipeline({:filter, {field, op, value, opts}}) do
    if opts == [] do
      "|> Query.filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)})"
    else
      "|> Query.filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)}, #{inspect(opts)})"
    end
  end

  defp operation_to_pipeline({:order, {field, direction, opts}}) do
    if opts == [] do
      "|> Query.order(#{inspect(field)}, #{inspect(direction)})"
    else
      "|> Query.order(#{inspect(field)}, #{inspect(direction)}, #{inspect(opts)})"
    end
  end

  defp operation_to_pipeline({:limit, value}) do
    "|> Query.limit(#{value})"
  end

  defp operation_to_pipeline({:offset, value}) do
    "|> Query.offset(#{value})"
  end

  defp operation_to_pipeline({:paginate, {type, opts}}) do
    "|> Query.paginate(#{inspect(type)}, #{format_keyword_list(opts)})"
  end

  defp operation_to_pipeline({:join, {assoc, type, opts}}) do
    if opts == [] do
      "|> Query.join(#{inspect(assoc)}, #{inspect(type)})"
    else
      "|> Query.join(#{inspect(assoc)}, #{inspect(type)}, #{inspect(opts)})"
    end
  end

  defp operation_to_pipeline({:preload, {assoc, nil}}) do
    "|> Query.preload(#{inspect(assoc)})"
  end

  defp operation_to_pipeline({:preload, {assoc, fun}}) when is_function(fun) do
    "|> Query.preload(#{inspect(assoc)}, fn token -> token end)"
  end

  defp operation_to_pipeline({:preload, assoc}) when is_atom(assoc) do
    "|> Query.preload(#{inspect(assoc)})"
  end

  defp operation_to_pipeline({:preload, list}) when is_list(list) do
    "|> Query.preload(#{inspect(list)})"
  end

  defp operation_to_pipeline({:select, fields}) do
    "|> Query.select(#{inspect(fields)})"
  end

  defp operation_to_pipeline({:group_by, fields}) do
    "|> Query.group_by(#{inspect(fields)})"
  end

  defp operation_to_pipeline({:having, conditions}) do
    "|> Query.having(#{inspect(conditions)})"
  end

  defp operation_to_pipeline({:distinct, value}) do
    "|> Query.distinct(#{inspect(value)})"
  end

  defp operation_to_pipeline({:lock, mode}) do
    "|> Query.lock(#{inspect(mode)})"
  end

  defp operation_to_pipeline(op) do
    "|> # Unsupported operation: #{inspect(op)}"
  end

  # Spec to DSL helpers
  defp add_spec_filters(lines, nil), do: lines
  defp add_spec_filters(lines, []), do: lines

  defp add_spec_filters(lines, filters) when is_list(filters) do
    filter_lines =
      Enum.map(filters, fn
        {:filter, field, op, value, []} ->
          "filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)})"

        {:filter, field, op, value, opts} ->
          "filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)}, #{inspect(opts)})"
      end)

    lines ++ filter_lines
  end

  defp add_spec_orders(lines, nil), do: lines
  defp add_spec_orders(lines, []), do: lines

  defp add_spec_orders(lines, orders) when is_list(orders) do
    order_lines =
      Enum.map(orders, fn
        {:order, field, direction, []} ->
          "order(#{inspect(field)}, #{inspect(direction)})"

        {:order, field, direction, opts} ->
          "order(#{inspect(field)}, #{inspect(direction)}, #{inspect(opts)})"
      end)

    lines ++ order_lines
  end

  defp add_spec_joins(lines, nil), do: lines
  defp add_spec_joins(lines, []), do: lines

  defp add_spec_joins(lines, joins) when is_list(joins) do
    join_lines =
      Enum.map(joins, fn
        {:join, assoc, type, []} ->
          "join(#{inspect(assoc)}, #{inspect(type)})"

        {:join, assoc, type, opts} ->
          "join(#{inspect(assoc)}, #{inspect(type)}, #{inspect(opts)})"
      end)

    lines ++ join_lines
  end

  defp add_spec_preloads(lines, nil), do: lines
  defp add_spec_preloads(lines, []), do: lines

  defp add_spec_preloads(lines, preloads) when is_list(preloads) do
    preload_lines =
      Enum.map(preloads, fn
        {:preload, assoc, nil, _opts} ->
          "preload(#{inspect(assoc)})"

        {:preload, assoc, nested_spec, _opts} when is_map(nested_spec) ->
          nested = format_nested_spec(nested_spec)
          "preload(#{inspect(assoc)}) do\n#{indent(nested, 2)}\nend"
      end)

    lines ++ preload_lines
  end

  defp add_spec_select(lines, nil), do: lines
  defp add_spec_select(lines, select), do: lines ++ ["select(#{inspect(select)})"]

  defp add_spec_group_by(lines, nil), do: lines
  defp add_spec_group_by(lines, group), do: lines ++ ["group_by(#{inspect(group)})"]

  defp add_spec_having(lines, nil), do: lines
  defp add_spec_having(lines, having), do: lines ++ ["having(#{inspect(having)})"]

  defp add_spec_distinct(lines, nil), do: lines
  defp add_spec_distinct(lines, distinct), do: lines ++ ["distinct(#{inspect(distinct)})"]

  defp add_spec_limit(lines, nil), do: lines
  defp add_spec_limit(lines, limit), do: lines ++ ["limit(#{limit})"]

  defp add_spec_offset(lines, nil), do: lines
  defp add_spec_offset(lines, offset), do: lines ++ ["offset(#{offset})"]

  defp add_spec_pagination(lines, nil), do: lines

  defp add_spec_pagination(lines, {:paginate, type, config, _opts}) do
    opts_str =
      config
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> Enum.join(", ")

    lines ++ ["paginate(#{inspect(type)}, #{opts_str})"]
  end

  # Spec to pipeline helpers
  defp add_spec_filters_pipeline(lines, nil), do: lines
  defp add_spec_filters_pipeline(lines, []), do: lines

  defp add_spec_filters_pipeline(lines, filters) when is_list(filters) do
    filter_lines =
      Enum.map(filters, fn
        {:filter, field, op, value, []} ->
          "|> Query.filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)})"

        {:filter, field, op, value, opts} ->
          "|> Query.filter(#{inspect(field)}, #{inspect(op)}, #{format_value(value)}, #{inspect(opts)})"
      end)

    lines ++ filter_lines
  end

  defp add_spec_orders_pipeline(lines, nil), do: lines
  defp add_spec_orders_pipeline(lines, []), do: lines

  defp add_spec_orders_pipeline(lines, orders) when is_list(orders) do
    order_lines =
      Enum.map(orders, fn
        {:order, field, direction, []} ->
          "|> Query.order(#{inspect(field)}, #{inspect(direction)})"

        {:order, field, direction, opts} ->
          "|> Query.order(#{inspect(field)}, #{inspect(direction)}, #{inspect(opts)})"
      end)

    lines ++ order_lines
  end

  defp add_spec_joins_pipeline(lines, nil), do: lines
  defp add_spec_joins_pipeline(lines, []), do: lines

  defp add_spec_joins_pipeline(lines, joins) when is_list(joins) do
    join_lines =
      Enum.map(joins, fn
        {:join, assoc, type, []} ->
          "|> Query.join(#{inspect(assoc)}, #{inspect(type)})"

        {:join, assoc, type, opts} ->
          "|> Query.join(#{inspect(assoc)}, #{inspect(type)}, #{inspect(opts)})"
      end)

    lines ++ join_lines
  end

  defp add_spec_preloads_pipeline(lines, nil), do: lines
  defp add_spec_preloads_pipeline(lines, []), do: lines

  defp add_spec_preloads_pipeline(lines, preloads) when is_list(preloads) do
    preload_lines =
      Enum.map(preloads, fn
        {:preload, assoc, nil, _opts} ->
          "|> Query.preload(#{inspect(assoc)})"

        {:preload, assoc, _nested_spec, _opts} ->
          "|> Query.preload(#{inspect(assoc)}, fn token -> token end)"
      end)

    lines ++ preload_lines
  end

  defp add_spec_select_pipeline(lines, nil), do: lines

  defp add_spec_select_pipeline(lines, select) do
    lines ++ ["|> Query.select(#{inspect(select)})"]
  end

  defp add_spec_group_by_pipeline(lines, nil), do: lines

  defp add_spec_group_by_pipeline(lines, group) do
    lines ++ ["|> Query.group_by(#{inspect(group)})"]
  end

  defp add_spec_having_pipeline(lines, nil), do: lines

  defp add_spec_having_pipeline(lines, having) do
    lines ++ ["|> Query.having(#{inspect(having)})"]
  end

  defp add_spec_distinct_pipeline(lines, nil), do: lines

  defp add_spec_distinct_pipeline(lines, distinct) do
    lines ++ ["|> Query.distinct(#{inspect(distinct)})"]
  end

  defp add_spec_limit_pipeline(lines, nil), do: lines

  defp add_spec_limit_pipeline(lines, limit) do
    lines ++ ["|> Query.limit(#{limit})"]
  end

  defp add_spec_offset_pipeline(lines, nil), do: lines

  defp add_spec_offset_pipeline(lines, offset) do
    lines ++ ["|> Query.offset(#{offset})"]
  end

  defp add_spec_pagination_pipeline(lines, nil), do: lines

  defp add_spec_pagination_pipeline(lines, {:paginate, type, config, _opts}) do
    opts_str =
      config
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> Enum.join(", ")

    lines ++ ["|> Query.paginate(#{inspect(type)}, #{opts_str})"]
  end

  # Formatting helpers
  defp format_value({:param, key}), do: "{:param, #{inspect(key)}}"
  defp format_value(value), do: inspect(value)

  defp format_keyword_list(list) do
    list
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp format_nested_spec(spec) when is_map(spec) do
    []
    |> add_spec_filters(spec[:filters])
    |> add_spec_orders(spec[:orders])
    |> add_spec_joins(spec[:joins])
    |> add_spec_preloads(spec[:preloads])
    |> add_spec_limit(spec[:limit])
    |> add_spec_offset(spec[:offset])
    |> add_spec_pagination(spec[:pagination])
    |> Enum.join("\n")
  end

  defp indent(string, spaces) do
    padding = String.duplicate(" ", spaces)

    string
    |> String.split("\n")
    |> Enum.map(&(padding <> &1))
    |> Enum.join("\n")
  end
end
