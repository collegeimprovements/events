defmodule Events.Query.Executor do
  @moduledoc false
  # Internal module - use Events.Query public API instead.
  #
  # Executes queries with production features:
  # - Telemetry integration
  # - Optional caching
  # - Batch execution
  # - Streaming support
  # - Timeout handling
  # - Total count computation

  import Ecto.Query
  alias Events.Query.{Token, Builder, Result}

  @default_timeout 15_000
  @default_repo Events.Repo

  @doc """
  Execute a query token and return result or error tuple.

  Returns `{:ok, result}` on success or `{:error, error}` on failure.
  This is the safe variant that never raises exceptions.

  For the raising variant, use `execute!/2`.

  ## Examples

      case Query.execute(token) do
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

      result = Query.execute!(token)
      IO.puts("Got \#{length(result.data)} records")
  """
  @spec execute!(Token.t(), keyword()) :: Result.t()
  def execute!(%Token{} = token, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    repo = opts[:repo] || @default_repo
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
      total_count =
        if include_total && has_pagination?(token) do
          count_query = build_count_query(query)
          repo.aggregate(count_query, :count, timeout: timeout)
        end

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

  - `:repo` - Repo to use (default: Events.Repo)
  - `:max_rows` - Batch size for streaming (default: 500)

  ## Warning

  Streams should be used within a transaction for consistent reads.
  Consider adding a limit or pagination for bounded result sets.

  ## Examples

      # Basic streaming
      token
      |> Query.stream()
      |> Stream.each(&process_record/1)
      |> Stream.run()

      # With transaction for consistency
      Repo.transaction(fn ->
        token
        |> Query.stream(max_rows: 1000)
        |> Stream.each(&process_record/1)
        |> Stream.run()
      end)
  """
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  def stream(%Token{} = token, opts \\ []) do
    repo = opts[:repo] || @default_repo
    max_rows = opts[:max_rows] || 500

    # Warn if query has no limits - potential for large result sets
    unless has_pagination?(token) or has_explicit_limit?(token) do
      require Logger

      Logger.warning("""
      Stream executed without pagination or limit.
      This may load large amounts of data. Consider:
      1. Adding pagination: Query.paginate(token, :cursor, limit: 1000)
      2. Adding explicit limit: Query.limit(token, 10000)
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
        User |> Query.new() |> Query.filter(:active, :eq, true),
        Post |> Query.new() |> Query.limit(10)
      ]

      results = Query.batch(tokens)

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
    # Allow opt-out via unsafe: true option (for streaming, aggregations, etc.)
    if opts[:unsafe] do
      token
    else
      has_pagination = has_pagination?(token)
      has_limit = has_explicit_limit?(token)

      cond do
        # Already has pagination or explicit limit - safe
        has_pagination or has_limit ->
          token

        # No limiting at all - apply safe default
        true ->
          safe_limit = opts[:default_limit] || Token.default_limit()

          require Logger

          Logger.warning("""
          Query executed without pagination or limit. Automatically limiting to #{safe_limit} records.

          To fix this warning:
          1. Add pagination: Query.paginate(token, :cursor, limit: 20)
          2. Add explicit limit: Query.limit(token, 100)
          3. Use streaming: Query.stream(token) for large datasets
          4. Pass unsafe: true if you really need all records
          """)

          Token.add_operation(token, {:limit, safe_limit})
      end
    end
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
  # Telemetry events emitted:
  # - [:events, :query, :start] - Query execution starting
  # - [:events, :query, :stop] - Query execution completed
  # - [:events, :query, :exception] - Query execution failed
  #
  # Metadata includes filter context for debugging slow queries.

  defp emit_telemetry_start(token, opts) do
    if opts[:telemetry] != false do
      {filter_summary, filter_count} = extract_filter_context(token)

      :telemetry.execute(
        [:events, :query, :start],
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
  end

  defp emit_telemetry_stop(token, result, opts) do
    if opts[:telemetry] != false do
      {filter_summary, filter_count} = extract_filter_context(token)

      :telemetry.execute(
        [:events, :query, :stop],
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
    if opts[:telemetry] != false do
      :telemetry.execute(
        [:events, :query, :exception],
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
  end
end
