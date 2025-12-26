defmodule OmScheduler.Workflow.Schemas.WorkflowExecution do
  @moduledoc """
  Ecto schema for persisted workflow executions.

  This schema tracks individual workflow runs in the database for:
  - Durability across restarts
  - Query and analytics
  - Audit trail of executions
  """

  use OmScheduler.Schema

  alias OmScheduler.Workflow.Execution
  alias OmScheduler.Workflow.Schemas.{WorkflowDefinition, WorkflowStepExecution}

  schema "workflow_executions" do
    belongs_to :workflow_definition, WorkflowDefinition
    has_many :step_executions, WorkflowStepExecution

    field :workflow_name, :string
    field :workflow_version, :integer, default: 1

    # State
    field :state, :string, default: "pending"
    field :current_step, :string

    # Context
    field :context, :map, default: %{}
    field :initial_context, :map, default: %{}

    # Step tracking (denormalized for quick queries)
    field :step_states, :map, default: %{}
    field :step_results, :map, default: %{}
    field :step_errors, :map, default: %{}
    field :step_attempts, :map, default: %{}
    field :completed_steps, {:array, :string}, default: []
    field :running_steps, {:array, :string}, default: []
    field :pending_steps, {:array, :string}, default: []
    field :skipped_steps, {:array, :string}, default: []
    field :cancelled_steps, {:array, :string}, default: []

    # Trigger info
    field :trigger_type, :string
    field :trigger_source, :string

    # Timestamps
    field :scheduled_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :paused_at, :utc_datetime_usec
    field :duration_ms, :integer

    # Retry info
    field :attempt, :integer, default: 1
    field :max_attempts, :integer, default: 1

    # Error info
    field :error, :string
    field :error_step, :string
    field :stacktrace, :string
    field :cancellation_reason, :string

    # Hierarchy
    belongs_to :parent_execution, __MODULE__
    field :child_executions, {:array, :binary_id}, default: []

    # Graft expansions
    field :graft_expansions, :map, default: %{}

    # Timeline (serialized step info history)
    field :timeline, {:array, :map}, default: []

    # Metadata
    field :metadata, :map, default: %{}
    field :node, :string

    timestamps()
  end

  @required_fields [:workflow_name]
  @optional_fields [
    :workflow_definition_id,
    :workflow_version,
    :state,
    :current_step,
    :context,
    :initial_context,
    :step_states,
    :step_results,
    :step_errors,
    :step_attempts,
    :completed_steps,
    :running_steps,
    :pending_steps,
    :skipped_steps,
    :cancelled_steps,
    :trigger_type,
    :trigger_source,
    :scheduled_at,
    :started_at,
    :completed_at,
    :paused_at,
    :duration_ms,
    :attempt,
    :max_attempts,
    :error,
    :error_step,
    :stacktrace,
    :cancellation_reason,
    :parent_execution_id,
    :child_executions,
    :graft_expansions,
    :timeline,
    :metadata,
    :node
  ]

  @doc """
  Creates a changeset for a workflow execution.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:workflow_definition_id)
    |> foreign_key_constraint(:parent_execution_id)
  end

  @doc """
  Converts an Execution struct to database attributes.
  """
  @spec from_execution(Execution.t(), binary() | nil) :: map()
  def from_execution(%Execution{} = exec, workflow_definition_id \\ nil) do
    %{
      workflow_definition_id: workflow_definition_id,
      workflow_name: Atom.to_string(exec.workflow_name),
      workflow_version: exec.workflow_version,
      state: Atom.to_string(exec.state),
      current_step: if(exec.current_step, do: Atom.to_string(exec.current_step)),
      context: serialize_context(exec.context),
      initial_context: serialize_context(exec.initial_context),
      step_states: serialize_step_map(exec.step_states),
      step_results: serialize_results(exec.step_results),
      step_errors: serialize_errors(exec.step_errors),
      step_attempts: serialize_step_map(exec.step_attempts),
      completed_steps: Enum.map(exec.completed_steps, &Atom.to_string/1),
      running_steps: Enum.map(exec.running_steps, &Atom.to_string/1),
      pending_steps: Enum.map(exec.pending_steps, &Atom.to_string/1),
      skipped_steps: Enum.map(exec.skipped_steps, &Atom.to_string/1),
      cancelled_steps: Enum.map(exec.cancelled_steps, &Atom.to_string/1),
      trigger_type: Atom.to_string(exec.trigger.type),
      trigger_source: serialize_trigger_source(exec.trigger.source),
      scheduled_at: exec.scheduled_at,
      started_at: exec.started_at,
      completed_at: exec.completed_at,
      paused_at: exec.paused_at,
      duration_ms: exec.duration_ms,
      attempt: exec.attempt,
      max_attempts: exec.max_attempts,
      error: serialize_error(exec.error),
      error_step: if(exec.error_step, do: Atom.to_string(exec.error_step)),
      stacktrace: exec.stacktrace,
      cancellation_reason: serialize_error(exec.cancellation_reason),
      parent_execution_id: exec.parent_execution_id,
      child_executions: exec.child_executions,
      graft_expansions: serialize_graft_expansions(exec.graft_expansions),
      timeline: serialize_timeline(exec.timeline),
      metadata: exec.metadata,
      node: if(exec.node, do: Atom.to_string(exec.node))
    }
  end

  @doc """
  Converts a database record to an Execution struct.
  """
  @spec to_execution(Ecto.Schema.t()) :: Execution.t()
  def to_execution(%__MODULE__{} = schema) do
    %Execution{
      id: schema.id,
      workflow_name: String.to_existing_atom(schema.workflow_name),
      workflow_version: schema.workflow_version,
      state: String.to_existing_atom(schema.state),
      current_step: if(schema.current_step, do: String.to_existing_atom(schema.current_step)),
      context: deserialize_context(schema.context),
      initial_context: deserialize_context(schema.initial_context),
      step_states: deserialize_step_states(schema.step_states),
      step_results: deserialize_results(schema.step_results),
      step_errors: deserialize_errors(schema.step_errors),
      step_attempts: deserialize_step_attempts(schema.step_attempts),
      completed_steps: Enum.map(schema.completed_steps, &String.to_existing_atom/1),
      running_steps: Enum.map(schema.running_steps, &String.to_existing_atom/1),
      pending_steps: Enum.map(schema.pending_steps, &String.to_existing_atom/1),
      skipped_steps: Enum.map(schema.skipped_steps, &String.to_existing_atom/1),
      cancelled_steps: Enum.map(schema.cancelled_steps, &String.to_existing_atom/1),
      trigger: %{
        type: String.to_existing_atom(schema.trigger_type || "manual"),
        source: schema.trigger_source
      },
      scheduled_at: schema.scheduled_at,
      started_at: schema.started_at,
      completed_at: schema.completed_at,
      paused_at: schema.paused_at,
      duration_ms: schema.duration_ms,
      attempt: schema.attempt,
      max_attempts: schema.max_attempts,
      error: schema.error,
      error_step: if(schema.error_step, do: String.to_existing_atom(schema.error_step)),
      stacktrace: schema.stacktrace,
      cancellation_reason: schema.cancellation_reason,
      parent_execution_id: schema.parent_execution_id,
      child_executions: schema.child_executions || [],
      graft_expansions: deserialize_graft_expansions(schema.graft_expansions),
      timeline: deserialize_timeline(schema.timeline),
      metadata: schema.metadata || %{},
      node: if(schema.node, do: String.to_existing_atom(schema.node))
    }
  end

  # ============================================
  # Serialization Helpers
  # ============================================

  defp serialize_context(context) when is_map(context) do
    # Convert atom keys to strings for JSON storage
    Map.new(context, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, serialize_value(v)}
    end)
  end

  defp serialize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize_value(value) when is_map(value), do: serialize_context(value)

  defp serialize_value(value) when is_list(value) do
    Enum.map(value, &serialize_value/1)
  end

  defp serialize_value(value), do: value

  defp serialize_step_map(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if is_atom(v), do: Atom.to_string(v), else: v
      {key, value}
    end)
  end

  defp serialize_results(results) when is_map(results) do
    Map.new(results, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, serialize_value(v)}
    end)
  end

  defp serialize_errors(errors) when is_map(errors) do
    Map.new(errors, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, serialize_error(v)}
    end)
  end

  defp serialize_error(nil), do: nil
  defp serialize_error(error) when is_binary(error), do: error
  defp serialize_error(error) when is_atom(error), do: Atom.to_string(error)
  defp serialize_error(error), do: inspect(error)

  defp serialize_trigger_source(nil), do: nil
  defp serialize_trigger_source(source) when is_binary(source), do: source
  defp serialize_trigger_source(source), do: inspect(source)

  defp serialize_graft_expansions(expansions) when is_map(expansions) do
    Map.new(expansions, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = Enum.map(v, fn s -> if is_atom(s), do: Atom.to_string(s), else: s end)
      {key, value}
    end)
  end

  defp serialize_timeline(timeline) when is_list(timeline) do
    Enum.map(timeline, fn entry ->
      %{
        "name" => Atom.to_string(entry.name),
        "state" => Atom.to_string(entry.state),
        "started_at" => entry.started_at,
        "completed_at" => entry.completed_at,
        "duration_ms" => entry.duration_ms,
        "attempt" => entry.attempt,
        "error" => serialize_error(entry.error)
      }
    end)
  end

  # ============================================
  # Deserialization Helpers
  # ============================================

  defp deserialize_context(nil), do: %{}

  defp deserialize_context(context) when is_map(context) do
    # Keep string keys - they'll be accessed as strings in the workflow
    context
  end

  defp deserialize_step_states(nil), do: %{}

  defp deserialize_step_states(states) when is_map(states) do
    Map.new(states, fn {k, v} ->
      {String.to_existing_atom(k), String.to_existing_atom(v)}
    end)
  end

  defp deserialize_step_attempts(nil), do: %{}

  defp deserialize_step_attempts(attempts) when is_map(attempts) do
    Map.new(attempts, fn {k, v} ->
      {String.to_existing_atom(k), v}
    end)
  end

  defp deserialize_results(nil), do: %{}

  defp deserialize_results(results) when is_map(results) do
    Map.new(results, fn {k, v} ->
      {String.to_existing_atom(k), v}
    end)
  end

  defp deserialize_errors(nil), do: %{}

  defp deserialize_errors(errors) when is_map(errors) do
    Map.new(errors, fn {k, v} ->
      {String.to_existing_atom(k), v}
    end)
  end

  defp deserialize_graft_expansions(nil), do: %{}

  defp deserialize_graft_expansions(expansions) when is_map(expansions) do
    Map.new(expansions, fn {k, v} ->
      {String.to_existing_atom(k), Enum.map(v, &String.to_existing_atom/1)}
    end)
  end

  defp deserialize_timeline(nil), do: []

  defp deserialize_timeline(timeline) when is_list(timeline) do
    Enum.map(timeline, fn entry ->
      %{
        name: String.to_existing_atom(entry["name"]),
        state: String.to_existing_atom(entry["state"]),
        started_at: entry["started_at"],
        completed_at: entry["completed_at"],
        duration_ms: entry["duration_ms"],
        attempt: entry["attempt"],
        error: entry["error"]
      }
    end)
  end
end
