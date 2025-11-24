defmodule Events.Query.Executor do
  @moduledoc """
  Executes queries with production features.

  - Telemetry integration
  - Optional caching
  - Batch execution
  - Streaming support
  - Timeout handling
  - Total count computation
  """

  alias Events.Query.{Token, Builder, Result}

  @default_timeout 15_000
  @default_repo Events.Repo

  @doc "Execute a query token and return structured result"
  @spec execute(Token.t(), keyword()) :: Result.t()
  def execute(%Token{} = token, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    repo = opts[:repo] || @default_repo
    timeout = opts[:timeout] || @default_timeout
    include_total = opts[:include_total_count] || false

    # Emit telemetry start event
    emit_telemetry_start(token, opts)

    try do
      # Build query
      build_start = System.monotonic_time(:microsecond)
      query = Builder.build(token)
      build_time = System.monotonic_time(:microsecond) - build_start

      # Execute query
      query_start = System.monotonic_time(:microsecond)
      data = repo.all(query, timeout: timeout)
      query_time = System.monotonic_time(:microsecond) - query_start

      # Compute total count if requested
      total_count =
        if include_total && has_pagination?(token) do
          count_query = build_count_query(query)
          repo.one(from(q in subquery(count_query), select: count("*")), timeout: timeout)
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

  @doc "Execute query and return stream"
  @spec stream(Token.t(), keyword()) :: Enumerable.t()
  def stream(%Token{} = token, opts \\ []) do
    repo = opts[:repo] || @default_repo
    max_rows = opts[:max_rows] || 500

    query = Builder.build(token)
    repo.stream(query, max_rows: max_rows)
  end

  @doc "Execute multiple queries in batch"
  @spec batch([Token.t()], keyword()) :: [Result.t()]
  def batch(tokens, opts \\ []) when is_list(tokens) do
    # Execute all queries in parallel using Task
    tasks =
      Enum.map(tokens, fn token ->
        Task.async(fn -> execute(token, opts) end)
      end)

    # Collect results maintaining order
    Enum.map(tasks, &Task.await(&1, opts[:timeout] || @default_timeout))
  end

  ## Helpers

  defp has_pagination?(%Token{operations: ops}) do
    Enum.any?(ops, fn {op, _} -> op == :paginate end)
  end

  defp get_pagination_type(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {type, _opts}} -> type
      _ -> nil
    end
  end

  defp get_limit(%Token{operations: ops}) do
    # Check paginate operation first
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {_type, opts}} ->
        opts[:limit]

      _ ->
        # Check limit operation
        case Enum.find(ops, fn {op, _} -> op == :limit end) do
          {:limit, value} -> value
          _ -> nil
        end
    end
  end

  defp get_offset(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {:offset, opts}} -> opts[:offset] || 0
      _ -> 0
    end
  end

  defp get_cursor_fields(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {:cursor, opts}} -> opts[:cursor_fields]
      _ -> nil
    end
  end

  defp get_after_cursor(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {:cursor, opts}} -> opts[:after]
      _ -> nil
    end
  end

  defp get_before_cursor(%Token{operations: ops}) do
    case Enum.find(ops, fn {op, _} -> op == :paginate end) do
      {:paginate, {:cursor, opts}} -> opts[:before]
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

  defp emit_telemetry_start(token, opts) do
    if opts[:telemetry] != false do
      :telemetry.execute(
        [:events, :query, :start],
        %{system_time: System.system_time()},
        %{
          source: token.source,
          operation_count: length(token.operations),
          opts: opts
        }
      )
    end
  end

  defp emit_telemetry_stop(token, result, opts) do
    if opts[:telemetry] != false do
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
          opts: opts
        }
      )
    end
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
