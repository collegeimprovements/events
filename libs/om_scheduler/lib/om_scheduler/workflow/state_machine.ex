defmodule OmScheduler.Workflow.StateMachine do
  @moduledoc """
  State machine for workflow and step lifecycle management.

  Handles:
  - State transitions with validation
  - Dependency resolution
  - Ready step identification
  - Workflow completion detection
  """

  alias OmScheduler.Workflow
  alias OmScheduler.Workflow.{Step, Execution}

  # ============================================
  # Workflow State Transitions
  # ============================================

  @workflow_transitions %{
    pending: [:running, :cancelled],
    running: [:completed, :failed, :cancelled, :paused],
    paused: [:running, :cancelled],
    completed: [],
    failed: [],
    cancelled: []
  }

  @step_transitions %{
    pending: [:ready, :running, :skipped, :cancelled],
    ready: [:running, :skipped, :cancelled],
    running: [:completed, :failed, :cancelled, :awaiting],
    awaiting: [:running, :cancelled, :pending],
    completed: [],
    failed: [:pending],
    skipped: [],
    cancelled: []
  }

  @doc """
  Validates and performs a workflow state transition.
  """
  @spec transition_workflow(Execution.t(), Workflow.state()) ::
          {:ok, Execution.t()} | {:error, term()}
  def transition_workflow(%Execution{state: current} = exec, new_state) do
    allowed = Map.get(@workflow_transitions, current, [])

    if new_state in allowed do
      {:ok, %{exec | state: new_state}}
    else
      {:error, {:invalid_transition, current, new_state}}
    end
  end

  @doc """
  Validates and performs a step state transition.
  """
  @spec transition_step(Step.t(), Step.state()) :: {:ok, Step.t()} | {:error, term()}
  def transition_step(%Step{state: current} = step, new_state) do
    allowed = Map.get(@step_transitions, current, [])

    if new_state in allowed do
      {:ok, Step.transition(step, new_state)}
    else
      {:error, {:invalid_transition, current, new_state}}
    end
  end

  # ============================================
  # Dependency Resolution
  # ============================================

  @doc """
  Gets all steps that are ready to execute.

  A step is ready when:
  1. It's in :pending state
  2. All dependencies are satisfied
  3. Group dependencies (if any) are satisfied
  4. Graft dependencies (if any) are satisfied
  """
  @spec get_ready_steps(Workflow.t(), Execution.t()) :: [atom()]
  def get_ready_steps(%Workflow{} = workflow, %Execution{} = exec) do
    completed_set = MapSet.new(exec.completed_steps)
    groups_completed = get_completed_groups(workflow, exec)

    workflow.steps
    |> Enum.filter(fn {name, _step} ->
      Map.get(exec.step_states, name) == :pending
    end)
    |> Enum.filter(fn {name, step} ->
      dependencies_satisfied?(step, name, workflow, completed_set, groups_completed, exec)
    end)
    |> Enum.map(fn {name, _step} -> name end)
  end

  @doc """
  Checks if a specific step's dependencies are satisfied.
  """
  @spec dependencies_satisfied?(Step.t(), atom(), Workflow.t(), MapSet.t(), map(), Execution.t()) ::
          boolean()
  def dependencies_satisfied?(
        %Step{} = step,
        step_name,
        %Workflow{} = workflow,
        completed_set,
        groups_completed,
        %Execution{} = exec
      ) do
    # Check direct dependencies
    direct_satisfied =
      case step.depends_on do
        [] -> true
        deps -> Enum.all?(deps, &MapSet.member?(completed_set, &1))
      end

    # Check any dependencies
    any_satisfied =
      case step.depends_on_any do
        [] -> true
        deps -> Enum.any?(deps, &MapSet.member?(completed_set, &1))
      end

    # Check group dependencies
    group_satisfied =
      case step.depends_on_group do
        nil -> true
        group -> Map.get(groups_completed, group, false)
      end

    # Check graft dependencies
    graft_satisfied =
      case step.depends_on_graft do
        nil -> true
        graft_name -> graft_completed?(graft_name, workflow, exec)
      end

    # Check adjacency list dependencies
    adjacency_satisfied =
      case Map.get(workflow.adjacency, step_name, []) do
        [] ->
          true

        deps ->
          Enum.all?(deps, fn
            {:group, group_name} -> Map.get(groups_completed, group_name, false)
            {:graft, graft_name} -> graft_completed?(graft_name, workflow, exec)
            dep -> MapSet.member?(completed_set, dep)
          end)
      end

    direct_satisfied and any_satisfied and group_satisfied and graft_satisfied and
      adjacency_satisfied
  end

  @doc """
  Gets a map of group names to their completion status.
  """
  @spec get_completed_groups(Workflow.t(), Execution.t()) :: %{atom() => boolean()}
  def get_completed_groups(%Workflow{groups: groups}, %Execution{} = exec) do
    completed_set = MapSet.new(exec.completed_steps ++ exec.skipped_steps)

    Map.new(groups, fn {group_name, members} ->
      all_done = Enum.all?(members, &MapSet.member?(completed_set, &1))
      {group_name, all_done}
    end)
  end

  @doc """
  Checks if a graft and all its expanded steps are completed.
  """
  @spec graft_completed?(atom(), Workflow.t(), Execution.t()) :: boolean()
  def graft_completed?(graft_name, %Workflow{grafts: grafts}, %Execution{} = exec) do
    case Map.get(grafts, graft_name) do
      nil ->
        true

      graft ->
        if graft.expanded do
          expanded_steps = Map.get(exec.graft_expansions, graft_name, [])
          completed_set = MapSet.new(exec.completed_steps ++ exec.skipped_steps)
          Enum.all?(expanded_steps, &MapSet.member?(completed_set, &1))
        else
          # Graft not yet expanded, check if graft step itself is completed
          MapSet.member?(MapSet.new(exec.completed_steps), graft_name)
        end
    end
  end

  # ============================================
  # Completion Detection
  # ============================================

  @doc """
  Checks if the workflow execution is complete.

  A workflow is complete when all steps are in terminal states
  (completed, failed, skipped, or cancelled).
  """
  @spec workflow_complete?(Workflow.t(), Execution.t()) :: boolean()
  def workflow_complete?(%Workflow{} = workflow, %Execution{} = exec) do
    all_steps = Map.keys(workflow.steps)

    # Include any dynamically expanded steps from grafts
    all_steps =
      exec.graft_expansions
      |> Map.values()
      |> List.flatten()
      |> Kernel.++(all_steps)
      |> Enum.uniq()

    terminal_steps =
      (exec.completed_steps ++ failed_steps(exec) ++ exec.skipped_steps ++ exec.cancelled_steps)
      |> MapSet.new()

    Enum.all?(all_steps, &MapSet.member?(terminal_steps, &1))
  end

  # Handle missing field gracefully
  defp failed_steps(%Execution{} = exec) do
    exec.step_states
    |> Enum.filter(fn {_name, state} -> state == :failed end)
    |> Enum.map(fn {name, _state} -> name end)
  end

  @doc """
  Checks if workflow has any failed steps.
  """
  @spec has_failures?(Execution.t()) :: boolean()
  def has_failures?(%Execution{} = exec) do
    Enum.any?(exec.step_states, fn {_name, state} -> state == :failed end)
  end

  @doc """
  Gets all steps that failed.
  """
  @spec get_failed_steps(Execution.t()) :: [atom()]
  def get_failed_steps(%Execution{} = exec) do
    failed_steps(exec)
  end

  @doc """
  Checks if workflow should fail based on step failures and on_error settings.
  """
  @spec should_fail?(Workflow.t(), Execution.t()) :: boolean()
  def should_fail?(%Workflow{} = workflow, %Execution{} = exec) do
    failed_steps = get_failed_steps(exec)

    Enum.any?(failed_steps, fn step_name ->
      case Map.get(workflow.steps, step_name) do
        nil -> true
        step -> step.on_error == :fail
      end
    end)
  end

  # ============================================
  # Snooze/Pause Handling
  # ============================================

  @doc """
  Checks if workflow is paused waiting for human input.
  """
  @spec is_awaiting?(Execution.t()) :: boolean()
  def is_awaiting?(%Execution{} = exec) do
    exec.state == :paused or
      Enum.any?(exec.step_states, fn {_name, state} -> state == :awaiting end)
  end

  @doc """
  Gets steps that are awaiting human input.
  """
  @spec get_awaiting_steps(Execution.t()) :: [atom()]
  def get_awaiting_steps(%Execution{} = exec) do
    exec.step_states
    |> Enum.filter(fn {_name, state} -> state == :awaiting end)
    |> Enum.map(fn {name, _state} -> name end)
  end

  # ============================================
  # Rollback Order
  # ============================================

  @doc """
  Gets steps that need rollback in the correct order (reverse completion order).
  """
  @spec get_rollback_order(Workflow.t(), Execution.t()) :: [atom()]
  def get_rollback_order(%Workflow{} = workflow, %Execution{} = exec) do
    # Get completed steps in reverse order (most recent first)
    exec.completed_steps
    |> Enum.reverse()
    |> Enum.filter(fn step_name ->
      case Map.get(workflow.steps, step_name) do
        nil -> false
        step -> Step.has_rollback?(step)
      end
    end)
  end

  # ============================================
  # Condition Evaluation
  # ============================================

  @doc """
  Evaluates a step's condition with the current context.

  Returns true if:
  - Step has no condition
  - Condition function returns true
  """
  @spec evaluate_condition(Step.t(), map()) :: boolean()
  def evaluate_condition(%Step{condition: nil}, _ctx), do: true

  def evaluate_condition(%Step{condition: condition}, ctx) when is_function(condition, 1) do
    try do
      condition.(ctx)
    rescue
      _ -> false
    end
  end

  @doc """
  Gets steps that should be skipped due to condition evaluation.
  """
  @spec get_skippable_steps(Workflow.t(), Execution.t()) :: [atom()]
  def get_skippable_steps(%Workflow{} = workflow, %Execution{} = exec) do
    ready_steps = get_ready_steps(workflow, exec)

    Enum.filter(ready_steps, fn step_name ->
      step = Map.get(workflow.steps, step_name)
      step && not evaluate_condition(step, exec.context)
    end)
  end

  # ============================================
  # Progress Tracking
  # ============================================

  @doc """
  Gets workflow progress as percentage.
  """
  @spec progress_percentage(Workflow.t(), Execution.t()) :: float()
  def progress_percentage(%Workflow{} = workflow, %Execution{} = exec) do
    total = map_size(workflow.steps) + length(List.flatten(Map.values(exec.graft_expansions)))

    if total == 0 do
      100.0
    else
      completed = length(exec.completed_steps) + length(exec.skipped_steps)
      completed / total * 100
    end
  end

  @doc """
  Gets current step being executed (if any).
  """
  @spec current_step(Execution.t()) :: atom() | nil
  def current_step(%Execution{running_steps: [step | _]}), do: step
  def current_step(%Execution{}), do: nil

  @doc """
  Checks if workflow can proceed (not blocked).
  """
  @spec can_proceed?(Workflow.t(), Execution.t()) :: boolean()
  def can_proceed?(%Workflow{} = workflow, %Execution{} = exec) do
    cond do
      exec.state != :running -> false
      is_awaiting?(exec) -> false
      workflow_complete?(workflow, exec) -> false
      should_fail?(workflow, exec) -> false
      true -> length(get_ready_steps(workflow, exec)) > 0 or length(exec.running_steps) > 0
    end
  end
end
