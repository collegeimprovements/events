defmodule Events.Core.Query.Builder.Advanced do
  @moduledoc false
  # Internal module for Builder - advanced query features
  #
  # Handles lock, CTE, window functions, raw WHERE, and ordering operations.

  import Ecto.Query
  alias Events.Core.Query.Token

  ## Public API (for Builder)

  @doc """
  Apply ordering to a query.
  """
  @spec apply_order(Ecto.Query.t(), {atom(), :asc | :desc, keyword()}) :: Ecto.Query.t()
  def apply_order(query, {field, direction, opts}) do
    binding = opts[:binding] || :root
    from([{^binding, q}] in query, order_by: [{^direction, field(q, ^field)}])
  end

  @doc """
  Apply lock mode to a query.

  Supports common lock modes as atoms and custom SQL lock strings.
  """
  @spec apply_lock(Ecto.Query.t(), atom() | String.t()) :: Ecto.Query.t()
  def apply_lock(query, :update) do
    from(q in query, lock: "FOR UPDATE")
  end

  def apply_lock(query, :share) do
    from(q in query, lock: "FOR SHARE")
  end

  def apply_lock(query, :update_nowait) do
    from(q in query, lock: "FOR UPDATE NOWAIT")
  end

  def apply_lock(query, :update_skip_locked) do
    from(q in query, lock: "FOR UPDATE SKIP LOCKED")
  end

  def apply_lock(query, mode) when is_binary(mode) do
    # String lock mode - use as fragment
    from(q in query, lock: fragment(^mode))
  end

  def apply_lock(query, _mode) do
    # Unknown mode, skip
    query
  end

  @doc """
  Apply CTE (Common Table Expression) to a query.

  Supports Token, Ecto.Query, and raw SQL fragments as CTE sources.
  Supports recursive CTEs via options.
  """
  @spec apply_cte(Ecto.Query.t(), {atom(), any(), keyword()} | {atom(), any()}) :: Ecto.Query.t()
  def apply_cte(query, {name, cte_source, opts}) when is_list(opts) do
    query
    |> maybe_enable_recursive(Keyword.get(opts, :recursive, false))
    |> apply_cte_query(name, cte_source)
  end

  def apply_cte(query, {name, cte_source}) do
    apply_cte_query(query, name, cte_source)
  end

  @doc """
  Apply window definition to a query.

  Returns query unchanged - window definitions are informational.
  The generated SQL can be accessed via get_window_sql/2 for raw queries.
  """
  @spec apply_window(Ecto.Query.t(), {atom(), keyword()}) :: Ecto.Query.t()
  def apply_window(query, {name, definition}) when is_atom(name) and is_list(definition) do
    # Build the window SQL for reference (can be used in raw fragments)
    _window_sql = build_window_sql(name, definition)

    # Return query unchanged - window definitions are informational
    # Users who need window functions should use Ecto's native windows or raw fragments
    query
  end

  @doc """
  Generate window SQL clause string from a definition.

  This can be used to construct raw SQL queries with window functions.

  ## Example

      window_sql = Advanced.get_window_sql(:my_window, [
        partition_by: :category_id,
        order_by: [desc: :price],
        frame: {:rows, :unbounded_preceding, :current_row}
      ])
      # => "WINDOW my_window AS (PARTITION BY category_id ORDER BY price DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)"
  """
  @spec get_window_sql(atom(), keyword()) :: String.t()
  def get_window_sql(name, definition) when is_atom(name) and is_list(definition) do
    build_window_sql(name, definition)
  end

  @doc """
  Build a window function expression for use in select.

  Window functions return values computed across a set of rows related
  to the current row. The window is defined using `Query.window/3` and
  referenced by name in the select clause.

  ## Usage

  In select maps, use `{:window, func, over: :window_name}`:

      select(%{
        rank: {:window, :row_number, over: :w},
        running_total: {:window, {:sum, :amount}, over: :w}
      })

  ## Supported Functions

  - `:row_number` - Sequential row number
  - `:rank` - Rank with gaps for ties
  - `:dense_rank` - Rank without gaps
  - `{:sum, field}` - Sum of field over window
  - `{:avg, field}` - Average of field over window
  - `{:count, field}` - Count of field over window
  - `{:count}` - Count of all rows over window
  - `{:min, field}` - Minimum value over window
  - `{:max, field}` - Maximum value over window
  - `{:lag, field}` - Value from previous row
  - `{:lead, field}` - Value from next row
  - `{:first_value, field}` - First value in window frame
  - `{:last_value, field}` - Last value in window frame
  """
  def build_window_select_expr(func, window_name) when is_atom(window_name) do
    # Build the complete window function SQL using the window name reference
    # Since Ecto doesn't support dynamic window references, we use the
    # inline OVER clause syntax instead of named windows
    raise ArgumentError, """
    Dynamic window function references are not supported by Ecto's compile-time macros.

    For window functions, use one of these approaches:

    1. Use raw SQL with raw_where or raw select fragments:

       select(%{
         rank: fragment("ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY price DESC)")
       })

    2. Build the query directly with Ecto.Query macros:

       from(p in Product,
         windows: [w: [partition_by: :category_id, order_by: [desc: :price]]],
         select: %{name: p.name, rank: over(row_number(), :w)}
       )

    Window function: #{inspect(func)}
    Window name: #{inspect(window_name)}
    """
  end

  @doc """
  Apply raw WHERE clause with SQL fragment.

  Supports positional and named parameters.
  """
  @spec apply_raw_where(Ecto.Query.t(), {String.t(), list() | map()}) :: Ecto.Query.t()
  @spec apply_raw_where(Ecto.Query.t(), {String.t(), list(), keyword()}) :: Ecto.Query.t()
  def apply_raw_where(query, {sql, params, _opts}) when is_binary(sql) and is_list(params) do
    # Build fragment with positional parameters directly
    fragment_expr = build_fragment(sql, params)

    # Apply the where clause
    from(q in query, where: ^fragment_expr)
  end

  def apply_raw_where(query, {sql, params}) when is_binary(sql) and is_map(params) do
    # Convert named parameters to positional
    {positional_sql, positional_params} = convert_named_params_to_positional(sql, params)

    # Build fragment with positional parameters
    fragment_expr = build_fragment(positional_sql, positional_params)

    # Apply the where clause
    from(q in query, where: ^fragment_expr)
  end

  def apply_raw_where(query, {sql, params}) when is_binary(sql) and is_list(params) do
    fragment_expr = build_fragment(sql, params)
    from(q in query, where: ^fragment_expr)
  end

  ## Private Helpers

  defp maybe_enable_recursive(query, true), do: recursive_ctes(query, true)
  defp maybe_enable_recursive(query, false), do: query

  defp apply_cte_query(query, name, %Token{} = cte_token) do
    # Build the CTE query from the token - use runtime apply to avoid circular dependency
    cte_query = apply(Events.Core.Query.Builder, :build, [cte_token])

    # Apply the CTE using Ecto.Query.with_cte/3
    query |> with_cte(^name, as: ^cte_query)
  end

  defp apply_cte_query(query, name, %Ecto.Query{} = cte_query) do
    # Use the Ecto query directly as CTE
    query |> with_cte(^name, as: ^cte_query)
  end

  defp apply_cte_query(query, name, {:fragment, sql}) when is_binary(sql) do
    # Raw SQL fragment as CTE
    query |> with_cte(^name, as: fragment(^sql))
  end

  defp build_window_sql(name, definition) do
    window_body =
      []
      |> maybe_add_partition(definition[:partition_by])
      |> maybe_add_order(definition[:order_by])
      |> maybe_add_frame(definition[:frame])
      |> Enum.reverse()
      |> Enum.join(" ")

    "WINDOW #{name} AS (#{window_body})"
  end

  # Partition by clause helpers
  defp maybe_add_partition(parts, nil), do: parts
  defp maybe_add_partition(parts, field) when is_atom(field), do: ["PARTITION BY #{field}" | parts]

  defp maybe_add_partition(parts, fields) when is_list(fields) do
    field_str = Enum.map_join(fields, ", ", &Atom.to_string/1)
    ["PARTITION BY #{field_str}" | parts]
  end

  # Order by clause helpers
  defp maybe_add_order(parts, nil), do: parts
  defp maybe_add_order(parts, field) when is_atom(field), do: ["ORDER BY #{field} ASC" | parts]

  defp maybe_add_order(parts, orders) when is_list(orders) do
    order_str = Enum.map_join(orders, ", ", &format_order_clause/1)
    ["ORDER BY #{order_str}" | parts]
  end

  defp format_order_clause({dir, field}) when dir in [:asc, :desc] do
    "#{field} #{String.upcase(Atom.to_string(dir))}"
  end

  defp format_order_clause({field, dir}) when dir in [:asc, :desc] do
    "#{field} #{String.upcase(Atom.to_string(dir))}"
  end

  defp format_order_clause(field) when is_atom(field), do: "#{field} ASC"

  # Frame clause helper
  defp maybe_add_frame(parts, nil), do: parts
  defp maybe_add_frame(parts, frame_spec), do: [build_frame_sql(frame_spec) | parts]

  # Build SQL for window frame specification
  # Supports ROWS, RANGE, and GROUPS frame types
  #
  # Examples:
  #   {:rows, :unbounded_preceding, :current_row}
  #   {:range, {:preceding, 1}, {:following, 1}}
  #   {:groups, :current_row, :unbounded_following}
  defp build_frame_sql({frame_type, start_bound, end_bound})
       when frame_type in [:rows, :range, :groups] do
    type_str = frame_type |> Atom.to_string() |> String.upcase()
    start_str = build_frame_bound(start_bound)
    end_str = build_frame_bound(end_bound)
    "#{type_str} BETWEEN #{start_str} AND #{end_str}"
  end

  # Shorthand: just start bound (implies CURRENT ROW as end for ROWS/RANGE)
  defp build_frame_sql({frame_type, start_bound})
       when frame_type in [:rows, :range, :groups] do
    type_str = frame_type |> Atom.to_string() |> String.upcase()
    start_str = build_frame_bound(start_bound)
    "#{type_str} #{start_str}"
  end

  # Frame bound specifications
  defp build_frame_bound(:unbounded_preceding), do: "UNBOUNDED PRECEDING"
  defp build_frame_bound(:unbounded_following), do: "UNBOUNDED FOLLOWING"
  defp build_frame_bound(:current_row), do: "CURRENT ROW"
  defp build_frame_bound({:preceding, n}) when is_integer(n), do: "#{n} PRECEDING"
  defp build_frame_bound({:following, n}) when is_integer(n), do: "#{n} FOLLOWING"

  # Convert named parameters (:name) to positional (?)
  defp convert_named_params_to_positional(sql, params) do
    # Find all named parameters in order they appear
    param_names =
      Regex.scan(~r/:(\w+)/, sql)
      |> Enum.map(fn [_full, name] -> String.to_atom(name) end)

    # Replace named params with ?
    positional_sql = Regex.replace(~r/:(\w+)/, sql, "?")

    # Build positional params list in order
    positional_params = Enum.map(param_names, &Map.get(params, &1))

    {positional_sql, positional_params}
  end

  # Build a fragment dynamically with list of parameters
  # Note: SQL string must be passed as literal for security.
  # We use Code.eval_quoted to build the fragment at runtime
  defp build_fragment(sql, params) do
    # Build the fragment AST with the literal SQL and parameter list
    # Since fragment/1 is a macro, we need to construct the call properly
    param_asts = Enum.map(params, fn param -> quote do: ^unquote(Macro.escape(param)) end)

    fragment_ast =
      case param_asts do
        [] ->
          quote do: fragment(unquote(sql))

        [p1] ->
          quote do: fragment(unquote(sql), unquote(p1))

        [p1, p2] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2))

        [p1, p2, p3] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2), unquote(p3))

        [p1, p2, p3, p4] ->
          quote do: fragment(unquote(sql), unquote(p1), unquote(p2), unquote(p3), unquote(p4))

        [p1, p2, p3, p4, p5] ->
          quote do:
                  fragment(
                    unquote(sql),
                    unquote(p1),
                    unquote(p2),
                    unquote(p3),
                    unquote(p4),
                    unquote(p5)
                  )

        _ ->
          raise ArgumentError,
                "raw_where supports maximum 5 parameters, got #{length(params)}. " <>
                  "Consider using multiple where clauses or a custom fragment."
      end

    # Evaluate the AST to get the actual dynamic expression
    quoted =
      quote do
        Ecto.Query.dynamic([], unquote(fragment_ast))
      end

    {result, _} = Code.eval_quoted(quoted, [], __ENV__)
    result
  end
end
