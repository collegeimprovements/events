defmodule Events.Infra.Scheduler.Workflow.Schemas.WorkflowStepExecution do
  @moduledoc """
  Ecto schema for individual step executions within a workflow.

  This schema provides detailed tracking of each step execution for:
  - Fine-grained step analytics
  - Debugging failed steps
  - Performance monitoring
  """

  use Events.Core.Schema

  alias Events.Infra.Scheduler.Workflow.Schemas.WorkflowExecution

  schema "workflow_step_executions" do
    belongs_to :workflow_execution, WorkflowExecution

    field :step_name, :string

    # State
    field :state, :string, default: "pending"
    field :attempt, :integer, default: 0

    # Timing
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer

    # Result
    field :result, :map
    field :error, :string
    field :stacktrace, :string

    # Metadata
    field :metadata, :map, default: %{}

    timestamps()
  end

  @required_fields [:workflow_execution_id, :step_name]
  @optional_fields [
    :state,
    :attempt,
    :started_at,
    :completed_at,
    :duration_ms,
    :result,
    :error,
    :stacktrace,
    :metadata
  ]

  @doc """
  Creates a changeset for a step execution.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:workflow_execution_id)
    |> unique_constraint([:workflow_execution_id, :step_name])
  end

  @doc """
  Creates a new step execution record.
  """
  @spec new(binary(), atom() | String.t()) :: map()
  def new(workflow_execution_id, step_name) do
    %{
      workflow_execution_id: workflow_execution_id,
      step_name: to_string(step_name),
      state: "pending",
      attempt: 0
    }
  end

  @doc """
  Marks the step as started.
  """
  @spec start(map(), non_neg_integer()) :: map()
  def start(step, attempt \\ 1) do
    step
    |> Map.put(:state, "running")
    |> Map.put(:attempt, attempt)
    |> Map.put(:started_at, DateTime.utc_now())
  end

  @doc """
  Marks the step as completed.
  """
  @spec complete(map(), term()) :: map()
  def complete(step, result) do
    now = DateTime.utc_now()

    duration =
      case step do
        %{started_at: started_at} when not is_nil(started_at) ->
          DateTime.diff(now, started_at, :millisecond)

        _ ->
          0
      end

    step
    |> Map.put(:state, "completed")
    |> Map.put(:completed_at, now)
    |> Map.put(:duration_ms, duration)
    |> Map.put(:result, serialize_result(result))
  end

  @doc """
  Marks the step as failed.
  """
  @spec fail(map(), term(), String.t() | nil) :: map()
  def fail(step, error, stacktrace \\ nil) do
    now = DateTime.utc_now()

    duration =
      case step do
        %{started_at: started_at} when not is_nil(started_at) ->
          DateTime.diff(now, started_at, :millisecond)

        _ ->
          0
      end

    step
    |> Map.put(:state, "failed")
    |> Map.put(:completed_at, now)
    |> Map.put(:duration_ms, duration)
    |> Map.put(:error, serialize_error(error))
    |> Map.put(:stacktrace, stacktrace)
  end

  @doc """
  Marks the step as skipped.
  """
  @spec skip(map(), term()) :: map()
  def skip(step, reason \\ nil) do
    now = DateTime.utc_now()

    step
    |> Map.put(:state, "skipped")
    |> Map.put(:started_at, now)
    |> Map.put(:completed_at, now)
    |> Map.put(:duration_ms, 0)
    |> Map.put(:result, %{"skipped" => true, "reason" => serialize_error(reason)})
  end

  @doc """
  Marks the step as cancelled.
  """
  @spec cancel(map()) :: map()
  def cancel(step) do
    now = DateTime.utc_now()

    duration =
      case step do
        %{started_at: started_at} when not is_nil(started_at) ->
          DateTime.diff(now, started_at, :millisecond)

        _ ->
          0
      end

    step
    |> Map.put(:state, "cancelled")
    |> Map.put(:completed_at, now)
    |> Map.put(:duration_ms, duration)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp serialize_result(result) when is_map(result), do: result
  defp serialize_result(:ok), do: %{"status" => "ok"}
  defp serialize_result({:ok, value}), do: %{"status" => "ok", "value" => serialize_value(value)}
  defp serialize_result(other), do: %{"value" => serialize_value(other)}

  defp serialize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize_value(value) when is_map(value), do: value

  defp serialize_value(value) when is_list(value) do
    Enum.map(value, &serialize_value/1)
  end

  defp serialize_value(value), do: value

  defp serialize_error(nil), do: nil
  defp serialize_error(error) when is_binary(error), do: error
  defp serialize_error(error) when is_atom(error), do: Atom.to_string(error)
  defp serialize_error(error), do: inspect(error)
end
