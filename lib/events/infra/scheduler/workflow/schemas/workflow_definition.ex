defmodule Events.Infra.Scheduler.Workflow.Schemas.WorkflowDefinition do
  @moduledoc """
  Ecto schema for persisted workflow definitions.

  This schema stores workflow definitions in the database for:
  - Durability across restarts
  - Versioning of workflow changes
  - Audit trail of workflow evolution
  """

  use Events.Core.Schema

  alias Events.Infra.Scheduler.Workflow

  schema "workflow_definitions" do
    field :name, :string
    field :version, :integer, default: 1
    field :module, :string

    # Serialized workflow structure
    field :steps, :map, default: %{}
    field :adjacency, :map, default: %{}
    field :execution_order, {:array, :string}, default: []
    field :groups, :map, default: %{}
    field :grafts, :map, default: %{}
    field :nested_workflows, :map, default: %{}

    # Trigger configuration
    field :trigger_type, :string, default: "manual"
    field :schedule, :map, default: %{}
    field :event_triggers, {:array, :string}, default: []

    # Handlers
    field :on_failure, :string
    field :on_success, :string
    field :on_cancel, :string
    field :on_step_error, :string

    # Timeout/Retry configuration
    field :timeout, :integer, default: 1_800_000
    field :max_retries, :integer, default: 0
    field :retry_delay, :integer, default: 5_000
    field :retry_backoff, :string, default: "exponential"
    field :step_timeout, :integer, default: 300_000
    field :step_max_retries, :integer, default: 3
    field :step_retry_delay, :integer, default: 1_000

    # Dead letter queue
    field :dead_letter, :boolean, default: false
    field :dead_letter_ttl, :integer

    # Metadata
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    # State
    field :enabled, :boolean, default: true

    timestamps()
  end

  @required_fields [:name]
  @optional_fields [
    :version,
    :module,
    :steps,
    :adjacency,
    :execution_order,
    :groups,
    :grafts,
    :nested_workflows,
    :trigger_type,
    :schedule,
    :event_triggers,
    :on_failure,
    :on_success,
    :on_cancel,
    :on_step_error,
    :timeout,
    :max_retries,
    :retry_delay,
    :retry_backoff,
    :step_timeout,
    :step_max_retries,
    :step_retry_delay,
    :dead_letter,
    :dead_letter_ttl,
    :tags,
    :metadata,
    :enabled
  ]

  @doc """
  Creates a changeset for a workflow definition.
  """
  def changeset(schema \\ %__MODULE__{}, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :version])
  end

  @doc """
  Converts a Workflow struct to database attributes.
  """
  @spec from_workflow(Workflow.t()) :: map()
  def from_workflow(%Workflow{} = workflow) do
    %{
      name: Atom.to_string(workflow.name),
      version: workflow.version,
      module: if(workflow.module, do: Atom.to_string(workflow.module)),
      steps: serialize_steps(workflow.steps),
      adjacency: serialize_adjacency(workflow.adjacency),
      execution_order: Enum.map(workflow.execution_order, &Atom.to_string/1),
      groups: serialize_groups(workflow.groups),
      grafts: workflow.grafts,
      nested_workflows: serialize_nested_workflows(workflow.nested_workflows),
      trigger_type: Atom.to_string(workflow.trigger_type),
      schedule: Keyword.new(workflow.schedule) |> Enum.into(%{}),
      event_triggers: workflow.event_triggers,
      on_failure: if(workflow.on_failure, do: Atom.to_string(workflow.on_failure)),
      on_success: if(workflow.on_success, do: Atom.to_string(workflow.on_success)),
      on_cancel: if(workflow.on_cancel, do: Atom.to_string(workflow.on_cancel)),
      on_step_error: if(workflow.on_step_error, do: Atom.to_string(workflow.on_step_error)),
      timeout: normalize_timeout(workflow.timeout),
      max_retries: workflow.max_retries,
      retry_delay: workflow.retry_delay,
      retry_backoff: serialize_backoff(workflow.retry_backoff),
      step_timeout: workflow.step_timeout,
      step_max_retries: workflow.step_max_retries,
      step_retry_delay: workflow.step_retry_delay,
      dead_letter: workflow.dead_letter,
      dead_letter_ttl: workflow.dead_letter_ttl,
      tags: workflow.tags,
      metadata: workflow.metadata
    }
  end

  @doc """
  Converts a database record to a Workflow struct.
  """
  @spec to_workflow(Ecto.Schema.t()) :: Workflow.t()
  def to_workflow(%__MODULE__{} = schema) do
    %Workflow{
      id: schema.id,
      name: String.to_existing_atom(schema.name),
      version: schema.version,
      module: if(schema.module, do: String.to_existing_atom(schema.module)),
      steps: deserialize_steps(schema.steps),
      adjacency: deserialize_adjacency(schema.adjacency),
      execution_order: Enum.map(schema.execution_order, &String.to_existing_atom/1),
      groups: deserialize_groups(schema.groups),
      grafts: schema.grafts,
      nested_workflows: deserialize_nested_workflows(schema.nested_workflows),
      trigger_type: String.to_existing_atom(schema.trigger_type),
      schedule: Enum.map(schema.schedule, fn {k, v} -> {String.to_existing_atom(k), v} end),
      event_triggers: schema.event_triggers,
      on_failure: if(schema.on_failure, do: String.to_existing_atom(schema.on_failure)),
      on_success: if(schema.on_success, do: String.to_existing_atom(schema.on_success)),
      on_cancel: if(schema.on_cancel, do: String.to_existing_atom(schema.on_cancel)),
      on_step_error: if(schema.on_step_error, do: String.to_existing_atom(schema.on_step_error)),
      timeout: schema.timeout,
      max_retries: schema.max_retries,
      retry_delay: schema.retry_delay,
      retry_backoff: deserialize_backoff(schema.retry_backoff),
      step_timeout: schema.step_timeout,
      step_max_retries: schema.step_max_retries,
      step_retry_delay: schema.step_retry_delay,
      dead_letter: schema.dead_letter,
      dead_letter_ttl: schema.dead_letter_ttl,
      tags: schema.tags,
      metadata: schema.metadata,
      state: :pending
    }
  end

  # ============================================
  # Serialization Helpers
  # ============================================

  defp serialize_steps(steps) do
    Map.new(steps, fn {name, step} ->
      {Atom.to_string(name), serialize_step(step)}
    end)
  end

  defp serialize_step(step) do
    %{
      "name" => Atom.to_string(step.name),
      "job" => serialize_job(step.job),
      "depends_on" => Enum.map(step.depends_on, &Atom.to_string/1),
      "depends_on_any" => Enum.map(step.depends_on_any, &Atom.to_string/1),
      "depends_on_group" => if(step.depends_on_group, do: Atom.to_string(step.depends_on_group)),
      "depends_on_graft" => if(step.depends_on_graft, do: Atom.to_string(step.depends_on_graft)),
      "group" => if(step.group, do: Atom.to_string(step.group)),
      "timeout" => step.timeout,
      "max_retries" => step.max_retries,
      "retry_delay" => step.retry_delay,
      "retry_backoff" => serialize_backoff(step.retry_backoff),
      "on_error" => Atom.to_string(step.on_error),
      "context_key" => Atom.to_string(step.context_key),
      "rollback" => if(step.rollback, do: Atom.to_string(step.rollback)),
      "await_approval" => step.await_approval,
      "cancellable" => step.cancellable,
      "metadata" => step.metadata
    }
  end

  defp serialize_job(job) when is_atom(job),
    do: %{"type" => "module", "module" => Atom.to_string(job)}

  defp serialize_job({:workflow, name}), do: %{"type" => "workflow", "name" => Atom.to_string(name)}

  defp serialize_job({m, f}),
    do: %{"type" => "mf", "module" => Atom.to_string(m), "function" => Atom.to_string(f)}

  defp serialize_job({m, f, a}),
    do: %{
      "type" => "mfa",
      "module" => Atom.to_string(m),
      "function" => Atom.to_string(f),
      "args" => a
    }

  defp serialize_job(_fun), do: %{"type" => "function"}

  defp serialize_adjacency(adj) do
    Map.new(adj, fn {name, deps} ->
      {Atom.to_string(name), Enum.map(deps, &serialize_dep/1)}
    end)
  end

  defp serialize_dep({:group, name}), do: %{"type" => "group", "name" => Atom.to_string(name)}
  defp serialize_dep({:graft, name}), do: %{"type" => "graft", "name" => Atom.to_string(name)}
  defp serialize_dep(name), do: Atom.to_string(name)

  defp serialize_groups(groups) do
    Map.new(groups, fn {name, members} ->
      {Atom.to_string(name), Enum.map(members, &Atom.to_string/1)}
    end)
  end

  defp serialize_nested_workflows(nested) do
    Map.new(nested, fn {name, workflow_name} ->
      {Atom.to_string(name), Atom.to_string(workflow_name)}
    end)
  end

  defp serialize_backoff(:fixed), do: "fixed"
  defp serialize_backoff(:exponential), do: "exponential"
  defp serialize_backoff(:linear), do: "linear"
  defp serialize_backoff(_), do: "exponential"

  defp normalize_timeout(:infinity), do: nil
  defp normalize_timeout(ms), do: ms

  # ============================================
  # Deserialization Helpers
  # ============================================

  defp deserialize_steps(steps) do
    Map.new(steps, fn {name, step_map} ->
      {String.to_existing_atom(name), deserialize_step(step_map)}
    end)
  end

  defp deserialize_step(map) do
    alias Events.Infra.Scheduler.Workflow.Step

    %Step{
      name: String.to_existing_atom(map["name"]),
      job: deserialize_job(map["job"]),
      depends_on: Enum.map(map["depends_on"] || [], &String.to_existing_atom/1),
      depends_on_any: Enum.map(map["depends_on_any"] || [], &String.to_existing_atom/1),
      depends_on_group:
        if(map["depends_on_group"], do: String.to_existing_atom(map["depends_on_group"])),
      depends_on_graft:
        if(map["depends_on_graft"], do: String.to_existing_atom(map["depends_on_graft"])),
      group: if(map["group"], do: String.to_existing_atom(map["group"])),
      timeout: map["timeout"],
      max_retries: map["max_retries"],
      retry_delay: map["retry_delay"],
      retry_backoff: deserialize_backoff(map["retry_backoff"]),
      on_error: String.to_existing_atom(map["on_error"]),
      context_key: String.to_existing_atom(map["context_key"]),
      rollback: if(map["rollback"], do: String.to_existing_atom(map["rollback"])),
      await_approval: map["await_approval"],
      cancellable: map["cancellable"],
      metadata: map["metadata"] || %{}
    }
  end

  defp deserialize_job(%{"type" => "module", "module" => m}), do: String.to_existing_atom(m)

  defp deserialize_job(%{"type" => "workflow", "name" => n}),
    do: {:workflow, String.to_existing_atom(n)}

  defp deserialize_job(%{"type" => "mf", "module" => m, "function" => f}),
    do: {String.to_existing_atom(m), String.to_existing_atom(f)}

  defp deserialize_job(%{"type" => "mfa", "module" => m, "function" => f, "args" => a}),
    do: {String.to_existing_atom(m), String.to_existing_atom(f), a}

  defp deserialize_job(%{"type" => "function"}), do: fn _ -> :ok end

  defp deserialize_adjacency(adj) do
    Map.new(adj, fn {name, deps} ->
      {String.to_existing_atom(name), Enum.map(deps, &deserialize_dep/1)}
    end)
  end

  defp deserialize_dep(%{"type" => "group", "name" => n}), do: {:group, String.to_existing_atom(n)}
  defp deserialize_dep(%{"type" => "graft", "name" => n}), do: {:graft, String.to_existing_atom(n)}
  defp deserialize_dep(name), do: String.to_existing_atom(name)

  defp deserialize_groups(groups) do
    Map.new(groups, fn {name, members} ->
      {String.to_existing_atom(name), Enum.map(members, &String.to_existing_atom/1)}
    end)
  end

  defp deserialize_nested_workflows(nested) do
    Map.new(nested, fn {name, workflow_name} ->
      {String.to_existing_atom(name), String.to_existing_atom(workflow_name)}
    end)
  end

  defp deserialize_backoff("fixed"), do: :fixed
  defp deserialize_backoff("exponential"), do: :exponential
  defp deserialize_backoff("linear"), do: :linear
  defp deserialize_backoff(_), do: :exponential
end
