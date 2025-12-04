defmodule Events.Infra.Scheduler.Workflow.Execution do
  @moduledoc """
  Tracks the execution state of a workflow run.

  An execution represents a single run of a workflow, including:
  - Current state and progress
  - Step states and results
  - Context accumulation
  - Timeline for introspection
  - Error information
  """

  alias Events.Infra.Scheduler.Workflow.Step

  @type state :: :pending | :running | :completed | :failed | :cancelled | :paused
  @type trigger :: %{type: :manual | :scheduled | :event, source: term()}

  @type step_info :: %{
          name: atom(),
          state: Step.state(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          attempt: non_neg_integer(),
          error: term() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          workflow_name: atom(),
          workflow_version: pos_integer(),
          state: state(),
          context: map(),
          initial_context: map(),
          step_states: %{atom() => Step.state()},
          step_results: %{atom() => term()},
          step_errors: %{atom() => term()},
          step_attempts: %{atom() => non_neg_integer()},
          completed_steps: [atom()],
          running_steps: [atom()],
          pending_steps: [atom()],
          skipped_steps: [atom()],
          cancelled_steps: [atom()],
          current_step: atom() | nil,
          trigger: trigger(),
          scheduled_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          paused_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          attempt: non_neg_integer(),
          max_attempts: non_neg_integer(),
          timeline: [step_info()],
          error: term() | nil,
          error_step: atom() | nil,
          stacktrace: String.t() | nil,
          cancellation_reason: term() | nil,
          parent_execution_id: String.t() | nil,
          child_executions: [String.t()],
          graft_expansions: %{atom() => [atom()]},
          metadata: map(),
          node: node()
        }

  defstruct [
    :id,
    :workflow_name,
    :current_step,
    :scheduled_at,
    :started_at,
    :completed_at,
    :paused_at,
    :duration_ms,
    :error,
    :error_step,
    :stacktrace,
    :cancellation_reason,
    :parent_execution_id,
    workflow_version: 1,
    state: :pending,
    context: %{},
    initial_context: %{},
    step_states: %{},
    step_results: %{},
    step_errors: %{},
    step_attempts: %{},
    completed_steps: [],
    running_steps: [],
    pending_steps: [],
    skipped_steps: [],
    cancelled_steps: [],
    trigger: %{type: :manual, source: nil},
    attempt: 1,
    max_attempts: 1,
    timeline: [],
    child_executions: [],
    graft_expansions: %{},
    metadata: %{},
    node: nil
  ]

  @doc """
  Creates a new execution for a workflow.
  """
  @spec new(atom(), map(), keyword()) :: t()
  def new(workflow_name, context \\ %{}, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      workflow_name: workflow_name,
      workflow_version: Keyword.get(opts, :version, 1),
      context: context,
      initial_context: context,
      trigger: build_trigger(opts),
      scheduled_at: Keyword.get(opts, :scheduled_at),
      max_attempts: Keyword.get(opts, :max_attempts, 1),
      parent_execution_id: Keyword.get(opts, :parent_execution_id),
      metadata: Keyword.get(opts, :metadata, %{}),
      node: node()
    }
  end

  @doc """
  Starts the execution.
  """
  @spec start(t(), [atom()]) :: t()
  def start(%__MODULE__{} = exec, step_names) do
    now = DateTime.utc_now()

    step_states = Map.new(step_names, fn name -> {name, :pending} end)
    step_attempts = Map.new(step_names, fn name -> {name, 0} end)

    %{
      exec
      | state: :running,
        started_at: now,
        step_states: step_states,
        step_attempts: step_attempts,
        pending_steps: step_names
    }
  end

  @doc """
  Records a step starting.
  """
  @spec step_started(t(), atom()) :: t()
  def step_started(%__MODULE__{} = exec, step_name) do
    now = DateTime.utc_now()
    attempts = Map.get(exec.step_attempts, step_name, 0) + 1

    timeline_entry = %{
      name: step_name,
      state: :running,
      started_at: now,
      completed_at: nil,
      duration_ms: nil,
      attempt: attempts,
      error: nil
    }

    %{
      exec
      | current_step: step_name,
        step_states: Map.put(exec.step_states, step_name, :running),
        step_attempts: Map.put(exec.step_attempts, step_name, attempts),
        running_steps: [step_name | exec.running_steps -- [step_name]],
        pending_steps: exec.pending_steps -- [step_name],
        timeline: [timeline_entry | exec.timeline]
    }
  end

  @doc """
  Records a step completing successfully.
  """
  @spec step_completed(t(), atom(), term()) :: t()
  def step_completed(%__MODULE__{} = exec, step_name, result) do
    now = DateTime.utc_now()

    # Update timeline entry
    timeline =
      update_timeline_entry(exec.timeline, step_name, fn entry ->
        duration =
          if entry.started_at, do: DateTime.diff(now, entry.started_at, :millisecond), else: 0

        %{entry | state: :completed, completed_at: now, duration_ms: duration}
      end)

    # Merge result into context
    new_context =
      case result do
        map when is_map(map) -> Map.merge(exec.context, map)
        _ -> exec.context
      end

    %{
      exec
      | step_states: Map.put(exec.step_states, step_name, :completed),
        step_results: Map.put(exec.step_results, step_name, result),
        completed_steps: [step_name | exec.completed_steps],
        running_steps: exec.running_steps -- [step_name],
        context: new_context,
        timeline: timeline,
        current_step: nil
    }
  end

  @doc """
  Records a step failing.
  """
  @spec step_failed(t(), atom(), term(), String.t() | nil) :: t()
  def step_failed(%__MODULE__{} = exec, step_name, error, stacktrace \\ nil) do
    now = DateTime.utc_now()

    timeline =
      update_timeline_entry(exec.timeline, step_name, fn entry ->
        duration =
          if entry.started_at, do: DateTime.diff(now, entry.started_at, :millisecond), else: 0

        %{entry | state: :failed, completed_at: now, duration_ms: duration, error: error}
      end)

    %{
      exec
      | step_states: Map.put(exec.step_states, step_name, :failed),
        step_errors: Map.put(exec.step_errors, step_name, error),
        running_steps: exec.running_steps -- [step_name],
        timeline: timeline,
        current_step: nil,
        error: error,
        error_step: step_name,
        stacktrace: stacktrace
    }
  end

  @doc """
  Records a step being skipped.
  """
  @spec step_skipped(t(), atom(), term()) :: t()
  def step_skipped(%__MODULE__{} = exec, step_name, reason \\ nil) do
    now = DateTime.utc_now()

    timeline_entry = %{
      name: step_name,
      state: :skipped,
      started_at: now,
      completed_at: now,
      duration_ms: 0,
      attempt: 0,
      error: nil
    }

    %{
      exec
      | step_states: Map.put(exec.step_states, step_name, :skipped),
        step_results: Map.put(exec.step_results, step_name, {:skipped, reason}),
        skipped_steps: [step_name | exec.skipped_steps],
        pending_steps: exec.pending_steps -- [step_name],
        timeline: [timeline_entry | exec.timeline]
    }
  end

  @doc """
  Records a step entering await state.
  """
  @spec step_awaiting(t(), atom(), keyword()) :: t()
  def step_awaiting(%__MODULE__{} = exec, step_name, opts) do
    timeline =
      update_timeline_entry(exec.timeline, step_name, fn entry ->
        %{entry | state: :awaiting}
      end)

    %{
      exec
      | state: :paused,
        step_states: Map.put(exec.step_states, step_name, :awaiting),
        running_steps: exec.running_steps -- [step_name],
        paused_at: DateTime.utc_now(),
        timeline: timeline,
        metadata: Map.put(exec.metadata, :await_opts, opts)
    }
  end

  @doc """
  Records a step being cancelled.
  """
  @spec step_cancelled(t(), atom()) :: t()
  def step_cancelled(%__MODULE__{} = exec, step_name) do
    %{
      exec
      | step_states: Map.put(exec.step_states, step_name, :cancelled),
        cancelled_steps: [step_name | exec.cancelled_steps],
        running_steps: exec.running_steps -- [step_name],
        pending_steps: exec.pending_steps -- [step_name]
    }
  end

  @doc """
  Marks execution as completed.
  """
  @spec complete(t()) :: t()
  def complete(%__MODULE__{} = exec) do
    now = DateTime.utc_now()
    duration = if exec.started_at, do: DateTime.diff(now, exec.started_at, :millisecond), else: 0

    %{exec | state: :completed, completed_at: now, duration_ms: duration, current_step: nil}
  end

  @doc """
  Marks execution as failed.
  """
  @spec fail(t(), term(), atom() | nil) :: t()
  def fail(%__MODULE__{} = exec, error, error_step \\ nil) do
    now = DateTime.utc_now()
    duration = if exec.started_at, do: DateTime.diff(now, exec.started_at, :millisecond), else: 0

    # Cancel any running steps
    cancelled_steps = exec.running_steps

    step_states =
      Enum.reduce(cancelled_steps, exec.step_states, fn step, acc ->
        Map.put(acc, step, :cancelled)
      end)

    %{
      exec
      | state: :failed,
        completed_at: now,
        duration_ms: duration,
        error: error,
        error_step: error_step || exec.error_step,
        current_step: nil,
        running_steps: [],
        cancelled_steps: exec.cancelled_steps ++ cancelled_steps,
        step_states: step_states
    }
  end

  @doc """
  Marks execution as cancelled.
  """
  @spec cancel(t(), term()) :: t()
  def cancel(%__MODULE__{} = exec, reason \\ :user_requested) do
    now = DateTime.utc_now()
    duration = if exec.started_at, do: DateTime.diff(now, exec.started_at, :millisecond), else: 0

    # Cancel all running and pending steps
    to_cancel = exec.running_steps ++ exec.pending_steps

    step_states =
      Enum.reduce(to_cancel, exec.step_states, fn step, acc ->
        Map.put(acc, step, :cancelled)
      end)

    %{
      exec
      | state: :cancelled,
        completed_at: now,
        duration_ms: duration,
        cancellation_reason: reason,
        current_step: nil,
        running_steps: [],
        pending_steps: [],
        cancelled_steps: exec.cancelled_steps ++ to_cancel,
        step_states: step_states
    }
  end

  @doc """
  Pauses the execution.
  """
  @spec pause(t()) :: t()
  def pause(%__MODULE__{} = exec) do
    %{exec | state: :paused, paused_at: DateTime.utc_now()}
  end

  @doc """
  Resumes a paused execution.
  """
  @spec resume(t(), map()) :: t()
  def resume(%__MODULE__{} = exec, additional_context \\ %{}) do
    new_context = Map.merge(exec.context, additional_context)

    # Resume any awaiting steps to pending
    step_states =
      Enum.reduce(exec.step_states, exec.step_states, fn {name, state}, acc ->
        if state == :awaiting do
          Map.put(acc, name, :pending)
        else
          acc
        end
      end)

    awaiting_steps =
      exec.step_states
      |> Enum.filter(fn {_name, state} -> state == :awaiting end)
      |> Enum.map(fn {name, _} -> name end)

    %{
      exec
      | state: :running,
        context: new_context,
        paused_at: nil,
        step_states: step_states,
        pending_steps: exec.pending_steps ++ awaiting_steps
    }
  end

  @doc """
  Records a graft expansion.
  """
  @spec record_graft_expansion(t(), atom(), [atom()]) :: t()
  def record_graft_expansion(%__MODULE__{} = exec, graft_name, expanded_steps) do
    # Add expanded steps to pending
    new_pending = exec.pending_steps ++ expanded_steps

    # Initialize step states for expanded steps
    new_step_states =
      Enum.reduce(expanded_steps, exec.step_states, fn name, acc ->
        Map.put(acc, name, :pending)
      end)

    new_step_attempts =
      Enum.reduce(expanded_steps, exec.step_attempts, fn name, acc ->
        Map.put(acc, name, 0)
      end)

    %{
      exec
      | graft_expansions: Map.put(exec.graft_expansions, graft_name, expanded_steps),
        pending_steps: new_pending,
        step_states: new_step_states,
        step_attempts: new_step_attempts
    }
  end

  @doc """
  Adds a child execution (for nested workflows).
  """
  @spec add_child_execution(t(), String.t()) :: t()
  def add_child_execution(%__MODULE__{} = exec, child_id) do
    %{exec | child_executions: [child_id | exec.child_executions]}
  end

  @doc """
  Gets progress as a tuple {completed, total}.
  """
  @spec progress(t()) :: {non_neg_integer(), non_neg_integer()}
  def progress(%__MODULE__{} = exec) do
    completed = length(exec.completed_steps) + length(exec.skipped_steps)
    total = map_size(exec.step_states)
    {completed, total}
  end

  @doc """
  Gets error context for failure handlers.
  """
  @spec error_context(t()) :: map()
  def error_context(%__MODULE__{} = exec) do
    Map.merge(exec.context, %{
      __error__: exec.error,
      __error_step__: exec.error_step,
      __attempts__: Map.get(exec.step_attempts, exec.error_step, 0),
      __stacktrace__: exec.stacktrace
    })
  end

  @doc """
  Checks if execution is in a terminal state.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}) do
    state in [:completed, :failed, :cancelled]
  end

  @doc """
  Gets formatted timeline for introspection.
  """
  @spec get_timeline(t()) :: [step_info()]
  def get_timeline(%__MODULE__{timeline: timeline}) do
    Enum.reverse(timeline)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp generate_id do
    # Generate UUID-like ID
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
        e::binary-size(12)>> = hex

      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end)
  end

  defp build_trigger(opts) do
    type =
      cond do
        Keyword.has_key?(opts, :event) -> :event
        Keyword.has_key?(opts, :scheduled_at) -> :scheduled
        true -> :manual
      end

    source = Keyword.get(opts, :trigger_source)

    %{type: type, source: source}
  end

  defp update_timeline_entry(timeline, step_name, update_fn) do
    case Enum.split_while(timeline, fn entry -> entry.name != step_name end) do
      {before, [entry | after_entries]} ->
        before ++ [update_fn.(entry) | after_entries]

      {all, []} ->
        all
    end
  end
end
