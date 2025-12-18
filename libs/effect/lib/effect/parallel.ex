defmodule Effect.Parallel do
  @moduledoc """
  Concurrent execution for Effect steps.

  Runs multiple steps in parallel using `Task.async_stream` with configurable
  failure handling and result merging.

  ## Failure Modes

  - `:fail_fast` (default) - Stop on first failure, trigger rollback
  - `:continue` - Wait for all, collect errors, trigger rollback if any failed

  ## Result Merging

  Results are merged left-to-right by declaration order. Last writer wins
  for duplicate keys.

  ## Example

      Effect.parallel(effect, :checks, [
        {:fraud, &check_fraud/1},
        {:inventory, &check_inventory/1}
      ], after: :validate, on_error: :fail_fast)
  """

  alias Effect.{Context, Step}

  @type on_error :: :fail_fast | :continue
  @type parallel_opts :: [
          on_error: on_error(),
          timeout: pos_integer(),
          max_concurrency: pos_integer()
        ]

  @default_timeout 30_000
  @default_max_concurrency System.schedulers_online() * 2

  @doc """
  Executes multiple step functions in parallel.

  Returns `{:ok, merged_results, step_results}` or `{:error, failed_step, reason, completed_steps}`.

  ## Options

  - `:on_error` - `:fail_fast` (default) or `:continue`
  - `:timeout` - Per-step timeout in ms (default: 30_000)
  - `:max_concurrency` - Max concurrent tasks (default: schedulers * 2)
  """
  @spec execute([{atom(), Step.step_fun()}], map(), map(), parallel_opts()) ::
          {:ok, map(), [{atom(), map()}]}
          | {:error, atom(), term(), [{atom(), map()}]}
  def execute(steps, ctx, services, opts \\ []) do
    on_error = Keyword.get(opts, :on_error, :fail_fast)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)

    # Snapshot context for all parallel steps
    snapshot = Context.snapshot(ctx)

    # Execute all steps concurrently
    results =
      steps
      |> Task.async_stream(
        fn {name, fun} ->
          result = execute_step(fun, snapshot, services)
          {name, result}
        end,
        timeout: timeout,
        max_concurrency: max_concurrency,
        ordered: true
      )
      |> Enum.to_list()

    # Process results based on error handling mode
    process_results(results, on_error)
  end

  # Execute a single step function
  defp execute_step(fun, ctx, _services) when is_function(fun, 1) do
    try do
      fun.(ctx)
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  defp execute_step(fun, ctx, services) when is_function(fun, 2) do
    try do
      fun.(ctx, services)
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  # Process results based on error mode
  defp process_results(results, :fail_fast) do
    process_fail_fast(results, [], [])
  end

  defp process_results(results, :continue) do
    process_continue(results, [], [])
  end

  # Fail-fast: stop at first error
  defp process_fail_fast([], completed, _errors) do
    # All succeeded - merge results
    merged = merge_results(completed)
    {:ok, merged, completed}
  end

  defp process_fail_fast([{:ok, {name, {:ok, result}}} | rest], completed, errors)
       when is_map(result) do
    process_fail_fast(rest, completed ++ [{name, result}], errors)
  end

  defp process_fail_fast([{:ok, {name, {:error, reason}}} | _rest], completed, _errors) do
    {:error, name, reason, completed}
  end

  defp process_fail_fast([{:ok, {name, nil}} | rest], completed, errors) do
    # Treat nil as {:ok, %{}}
    process_fail_fast(rest, completed ++ [{name, %{}}], errors)
  end

  defp process_fail_fast([{:ok, {name, other}} | _rest], completed, _errors) do
    {:error, name, {:invalid_step_return, other}, completed}
  end

  defp process_fail_fast([{:exit, reason} | _rest], completed, _errors) do
    {:error, :unknown, {:task_exit, reason}, completed}
  end

  # Continue mode: collect all results, then decide
  defp process_continue([], completed, []) do
    # All succeeded
    merged = merge_results(completed)
    {:ok, merged, completed}
  end

  defp process_continue([], completed, [{name, reason} | _]) do
    # Some failed - return first error
    {:error, name, reason, completed}
  end

  defp process_continue([{:ok, {name, {:ok, result}}} | rest], completed, errors)
       when is_map(result) do
    process_continue(rest, completed ++ [{name, result}], errors)
  end

  defp process_continue([{:ok, {name, {:error, reason}}} | rest], completed, errors) do
    process_continue(rest, completed, errors ++ [{name, reason}])
  end

  defp process_continue([{:ok, {name, nil}} | rest], completed, errors) do
    process_continue(rest, completed ++ [{name, %{}}], errors)
  end

  defp process_continue([{:ok, {name, other}} | rest], completed, errors) do
    process_continue(rest, completed, errors ++ [{name, {:invalid_step_return, other}}])
  end

  defp process_continue([{:exit, reason} | rest], completed, errors) do
    process_continue(rest, completed, errors ++ [{:unknown, {:task_exit, reason}}])
  end

  # Merge results in declaration order (last writer wins)
  defp merge_results(step_results) do
    Enum.reduce(step_results, %{}, fn {_name, result}, acc ->
      Map.merge(acc, result)
    end)
  end
end
