defmodule OmScheduler.Executor do
  @moduledoc """
  Executes scheduled jobs.

  Handles:
  - Running job functions with timeout
  - Retry logic
  - Telemetry emission
  - Execution recording
  """

  alias OmScheduler.{
    Job,
    Execution,
    Telemetry,
    Middleware,
    Config,
    CircuitBreaker,
    ErrorClassifier,
    DeadLetter
  }

  @type result :: {:ok, term()} | {:error, term()} | {:retry, term()}

  @heartbeat_interval 30_000

  @doc """
  Executes a job.

  Returns `{:ok, result}` on success, `{:error, reason}` on failure,
  or `{:retry, reason}` if the job should be retried.
  """
  @spec execute(Job.t(), keyword()) :: result()
  def execute(%Job{} = job, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    store = Keyword.get(opts, :store)
    middleware = Keyword.get(opts, :middleware) || get_middleware()

    # Check circuit breaker if configured
    case check_circuit_breaker(job) do
      :ok ->
        execute_with_circuit_tracking(job, attempt, store, middleware)

      {:error, :circuit_open} ->
        Telemetry.job_skip(%{job: job, job_name: job.name, queue: job.queue}, :circuit_open)
        {:error, :circuit_open}
    end
  end

  defp check_circuit_breaker(%Job{} = job) do
    case get_circuit_breaker(job) do
      nil -> :ok
      circuit_name -> CircuitBreaker.allow?(circuit_name)
    end
  end

  defp get_circuit_breaker(%Job{meta: meta}) when is_map(meta) do
    Map.get(meta, "circuit_breaker") || Map.get(meta, :circuit_breaker)
  end

  defp get_circuit_breaker(_), do: nil

  defp execute_with_circuit_tracking(job, attempt, store, middleware) do
    circuit_name = get_circuit_breaker(job)

    result =
      case middleware do
        [] -> execute_without_middleware(job, attempt, store)
        mw -> execute_with_middleware(job, mw, attempt, store)
      end

    # Record result with circuit breaker
    if circuit_name do
      case result do
        {:ok, _} -> CircuitBreaker.record_success(circuit_name)
        {:error, error} -> maybe_record_circuit_failure(circuit_name, error)
        {:retry, error} -> maybe_record_circuit_failure(circuit_name, error)
      end
    end

    result
  end

  defp maybe_record_circuit_failure(circuit_name, error) do
    # Only record failures that should trip the circuit
    if should_trip_circuit?(error) do
      CircuitBreaker.record_failure(circuit_name, error)
    end
  end

  defp should_trip_circuit?(error) do
    alias FnTypes.Protocols.Recoverable

    try do
      Recoverable.trips_circuit?(error)
    rescue
      # If protocol not implemented, default to tripping on infrastructure errors
      _ -> is_infrastructure_error?(error)
    end
  end

  defp is_infrastructure_error?(:timeout), do: true
  defp is_infrastructure_error?({:timeout, _}), do: true
  defp is_infrastructure_error?({:exit, _}), do: true
  defp is_infrastructure_error?({:exception, _, _}), do: true
  defp is_infrastructure_error?(:circuit_open), do: false
  defp is_infrastructure_error?(_), do: false

  defp execute_with_middleware(job, middleware, attempt, store) do
    Middleware.wrap(job, middleware, fn ->
      do_execute(job, attempt, store)
    end)
  end

  defp execute_without_middleware(job, attempt, store) do
    do_execute(job, attempt, store)
  end

  defp do_execute(job, attempt, store) do
    meta = %{
      job: job,
      job_name: job.name,
      queue: job.queue,
      attempt: attempt
    }

    # Record execution start
    execution = Execution.start(job, attempt)
    maybe_record_start(execution, store)

    start_time = System.monotonic_time()
    Telemetry.job_start(meta)

    # Start heartbeat timer for long-running jobs
    heartbeat_ref = start_heartbeat_timer(job.name, store)

    result =
      try do
        # Execute with timeout
        task =
          Task.async(fn ->
            run_job_function(job)
          end)

        case Task.yield(task, job.timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} ->
            result

          nil ->
            {:error, :timeout}

          {:exit, reason} ->
            {:error, {:exit, reason}}
        end
      rescue
        exception ->
          {:error, {:exception, exception, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason, __STACKTRACE__}}
      after
        stop_heartbeat_timer(heartbeat_ref)
      end

    duration = System.monotonic_time() - start_time

    handle_result(result, job, execution, meta, duration, attempt, store)
  end

  defp get_middleware do
    conf = Config.get()
    Keyword.get(conf, :middleware, [])
  end

  # ============================================
  # Result Handling
  # ============================================

  defp handle_result({:ok, value}, _job, execution, meta, duration, _attempt, store) do
    execution = Execution.complete(execution, value)
    Telemetry.job_stop(Map.put(meta, :result, :ok), duration)
    maybe_record_complete(execution, store)
    {:ok, value}
  end

  defp handle_result(:ok, _job, execution, meta, duration, _attempt, store) do
    execution = Execution.complete(execution, :ok)
    Telemetry.job_stop(Map.put(meta, :result, :ok), duration)
    maybe_record_complete(execution, store)
    {:ok, :ok}
  end

  defp handle_result({:retry, reason}, job, execution, meta, duration, attempt, store) do
    handle_error_with_classification(job, execution, meta, duration, attempt, store, reason, nil)
  end

  defp handle_result({:error, :timeout}, job, execution, meta, duration, attempt, store) do
    execution = Execution.timeout(execution)
    Telemetry.job_exception(meta, duration, :error, :timeout, [])
    maybe_record_complete(execution, store)
    handle_error_with_classification(job, execution, meta, duration, attempt, store, :timeout, nil)
  end

  defp handle_result(
         {:error, {:exception, exception, stacktrace}},
         job,
         execution,
         meta,
         duration,
         attempt,
         store
       ) do
    execution = Execution.fail(execution, exception, format_stacktrace(stacktrace))
    Telemetry.job_exception(meta, duration, :error, exception, stacktrace)
    maybe_record_complete(execution, store)

    handle_error_with_classification(
      job,
      execution,
      meta,
      duration,
      attempt,
      store,
      {:exception, exception, stacktrace},
      format_stacktrace(stacktrace)
    )
  end

  defp handle_result({:error, reason}, job, execution, meta, duration, attempt, store) do
    execution = Execution.fail(execution, reason)
    Telemetry.job_exception(meta, duration, :error, reason, [])
    maybe_record_complete(execution, store)
    handle_error_with_classification(job, execution, meta, duration, attempt, store, reason, nil)
  end

  # Smart retry logic using error classification
  defp handle_error_with_classification(
         job,
         _execution,
         meta,
         _duration,
         attempt,
         _store,
         error,
         stacktrace
       ) do
    case ErrorClassifier.next_action(error, attempt) do
      {:retry, _delay} ->
        Telemetry.job_stop(Map.put(meta, :result, :retry), 0)
        {:retry, error}

      :dead_letter ->
        # Send to dead letter queue
        send_to_dead_letter(job, error, attempt, stacktrace)
        Telemetry.job_discard(meta, error)
        {:error, {:dead_letter, error}}

      :discard ->
        # Terminal error, don't retry
        Telemetry.job_discard(meta, error)
        {:error, error}
    end
  end

  defp send_to_dead_letter(job, error, attempt, stacktrace) do
    opts = if stacktrace, do: [stacktrace: stacktrace], else: []

    try do
      DeadLetter.insert(job, error, attempt, opts)
    rescue
      # DLQ might not be running
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  @doc """
  Calculates retry delay using exponential backoff.

  If an error is provided, uses smart delay based on error classification.
  Otherwise, falls back to job's configured retry_delay.
  """
  @spec retry_delay(Job.t(), pos_integer(), term()) :: pos_integer()
  def retry_delay(job, attempt, error \\ nil)

  def retry_delay(_job, attempt, error) when not is_nil(error) do
    # Use error-based delay from classification
    ErrorClassifier.retry_delay(error, attempt)
  end

  def retry_delay(%Job{retry_delay: base_delay}, attempt, _error) do
    # Exponential backoff with jitter
    base = base_delay * :math.pow(2, attempt - 1)
    jitter = :rand.uniform() * base * 0.1
    round(base + jitter)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp run_job_function(%Job{module: module_str, function: function_str, args: args}) do
    module = String.to_existing_atom("Elixir.#{module_str}")
    function = String.to_existing_atom(function_str)

    case args do
      args when args == %{} or args == nil ->
        apply(module, function, [])

      args when is_map(args) ->
        apply(module, function, [args])

      args when is_list(args) ->
        apply(module, function, args)
    end
  rescue
    ArgumentError ->
      # Module or function doesn't exist
      {:error, :undefined_function}
  end

  defp maybe_record_start(execution, nil), do: execution

  defp maybe_record_start(execution, store) do
    case store.record_execution_start(execution) do
      {:ok, exec} -> exec
      {:error, _} -> execution
    end
  end

  defp maybe_record_complete(execution, nil), do: execution

  defp maybe_record_complete(execution, store) do
    case store.record_execution_complete(execution) do
      {:ok, exec} -> exec
      {:error, _} -> execution
    end
  end

  defp format_stacktrace(stacktrace) do
    stacktrace
    |> Exception.format_stacktrace()
    |> String.slice(0, 2000)
  end

  # ============================================
  # Heartbeat Timer
  # ============================================

  defp start_heartbeat_timer(_job_name, nil), do: nil

  defp start_heartbeat_timer(job_name, store) do
    parent = self()

    spawn_link(fn ->
      heartbeat_loop(job_name, store, parent)
    end)
  end

  defp stop_heartbeat_timer(nil), do: :ok

  defp stop_heartbeat_timer(pid) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :normal)
    :ok
  end

  defp heartbeat_loop(job_name, store, parent) do
    receive do
      :stop ->
        :ok
    after
      @heartbeat_interval ->
        case Process.alive?(parent) do
          true ->
            store.record_heartbeat(job_name, node())
            heartbeat_loop(job_name, store, parent)

          false ->
            :ok
        end
    end
  end
end
