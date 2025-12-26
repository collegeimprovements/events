defmodule OmScheduler.Queue.Producer do
  @moduledoc """
  Processes jobs from a queue with configurable concurrency.

  Each queue has its own producer that manages concurrent job execution.
  """

  use GenServer
  require Logger

  alias OmScheduler.{Job, Executor, Telemetry, RateLimiter}

  @type state :: %{
          name: atom(),
          queue: atom(),
          concurrency: pos_integer(),
          running: map(),
          job_refs: map(),
          paused: boolean(),
          preempted: map(),
          preemption_enabled: boolean(),
          rate_limiter: atom() | nil,
          store: module(),
          conf: keyword()
        }

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts a queue producer.

  ## Options

  - `:name` - GenServer name
  - `:queue` - Queue name (atom)
  - `:concurrency` - Max concurrent jobs
  - `:store` - Store module
  - `:conf` - Scheduler config
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Pushes a job to the queue for execution.
  """
  @spec push(atom(), Job.t()) :: :ok | {:error, :paused | :full}
  def push(name, %Job{} = job) do
    GenServer.call(name, {:push, job})
  end

  @doc """
  Pauses the queue (stops accepting new jobs).
  """
  @spec pause(atom()) :: :ok
  def pause(name) do
    GenServer.call(name, :pause)
  end

  @doc """
  Resumes the queue.
  """
  @spec resume(atom()) :: :ok
  def resume(name) do
    GenServer.call(name, :resume)
  end

  @doc """
  Changes the concurrency limit.
  """
  @spec scale(atom(), pos_integer()) :: :ok
  def scale(name, concurrency) when is_integer(concurrency) and concurrency > 0 do
    GenServer.call(name, {:scale, concurrency})
  end

  @doc """
  Returns queue statistics.
  """
  @spec stats(atom()) :: map()
  def stats(name) do
    GenServer.call(name, :stats)
  end

  @doc """
  Cancels a running job by name.

  Returns `:ok` if the job was found and cancelled,
  `{:error, :not_running}` if the job is not currently running.
  """
  @spec cancel(atom(), String.t(), term()) :: :ok | {:error, :not_running}
  def cancel(name, job_name, reason \\ :cancelled) do
    GenServer.call(name, {:cancel, job_name, reason})
  end

  @doc """
  Returns list of currently running job names.
  """
  @spec running_jobs(atom()) :: [String.t()]
  def running_jobs(name) do
    GenServer.call(name, :running_jobs)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    queue = Keyword.fetch!(opts, :queue)
    concurrency = Keyword.fetch!(opts, :concurrency)
    store = Keyword.get(opts, :store)
    conf = Keyword.get(opts, :conf, [])

    preemption_enabled = Keyword.get(conf, :preemption, false)
    rate_limiter = Keyword.get(conf, :rate_limiter)

    state = %{
      name: Keyword.fetch!(opts, :name),
      queue: queue,
      concurrency: concurrency,
      running: %{},
      job_refs: %{},
      paused: false,
      preempted: %{},
      preemption_enabled: preemption_enabled,
      rate_limiter: rate_limiter,
      store: store,
      conf: conf
    }

    Logger.debug("[Scheduler.Queue.Producer] Started queue=#{queue} concurrency=#{concurrency}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:push, job}, _from, %{paused: true} = state) do
    Telemetry.job_skip(%{job: job, queue: state.queue}, :paused)
    {:reply, {:error, :paused}, state}
  end

  def handle_call(
        {:push, _job},
        _from,
        %{running: running, concurrency: concurrency, preemption_enabled: false} = state
      )
      when map_size(running) >= concurrency do
    {:reply, {:error, :full}, state}
  end

  def handle_call(
        {:push, job},
        _from,
        %{running: running, concurrency: concurrency, preemption_enabled: true} = state
      )
      when map_size(running) >= concurrency do
    # Try to preempt a lower priority job
    case find_preemptable_job(job, state) do
      nil ->
        {:reply, {:error, :full}, state}

      {ref, {preemptable_job, attempt}} ->
        new_state = preempt_job(ref, preemptable_job, attempt, job, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:push, job}, _from, state) do
    new_state = start_job(job, state)
    {:reply, :ok, new_state}
  end

  def handle_call(:pause, _from, state) do
    Telemetry.queue_event(:pause, state.queue)
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, state) do
    Telemetry.queue_event(:resume, state.queue)
    {:reply, :ok, %{state | paused: false}}
  end

  def handle_call({:scale, concurrency}, _from, state) do
    Telemetry.queue_event(:scale, state.queue, %{
      old_concurrency: state.concurrency,
      new_concurrency: concurrency
    })

    {:reply, :ok, %{state | concurrency: concurrency}}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      queue: state.queue,
      running: map_size(state.running),
      running_jobs: running_job_names(state),
      preempted: map_size(state.preempted),
      preempted_jobs: Map.keys(state.preempted),
      preemption_enabled: state.preemption_enabled,
      concurrency: state.concurrency,
      paused: state.paused,
      available: max(0, state.concurrency - map_size(state.running))
    }

    {:reply, stats, state}
  end

  def handle_call(:running_jobs, _from, state) do
    {:reply, running_job_names(state), state}
  end

  def handle_call({:cancel, job_name, reason}, _from, state) do
    case Map.get(state.job_refs, job_name) do
      nil ->
        {:reply, {:error, :not_running}, state}

      {ref, pid} ->
        # Demonitor and kill the process
        Process.demonitor(ref, [:flush])
        Process.exit(pid, :kill)

        # Remove from running maps
        {_job_info, running} = Map.pop(state.running, ref)
        job_refs = Map.delete(state.job_refs, job_name)

        # Mark as cancelled in store
        mark_job_cancelled(job_name, reason, state.store)

        Telemetry.job_cancel(%{job_name: job_name, queue: state.queue}, reason)

        new_state = %{state | running: running, job_refs: job_refs}
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed
    case Map.pop(state.running, ref) do
      {nil, _} ->
        {:noreply, state}

      {{job, attempt}, running} ->
        # Demonitor and flush
        Process.demonitor(ref, [:flush])

        # Remove from job_refs
        job_refs = Map.delete(state.job_refs, job.name)

        handle_job_result(job, result, attempt, %{state | running: running, job_refs: job_refs})
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed
    case Map.pop(state.running, ref) do
      {nil, _} ->
        {:noreply, state}

      {{job, attempt}, running} ->
        job_refs = Map.delete(state.job_refs, job.name)
        new_state = %{state | running: running, job_refs: job_refs}
        handle_task_crash(job, attempt, reason, new_state)
    end
  end

  def handle_info({:retry, job, attempt}, %{paused: true} = state) do
    # Queue is paused, re-schedule the retry
    schedule_retry(job, attempt, :paused, state)
    {:noreply, state}
  end

  def handle_info({:retry, job, attempt}, %{running: running, concurrency: concurrency} = state)
      when map_size(running) >= concurrency do
    # Queue is at capacity, re-schedule the retry
    schedule_retry(job, attempt, :at_capacity, state)
    {:noreply, state}
  end

  def handle_info({:retry, job, attempt}, state) do
    new_state = start_job(job, state, attempt)
    {:noreply, new_state}
  end

  def handle_info({:resume_preempted, job_name}, state) do
    case Map.pop(state.preempted, job_name) do
      {nil, _} ->
        {:noreply, state}

      {{job, attempt, ref, pid}, preempted} ->
        new_state = %{state | preempted: preempted}

        # Check if we have capacity now
        case map_size(new_state.running) < new_state.concurrency do
          true ->
            Logger.debug("[Scheduler.Queue.Producer] Resuming preempted job: #{job_name}")

            # Resume the suspended process
            :erlang.resume_process(pid)

            Telemetry.execute([:job, :resume], %{system_time: System.system_time()}, %{
              job_name: job_name,
              queue: state.queue,
              reason: :preemption_ended
            })

            # Add back to running
            resumed_state = %{
              new_state
              | running: Map.put(new_state.running, ref, {job, attempt}),
                job_refs: Map.put(new_state.job_refs, job_name, {ref, pid})
            }

            {:noreply, resumed_state}

          false ->
            # Still at capacity, re-queue for later
            Process.send_after(self(), {:resume_preempted, job_name}, 1000)
            {:noreply, %{state | preempted: Map.put(preempted, job_name, {job, attempt, ref, pid})}}
        end
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp handle_task_crash(%Job{max_retries: max_retries} = job, attempt, reason, state)
       when attempt < max_retries do
    schedule_retry(job, attempt + 1, reason, state)
    {:noreply, maybe_resume_preempted(state)}
  end

  defp handle_task_crash(job, _attempt, reason, state) do
    mark_job_failed(job.name, reason, state.store)
    {:noreply, maybe_resume_preempted(state)}
  end

  defp mark_job_failed(_name, _reason, nil), do: :ok

  defp mark_job_failed(name, reason, store) do
    store.mark_failed(name, reason, nil)
  end

  defp mark_job_cancelled(_name, _reason, nil), do: :ok

  defp mark_job_cancelled(name, reason, store) do
    store.mark_cancelled(name, reason)
  end

  defp start_job(job, state, attempt \\ 1) do
    case check_rate_limit(job, state) do
      :ok ->
        do_start_job(job, state, attempt)

      {:error, :rate_limited, retry_after} ->
        Logger.debug(
          "[Scheduler.Queue.Producer] Rate limited job=#{job.name}, retry_after=#{retry_after}ms"
        )

        Telemetry.job_skip(%{job: job, queue: state.queue}, :rate_limited)
        schedule_retry(job, attempt, :rate_limited, state)
        state
    end
  end

  defp do_start_job(job, state, attempt) do
    task =
      Task.async(fn ->
        Executor.execute(job, attempt: attempt, store: state.store)
      end)

    %{
      state
      | running: Map.put(state.running, task.ref, {job, attempt}),
        job_refs: Map.put(state.job_refs, job.name, {task.ref, task.pid})
    }
  end

  defp check_rate_limit(_job, %{rate_limiter: nil}), do: :ok

  defp check_rate_limit(job, %{rate_limiter: rate_limiter}) do
    RateLimiter.acquire_job(job, rate_limiter)
  end

  defp handle_job_result(job, {:ok, _value} = result, _attempt, state) do
    mark_job_completed(job, result, state.store)
    {:noreply, maybe_resume_preempted(state)}
  end

  defp handle_job_result(job, {:retry, reason}, attempt, state) do
    schedule_retry(job, attempt + 1, reason, state)
    {:noreply, state}
  end

  defp handle_job_result(job, {:error, reason}, _attempt, state) do
    mark_job_error(job, reason, state.store)
    {:noreply, maybe_resume_preempted(state)}
  end

  defp mark_job_completed(_job, _result, nil), do: :ok

  defp mark_job_completed(job, result, store) do
    next_run = calculate_next_run(job)
    store.mark_completed(job.name, result, next_run)
  end

  defp mark_job_error(_job, _reason, nil), do: :ok

  defp mark_job_error(job, reason, store) do
    next_run = calculate_next_run(job)
    store.mark_failed(job.name, reason, next_run)
  end

  defp schedule_retry(job, attempt, :rate_limited, state) do
    # For rate limited jobs, use a shorter delay based on the rate limiter
    delay =
      case check_rate_limit_delay(job, state) do
        {:ok, retry_after} when retry_after > 0 -> retry_after
        _ -> Executor.retry_delay(job, attempt)
      end

    Process.send_after(self(), {:retry, job, attempt}, delay)
  end

  defp schedule_retry(job, attempt, _reason, _state) do
    delay = Executor.retry_delay(job, attempt)

    # Schedule retry after delay
    Process.send_after(self(), {:retry, job, attempt}, delay)
  end

  defp check_rate_limit_delay(_job, %{rate_limiter: nil}), do: {:ok, 0}

  defp check_rate_limit_delay(job, %{rate_limiter: rate_limiter}) do
    case RateLimiter.check_job(job, rate_limiter) do
      :ok -> {:ok, 0}
      {:error, :rate_limited, retry_after} -> {:ok, retry_after}
    end
  end

  defp calculate_next_run(%Job{schedule_type: :reboot}), do: nil

  defp calculate_next_run(job) do
    case Job.calculate_next_run(job, DateTime.utc_now()) do
      {:ok, next} -> next
      {:error, _} -> nil
    end
  end

  defp running_job_names(state) do
    Map.keys(state.job_refs)
  end

  # ============================================
  # Preemption Helpers
  # ============================================

  defp find_preemptable_job(%Job{priority: incoming_priority}, state) do
    # Find a running job with lower priority (higher number = lower priority)
    # Only preempt if the incoming job has higher priority (lower number)
    state.running
    |> Enum.filter(fn {_ref, {job, _attempt}} ->
      job.priority > incoming_priority
    end)
    |> Enum.max_by(fn {_ref, {job, _attempt}} -> job.priority end, fn -> nil end)
  end

  defp preempt_job(ref, preemptable_job, attempt, incoming_job, state) do
    Logger.info(
      "[Scheduler.Queue.Producer] Preempting job #{preemptable_job.name} (priority #{preemptable_job.priority}) " <>
        "for #{incoming_job.name} (priority #{incoming_job.priority})"
    )

    # Get the task pid and suspend it
    case Map.get(state.job_refs, preemptable_job.name) do
      {^ref, pid} ->
        # Suspend the process instead of killing it
        :erlang.suspend_process(pid)

        Telemetry.execute([:job, :preempt], %{system_time: System.system_time()}, %{
          preempted_job: preemptable_job.name,
          preempted_priority: preemptable_job.priority,
          incoming_job: incoming_job.name,
          incoming_priority: incoming_job.priority,
          queue: state.queue
        })

        # Move to preempted map
        {_, running} = Map.pop(state.running, ref)
        job_refs = Map.delete(state.job_refs, preemptable_job.name)

        # Store suspended process info
        preempted =
          Map.put(state.preempted, preemptable_job.name, {preemptable_job, attempt, ref, pid})

        # Start the new job
        new_state = %{state | running: running, job_refs: job_refs, preempted: preempted}
        start_job(incoming_job, new_state)

      _ ->
        # Ref mismatch, just start the job normally (shouldn't happen)
        start_job(incoming_job, state)
    end
  end

  defp maybe_resume_preempted(state) do
    # Check if we can resume any preempted jobs
    case Map.keys(state.preempted) do
      [] ->
        state

      [job_name | _] ->
        Process.send_after(self(), {:resume_preempted, job_name}, 100)
        state
    end
  end
end
