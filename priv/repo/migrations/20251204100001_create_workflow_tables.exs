defmodule Events.Core.Repo.Migrations.CreateWorkflowTables do
  use OmMigration

  def change do
    # ============================================
    # Workflow Definitions Table
    # ============================================
    create table(:workflow_definitions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :version, :integer, null: false, default: 1
      add :module, :string

      # Serialized workflow structure
      add :steps, :map, default: %{}
      add :adjacency, :map, default: %{}
      add :execution_order, {:array, :string}, default: []
      add :groups, :map, default: %{}
      add :grafts, :map, default: %{}
      add :nested_workflows, :map, default: %{}

      # Trigger configuration
      add :trigger_type, :string, default: "manual"
      add :schedule, :map, default: %{}
      add :event_triggers, {:array, :string}, default: []

      # Handlers
      add :on_failure, :string
      add :on_success, :string
      add :on_cancel, :string
      add :on_step_error, :string

      # Timeout/Retry configuration
      add :timeout, :integer, default: 1_800_000
      add :max_retries, :integer, default: 0
      add :retry_delay, :integer, default: 5_000
      add :retry_backoff, :string, default: "exponential"
      add :step_timeout, :integer, default: 300_000
      add :step_max_retries, :integer, default: 3
      add :step_retry_delay, :integer, default: 1_000

      # Dead letter queue
      add :dead_letter, :boolean, default: false
      add :dead_letter_ttl, :integer

      # Metadata
      add :tags, {:array, :string}, default: []
      add :metadata, :map, default: %{}

      # State
      add :enabled, :boolean, default: true

      timestamps()
    end

    # Unique workflow name + version
    create unique_index(:workflow_definitions, [:name, :version])
    create index(:workflow_definitions, [:name])
    create index(:workflow_definitions, [:tags], using: :gin)
    create index(:workflow_definitions, [:trigger_type])
    create index(:workflow_definitions, [:enabled])

    # ============================================
    # Workflow Executions Table
    # ============================================
    create table(:workflow_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :workflow_definition_id,
          references(:workflow_definitions, type: :uuid, on_delete: :nilify_all)

      add :workflow_name, :string, null: false
      add :workflow_version, :integer, null: false, default: 1

      # State
      add :state, :string, default: "pending"
      add :current_step, :string

      # Context
      add :context, :map, default: %{}
      add :initial_context, :map, default: %{}

      # Step tracking
      add :step_states, :map, default: %{}
      add :step_results, :map, default: %{}
      add :step_errors, :map, default: %{}
      add :step_attempts, :map, default: %{}
      add :completed_steps, {:array, :string}, default: []
      add :running_steps, {:array, :string}, default: []
      add :pending_steps, {:array, :string}, default: []
      add :skipped_steps, {:array, :string}, default: []
      add :cancelled_steps, {:array, :string}, default: []

      # Trigger info
      add :trigger_type, :string
      add :trigger_source, :string

      # Timestamps
      add :scheduled_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :paused_at, :utc_datetime_usec
      add :duration_ms, :integer

      # Retry info
      add :attempt, :integer, default: 1
      add :max_attempts, :integer, default: 1

      # Error info
      add :error, :text
      add :error_step, :string
      add :stacktrace, :text
      add :cancellation_reason, :text

      # Hierarchy
      add :parent_execution_id,
          references(:workflow_executions, type: :uuid, on_delete: :nilify_all)

      add :child_executions, {:array, :uuid}, default: []

      # Graft expansions
      add :graft_expansions, :map, default: %{}

      # Timeline (serialized step info history)
      add :timeline, {:array, :map}, default: []

      # Metadata
      add :metadata, :map, default: %{}
      add :node, :string

      timestamps()
    end

    # Query executions by workflow
    create index(:workflow_executions, [:workflow_name])
    create index(:workflow_executions, [:workflow_definition_id])

    # Query by state
    create index(:workflow_executions, [:state])

    create index(:workflow_executions, [:workflow_name, :state],
             name: :workflow_executions_name_state_index
           )

    # Query running executions
    create index(:workflow_executions, [:state],
             where: "state = 'running'",
             name: :workflow_executions_running_index
           )

    # Query by time
    create index(:workflow_executions, [:started_at])
    create index(:workflow_executions, [:scheduled_at])
    create index(:workflow_executions, [:completed_at])

    # Query parent/child hierarchy
    create index(:workflow_executions, [:parent_execution_id])

    # For pruning old executions
    create index(:workflow_executions, [:inserted_at])

    # Composite for recent executions by workflow
    create index(:workflow_executions, [:workflow_name, :inserted_at],
             name: :workflow_executions_name_inserted_index
           )

    # ============================================
    # Workflow Step Executions Table (detailed step tracking)
    # ============================================
    create table(:workflow_step_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :workflow_execution_id,
          references(:workflow_executions, type: :uuid, on_delete: :delete_all),
          null: false

      add :step_name, :string, null: false

      # State
      add :state, :string, default: "pending"
      add :attempt, :integer, default: 0

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      # Result
      add :result, :map
      add :error, :text
      add :stacktrace, :text

      # Metadata
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Query steps by execution
    create index(:workflow_step_executions, [:workflow_execution_id])

    # Query by step name across executions
    create index(:workflow_step_executions, [:step_name])

    # Unique step per execution
    create unique_index(:workflow_step_executions, [:workflow_execution_id, :step_name])

    # Query by state
    create index(:workflow_step_executions, [:state])

    # Query by time
    create index(:workflow_step_executions, [:started_at])
    create index(:workflow_step_executions, [:completed_at])
  end
end
