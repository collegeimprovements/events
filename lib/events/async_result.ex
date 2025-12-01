defmodule Events.AsyncResult do
  @moduledoc """
  Concurrent operations on Result types.

  Provides utilities for executing result-returning operations in parallel,
  with configurable concurrency, timeouts, and error handling strategies.

  ## Design Philosophy

  - **Fail-fast by default**: Returns first error encountered
  - **Configurable settlement**: Can collect all results (successes and failures)
  - **Bounded concurrency**: Controls resource usage with max_concurrency
  - **Timeout safety**: All operations have configurable timeouts
  - **Task supervision**: Uses `Task.Supervisor` for crash isolation

  ## Basic Usage

      # Execute multiple operations in parallel
      AsyncResult.parallel([
        fn -> fetch_user(1) end,
        fn -> fetch_user(2) end,
        fn -> fetch_user(3) end
      ])
      #=> {:ok, [user1, user2, user3]} | {:error, reason}

      # Map over items in parallel
      AsyncResult.parallel_map([1, 2, 3], fn id ->
        fetch_user(id)
      end)
      #=> {:ok, [user1, user2, user3]}

      # Race multiple alternatives
      AsyncResult.race([
        fn -> fetch_from_primary() end,
        fn -> fetch_from_replica() end
      ])
      #=> {:ok, first_success}

  ## Settlement Mode

      # Get all results, both successes and failures
      AsyncResult.parallel_settle([
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ])
      #=> %{
        ok: [1, 3],
        errors: [:bad],
        results: [{:ok, 1}, {:error, :bad}, {:ok, 3}]
      }

  ## Configuration

      AsyncResult.parallel(tasks,
        max_concurrency: 5,      # Limit concurrent tasks
        timeout: 5000,           # Per-task timeout in ms
        ordered: true,           # Preserve input order
        on_timeout: :error       # :error | :kill | {:default, value}
      )
  """

  alias Events.Result

  # ============================================
  # Types
  # ============================================

  @type task_fun(a) :: (-> Result.t(a, term()))
  @type task_fun_with_arg(a, b) :: (a -> Result.t(b, term()))

  @type settlement :: %{
          ok: [term()],
          errors: [term()],
          results: [Result.t()]
        }

  @type options :: [
          max_concurrency: pos_integer(),
          timeout: timeout(),
          ordered: boolean(),
          on_timeout: :error | :kill | {:default, term()},
          supervisor: atom() | pid()
        ]

  @default_timeout 5_000
  @default_max_concurrency System.schedulers_online() * 2

  # ============================================
  # Parallel Execution
  # ============================================

  @doc """
  Executes multiple result-returning functions in parallel.

  Returns `{:ok, values}` if all succeed, `{:error, first_error}` otherwise.
  Tasks are executed concurrently with bounded parallelism.

  ## Options

  - `:max_concurrency` - Maximum concurrent tasks (default: #{@default_max_concurrency})
  - `:timeout` - Per-task timeout in ms (default: #{@default_timeout})
  - `:ordered` - Preserve input order in results (default: true)
  - `:on_timeout` - How to handle timeouts: `:error`, `:kill`, or `{:default, value}`

  ## Examples

      AsyncResult.parallel([
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:ok, 3} end
      ])
      #=> {:ok, [1, 2, 3]}

      AsyncResult.parallel([
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ])
      #=> {:error, :bad}

      AsyncResult.parallel(tasks, max_concurrency: 5, timeout: 10_000)
  """
  @spec parallel([task_fun(a)], options()) :: Result.t([a], term()) when a: term()
  def parallel(tasks, opts \\ [])

  def parallel([], _opts), do: {:ok, []}

  def parallel(tasks, opts) when is_list(tasks) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)
    on_timeout = Keyword.get(opts, :on_timeout, :error)

    tasks
    |> indexed_if_ordered(ordered)
    |> Task.async_stream(
      fn task -> execute_task(task, ordered) end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: on_timeout_handler(on_timeout),
      ordered: ordered
    )
    |> collect_stream_results(ordered, on_timeout)
  end

  @doc """
  Maps a result-returning function over items in parallel.

  ## Examples

      AsyncResult.parallel_map([1, 2, 3], fn id ->
        case Repo.get(User, id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end
      end)
      #=> {:ok, [user1, user2, user3]}

      AsyncResult.parallel_map(ids, &fetch_user/1, max_concurrency: 10)
  """
  @spec parallel_map([a], task_fun_with_arg(a, b), options()) :: Result.t([b], term())
        when a: term(), b: term()
  def parallel_map(items, fun, opts \\ []) when is_list(items) and is_function(fun, 1) do
    tasks = Enum.map(items, fn item -> fn -> fun.(item) end end)
    parallel(tasks, opts)
  end

  @doc """
  Executes tasks in parallel, collecting all results.

  Unlike `parallel/2`, this does not fail-fast on errors.
  Returns a settlement map with all successes and failures.

  ## Examples

      AsyncResult.parallel_settle([
        fn -> {:ok, 1} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 3} end
      ])
      #=> %{
        ok: [1, 3],
        errors: [:bad],
        results: [{:ok, 1}, {:error, :bad}, {:ok, 3}]
      }
  """
  @spec parallel_settle([task_fun(term())], options()) :: settlement()
  def parallel_settle(tasks, opts \\ [])

  def parallel_settle([], _opts), do: %{ok: [], errors: [], results: []}

  def parallel_settle(tasks, opts) when is_list(tasks) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)

    results =
      tasks
      |> indexed_if_ordered(ordered)
      |> Task.async_stream(
        fn task -> execute_task(task, ordered) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: ordered
      )
      |> Enum.map(&extract_stream_result/1)
      |> maybe_reorder(ordered)

    settle_results(results)
  end

  @doc """
  Maps over items in parallel, settling all results.

  ## Examples

      AsyncResult.parallel_map_settle(ids, &fetch_user/1)
      #=> %{ok: [user1, user3], errors: [:not_found], results: [...]}
  """
  @spec parallel_map_settle([a], task_fun_with_arg(a, b), options()) :: settlement()
        when a: term(), b: term()
  def parallel_map_settle(items, fun, opts \\ []) when is_list(items) and is_function(fun, 1) do
    tasks = Enum.map(items, fn item -> fn -> fun.(item) end end)
    parallel_settle(tasks, opts)
  end

  # ============================================
  # Racing
  # ============================================

  @doc """
  Races multiple tasks, returning the first successful result.

  Cancels remaining tasks once a success is found.
  Returns error only if all tasks fail.

  ## Examples

      AsyncResult.race([
        fn -> fetch_from_cache() end,
        fn -> fetch_from_database() end,
        fn -> fetch_from_api() end
      ])
      #=> {:ok, first_success}

      # All fail
      AsyncResult.race([
        fn -> {:error, :cache_miss} end,
        fn -> {:error, :db_error} end
      ])
      #=> {:error, [:cache_miss, :db_error]}
  """
  @spec race([task_fun(a)], options()) :: Result.t(a, [term()]) when a: term()
  def race(tasks, opts \\ [])

  def race([], _opts), do: {:error, :no_tasks}

  def race(tasks, opts) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    parent = self()
    ref = make_ref()

    # Spawn all tasks
    task_refs =
      Enum.map(tasks, fn task ->
        Task.async(fn ->
          result = safe_execute(task)
          send(parent, {ref, self(), result})
          result
        end)
      end)

    # Wait for first success or all failures
    result = await_first_success(ref, task_refs, [], timeout)

    # Clean up remaining tasks
    Enum.each(task_refs, fn task ->
      Task.shutdown(task, :brutal_kill)
    end)

    result
  end

  @doc """
  Races with a fallback that's only executed if all primary tasks fail.

  ## Examples

      AsyncResult.race_with_fallback(
        [
          fn -> fetch_from_cache() end,
          fn -> fetch_from_hot_replica() end
        ],
        fn -> fetch_from_cold_storage() end
      )
  """
  @spec race_with_fallback([task_fun(a)], task_fun(a), options()) :: Result.t(a, term())
        when a: term()
  def race_with_fallback(primary_tasks, fallback, opts \\ []) do
    case race(primary_tasks, opts) do
      {:ok, _} = success -> success
      {:error, _} -> fallback.()
    end
  end

  # ============================================
  # Sequential with Early Exit
  # ============================================

  @doc """
  Executes tasks sequentially until first success.

  Useful when you want to try alternatives in order without parallel overhead.

  ## Examples

      AsyncResult.first_ok([
        fn -> check_local_cache() end,
        fn -> check_distributed_cache() end,
        fn -> fetch_from_source() end
      ])
      #=> {:ok, value} | {:error, :all_failed}
  """
  @spec first_ok([task_fun(a)]) :: Result.t(a, :all_failed) when a: term()
  def first_ok([]), do: {:error, :all_failed}

  def first_ok([task | rest]) do
    case safe_execute(task) do
      {:ok, _} = success -> success
      {:error, _} -> first_ok(rest)
    end
  end

  @doc """
  Executes tasks sequentially until first failure.

  Returns all successful values up to (but not including) the first failure.

  ## Examples

      AsyncResult.until_error([
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:error, :bad} end,
        fn -> {:ok, 4} end
      ])
      #=> {:error, {:at_index, 2, :bad, [1, 2]}}
  """
  @spec until_error([task_fun(a)]) :: Result.t([a], {:at_index, non_neg_integer(), term(), [a]})
        when a: term()
  def until_error(tasks) when is_list(tasks) do
    do_until_error(tasks, 0, [])
  end

  defp do_until_error([], _index, acc), do: {:ok, Enum.reverse(acc)}

  defp do_until_error([task | rest], index, acc) do
    case safe_execute(task) do
      {:ok, value} -> do_until_error(rest, index + 1, [value | acc])
      {:error, reason} -> {:error, {:at_index, index, reason, Enum.reverse(acc)}}
    end
  end

  # ============================================
  # Batch Operations
  # ============================================

  @doc """
  Executes tasks in batches with configurable concurrency per batch.

  Useful for rate-limited APIs or resource-constrained operations.

  ## Examples

      AsyncResult.batch(tasks, batch_size: 10, delay_between_batches: 1000)
      #=> {:ok, all_results}
  """
  @spec batch([task_fun(a)], keyword()) :: Result.t([a], term()) when a: term()
  def batch(tasks, opts \\ []) when is_list(tasks) do
    batch_size = Keyword.get(opts, :batch_size, 10)
    delay = Keyword.get(opts, :delay_between_batches, 0)
    task_opts = Keyword.take(opts, [:timeout, :on_timeout])

    tasks
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {batch, index}, {:ok, acc} ->
      # Add delay between batches (not before first batch)
      add_batch_delay(index, delay)

      case parallel(batch, task_opts) do
        {:ok, results} -> {:cont, {:ok, acc ++ results}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp add_batch_delay(0, _delay), do: :ok
  defp add_batch_delay(_index, 0), do: :ok
  defp add_batch_delay(_index, delay), do: Process.sleep(delay)

  # ============================================
  # Retry with Parallel Fallbacks
  # ============================================

  @doc """
  Retries a task with exponential backoff.

  ## Options

  - `:max_attempts` - Maximum retry attempts (default: 3)
  - `:initial_delay` - Initial delay in ms (default: 100)
  - `:max_delay` - Maximum delay cap in ms (default: 5000)
  - `:multiplier` - Delay multiplier (default: 2)
  - `:jitter` - Add random jitter (default: true)

  ## Examples

      AsyncResult.retry(fn -> flaky_api_call() end,
        max_attempts: 5,
        initial_delay: 100,
        max_delay: 2000
      )
  """
  @spec retry(task_fun(a), keyword()) :: Result.t(a, term()) when a: term()
  def retry(task, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    initial_delay = Keyword.get(opts, :initial_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 5000)
    multiplier = Keyword.get(opts, :multiplier, 2)
    jitter = Keyword.get(opts, :jitter, true)

    do_retry(task, 1, max_attempts, initial_delay, max_delay, multiplier, jitter, nil)
  end

  defp do_retry(_task, attempt, max_attempts, _delay, _max_delay, _multiplier, _jitter, last_error)
       when attempt > max_attempts do
    {:error, {:max_retries_exceeded, last_error}}
  end

  defp do_retry(task, attempt, max_attempts, delay, max_delay, multiplier, jitter, _last_error) do
    case safe_execute(task) do
      {:ok, _} = success ->
        success

      {:error, reason} ->
        # Don't sleep after last attempt
        sleep_unless_last(attempt, max_attempts, delay, jitter)

        next_delay = min(delay * multiplier, max_delay)
        do_retry(task, attempt + 1, max_attempts, next_delay, max_delay, multiplier, jitter, reason)
    end
  end

  defp sleep_unless_last(attempt, max_attempts, _delay, _jitter) when attempt >= max_attempts,
    do: :ok

  defp sleep_unless_last(_attempt, _max_attempts, delay, true) do
    jitter_range = max(1, div(delay, 2))
    jittered = delay + :rand.uniform(jitter_range)
    Process.sleep(jittered)
  end

  defp sleep_unless_last(_attempt, _max_attempts, delay, false), do: Process.sleep(delay)

  # ============================================
  # Combinators
  # ============================================

  @doc """
  Combines results from two parallel tasks.

  ## Examples

      AsyncResult.combine(
        fn -> fetch_user(id) end,
        fn -> fetch_preferences(id) end
      )
      #=> {:ok, {user, preferences}}
  """
  @spec combine(task_fun(a), task_fun(b), options()) :: Result.t({a, b}, term())
        when a: term(), b: term()
  def combine(task1, task2, opts \\ []) do
    case parallel([task1, task2], opts) do
      {:ok, [a, b]} -> {:ok, {a, b}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Combines results from two parallel tasks with a function.

  ## Examples

      AsyncResult.combine_with(
        fn -> fetch_user(id) end,
        fn -> fetch_preferences(id) end,
        fn user, prefs -> Map.put(user, :preferences, prefs) end
      )
      #=> {:ok, user_with_preferences}
  """
  @spec combine_with(task_fun(a), task_fun(b), (a, b -> c), options()) :: Result.t(c, term())
        when a: term(), b: term(), c: term()
  def combine_with(task1, task2, combiner, opts \\ []) when is_function(combiner, 2) do
    case combine(task1, task2, opts) do
      {:ok, {a, b}} -> {:ok, combiner.(a, b)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Combines multiple parallel tasks with a reducer.

  ## Examples

      AsyncResult.combine_all([
        fn -> {:ok, 1} end,
        fn -> {:ok, 2} end,
        fn -> {:ok, 3} end
      ], fn acc, val -> acc + val end, 0)
      #=> {:ok, 6}
  """
  @spec combine_all([task_fun(a)], (b, a -> b), b, options()) :: Result.t(b, term())
        when a: term(), b: term()
  def combine_all(tasks, reducer, initial, opts \\ []) when is_function(reducer, 2) do
    case parallel(tasks, opts) do
      {:ok, values} -> {:ok, Enum.reduce(values, initial, reducer)}
      {:error, _} = error -> error
    end
  end

  # ============================================
  # Mapping and Transformation
  # ============================================

  @doc """
  Maps a function over the results of parallel execution.

  ## Examples

      AsyncResult.parallel([fn -> {:ok, 1} end, fn -> {:ok, 2} end])
      |> AsyncResult.map(fn values -> Enum.sum(values) end)
      #=> {:ok, 3}
  """
  @spec map(Result.t([a], e), ([a] -> b)) :: Result.t(b, e) when a: term(), b: term(), e: term()
  def map({:ok, values}, fun) when is_function(fun, 1), do: {:ok, fun.(values)}
  def map({:error, _} = error, _fun), do: error

  @doc """
  Chains async operations.

  ## Examples

      AsyncResult.parallel([fn -> {:ok, 1} end])
      |> AsyncResult.and_then(fn [x] -> {:ok, x * 2} end)
      #=> {:ok, 2}
  """
  @spec and_then(Result.t(a, e), (a -> Result.t(b, e))) :: Result.t(b, e)
        when a: term(), b: term(), e: term()
  def and_then({:ok, value}, fun) when is_function(fun, 1), do: fun.(value)
  def and_then({:error, _} = error, _fun), do: error

  # ============================================
  # Context and Error Enhancement
  # ============================================

  @doc """
  Wraps a task function to add context metadata to errors.

  ## Examples

      AsyncResult.with_context(fn -> fetch_user(id) end, user_id: id, operation: :fetch)
      #=> {:ok, user} | {:error, %{reason: :not_found, context: %{user_id: 123, operation: :fetch}}}
  """
  @spec with_context(task_fun(a), keyword() | map()) :: task_fun(a) when a: term()
  def with_context(task, context) when is_function(task, 0) do
    context_map = if is_list(context), do: Map.new(context), else: context

    fn ->
      case task.() do
        {:ok, _} = success -> success
        {:error, reason} -> {:error, %{reason: reason, context: context_map}}
      end
    end
  end

  @doc """
  Executes parallel tasks with context attached to each.

  ## Examples

      tasks = [
        {fn -> fetch_user(1) end, user_id: 1},
        {fn -> fetch_user(2) end, user_id: 2}
      ]
      AsyncResult.parallel_with_context(tasks)
  """
  @spec parallel_with_context([{task_fun(a), keyword() | map()}], options()) ::
          Result.t([a], term())
        when a: term()
  def parallel_with_context(tasks_with_context, opts \\ []) do
    tasks = Enum.map(tasks_with_context, fn {task, ctx} -> with_context(task, ctx) end)
    parallel(tasks, opts)
  end

  # ============================================
  # Progress Tracking
  # ============================================

  @doc """
  Executes tasks in parallel with progress callback.

  The callback receives `{completed, total}` after each task completes.

  ## Examples

      AsyncResult.parallel_with_progress(
        tasks,
        fn completed, total ->
          IO.puts("Progress: \#{completed}/\#{total}")
        end
      )
  """
  @spec parallel_with_progress(
          [task_fun(a)],
          (non_neg_integer(), non_neg_integer() -> any()),
          options()
        ) :: Result.t([a], term())
        when a: term()
  def parallel_with_progress(tasks, progress_callback, opts \\ [])
      when is_list(tasks) and is_function(progress_callback, 2) do
    total = length(tasks)

    if total == 0 do
      {:ok, []}
    else
      parent = self()
      ref = make_ref()

      max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      # Wrap tasks to report progress
      indexed_tasks =
        tasks
        |> Enum.with_index()
        |> Enum.map(fn {task, index} ->
          {index,
           fn ->
             result = safe_execute(task)
             send(parent, {:progress, ref, index, result})
             result
           end}
        end)

      # Start initial batch of tasks
      {initial_tasks, remaining} = Enum.split(indexed_tasks, max_concurrency)
      running_count = length(initial_tasks)
      Enum.each(initial_tasks, fn {_idx, task} -> spawn_link(task) end)

      # Collect results with progress tracking
      collect_with_progress(ref, running_count, remaining, [], 0, total, progress_callback, timeout)
    end
  end

  defp collect_with_progress(_ref, 0, [], results, _completed, _total, _callback, _timeout) do
    sorted = results |> Enum.sort_by(fn {idx, _} -> idx end) |> Enum.map(fn {_, r} -> r end)

    case Enum.find(sorted, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(sorted, fn {:ok, v} -> v end)}
      error -> error
    end
  end

  defp collect_with_progress(
         ref,
         running_count,
         remaining,
         results,
         completed,
         total,
         callback,
         timeout
       ) do
    receive do
      {:progress, ^ref, index, result} ->
        new_completed = completed + 1
        callback.(new_completed, total)

        # Start next task if any remaining
        {new_running_count, new_remaining} =
          case remaining do
            [{_idx, next_task} | rest] ->
              spawn_link(next_task)
              {running_count, rest}

            [] ->
              {running_count - 1, []}
          end

        collect_with_progress(
          ref,
          new_running_count,
          new_remaining,
          [{index, result} | results],
          new_completed,
          total,
          callback,
          timeout
        )
    after
      timeout ->
        {:error, :timeout}
    end
  end

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Wraps a potentially raising function in a result.

  ## Examples

      AsyncResult.safe(fn -> dangerous_operation() end)
      #=> {:ok, result} | {:error, %RuntimeError{...}}
  """
  @spec safe((-> a)) :: Result.t(a, Exception.t()) when a: term()
  def safe(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e -> {:error, e}
  end

  @doc """
  Executes with a timeout, returning error on timeout.

  ## Examples

      AsyncResult.with_timeout(fn -> slow_operation() end, 5000)
      #=> {:ok, result} | {:error, :timeout}
  """
  @spec with_timeout(task_fun(a), timeout()) :: Result.t(a, :timeout | term()) when a: term()
  def with_timeout(task, timeout) when is_integer(timeout) and timeout > 0 do
    task_ref = Task.async(fn -> safe_execute(task) end)

    case Task.yield(task_ref, timeout) || Task.shutdown(task_ref, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp safe_execute(fun) when is_function(fun, 0) do
    fun.()
  rescue
    e -> {:error, {:exception, e}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp indexed_if_ordered(tasks, true), do: Enum.with_index(tasks)
  defp indexed_if_ordered(tasks, false), do: tasks

  defp execute_task({task, index}, true) when is_function(task, 0), do: {index, safe_execute(task)}
  defp execute_task(task, false) when is_function(task, 0), do: safe_execute(task)

  defp on_timeout_handler(:error), do: :kill_task
  defp on_timeout_handler(:kill), do: :kill_task
  defp on_timeout_handler({:default, _}), do: :kill_task

  defp collect_stream_results(stream, ordered, on_timeout) do
    stream
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, result}, {:ok, acc} ->
        handle_stream_result(result, acc, ordered)

      {:exit, :timeout}, {:ok, _acc} ->
        handle_timeout(on_timeout)

      {:exit, reason}, {:ok, _acc} ->
        {:halt, {:error, {:task_exit, reason}}}
    end)
    |> finalize_results(ordered)
  end

  defp handle_stream_result({index, {:ok, value}}, acc, true),
    do: {:cont, {:ok, [{index, value} | acc]}}

  defp handle_stream_result({_index, {:error, reason}}, _acc, true), do: {:halt, {:error, reason}}
  defp handle_stream_result({:ok, value}, acc, false), do: {:cont, {:ok, [value | acc]}}
  defp handle_stream_result({:error, reason}, _acc, false), do: {:halt, {:error, reason}}

  defp handle_timeout(:error), do: {:halt, {:error, :timeout}}
  defp handle_timeout(:kill), do: {:halt, {:error, :timeout}}
  defp handle_timeout({:default, value}), do: {:cont, {:ok, [value]}}

  defp finalize_results({:ok, results}, true) do
    sorted =
      results
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_, value} -> value end)

    {:ok, sorted}
  end

  defp finalize_results({:ok, results}, false), do: {:ok, Enum.reverse(results)}
  defp finalize_results(error, _ordered), do: error

  defp extract_stream_result({:ok, {_index, result}}), do: result
  defp extract_stream_result({:ok, result}), do: result
  defp extract_stream_result({:exit, :timeout}), do: {:error, :timeout}
  defp extract_stream_result({:exit, reason}), do: {:error, {:task_exit, reason}}

  defp maybe_reorder(results, true) do
    results
    |> Enum.with_index()
    |> Enum.sort_by(fn {_, index} -> index end)
    |> Enum.map(fn {result, _} -> result end)
  end

  defp maybe_reorder(results, false), do: results

  defp settle_results(results) do
    {oks, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, value}, {ok_acc, err_acc} -> {[value | ok_acc], err_acc}
        {:error, reason}, {ok_acc, err_acc} -> {ok_acc, [reason | err_acc]}
      end)

    %{
      ok: Enum.reverse(oks),
      errors: Enum.reverse(errors),
      results: results
    }
  end

  defp await_first_success(_ref, [], errors, _timeout), do: {:error, Enum.reverse(errors)}

  defp await_first_success(ref, remaining_tasks, errors, timeout) do
    receive do
      {^ref, pid, {:ok, value}} ->
        # Found success, cancel remaining
        remaining_tasks
        |> Enum.reject(fn task -> task.pid == pid end)
        |> Enum.each(&Task.shutdown(&1, :brutal_kill))

        {:ok, value}

      {^ref, pid, {:error, reason}} ->
        remaining = Enum.reject(remaining_tasks, fn task -> task.pid == pid end)
        await_first_success(ref, remaining, [reason | errors], timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end
end
