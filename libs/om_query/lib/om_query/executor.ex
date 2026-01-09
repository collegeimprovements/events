defmodule OmQuery.Executor do
  @moduledoc false
  # Internal module - use OmQuery public API instead.
  #
  # Executes queries with production features:
  # - Telemetry integration
  # - Optional caching
  # - Batch execution
  # - Streaming support
  # - Timeout handling
  # - Total count computation

  import Ecto.Query
  alias OmQuery.{Token, Builder, Result}

  @default_timeout 15_000

  # Configurable defaults - can be overridden via application config
  # config :om_query, default_repo: MyApp.Repo, telemetry_prefix: [:my_app, :query]
  @default_repo Application.compile_env(:om_query, :default_repo, nil)
  @telemetry_prefix Application.compile_env(:om_query, :telemetry_prefix, [:om_query])

  @doc """
  Execute a query token and return result or error tuple.

  Returns `{:ok, result}` on success or `{:error, error}` on failure.
  This is the safe variant that never raises exceptions.

  For the raising variant, use `execute!/2`.

  ## Examples

      case OmQuery.execute(token) do
        {:ok, res} ->
          IO.puts("Got \#{length(res.data)} records")
        {:error, error} ->
          Logger.error("Query failed: \#{Exception.message(error)}")
      end
  """
  @spec execute(Token.t(), keyword()) :: {:ok, Result.t()} | {:error, Exception.t()}
  def execute(%Token{} = token, opts \\ []) do
    {:ok, execute!(token, opts)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Execute a query token and return structured result.

  Raises exceptions on failure. For a safe variant that returns tuples,
  use `execute/2`.

  ## Examples

      result = OmQuery.execute!(token)
      IO.puts("Got \#{length(result.data)} records")
  """
  @spec execute!(Token.t(), keyword()) :: Result.t()
  def execute!(%Token{} = token, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    repo = get_repo(opts)
    timeout = opts[:timeout] || @default_timeout
    include_total = opts[:include_total_count] || false

    # Emit telemetry start event
    emit_telemetry_start(token, opts)

    try do
      # Ensure safe limits for queries without pagination
      token = ensure_safe_limits(token, opts)

      # Build query
      query = Builder.build(token)

      # Execute query
      query_start = System.monotonic_time(:microsecond)
      data = repo.all(query, timeout: timeout)
      query_time = System.monotonic_time(:microsecond) - query_start

      # Compute total count if requested
      total_count = maybe_compute_total(include_total, has_pagination?(token), query, repo, timeout)

      # Build result
      total_time = System.monotonic_time(:microsecond) - start_time

      result =
        Result.paginated(data,
          pagination_type: get_pagination_type(token),
          limit: get_limit(token),
          offset: get_offset(token),
          cursor_fields: get_cursor_fields(token),
          after_cursor: get_after_cursor(token),
          before_cursor: get_before_cursor(token),
          total_count: total_count,
          query_time_μs: query_time,
          total_time_μs: total_time,
          operation_count: length(token.operations),
          sql: get_sql(repo, query)
        )

      # Emit telemetry stop event
      emit_telemetry_stop(token, result, opts)

      result
    rescue
      e ->
        total_time = System.monotonic_time(:microsecond) - start_time
        emit_telemetry_exception(token, e, total_time, opts)
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Execute query and return a stream for large datasets.

  Streams process records in batches without loading all into memory.
  Useful for exports, migrations, and processing large datasets.

  ## Options

  - `:repo` - Repo to use (default: configured default_repo)
  - `:max_rows` - Batch size for streaming (default: 500)

  ## Warning

  Streams should be used within a transaction for consistent reads.
  Consider adding a limit or pagination for bounded result sets.

  ## Examples

      # Basic streaming
      token
      |> OmQuery.stream()
      |> Stream.each(&process_record/1)
      |> Stream.run()

      # With transaction for consistency
      Repo.transaction(fn ->
        token
        |> OmQuery.stream(max_rows: 1000)
        |> Stream.each(&process_record/1)
        |> Stream.run()
      end)
  """
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  def stream(%Token{} = token, opts \\ []) do
    repo = get_repo(opts)
    max_rows = opts[:max_rows] || 500

    # Warn if query has no limits - potential for large result sets
    unless has_pagination?(token) or has_explicit_limit?(token) do
      require Logger

      Logger.warning("""
      Stream executed without pagination or limit.
      This may load large amounts of data. Consider:
      1. Adding pagination: OmQuery.paginate(token, :cursor, limit: 1000)
      2. Adding explicit limit: OmQuery.limit(token, 10000)
      3. Using max_rows option to control batch size (current: #{max_rows})
      """)
    end

    query = Builder.build(token)
    repo.stream(query, max_rows: max_rows)
  end

  @doc """
  Execute multiple queries in parallel batch.

  Returns a list of results in the same order as input tokens.
  Each result is `{:ok, result}` or `{:error, exception}`, allowing
  partial failures without crashing the entire batch.

  ## Options

  - `:timeout` - Timeout per query in ms (default: 15000)
  - All options from `execute/2`

  ## Examples

      tokens = [
        User |> OmQuery.new() |> OmQuery.filter(:active, :eq, true),
        Post |> OmQuery.new() |> OmQuery.limit(10)
      ]

      results = OmQuery.batch(tokens)

      Enum.each(results, fn
        {:ok, result} -> IO.puts("Got \#{length(result.data)} records")
        {:error, error} -> IO.puts("Query failed: \#{Exception.message(error)}")
      end)
  """
  @spec batch([Token.t()], keyword()) :: [{:ok, Result.t()} | {:error, Exception.t()}]
  def batch(tokens, opts \\ []) when is_list(tokens) do
    timeout = opts[:timeout] || @default_timeout

    # Execute all queries in parallel using Task
    # Each task returns {:ok, result} or {:error, exception}
    tasks =
      Enum.map(tokens, fn token ->
        Task.async(fn ->
          try do
            execute(token, opts)
          rescue
            e -> {:error, e}
          end
        end)
      end)

    # Collect results maintaining order
    Enum.map(tasks, &Task.await(&1, timeout))
  end

  ## Helpers

  @doc false
  @spec ensure_safe_limits(Token.t(), keyword()) :: Token.t()
  defp ensure_safe_limits(%Token{} = token, opts) do
    do_ensure_safe_limits(token, opts[:unsafe], opts)
  end

  # Unsafe mode - skip all limit checks
  defp do_ensure_safe_limits(token, true, _opts), do: token

  # Safe mode - check for pagination or limit
  defp do_ensure_safe_limits(token, _unsafe, opts) do
    case {has_pagination?(token), has_explicit_limit?(token)} do
      {true, _} -> token
      {_, true} -> token
      {false, false} -> apply_safe_limit(token, opts)
    end
  end

  defp apply_safe_limit(token, opts) do
    require Logger
    safe_limit = opts[:default_limit] || Token.default_limit()

    Logger.warning("""
    Query executed without pagination or limit. Automatically limiting to #{safe_limit} records.

    To fix this warning:
    1. Add pagination: OmQuery.paginate(token, :cursor, limit: 20)
    2. Add explicit limit: OmQuery.limit(token, 100)
    3. Use streaming: OmQuery.stream(token) for large datasets
    4. Pass unsafe: true if you really need all records
    """)

    Token.add_operation(token, {:limit, safe_limit})
  end

  defp has_pagination?(%Token{operations: ops}) do
    Enum.any?(ops, fn {op, _} -> op == :paginate end)
  end

  defp has_explicit_limit?(%Token{operations: ops}) do
    Enum.any?(ops, fn {op, _} -> op == :limit end)
  end

  # Unified pagination info extraction
  # Single helper reduces code duplication across 6+ functions

  defp get_pagination_info(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {type, opts}} -> {type, opts}
      _ -> {nil, []}
    end
  end

  defp get_pagination_type(token) do
    {type, _opts} = get_pagination_info(token)
    type
  end

  defp get_limit(%Token{operations: ops} = token) do
    {_type, opts} = get_pagination_info(token)

    case opts[:limit] do
      nil ->
        # Fallback to explicit limit operation
        case Enum.find(ops, fn {op, _} -> op == :limit end) do
          {:limit, value} -> value
          _ -> nil
        end

      limit ->
        limit
    end
  end

  defp get_offset(token) do
    case get_pagination_info(token) do
      {:offset, opts} -> opts[:offset] || 0
      _ -> 0
    end
  end

  defp get_cursor_fields(token) do
    case get_pagination_info(token) do
      {:cursor, opts} -> opts[:cursor_fields]
      _ -> nil
    end
  end

  defp get_after_cursor(token) do
    case get_pagination_info(token) do
      {:cursor, opts} -> opts[:after]
      _ -> nil
    end
  end

  defp get_before_cursor(token) do
    case get_pagination_info(token) do
      {:cursor, opts} -> opts[:before]
      _ -> nil
    end
  end

  defp build_count_query(query) do
    # Remove limit, offset, order_by for count
    query
    |> exclude(:limit)
    |> exclude(:offset)
    |> exclude(:order_by)
    |> exclude(:preload)
    |> exclude(:select)
  end

  defp maybe_compute_total(true, true, query, repo, timeout) do
    query
    |> build_count_query()
    |> repo.aggregate(:count, timeout: timeout)
  end

  defp maybe_compute_total(_include_total, _has_pagination, _query, _repo, _timeout), do: nil

  defp get_sql(repo, query) do
    try do
      {sql, _params} = repo.to_sql(:all, query)
      sql
    rescue
      _ -> nil
    end
  end

  ## Telemetry
  #
  # Telemetry events emitted (prefix configurable via :om_query, :telemetry_prefix):
  # - [prefix, :start] - Query execution starting
  # - [prefix, :stop] - Query execution completed
  # - [prefix, :exception] - Query execution failed
  #
  # Metadata includes filter context for debugging slow queries.

  defp emit_telemetry_start(token, opts) do
    do_emit_telemetry_start(token, opts, opts[:telemetry])
  end

  defp do_emit_telemetry_start(_token, _opts, false), do: :ok

  defp do_emit_telemetry_start(token, opts, _enabled) do
    {filter_summary, filter_count} = extract_filter_context(token)

    :telemetry.execute(
      @telemetry_prefix ++ [:start],
      %{system_time: System.system_time()},
      %{
        source: token.source,
        operation_count: length(token.operations),
        filter_count: filter_count,
        filters: filter_summary,
        has_pagination: has_pagination?(token),
        has_joins: has_joins?(token),
        opts: opts
      }
    )
  end

  defp emit_telemetry_stop(token, result, opts) do
    do_emit_telemetry_stop(token, result, opts, opts[:telemetry])
  end

  defp do_emit_telemetry_stop(_token, _result, _opts, false), do: :ok

  defp do_emit_telemetry_stop(token, result, opts, _enabled) do
    {filter_summary, filter_count} = extract_filter_context(token)

    :telemetry.execute(
      @telemetry_prefix ++ [:stop],
      %{
        duration: result.metadata.total_time_μs * 1000,
        query_time: result.metadata.query_time_μs * 1000
      },
      %{
        source: token.source,
        operation_count: length(token.operations),
        result_count: length(result.data || []),
        filter_count: filter_count,
        filters: filter_summary,
        has_pagination: has_pagination?(token),
        opts: opts
      }
    )
  end

  # Extract filter context for telemetry (field:operator format, no values for security)
  defp extract_filter_context(%Token{operations: ops}) do
    filters =
      ops
      |> Enum.filter(fn {op, _} -> op == :filter end)
      |> Enum.map(fn {:filter, {field, op, _value, _opts}} -> "#{field}:#{op}" end)

    {filters, length(filters)}
  end

  defp has_joins?(%Token{operations: ops}) do
    Enum.any?(ops, fn {op, _} -> op == :join end)
  end

  defp emit_telemetry_exception(token, exception, duration, opts) do
    do_emit_telemetry_exception(token, exception, duration, opts, opts[:telemetry])
  end

  defp do_emit_telemetry_exception(_token, _exception, _duration, _opts, false), do: :ok

  defp do_emit_telemetry_exception(token, exception, duration, opts, _enabled) do
    :telemetry.execute(
      @telemetry_prefix ++ [:exception],
      %{duration: duration * 1000},
      %{
        source: token.source,
        operation_count: length(token.operations),
        kind: :error,
        reason: exception,
        opts: opts
      }
    )
  end

  # Helper to get repo from opts or configured default
  defp get_repo(opts) do
    opts[:repo] || @default_repo ||
      raise "No repo configured. Pass :repo option or configure default_repo: config :om_query, default_repo: MyApp.Repo"
  end

  # ============================================================================
  # Batch Operations (update_all, delete_all)
  # ============================================================================

  @doc """
  Execute a batch update on all records matching the query filters.

  Returns `{:ok, {count, returning}}` on success or `{:error, reason}` on failure.

  ## Update Operations

  Supports Ecto's update operations:
  - `:set` - Set field(s) to value(s)
  - `:inc` - Increment numeric field(s) by value(s)
  - `:push` - Append value(s) to array field(s)
  - `:pull` - Remove value(s) from array field(s)

  ## Options

  - `:repo` - Ecto repo to use (default: configured)
  - `:timeout` - Query timeout in ms (default: 15000)
  - `:returning` - Fields to return (e.g., `[:id, :status]` or `true` for all)
  - `:prefix` - Database schema prefix for multi-tenant apps

  ## Examples

      # Set status to archived for inactive users
      User
      |> OmQuery.filter(:status, :eq, "inactive")
      |> OmQuery.filter(:last_login, :lt, one_year_ago)
      |> OmQuery.update_all(set: [status: "archived"])
      #=> {:ok, {42, nil}}

      # Increment retry count
      Job
      |> OmQuery.filter(:status, :eq, "failed")
      |> OmQuery.update_all(inc: [retry_count: 1])

      # With returning
      User
      |> OmQuery.filter(:id, :in, user_ids)
      |> OmQuery.update_all([set: [verified: true]], returning: [:id, :email])
      #=> {:ok, {3, [%{id: 1, email: "a@b.com"}, ...]}}

      # Multiple operations
      Product
      |> OmQuery.filter(:category, :eq, "electronics")
      |> OmQuery.update_all(set: [on_sale: true], inc: [view_count: 1])
  """
  @spec update_all(Token.t(), keyword(), keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  def update_all(%Token{} = token, updates, opts \\ []) when is_list(updates) do
    {:ok, update_all!(token, updates, opts)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Execute a batch update. Raises on failure.

  See `update_all/3` for documentation.
  """
  @spec update_all!(Token.t(), keyword(), keyword()) :: {non_neg_integer(), nil | [map()]}
  def update_all!(%Token{} = token, updates, opts \\ []) when is_list(updates) do
    repo = get_repo(opts)
    timeout = opts[:timeout] || @default_timeout

    # Build the base query from token (filters, joins only - no select, order, pagination)
    query = build_update_query(token)

    # Build repo options
    repo_opts =
      opts
      |> Keyword.take([:returning, :prefix])
      |> Keyword.put(:timeout, timeout)

    # Execute update_all
    repo.update_all(query, updates, repo_opts)
  end

  @doc """
  Execute a batch delete on all records matching the query filters.

  Returns `{:ok, {count, returning}}` on success or `{:error, reason}` on failure.

  ## Options

  - `:repo` - Ecto repo to use (default: configured)
  - `:timeout` - Query timeout in ms (default: 15000)
  - `:returning` - Fields to return (e.g., `[:id]` or `true` for all)
  - `:prefix` - Database schema prefix for multi-tenant apps

  ## Examples

      # Delete old soft-deleted records
      User
      |> OmQuery.filter(:deleted_at, :not_nil, true)
      |> OmQuery.filter(:deleted_at, :lt, one_year_ago)
      |> OmQuery.delete_all()
      #=> {:ok, {15, nil}}

      # Delete with returning
      Session
      |> OmQuery.filter(:expires_at, :lt, DateTime.utc_now())
      |> OmQuery.delete_all(returning: [:id, :user_id])
      #=> {:ok, {100, [%{id: 1, user_id: 5}, ...]}}

      # Delete from joined query
      Post
      |> OmQuery.join(:inner, :user, on: [id: :user_id])
      |> OmQuery.filter(:status, :eq, "banned", binding: :user)
      |> OmQuery.delete_all()
  """
  @spec delete_all(Token.t(), keyword()) ::
          {:ok, {non_neg_integer(), nil | [map()]}} | {:error, term()}
  def delete_all(%Token{} = token, opts \\ []) do
    {:ok, delete_all!(token, opts)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Execute a batch delete. Raises on failure.

  See `delete_all/2` for documentation.
  """
  @spec delete_all!(Token.t(), keyword()) :: {non_neg_integer(), nil | [map()]}
  def delete_all!(%Token{} = token, opts \\ []) do
    repo = get_repo(opts)
    timeout = opts[:timeout] || @default_timeout

    # Build the base query from token (filters, joins only)
    query = build_delete_query(token)

    # Build repo options
    repo_opts =
      opts
      |> Keyword.take([:returning, :prefix])
      |> Keyword.put(:timeout, timeout)

    # Execute delete_all
    repo.delete_all(query, repo_opts)
  end

  # Build a query suitable for update_all (only where/join clauses)
  defp build_update_query(%Token{} = token) do
    # Remove operations not supported by update_all
    cleaned_token = clean_token_for_bulk(token)
    Builder.build(cleaned_token)
  end

  # Build a query suitable for delete_all (only where/join clauses)
  defp build_delete_query(%Token{} = token) do
    # Remove operations not supported by delete_all
    cleaned_token = clean_token_for_bulk(token)
    Builder.build(cleaned_token)
  end

  # Remove operations not allowed in update_all/delete_all
  # Ecto only allows where and join expressions for bulk operations
  defp clean_token_for_bulk(%Token{} = token) do
    allowed_ops = [:filter, :filter_group, :join, :raw_where, :field_compare]

    cleaned_ops =
      Enum.filter(token.operations, fn {op, _} ->
        op in allowed_ops
      end)

    %{token | operations: cleaned_ops}
  end

  # ============================================================================
  # Query Plan Analysis (EXPLAIN)
  # ============================================================================

  @doc """
  Get the execution plan for a query without running it.

  Returns `{:ok, plan}` on success or `{:error, reason}` on failure.

  ## PostgreSQL Options

  | Option | Type | Description |
  |--------|------|-------------|
  | `:analyze` | boolean | Execute query and show actual times (default: false) |
  | `:verbose` | boolean | Show additional details |
  | `:costs` | boolean | Show estimated costs (default: true) |
  | `:buffers` | boolean | Show buffer usage (requires analyze) |
  | `:timing` | boolean | Show timing info (requires analyze) |
  | `:summary` | boolean | Show summary statistics |
  | `:format` | atom | Output format: `:text`, `:yaml`, or `:map` |

  ## Examples

      # Basic plan
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain()
      #=> {:ok, "Seq Scan on users  (cost=0.00..12.00 rows=1 width=100)\\n  Filter: (status = 'active')"}

      # With analyze (executes the query)
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(analyze: true)
      #=> {:ok, "Seq Scan on users  (cost=0.00..12.00 rows=1 width=100) (actual time=0.01..0.01 rows=0 loops=1)"}

      # As structured map
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(format: :map)
      #=> {:ok, [%{"Plan" => %{"Node Type" => "Seq Scan", ...}}]}

      # Full analysis with buffers
      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain(analyze: true, buffers: true, timing: true)

  ## Safety Note

  When `analyze: true`, the query is actually executed (in a rolled-back transaction).
  Use with caution on production databases with expensive queries.
  """
  @spec explain(Token.t(), keyword()) :: {:ok, String.t() | list(map())} | {:error, term()}
  def explain(%Token{} = token, opts) do
    {:ok, explain!(token, opts)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Get the execution plan for a query. Raises on failure.

  See `explain/2` for documentation.
  """
  @spec explain!(Token.t(), keyword()) :: String.t() | list(map())
  def explain!(%Token{} = token, opts) do
    repo = get_repo(opts)

    # Build query from token
    query = Builder.build(token)

    # Split our options from explain options
    {our_opts, explain_opts} = Keyword.split(opts, [:repo, :timeout])
    timeout = our_opts[:timeout] || @default_timeout

    # Add timeout to explain options
    explain_opts = Keyword.put(explain_opts, :timeout, timeout)

    # Call repo.explain
    repo.explain(:all, query, explain_opts)
  end

  @doc """
  Print the execution plan to stdout and return the token unchanged.

  Useful for debugging in pipelines without breaking the chain.

  ## Examples

      User
      |> OmQuery.filter(:status, :eq, "active")
      |> OmQuery.explain_to_stdout(analyze: true)
      |> OmQuery.execute()

      # Prints:
      # ┌─────────────────────────────────────────────────────────┐
      # │ EXPLAIN ANALYZE                                         │
      # ├─────────────────────────────────────────────────────────┤
      # │ Seq Scan on users  (cost=0.00..12.00 rows=1 width=100) │
      # │   Filter: (status = 'active')                          │
      # └─────────────────────────────────────────────────────────┘
  """
  @spec explain_to_stdout(Token.t(), keyword()) :: Token.t()
  def explain_to_stdout(%Token{} = token, opts) do
    case explain(token, opts) do
      {:ok, plan} ->
        header = if opts[:analyze], do: "EXPLAIN ANALYZE", else: "EXPLAIN"
        IO.puts("")
        IO.puts("┌─ #{header} " <> String.duplicate("─", 50))
        IO.puts("│")

        plan
        |> to_string()
        |> String.split("\n")
        |> Enum.each(fn line -> IO.puts("│ #{line}") end)

        IO.puts("│")
        IO.puts("└" <> String.duplicate("─", 55))
        IO.puts("")

      {:error, error} ->
        IO.puts("EXPLAIN ERROR: #{inspect(error)}")
    end

    token
  end
end
