defmodule Events.Infra.Scheduler.Workflow.Engine do
  @moduledoc """
  Workflow execution engine.

  Orchestrates workflow execution including:
  - Starting and scheduling workflows
  - Step execution with timeout and retry
  - Parallel execution of ready steps
  - Cancellation and pause/resume
  - Rollback on failure (saga pattern)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.Workflow.{Step, Execution, StateMachine, Registry, Store, Telemetry}
  alias Events.Infra.Scheduler.Workflow.Step.Executable

  @type start_opts :: [context: map(), scheduled_at: DateTime.t(), in: {pos_integer(), atom()}]

  defstruct [:workflow, :execution, :store, :step_concurrency, :timers]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts a workflow execution.
  """
  @spec start_workflow(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def start_workflow(workflow_name, context \\ %{}) do
    with {:ok, workflow} <- get_workflow(workflow_name) do
      execution = Execution.new(workflow_name, context, version: workflow.version)

      case GenServer.start(__MODULE__, {workflow, execution}, name: via(execution.id)) do
        {:ok, _pid} -> {:ok, execution.id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Starts a workflow and waits for completion (for nested workflows).
  """
  @spec start_workflow_sync(atom(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def start_workflow_sync(workflow_name, context \\ %{}, timeout \\ :timer.minutes(30)) do
    with {:ok, execution_id} <- start_workflow(workflow_name, context) do
      wait_for_completion(execution_id, timeout)
    end
  end

  @doc """
  Schedules a workflow for future execution.
  """
  @spec schedule_workflow(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def schedule_workflow(workflow_name, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    scheduled_at = get_scheduled_time(opts)

    with {:ok, workflow} <- get_workflow(workflow_name) do
      execution =
        Execution.new(workflow_name, context, version: workflow.version, scheduled_at: scheduled_at)

      delay = DateTime.diff(scheduled_at, DateTime.utc_now(), :millisecond)
      delay = max(delay, 0)

      Process.send_after(self(), {:start_scheduled, workflow, execution}, delay)
      {:ok, execution.id}
    end
  end

  @doc """
  Cancels a running workflow.
  """
  @spec cancel(String.t(), keyword()) :: :ok | {:error, term()}
  def cancel(execution_id, opts \\ []) do
    case GenServer.whereis(via(execution_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:cancel, opts})
    end
  end

  @doc """
  Cancels all running executions of a workflow.
  """
  @spec cancel_all(atom(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cancel_all(workflow_name, opts \\ []) do
    executions = list_running(workflow_name)

    count =
      Enum.count(executions, fn exec ->
        case cancel(exec.id, opts) do
          :ok -> true
          _ -> false
        end
      end)

    {:ok, count}
  end

  @doc """
  Pauses a running workflow.
  """
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(execution_id) do
    case GenServer.whereis(via(execution_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :pause)
    end
  end

  @doc """
  Resumes a paused workflow.
  """
  @spec resume(String.t(), keyword()) :: :ok | {:error, term()}
  def resume(execution_id, opts \\ []) do
    case GenServer.whereis(via(execution_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:resume, opts})
    end
  end

  @doc """
  Gets current state of an execution.
  """
  @spec get_state(String.t()) :: {:ok, map()} | {:error, term()}
  def get_state(execution_id) do
    case GenServer.whereis(via(execution_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  @doc """
  Lists running executions for a workflow.
  """
  @spec list_running(atom()) :: [map()]
  def list_running(_workflow_name) do
    # In production, query from store
    []
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init({workflow, execution}) do
    state = %__MODULE__{
      workflow: workflow,
      execution: execution,
      store: Store,
      step_concurrency: 5,
      timers: %{}
    }

    # Emit telemetry for workflow start
    Telemetry.workflow_start(workflow.name, execution.id, %{
      trigger_type: execution.trigger.type
    })

    # Persist initial execution state
    persist_execution(state)

    # Start execution immediately
    send(self(), :run)

    {:ok, state}
  end

  @impl true
  def handle_call({:cancel, opts}, _from, state) do
    reason = Keyword.get(opts, :reason, :user_requested)
    do_rollback = Keyword.get(opts, :rollback, false)

    new_exec = Execution.cancel(state.execution, reason)

    # Emit telemetry for cancellation
    Telemetry.workflow_cancel(state.workflow.name, new_exec.id, reason)

    if do_rollback do
      run_rollbacks(state.workflow, new_exec)
    end

    # Run on_cancel handler if defined
    if state.workflow.on_cancel do
      run_handler(state.workflow.module, state.workflow.on_cancel, new_exec.context)
    end

    new_state = %{state | execution: new_exec}
    persist_execution(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call(:pause, _from, state) do
    new_exec = Execution.pause(state.execution)

    # Emit telemetry for pause
    Telemetry.workflow_pause(state.workflow.name, new_exec.id, new_exec.current_step)

    new_state = %{state | execution: new_exec}
    persist_execution(new_state)

    {:reply, :ok, new_state}
  end

  def handle_call({:resume, opts}, _from, state) do
    additional_context = Keyword.get(opts, :context, %{})
    new_exec = Execution.resume(state.execution, additional_context)

    # Emit telemetry for resume
    Telemetry.workflow_resume(state.workflow.name, new_exec.id)

    new_state = %{state | execution: new_exec}
    persist_execution(new_state)

    # Continue execution
    send(self(), :run)

    {:reply, :ok, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {completed, total} = Execution.progress(state.execution)

    reply = %{
      id: state.execution.id,
      workflow: state.execution.workflow_name,
      state: state.execution.state,
      current_step: state.execution.current_step,
      progress: {completed, total},
      context: state.execution.context,
      started_at: state.execution.started_at,
      duration_ms: state.execution.duration_ms
    }

    {:reply, {:ok, reply}, state}
  end

  @impl true
  def handle_info(:run, state) do
    new_state = run_workflow(state)
    {:noreply, new_state}
  end

  def handle_info({:step_completed, step_name, result}, state) do
    new_state = handle_step_result(state, step_name, {:ok, result})
    {:noreply, new_state}
  end

  def handle_info({:step_failed, step_name, error}, state) do
    new_state = handle_step_result(state, step_name, {:error, error})
    {:noreply, new_state}
  end

  def handle_info({:step_timeout, step_name}, state) do
    new_state = handle_step_result(state, step_name, {:error, :timeout})
    {:noreply, new_state}
  end

  def handle_info({:start_scheduled, workflow, execution}, _state) do
    # Start the scheduled workflow
    state = %__MODULE__{
      workflow: workflow,
      execution: execution,
      store: nil,
      step_concurrency: 5,
      timers: %{}
    }

    send(self(), :run)
    {:noreply, state}
  end

  # ============================================
  # Core Execution Logic
  # ============================================

  defp run_workflow(state) do
    workflow = state.workflow
    exec = state.execution

    cond do
      # Not running yet - start
      exec.state == :pending ->
        step_names = Map.keys(workflow.steps)
        new_exec = Execution.start(exec, step_names)
        run_workflow(%{state | execution: new_exec})

      # Completed or failed - stop
      Execution.terminal?(exec) ->
        finalize_workflow(state)

      # Paused - wait
      exec.state == :paused ->
        state

      # Running - execute ready steps
      exec.state == :running ->
        execute_ready_steps(state)
    end
  end

  defp execute_ready_steps(state) do
    workflow = state.workflow
    exec = state.execution

    # Check for workflow-level failure
    if StateMachine.should_fail?(workflow, exec) do
      fail_workflow(state)
    else
      # Get ready steps
      ready = StateMachine.get_ready_steps(workflow, exec)

      # Check conditions and skip if needed
      {to_execute, to_skip} = partition_by_condition(ready, workflow, exec)

      # Skip steps with false conditions
      exec =
        Enum.reduce(to_skip, exec, fn step_name, acc ->
          Execution.step_skipped(acc, step_name, :condition_not_met)
        end)

      # Execute ready steps (up to concurrency limit)
      running_count = length(exec.running_steps)
      available_slots = max(0, state.step_concurrency - running_count)
      steps_to_run = Enum.take(to_execute, available_slots)

      {new_exec, new_timers} =
        Enum.reduce(steps_to_run, {exec, state.timers}, fn step_name, {e, t} ->
          execute_step(step_name, workflow, e, t)
        end)

      new_state = %{state | execution: new_exec, timers: new_timers}

      # Check if workflow is complete
      if StateMachine.workflow_complete?(workflow, new_exec) do
        finalize_workflow(new_state)
      else
        new_state
      end
    end
  end

  defp execute_step(step_name, workflow, exec, timers) do
    step = Map.get(workflow.steps, step_name)
    timeout = Step.get_timeout(step, exec.context)

    # Mark step as running
    attempt = Map.get(exec.step_attempts, step_name, 0) + 1
    exec = Execution.step_started(exec, step_name)

    # Emit telemetry for step start
    Telemetry.step_start(workflow.name, exec.id, step_name, attempt)

    # Persist step start to database
    Store.record_step_start(exec.id, step_name, attempt)

    # Set cancellation flag in process dict
    Process.put(:__workflow_cancelled__, false)

    # Execute asynchronously
    parent = self()
    start_time = System.monotonic_time()

    Task.start(fn ->
      result = execute_step_with_retry(step, exec.context, workflow)
      duration = System.monotonic_time() - start_time

      case result do
        {:ok, value} ->
          Telemetry.step_stop(workflow.name, exec.id, step_name, duration, {:ok, value})
          send(parent, {:step_completed, step_name, value})

        {:error, error} ->
          send(parent, {:step_failed, step_name, error})

        {:skip, reason} ->
          Telemetry.step_skip(workflow.name, exec.id, step_name, reason)
          send(parent, {:step_completed, step_name, {:skipped, reason}})

        {:await, opts} ->
          send(parent, {:step_awaiting, step_name, opts})

        {:expand, expansions} ->
          send(parent, {:step_expand, step_name, expansions})

        {:snooze, duration} ->
          send(parent, {:step_snooze, step_name, duration})
      end
    end)

    # Set timeout timer
    timer_ref =
      if timeout != :infinity do
        Process.send_after(self(), {:step_timeout, step_name}, timeout)
      end

    timers = if timer_ref, do: Map.put(timers, step_name, timer_ref), else: timers

    {exec, timers}
  end

  defp execute_step_with_retry(step, context, workflow) do
    result = Executable.execute(step.job, context)

    case result do
      {:ok, _} = success ->
        success

      :ok ->
        {:ok, %{}}

      {:error, error} ->
        if Step.can_retry?(step) and Step.should_retry_error?(step, error) do
          delay = Step.calculate_retry_delay(step)
          Process.sleep(delay)
          new_step = Step.reset_for_retry(step)
          execute_step_with_retry(new_step, context, workflow)
        else
          {:error, error}
        end

      other ->
        other
    end
  end

  defp handle_step_result(state, step_name, result) do
    # Cancel timeout timer
    case Map.get(state.timers, step_name) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    new_timers = Map.delete(state.timers, step_name)

    new_exec =
      case result do
        {:ok, value} ->
          # Record step completion in database
          Store.record_step_complete(state.execution.id, step_name, value)
          Execution.step_completed(state.execution, step_name, value)

        {:error, error} ->
          step = Map.get(state.workflow.steps, step_name)

          # Emit telemetry for step failure
          Telemetry.step_exception(
            state.workflow.name,
            state.execution.id,
            step_name,
            0,
            :error,
            error,
            []
          )

          # Record step failure in database
          Store.record_step_failed(state.execution.id, step_name, error)

          case step.on_error do
            :fail ->
              Execution.step_failed(state.execution, step_name, error)

            :skip ->
              Execution.step_skipped(state.execution, step_name, error)

            :continue ->
              exec = Execution.step_failed(state.execution, step_name, error)
              # Continue workflow despite failure
              %{exec | step_states: Map.put(exec.step_states, step_name, :failed)}
          end
      end

    new_state = %{state | execution: new_exec, timers: new_timers}

    # Persist updated execution state
    persist_execution(new_state)

    # Call on_step_error if configured and step failed
    case result do
      {:error, error} when state.workflow.on_step_error != nil ->
        attempt = Map.get(new_exec.step_attempts, step_name, 0)

        run_step_error_handler(
          state.workflow.module,
          state.workflow.on_step_error,
          new_exec.context,
          step_name,
          error,
          attempt
        )

      _ ->
        :ok
    end

    # Continue execution
    send(self(), :run)
    new_state
  end

  defp fail_workflow(state) do
    exec = Execution.fail(state.execution, state.execution.error, state.execution.error_step)

    # Emit telemetry for workflow failure
    Telemetry.workflow_fail(state.workflow.name, exec.id, exec.error, exec.error_step)

    # Run rollbacks with telemetry
    Telemetry.rollback_span(state.workflow.name, exec.id, exec.completed_steps, %{}, fn ->
      run_rollbacks(state.workflow, exec)
    end)

    # Run on_failure handler
    if state.workflow.on_failure do
      ctx = Execution.error_context(exec)
      run_handler(state.workflow.module, state.workflow.on_failure, ctx)
    end

    new_state = %{state | execution: exec}
    persist_execution(new_state)
    new_state
  end

  defp finalize_workflow(state) do
    exec = state.execution
    workflow = state.workflow

    cond do
      StateMachine.has_failures?(exec) and StateMachine.should_fail?(workflow, exec) ->
        fail_workflow(state)

      true ->
        # Mark as completed
        new_exec = Execution.complete(exec)

        # Emit telemetry for workflow completion
        Telemetry.workflow_stop(workflow.name, new_exec.id, new_exec.duration_ms || 0, %{
          state: :completed
        })

        # Run on_success handler
        if workflow.on_success do
          run_handler(workflow.module, workflow.on_success, new_exec.context)
        end

        new_state = %{state | execution: new_exec}
        persist_execution(new_state)
        new_state
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp partition_by_condition(ready_steps, workflow, exec) do
    Enum.split_with(ready_steps, fn step_name ->
      step = Map.get(workflow.steps, step_name)
      StateMachine.evaluate_condition(step, exec.context)
    end)
  end

  defp run_rollbacks(workflow, exec) do
    rollback_order = StateMachine.get_rollback_order(workflow, exec)

    Enum.each(rollback_order, fn step_name ->
      step = Map.get(workflow.steps, step_name)

      try do
        Executable.rollback(step.job, exec.context)
      rescue
        e ->
          Logger.error("Rollback failed for step #{step_name}: #{Exception.message(e)}")
      end
    end)
  end

  defp run_handler(module, handler, context) when is_atom(handler) do
    try do
      apply(module, handler, [context])
    rescue
      e ->
        Logger.error("Handler #{handler} failed: #{Exception.message(e)}")
    end
  end

  defp run_handler(_module, _handler, _context), do: :ok

  defp run_step_error_handler(module, handler, context, step_name, error, attempt) do
    try do
      apply(module, handler, [context, step_name, error, attempt])
    rescue
      e ->
        Logger.error("Step error handler failed: #{Exception.message(e)}")
    end
  end

  defp get_workflow(workflow_name) do
    # Try Registry first (in-memory, faster)
    case Registry.get_workflow(workflow_name) do
      {:ok, workflow} ->
        {:ok, workflow}

      {:error, :not_found} ->
        # Fallback to database Store
        case Store.get_workflow(workflow_name) do
          {:ok, workflow} ->
            # Cache in Registry for future lookups
            Registry.register_workflow(workflow)
            {:ok, workflow}

          {:error, :not_found} ->
            {:error, {:workflow_not_found, workflow_name}}

          error ->
            error
        end
    end
  catch
    :exit, _ ->
      # Registry not running, try Store directly
      case Store.get_workflow(workflow_name) do
        {:ok, workflow} -> {:ok, workflow}
        {:error, :not_found} -> {:error, {:workflow_not_found, workflow_name}}
        error -> error
      end
  end

  defp get_scheduled_time(opts) do
    cond do
      Keyword.has_key?(opts, :at) ->
        Keyword.get(opts, :at)

      Keyword.has_key?(opts, :in) ->
        {amount, unit} = Keyword.get(opts, :in)
        ms = amount * time_unit_to_ms(unit)
        DateTime.add(DateTime.utc_now(), ms, :millisecond)

      true ->
        DateTime.utc_now()
    end
  end

  defp time_unit_to_ms(:millisecond), do: 1
  defp time_unit_to_ms(:second), do: 1000
  defp time_unit_to_ms(:minute), do: 60_000
  defp time_unit_to_ms(:hour), do: 3_600_000
  defp time_unit_to_ms(:day), do: 86_400_000

  defp wait_for_completion(execution_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(execution_id, deadline)
  end

  defp wait_loop(execution_id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case get_state(execution_id) do
        {:ok, %{state: :completed, context: ctx}} ->
          {:ok, ctx}

        {:ok, %{state: :failed, context: ctx}} ->
          error = Map.get(ctx, :__error__, :unknown)
          {:error, error}

        {:ok, %{state: :cancelled}} ->
          {:error, :cancelled}

        {:ok, _} ->
          Process.sleep(100)
          wait_loop(execution_id, deadline)

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end
  end

  defp via(execution_id) do
    {:via, Registry, {Events.Infra.Scheduler.Workflow.Registry, execution_id}}
  end

  defp persist_execution(state) do
    # Persist to database asynchronously to avoid blocking
    Task.start(fn ->
      case Store.update_execution(state.execution) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[Workflow.Engine] Failed to persist execution: #{inspect(reason)}")
      end
    end)
  end
end
