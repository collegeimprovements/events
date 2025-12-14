defmodule FnTypes.AsyncResult do
  @moduledoc """
  Concurrent operations on Result types.

  A comprehensive wrapper around Elixir's `Task` and `Task.async_stream` that
  provides result-aware concurrent operations with configurable error handling.

  ## Design Philosophy

  - **Fail-fast by default**: Returns first error encountered
  - **Configurable settlement**: Use `settle: true` to collect all results
  - **Bounded concurrency**: Controls resource usage with `:max_concurrency`
  - **Timeout safety**: All operations have configurable timeouts
  - **Task supervision**: Pass `:supervisor` option for crash isolation
  - **Streaming support**: Memory-efficient processing of large collections

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `async/1` + `await/2` | Explicit task handle control |
  | `parallel/2` | Execute multiple tasks, fail-fast |
  | `parallel_map/3` | Map function over items in parallel |
  | `race/2` | First success wins |
  | `hedge/3` | Hedged request with backup |
  | `stream/3` | Lazy evaluation for large collections |
  | `retry/2` | Retry with exponential backoff |
  | `fire_and_forget/2` | Side-effects only, no result |
  | `lazy/1` + `run_lazy/1` | Deferred computation |

  ## Basic Usage

      # Execute multiple operations in parallel
      AsyncResult.parallel([
        fn -> fetch_user(1) end,
        fn -> fetch_user(2) end
      ])
      #=> {:ok, [user1, user2]} | {:error, reason}

      # With settlement (collect all results)
      AsyncResult.parallel(tasks, settle: true)
      #=> %{ok: [val1, val3], errors: [:failed], results: [...]}

      # Map over items in parallel
      AsyncResult.parallel_map([1, 2, 3], &fetch_user/1)
      #=> {:ok, [user1, user2, user3]}

      # Race multiple alternatives
      AsyncResult.race([
        fn -> fetch_from_cache() end,
        fn -> fetch_from_db() end
      ])
      #=> {:ok, first_success}

  ## Explicit Task Handles

      handle = AsyncResult.async(fn -> expensive_operation() end)
      # ... do other work ...
      {:ok, result} = AsyncResult.await(handle)

  ## Common Options

      parallel(tasks,
        max_concurrency: 5,      # Limit concurrent tasks
        timeout: 5000,           # Per-task timeout in ms
        ordered: true,           # Preserve input order
        settle: true,            # Collect all results
        supervisor: MySupervisor # Crash isolation
      )
  """

  alias FnTypes.Result

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

  @type settlement_indexed(a) :: %{
          ok: [{a, term()}],
          errors: [{a, term()}],
          results: [{a, Result.t()}]
        }

  @type options :: [
          max_concurrency: pos_integer(),
          timeout: timeout(),
          ordered: boolean(),
          settle: boolean(),
          indexed: boolean(),
          supervisor: atom() | pid(),
          telemetry: [atom()],
          on_progress: (non_neg_integer(), non_neg_integer() -> any())
        ]

  @default_timeout 5_000
  @default_max_concurrency System.schedulers_online() * 2

  # ============================================
  # Internal Structs
  # ============================================

  @typedoc "A handle to an async task"
  @opaque handle :: %__MODULE__.Handle{task: Task.t(), ref: reference()}

  defmodule Handle do
    @moduledoc false
    @enforce_keys [:task, :ref]
    defstruct [:task, :ref]
  end

  @typedoc "A completed task with pre-computed result"
  @opaque completed_handle :: %__MODULE__.Completed{result: Result.t()}

  defmodule Completed do
    @moduledoc false
    @enforce_keys [:result]
    defstruct [:result]
  end

  # ============================================
  # Settlement Helpers
  # ============================================

  defmodule Settlement do
    @moduledoc """
    Helper functions for working with settlement results.

    Settlement results are returned when using `settle: true` option
    with `parallel/2` or `parallel_map/3`.
    """

    @type t :: %{ok: [term()], errors: [term()], results: [FnTypes.Result.t()]}
    @type indexed(a) :: %{
            ok: [{a, term()}],
            errors: [{a, term()}],
            results: [{a, FnTypes.Result.t()}]
          }

    @doc "Extract success values from settlement"
    @spec ok(t() | indexed(term())) :: [term()]
    def ok(%{ok: values}), do: values

    @doc "Extract error values from settlement"
    @spec errors(t() | indexed(term())) :: [term()]
    def errors(%{errors: values}), do: values

    @doc "Check if all tasks succeeded"
    @spec ok?(t() | indexed(term())) :: boolean()
    def ok?(%{errors: []}), do: true
    def ok?(%{errors: _}), do: false

    @doc "Check if any task failed"
    @spec failed?(t() | indexed(term())) :: boolean()
    def failed?(settlement), do: not ok?(settlement)

    @doc "Split into {successes, failures} tuple"
    @spec split(t()) :: {[term()], [term()]}
    def split(%{ok: oks, errors: errs}), do: {oks, errs}

    @doc "Split indexed settlement into maps"
    @spec split_indexed(indexed(a)) :: %{successes: %{a => term()}, failures: %{a => term()}}
          when a: term()
    def split_indexed(%{ok: oks, errors: errs}) do
      %{
        successes: Map.new(oks),
        failures: Map.new(errs)
      }
    end
  end

  # ============================================
  # Lazy Computation
  # ============================================

  defmodule Lazy do
    @moduledoc """
    A deferred async computation that hasn't started yet.

    Unlike `async/1` which starts immediately, `Lazy` captures the
    computation for later execution with `run_lazy/1`.
    """

    @enforce_keys [:fun]
    defstruct [:fun, opts: []]

    @type t(a) :: %__MODULE__{fun: (-> a), opts: keyword()}
  end

  # ============================================
  # Async/Await (Task Handles)
  # ============================================

  @doc """
  Starts an async task, returning a handle that must be awaited.

  ## Options

    * `:supervisor` - Use `Task.Supervisor` for crash isolation (unlinked task)

  ## Examples

      handle = AsyncResult.async(fn -> fetch_user(id) end)
      {:ok, user} = AsyncResult.await(handle)

      # Unlinked task (requires supervisor)
      handle = AsyncResult.async(fn -> risky_op() end, supervisor: MySupervisor)
  """
  @spec async(task_fun(a), keyword()) :: handle() when a: term()
  def async(fun, opts \\ []) when is_function(fun, 0) do
    task =
      case Keyword.get(opts, :supervisor) do
        nil ->
          Task.async(fn -> safe_execute(fun) end)

        supervisor ->
          Task.Supervisor.async_nolink(supervisor, fn -> safe_execute(fun) end)
      end

    %Handle{task: task, ref: task.ref}
  end

  @doc """
  Awaits a task handle, blocking until the result is available.

  ## Options

    * `:timeout` - Timeout in milliseconds (default: 5000)

  ## Examples

      {:ok, result} = AsyncResult.await(handle)
      {:ok, result} = AsyncResult.await(handle, timeout: 10_000)
  """
  @spec await(handle() | completed_handle(), keyword()) :: Result.t()
  def await(handle, opts \\ [])

  def await(%Completed{result: result}, _opts), do: result

  def await(%Handle{task: task}, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, _} = ok} -> ok
      {:ok, {:error, _} = error} -> error
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end

  @doc """
  Awaits multiple handles, returning results in order.

  ## Options

    * `:timeout` - Timeout in milliseconds (default: 5000)
    * `:settle` - If true, collect all results instead of fail-fast

  ## Examples

      {:ok, [r1, r2]} = AsyncResult.await_many([h1, h2])

      # With settlement
      %{ok: [...], errors: [...]} = AsyncResult.await_many(handles, settle: true)
  """
  @spec await_many([handle() | completed_handle()], keyword()) :: Result.t([term()]) | settlement()
  def await_many(handles, opts \\ []) when is_list(handles) do
    settle = Keyword.get(opts, :settle, false)
    results = Enum.map(handles, &await(&1, opts))

    if settle do
      settle_results(results)
    else
      collect_results(results)
    end
  end

  @doc """
  Non-blocking yield - checks if task is done without blocking.

  Returns `{:ok, result}` if done, `nil` if still running.

  ## Options

    * `:timeout` - How long to wait (default: 0)

  ## Examples

      case AsyncResult.yield(handle) do
        {:ok, result} -> handle_result(result)
        nil -> :still_running
      end
  """
  @spec yield(handle(), keyword()) :: {:ok, Result.t()} | nil
  def yield(%Handle{task: task}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 0)

    case Task.yield(task, timeout) do
      {:ok, result} -> {:ok, result}
      nil -> nil
      {:exit, reason} -> {:ok, {:error, {:exit, reason}}}
    end
  end

  @doc """
  Shuts down a running task.

  ## Options

    * `:timeout` - Graceful shutdown timeout before brutal kill (default: 5000)
    * `:brutal_kill` - If true, immediately kill without waiting

  ## Examples

      AsyncResult.shutdown(handle)
      AsyncResult.shutdown(handle, brutal_kill: true)
  """
  @spec shutdown(handle(), keyword()) :: {:ok, Result.t()} | nil
  def shutdown(%Handle{task: task}, opts \\ []) do
    timeout =
      if Keyword.get(opts, :brutal_kill, false) do
        :brutal_kill
      else
        Keyword.get(opts, :timeout, @default_timeout)
      end

    case Task.shutdown(task, timeout) do
      {:ok, result} -> {:ok, result}
      nil -> nil
      {:exit, reason} -> {:ok, {:error, {:exit, reason}}}
    end
  end

  @doc """
  Creates a pre-computed handle from an existing result.

  Useful for mixing cached results with async fetches.

  ## Examples

      handles = Enum.map(items, fn item ->
        case Cache.get(item) do
          {:ok, cached} -> AsyncResult.completed({:ok, cached})
          :miss -> AsyncResult.async(fn -> fetch(item) end)
        end
      end)
      AsyncResult.await_many(handles)
  """
  @spec completed(Result.t()) :: completed_handle()
  def completed(result) do
    %Completed{result: result}
  end

  # ============================================
  # Parallel Execution
  # ============================================

  @doc """
  Executes multiple tasks in parallel.

  By default, fails fast on first error. Use `settle: true` to collect all results.

  ## Options

    * `:max_concurrency` - Maximum concurrent tasks (default: schedulers * 2)
    * `:timeout` - Per-task timeout in ms (default: 5000)
    * `:ordered` - Preserve input order (default: true)
    * `:settle` - Collect all results, don't fail fast (default: false)
    * `:supervisor` - Task.Supervisor for crash isolation
    * `:telemetry` - Event prefix for telemetry (e.g., `[:myapp, :batch]`)
    * `:on_progress` - Callback `fn(completed, total) -> any()`

  ## Examples

      # Fail-fast (default)
      {:ok, [r1, r2, r3]} = AsyncResult.parallel([task1, task2, task3])
      {:error, reason} = AsyncResult.parallel([ok_task, failing_task])

      # Settlement mode
      %{ok: [...], errors: [...]} = AsyncResult.parallel(tasks, settle: true)

      # With progress callback
      AsyncResult.parallel(tasks, on_progress: fn done, total ->
        IO.puts("\#{done}/\#{total} complete")
      end)
  """
  @spec parallel([task_fun(a)], keyword()) :: Result.t([a]) | settlement() when a: term()
  def parallel(tasks, opts \\ []) when is_list(tasks) do
    settle = Keyword.get(opts, :settle, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)
    supervisor = Keyword.get(opts, :supervisor)
    telemetry_prefix = Keyword.get(opts, :telemetry)
    on_progress = Keyword.get(opts, :on_progress)

    total = length(tasks)
    counter = if on_progress, do: :counters.new(1, [:atomics]), else: nil

    start_time = if telemetry_prefix, do: System.monotonic_time(), else: nil
    if telemetry_prefix, do: emit_start(telemetry_prefix, %{count: total})

    stream_opts = [
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered,
      zip_input_on_exit: true
    ]

    execute_fn = fn task ->
      result = safe_execute(task)

      if counter do
        :counters.add(counter, 1, 1)
        on_progress.(:counters.get(counter, 1), total)
      end

      result
    end

    results =
      if supervisor do
        Task.Supervisor.async_stream_nolink(supervisor, tasks, execute_fn, stream_opts)
      else
        Task.async_stream(tasks, execute_fn, stream_opts)
      end
      |> Enum.map(&extract_stream_result/1)

    result =
      if settle do
        settle_results(results)
      else
        collect_results(results)
      end

    if telemetry_prefix do
      duration = System.monotonic_time() - start_time
      {success_count, error_count} = count_results(results)

      emit_stop(telemetry_prefix, %{
        duration: duration,
        count: total,
        success_count: success_count,
        error_count: error_count,
        result: if(match?({:ok, _}, result), do: :ok, else: :error)
      })
    end

    result
  end

  @doc """
  Maps a function over items in parallel.

  Equivalent to `parallel/2` but takes items and a function.

  ## Options

  Same as `parallel/2`, plus:

    * `:indexed` - Include input with result in settlement (requires `settle: true`)

  ## Examples

      {:ok, users} = AsyncResult.parallel_map(ids, &fetch_user/1)

      # With settlement
      %{ok: [...], errors: [...]} = AsyncResult.parallel_map(ids, &fetch/1, settle: true)

      # Track which inputs failed
      %{ok: [{1, val}], errors: [{2, reason}]} =
        AsyncResult.parallel_map(ids, &fetch/1, settle: true, indexed: true)
  """
  @spec parallel_map([a], task_fun_with_arg(a, b), keyword()) ::
          Result.t([b]) | settlement() | settlement_indexed(a)
        when a: term(), b: term()
  def parallel_map(items, fun, opts \\ []) when is_list(items) and is_function(fun, 1) do
    settle = Keyword.get(opts, :settle, false)
    indexed = Keyword.get(opts, :indexed, false)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)
    supervisor = Keyword.get(opts, :supervisor)

    stream_opts = [
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered,
      zip_input_on_exit: indexed
    ]

    results =
      if supervisor do
        Task.Supervisor.async_stream_nolink(
          supervisor,
          items,
          fn item -> safe_execute(fn -> fun.(item) end) end,
          stream_opts
        )
      else
        Task.async_stream(items, fn item -> safe_execute(fn -> fun.(item) end) end, stream_opts)
      end
      |> Enum.to_list()

    cond do
      settle and indexed ->
        settle_results_indexed(results, items)

      settle ->
        results
        |> Enum.map(&extract_stream_result/1)
        |> settle_results()

      true ->
        results
        |> Enum.map(&extract_stream_result/1)
        |> collect_results()
    end
  end

  # ============================================
  # Racing
  # ============================================

  @doc """
  Races multiple tasks, returning the first success.

  All tasks are started in parallel. The first one to return `{:ok, value}` wins.
  Remaining tasks are shut down. Only fails if ALL tasks fail.

  ## Options

    * `:timeout` - Overall timeout (default: 5000)

  ## Examples

      {:ok, data} = AsyncResult.race([
        fn -> fetch_from_cache() end,
        fn -> fetch_from_db() end,
        fn -> fetch_from_api() end
      ])

      # Returns {:error, [all_errors]} only if all fail
      {:error, [:not_cached, :db_down, :api_error]} = AsyncResult.race([...])
  """
  @spec race([task_fun(a)], keyword()) :: Result.t(a, [term()]) when a: term()
  def race(tasks, opts \\ []) when is_list(tasks) and length(tasks) > 0 do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    parent = self()
    ref = make_ref()

    # Start all tasks
    task_pids =
      Enum.map(tasks, fn task ->
        spawn_link(fn ->
          result = safe_execute(task)
          send(parent, {ref, self(), result})
        end)
      end)

    # Wait for first success or all failures
    result = race_collect(ref, task_pids, [], timeout)

    # Cleanup remaining tasks
    Enum.each(task_pids, fn pid ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    result
  end

  defp race_collect(_ref, [], errors, _timeout), do: {:error, Enum.reverse(errors)}

  defp race_collect(ref, remaining, errors, timeout) do
    receive do
      {^ref, _pid, {:ok, value}} ->
        {:ok, value}

      {^ref, pid, {:error, reason}} ->
        race_collect(ref, List.delete(remaining, pid), [reason | errors], timeout)
    after
      timeout ->
        {:error, [:timeout | errors]}
    end
  end

  @doc """
  Hedged request - starts backup if primary is slow.

  Starts the primary task immediately. If it doesn't complete within `delay` ms,
  starts the backup task. Returns whichever succeeds first.

  ## Options

    * `:delay` - Milliseconds before starting backup (default: 100)
    * `:timeout` - Overall timeout (default: 5000)

  ## Examples

      # If primary takes > 50ms, also try backup
      AsyncResult.hedge(
        fn -> fetch_from_primary() end,
        fn -> fetch_from_replica() end,
        delay: 50
      )
  """
  @spec hedge(task_fun(a), task_fun(a), keyword()) :: Result.t(a) when a: term()
  def hedge(primary, backup, opts \\ []) when is_function(primary, 0) and is_function(backup, 0) do
    delay = Keyword.get(opts, :delay, 100)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    parent = self()
    ref = make_ref()

    # Start primary immediately
    primary_pid =
      spawn_link(fn ->
        result = safe_execute(primary)
        send(parent, {ref, :primary, result})
      end)

    # Schedule backup start
    backup_pid_ref = make_ref()

    backup_timer = Process.send_after(self(), {backup_pid_ref, :start_backup}, delay)

    result = hedge_collect(ref, backup_pid_ref, primary_pid, nil, backup, parent, timeout)

    # Cleanup
    Process.cancel_timer(backup_timer)
    if Process.alive?(primary_pid), do: Process.exit(primary_pid, :shutdown)

    result
  end

  defp hedge_collect(ref, backup_pid_ref, primary_pid, backup_pid, backup_fun, parent, timeout) do
    receive do
      {^ref, _source, {:ok, value}} ->
        if backup_pid && Process.alive?(backup_pid), do: Process.exit(backup_pid, :shutdown)
        {:ok, value}

      {^ref, :primary, {:error, _} = error} ->
        if backup_pid do
          # Wait for backup
          receive do
            {^ref, :backup, result} -> result
          after
            timeout -> {:error, :timeout}
          end
        else
          error
        end

      {^ref, :backup, {:error, _}} ->
        # Backup failed, keep waiting for primary
        hedge_collect(ref, backup_pid_ref, primary_pid, nil, backup_fun, parent, timeout)

      {^backup_pid_ref, :start_backup} ->
        # Start backup task
        pid =
          spawn_link(fn ->
            result = safe_execute(backup_fun)
            send(parent, {ref, :backup, result})
          end)

        hedge_collect(ref, backup_pid_ref, primary_pid, pid, backup_fun, parent, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end

  # ============================================
  # Streaming
  # ============================================

  @doc """
  Creates a lazy stream for processing large collections.

  Unlike `parallel_map/3`, this returns a `Stream` that processes items
  on-demand with backpressure. Memory-efficient for large datasets.

  ## Options

    * `:max_concurrency` - Maximum concurrent tasks (default: schedulers * 2)
    * `:timeout` - Per-task timeout (default: 5000)
    * `:ordered` - Preserve input order (default: true)
    * `:on_error` - Error handling strategy:
      - `:halt` (default) - Stop stream on first error
      - `:skip` - Skip errors, only yield successes
      - `:include` - Include both successes and errors
      - `{:default, value}` - Replace errors with default value

  ## Examples

      # Process large dataset with backpressure
      large_dataset
      |> AsyncResult.stream(&transform/1, max_concurrency: 20)
      |> Stream.each(&save/1)
      |> Stream.run()

      # Skip errors
      items
      |> AsyncResult.stream(&fetch/1, on_error: :skip)
      |> Enum.to_list()
  """
  @spec stream(Enumerable.t(a), task_fun_with_arg(a, b), keyword()) :: Enumerable.t(Result.t(b))
        when a: term(), b: term()
  def stream(items, fun, opts \\ []) when is_function(fun, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)
    on_error = Keyword.get(opts, :on_error, :halt)

    items
    |> Task.async_stream(
      fn item -> safe_execute(fn -> fun.(item) end) end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      ordered: ordered
    )
    |> Stream.transform(:continue, fn
      _result, :halt ->
        {:halt, :halt}

      {:ok, {:ok, _} = result}, :continue ->
        {[result], :continue}

      {:ok, {:error, _reason} = result}, :continue ->
        case on_error do
          :halt -> {[result], :halt}
          :skip -> {[], :continue}
          :include -> {[result], :continue}
          {:default, value} -> {[{:ok, value}], :continue}
        end

      {:exit, reason}, :continue ->
        result = {:error, {:exit, reason}}

        case on_error do
          :halt -> {[result], :halt}
          :skip -> {[], :continue}
          :include -> {[result], :continue}
          {:default, value} -> {[{:ok, value}], :continue}
        end
    end)
  end

  # ============================================
  # Retry
  # ============================================

  @doc """
  Retries a task with exponential backoff.

  ## Options

    * `:max_attempts` - Maximum attempts (default: 3)
    * `:initial_delay` - Initial delay in ms (default: 100)
    * `:max_delay` - Maximum delay cap in ms (default: 5000)
    * `:multiplier` - Delay multiplier (default: 2)
    * `:jitter` - Add randomness to delay (default: true)
    * `:when` - Predicate `fn(error) -> boolean()` to decide if should retry
    * `:on_retry` - Callback `fn(attempt, error, delay) -> any()` between attempts

  ## Examples

      AsyncResult.retry(fn -> flaky_api_call() end,
        max_attempts: 5,
        initial_delay: 100
      )

      # Only retry specific errors
      AsyncResult.retry(fn -> api_call() end,
        when: fn
          {:error, :rate_limited} -> true
          {:error, :timeout} -> true
          _ -> false
        end
      )

      # With logging
      AsyncResult.retry(fn -> api_call() end,
        on_retry: fn attempt, error, delay ->
          Logger.warn("Attempt \#{attempt} failed: \#{inspect(error)}, retrying in \#{delay}ms")
        end
      )
  """
  @spec retry(task_fun(a), keyword()) :: Result.t(a, {:max_retries, term()}) when a: term()
  def retry(task, opts \\ []) when is_function(task, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    initial_delay = Keyword.get(opts, :initial_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 5000)
    multiplier = Keyword.get(opts, :multiplier, 2)
    jitter = Keyword.get(opts, :jitter, true)
    should_retry = Keyword.get(opts, :when, fn _ -> true end)
    on_retry = Keyword.get(opts, :on_retry)

    do_retry(
      task,
      1,
      max_attempts,
      initial_delay,
      max_delay,
      multiplier,
      jitter,
      should_retry,
      on_retry
    )
  end

  @doc """
  Retries a task using the `FnTypes.Recoverable` protocol to determine
  retry behavior based on the error type.

  This is a smarter retry that automatically:
  - Checks if the error is recoverable via `Recoverable.recoverable?/1`
  - Uses the strategy from `Recoverable.strategy/1`
  - Calculates delays via `Recoverable.retry_delay/2`
  - Limits attempts via `Recoverable.max_attempts/1`

  ## Options

    * `:normalize` - If true, normalizes errors to `FnTypes.Error` first (default: true)
    * `:on_retry` - Callback `fn(attempt, error, delay, strategy) -> any()` between attempts
    * `:telemetry` - Telemetry event prefix (e.g., `[:myapp, :retry]`)

  ## Examples

      # Automatic retry based on error type
      AsyncResult.retry_from_error(fn -> api_call() end)

      # Rate limit errors will wait using Retry-After
      # Timeout errors will use fixed delay retry
      # Network errors will use exponential backoff
      # Validation errors will NOT retry (fail fast)

      # With telemetry
      AsyncResult.retry_from_error(fn -> api_call() end,
        telemetry: [:myapp, :external_api]
      )

      # With logging callback
      AsyncResult.retry_from_error(fn -> api_call() end,
        on_retry: fn attempt, error, delay, strategy ->
          Logger.warning("Retry \#{attempt}: \#{strategy}, waiting \#{delay}ms",
            error: error
          )
        end
      )
  """
  @spec retry_from_error(task_fun(a), keyword()) :: Result.t(a, term()) when a: term()
  def retry_from_error(task, opts \\ []) when is_function(task, 0) do
    normalize = Keyword.get(opts, :normalize, true)
    on_retry = Keyword.get(opts, :on_retry)
    telemetry_prefix = Keyword.get(opts, :telemetry)

    if telemetry_prefix do
      :telemetry.execute(telemetry_prefix ++ [:start], %{system_time: System.system_time()}, %{})
    end

    result = do_retry_from_error(task, 1, normalize, on_retry, telemetry_prefix)

    if telemetry_prefix do
      status = if match?({:ok, _}, result), do: :ok, else: :error
      :telemetry.execute(telemetry_prefix ++ [:stop], %{}, %{result: status})
    end

    result
  end

  defp do_retry_from_error(task, attempt, normalize, on_retry, telemetry_prefix) do
    case safe_execute(task) do
      {:ok, _} = success ->
        success

      {:error, reason} = error ->
        # Normalize the error if requested
        normalized =
          if normalize do
            FnTypes.Protocols.Normalizable.normalize(reason, [])
          else
            reason
          end

        # Check if recoverable using the protocol
        recoverable = FnTypes.Protocols.Recoverable.recoverable?(normalized)
        max_attempts = FnTypes.Protocols.Recoverable.max_attempts(normalized)

        cond do
          not recoverable ->
            # Not recoverable, fail immediately
            if telemetry_prefix do
              emit_retry_telemetry(telemetry_prefix, attempt, normalized, 0, :fail_fast, false)
            end

            error

          attempt >= max_attempts ->
            # Max attempts reached
            if telemetry_prefix do
              emit_retry_telemetry(telemetry_prefix, attempt, normalized, 0, :max_retries, false)
            end

            {:error, {:max_retries, reason}}

          true ->
            # Calculate delay and retry
            strategy = FnTypes.Protocols.Recoverable.strategy(normalized)
            delay = FnTypes.Protocols.Recoverable.retry_delay(normalized, attempt)

            # Emit telemetry
            if telemetry_prefix do
              emit_retry_telemetry(telemetry_prefix, attempt, normalized, delay, strategy, true)
            end

            # Call on_retry callback
            if on_retry do
              on_retry.(attempt, normalized, delay, strategy)
            end

            # Wait and retry
            if delay > 0, do: Process.sleep(delay)

            do_retry_from_error(task, attempt + 1, normalize, on_retry, telemetry_prefix)
        end
    end
  end

  defp emit_retry_telemetry(prefix, attempt, error, delay, strategy, will_retry) do
    :telemetry.execute(
      prefix ++ [:retry],
      %{attempt: attempt, delay_ms: delay},
      %{
        error: error,
        strategy: strategy,
        recoverable: will_retry,
        severity: FnTypes.Protocols.Recoverable.severity(error)
      }
    )
  end

  defp do_retry(
         task,
         attempt,
         max_attempts,
         delay,
         max_delay,
         multiplier,
         jitter,
         should_retry,
         on_retry
       ) do
    case safe_execute(task) do
      {:ok, _} = success ->
        success

      {:error, reason} when attempt >= max_attempts ->
        {:error, {:max_retries, reason}}

      {:error, _reason} = error ->
        if should_retry.(error) do
          actual_delay = if jitter, do: add_jitter(delay), else: delay

          if on_retry, do: on_retry.(attempt, error, actual_delay)

          Process.sleep(actual_delay)
          next_delay = min(delay * multiplier, max_delay)

          do_retry(
            task,
            attempt + 1,
            max_attempts,
            next_delay,
            max_delay,
            multiplier,
            jitter,
            should_retry,
            on_retry
          )
        else
          error
        end
    end
  end

  defp add_jitter(delay) when delay < 4, do: delay

  defp add_jitter(delay) do
    variance = div(delay, 4)
    delay + :rand.uniform(max(1, variance * 2)) - variance
  end

  # ============================================
  # Fire-and-Forget
  # ============================================

  @doc """
  Starts a task without waiting for the result.

  Useful for side-effects like analytics, logging, or notifications
  where you don't need to wait for completion.

  ## Options

    * `:supervisor` - Task.Supervisor for crash isolation
    * `:link` - Link to caller (default: false)

  ## Examples

      {:ok, pid} = AsyncResult.fire_and_forget(fn -> send_analytics(event) end)

      # With supervisor
      AsyncResult.fire_and_forget(fn -> send_email(user) end,
        supervisor: MyApp.TaskSupervisor
      )
  """
  @spec fire_and_forget(task_fun(term()), keyword()) :: {:ok, pid()}
  def fire_and_forget(fun, opts \\ []) when is_function(fun, 0) do
    supervisor = Keyword.get(opts, :supervisor)
    link = Keyword.get(opts, :link, false)

    pid =
      cond do
        supervisor && link ->
          {:ok, pid} = Task.Supervisor.start_child(supervisor, fun)
          pid

        supervisor ->
          {:ok, pid} = Task.Supervisor.start_child(supervisor, fun)
          pid

        link ->
          spawn_link(fun)

        true ->
          spawn(fun)
      end

    {:ok, pid}
  end

  @doc """
  Executes a function over all items, ignoring results.

  Useful for side-effect operations like sending notifications.
  Always returns `:ok` when complete.

  ## Options

    * `:max_concurrency` - Maximum concurrent tasks (default: schedulers * 2)
    * `:timeout` - Per-task timeout (default: 5000)

  ## Examples

      :ok = AsyncResult.run_all(users, &send_notification/1, max_concurrency: 50)
  """
  @spec run_all([a], (a -> term()), keyword()) :: :ok when a: term()
  def run_all(items, fun, opts \\ []) when is_list(items) and is_function(fun, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    items
    |> Task.async_stream(fun, max_concurrency: max_concurrency, timeout: timeout)
    |> Stream.run()

    :ok
  end

  # ============================================
  # Batch & Sequential
  # ============================================

  @doc """
  Executes tasks in batches with optional delay between batches.

  Useful for rate-limiting or when you need to process in chunks.

  ## Options

    * `:batch_size` - Tasks per batch (default: 10)
    * `:delay_between_batches` - Milliseconds between batches (default: 0)
    * `:timeout` - Per-task timeout (default: 5000)

  ## Examples

      AsyncResult.batch(tasks,
        batch_size: 10,
        delay_between_batches: 1000
      )
  """
  @spec batch([task_fun(a)], keyword()) :: Result.t([a]) when a: term()
  def batch(tasks, opts \\ []) when is_list(tasks) do
    batch_size = Keyword.get(opts, :batch_size, 10)
    delay = Keyword.get(opts, :delay_between_batches, 0)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    tasks
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case parallel(batch, timeout: timeout) do
        {:ok, results} ->
          if delay > 0, do: Process.sleep(delay)
          {:cont, {:ok, acc ++ results}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @doc """
  Tries tasks sequentially until one succeeds.

  Executes tasks one at a time, stopping at the first success.
  Returns `{:error, :all_failed}` if all tasks fail.

  ## Examples

      {:ok, data} = AsyncResult.first_ok([
        fn -> check_l1_cache() end,
        fn -> check_l2_cache() end,
        fn -> fetch_from_db() end
      ])
  """
  @spec first_ok([task_fun(a)]) :: Result.t(a, :all_failed) when a: term()
  def first_ok([]), do: {:error, :all_failed}

  def first_ok([task | rest]) when is_function(task, 0) do
    case safe_execute(task) do
      {:ok, _} = success -> success
      {:error, _} -> first_ok(rest)
    end
  end

  # ============================================
  # Lazy Execution
  # ============================================

  @doc """
  Creates a lazy (deferred) computation.

  The task is NOT started until you call `run_lazy/1`. Useful for building
  up a collection of tasks before deciding to execute them.

  ## Options

    * `:timeout` - Timeout when executed (default: 5000)

  ## Examples

      lazy = AsyncResult.lazy(fn -> expensive_computation() end)
      # Nothing has run yet

      {:ok, result} = AsyncResult.run_lazy(lazy)
      # Now it runs
  """
  @spec lazy(task_fun(a), keyword()) :: Lazy.t(a) when a: term()
  def lazy(fun, opts \\ []) when is_function(fun, 0) do
    %Lazy{fun: fun, opts: opts}
  end

  @doc """
  Executes a lazy computation or list of lazy computations.

  ## Options (when executing multiple)

    * `:max_concurrency` - Maximum concurrent tasks (default: schedulers * 2)
    * `:settle` - Collect all results (default: false)

  ## Examples

      {:ok, result} = AsyncResult.run_lazy(lazy)

      {:ok, results} = AsyncResult.run_lazy([lazy1, lazy2, lazy3])

      %{ok: [...], errors: [...]} = AsyncResult.run_lazy(lazies, settle: true)
  """
  @spec run_lazy(Lazy.t(a) | [Lazy.t(a)], keyword()) :: Result.t(a) | Result.t([a]) | settlement()
        when a: term()
  def run_lazy(lazy_or_lazies, opts \\ [])

  def run_lazy(%Lazy{fun: fun, opts: lazy_opts}, _opts) do
    timeout = Keyword.get(lazy_opts, :timeout, @default_timeout)

    task = Task.async(fn -> safe_execute(fun) end)

    case Task.await(task, timeout) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
    end
  end

  def run_lazy(lazies, opts) when is_list(lazies) do
    tasks = Enum.map(lazies, fn %Lazy{fun: fun} -> fun end)
    parallel(tasks, opts)
  end

  @doc """
  Chains lazy computations.

  The next function receives the result of the previous and returns a new Lazy.

  ## Examples

      lazy = AsyncResult.lazy(fn -> fetch_user(id) end)
      |> AsyncResult.lazy_then(fn user ->
        AsyncResult.lazy(fn -> fetch_orders(user.id) end)
      end)

      {:ok, orders} = AsyncResult.run_lazy(lazy)
  """
  @spec lazy_then(Lazy.t(a), (a -> Lazy.t(b))) :: Lazy.t(b) when a: term(), b: term()
  def lazy_then(%Lazy{fun: fun, opts: opts}, next_fn) when is_function(next_fn, 1) do
    %Lazy{
      fun: fn ->
        case safe_execute(fun) do
          {:ok, value} ->
            %Lazy{fun: next_fun} = next_fn.(value)
            safe_execute(next_fun)

          {:error, _} = error ->
            error
        end
      end,
      opts: opts
    }
  end

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Wraps a potentially raising function, returning Result.

  ## Examples

      AsyncResult.safe(fn -> String.to_integer("not a number") end)
      #=> {:error, %ArgumentError{...}}

      AsyncResult.safe(fn -> 1 + 1 end)
      #=> {:ok, 2}
  """
  @spec safe((-> a)) :: Result.t(a, Exception.t()) when a: term()
  def safe(fun) when is_function(fun, 0) do
    try do
      {:ok, fun.()}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Executes a task with a timeout.

  Returns `{:error, :timeout}` if the task doesn't complete in time.

  ## Examples

      {:ok, result} = AsyncResult.timeout(fn -> fast_op() end, 1000)
      {:error, :timeout} = AsyncResult.timeout(fn -> slow_op() end, 100)
  """
  @spec timeout(task_fun(a), timeout()) :: Result.t(a, :timeout) when a: term()
  def timeout(task, timeout_ms) when is_function(task, 0) do
    task_struct = Task.async(fn -> safe_execute(task) end)

    case Task.yield(task_struct, timeout_ms) || Task.shutdown(task_struct) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp safe_execute(fun) do
    try do
      case fun.() do
        {:ok, _} = ok -> ok
        {:error, _} = error -> error
        other -> {:ok, other}
      end
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp extract_stream_result({:ok, result}), do: result
  defp extract_stream_result({:exit, reason}), do: {:error, {:exit, reason}}

  defp collect_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, _} = error, _ -> {:halt, error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp settle_results(results) do
    {oks, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, value}, {oks, errs} -> {[value | oks], errs}
        {:error, reason}, {oks, errs} -> {oks, [reason | errs]}
      end)

    %{
      ok: Enum.reverse(oks),
      errors: Enum.reverse(errors),
      results: results
    }
  end

  defp settle_results_indexed(stream_results, items) do
    indexed_results =
      stream_results
      |> Enum.with_index()
      |> Enum.map(fn
        {{:ok, result}, idx} -> {Enum.at(items, idx), result}
        {{:exit, reason}, idx} -> {Enum.at(items, idx), {:error, {:exit, reason}}}
      end)

    {oks, errors} =
      Enum.reduce(indexed_results, {[], []}, fn
        {input, {:ok, value}}, {oks, errs} -> {[{input, value} | oks], errs}
        {input, {:error, reason}}, {oks, errs} -> {oks, [{input, reason} | errs]}
      end)

    %{
      ok: Enum.reverse(oks),
      errors: Enum.reverse(errors),
      results: indexed_results
    }
  end

  defp count_results(results) do
    Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {s, e} -> {s + 1, e}
      {:error, _}, {s, e} -> {s, e + 1}
    end)
  end

  defp emit_start(prefix, metadata) do
    :telemetry.execute(prefix ++ [:start], %{system_time: System.system_time()}, metadata)
  end

  defp emit_stop(prefix, metadata) do
    :telemetry.execute(prefix ++ [:stop], %{}, metadata)
  end
end
