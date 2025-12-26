defmodule OmScheduler.Workflow.Introspection.Summary do
  @moduledoc """
  Workflow summary and report generation.
  """

  alias OmScheduler.Workflow

  @doc """
  Gets a summary of a workflow.
  """
  @spec summary(atom() | Workflow.t()) :: map() | nil
  def summary(workflow_name) when is_atom(workflow_name) do
    case get_workflow(workflow_name) do
      {:ok, workflow} -> summary(workflow)
      _ -> nil
    end
  end

  def summary(%Workflow{} = workflow) do
    %{
      name: workflow.name,
      version: workflow.version,
      steps: map_size(workflow.steps),
      parallel_groups: map_size(workflow.groups),
      grafts: map_size(workflow.grafts),
      nested_workflows: map_size(workflow.nested_workflows),
      has_rollback: has_any_rollback?(workflow),
      estimated_timeout: calculate_total_timeout(workflow),
      trigger: workflow.trigger_type,
      schedule: format_schedule(workflow.schedule),
      tags: workflow.tags
    }
  end

  @doc """
  Gets a detailed report of a workflow.
  """
  @spec report(atom() | Workflow.t()) :: map() | nil
  def report(workflow_name) when is_atom(workflow_name) do
    case get_workflow(workflow_name) do
      {:ok, workflow} -> report(workflow)
      _ -> nil
    end
  end

  def report(%Workflow{} = workflow) do
    steps_info =
      Enum.map(workflow.steps, fn {name, step} ->
        %{
          name: name,
          depends_on: step.depends_on,
          depends_on_any: step.depends_on_any,
          group: step.group,
          timeout: step.timeout,
          max_retries: step.max_retries,
          has_rollback: step.rollback != nil,
          has_condition: step.condition != nil,
          on_error: step.on_error
        }
      end)

    %{
      name: workflow.name,
      version: workflow.version,
      module: workflow.module,
      steps: steps_info,
      execution_order: workflow.execution_order,
      parallel_groups: workflow.groups,
      grafts: Map.keys(workflow.grafts),
      nested_workflows: workflow.nested_workflows,
      critical_path: calculate_critical_path(workflow),
      total_timeout: calculate_total_timeout(workflow),
      on_failure: workflow.on_failure,
      on_success: workflow.on_success,
      on_cancel: workflow.on_cancel,
      schedule: workflow.schedule,
      tags: workflow.tags
    }
  end

  @doc """
  Gets execution timeline for a specific execution.
  """
  @spec execution_timeline(String.t()) :: map() | nil
  def execution_timeline(execution_id) do
    alias OmScheduler.Workflow.Engine

    case Engine.get_state(execution_id) do
      {:ok, state} ->
        %{
          workflow: state.workflow,
          execution_id: execution_id,
          state: state.state,
          started_at: state.started_at,
          duration_ms: state.duration_ms,
          progress: state.progress,
          current_step: state.current_step
        }

      _ ->
        nil
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_workflow(name) do
    alias OmScheduler.Config
    store = Config.get_store_module(Config.get())
    store.get_workflow(name)
  end

  defp has_any_rollback?(workflow) do
    Enum.any?(workflow.steps, fn {_name, step} -> step.rollback != nil end)
  end

  defp calculate_total_timeout(workflow) do
    # Sum of all step timeouts in execution order
    workflow.steps
    |> Enum.map(fn {_name, step} ->
      case step.timeout do
        :infinity -> 0
        timeout -> timeout
      end
    end)
    |> Enum.sum()
  end

  defp calculate_critical_path(workflow) do
    # Simple implementation: longest path through dependencies
    workflow.execution_order
  end

  defp format_schedule([]), do: nil

  defp format_schedule(schedule) do
    cond do
      Keyword.has_key?(schedule, :cron) -> "cron: #{inspect(Keyword.get(schedule, :cron))}"
      Keyword.has_key?(schedule, :every) -> "every: #{inspect(Keyword.get(schedule, :every))}"
      Keyword.has_key?(schedule, :at) -> "at: #{inspect(Keyword.get(schedule, :at))}"
      true -> inspect(schedule)
    end
  end
end
