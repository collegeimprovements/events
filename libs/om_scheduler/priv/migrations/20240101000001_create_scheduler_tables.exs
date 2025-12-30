defmodule OmScheduler.Migrations.V1 do
  @moduledoc """
  Initial migration for OmScheduler tables.

  ## Usage

  Add to your app's migration:

      defmodule MyApp.Repo.Migrations.AddOmScheduler do
        use Ecto.Migration

        def up do
          OmScheduler.Migrations.V1.up()
        end

        def down do
          OmScheduler.Migrations.V1.down()
        end
      end
  """
  use Ecto.Migration

  def up do
    # Jobs table
    create table(:scheduler_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :queue, :string, default: "default"
      add :worker, :string, null: false
      add :args, :map, default: %{}
      add :meta, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :priority, :integer, default: 0
      add :state, :string, default: "active"

      # Scheduling
      add :schedule_type, :string, default: "once"
      add :cron_expression, :string
      add :interval_ms, :integer
      add :timezone, :string, default: "Etc/UTC"
      add :next_run_at, :utc_datetime_usec
      add :last_run_at, :utc_datetime_usec

      # Execution tracking
      add :run_count, :integer, default: 0
      add :error_count, :integer, default: 0
      add :last_result, :text
      add :last_error, :text

      # Retry configuration
      add :max_attempts, :integer, default: 3
      add :attempt, :integer, default: 0
      add :timeout, :integer, default: 300_000

      # Unique job enforcement
      add :unique, :boolean, default: false
      add :unique_key, :string
      add :unique_period, :integer

      # State
      add :enabled, :boolean, default: true
      add :paused, :boolean, default: false

      timestamps()
    end

    create unique_index(:scheduler_jobs, [:name])
    create index(:scheduler_jobs, [:queue])
    create index(:scheduler_jobs, [:state])
    create index(:scheduler_jobs, [:next_run_at])
    create index(:scheduler_jobs, [:enabled, :paused, :state, :next_run_at])

    # Executions table
    create table(:scheduler_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :job_name, :string, null: false
      add :queue, :string
      add :state, :string, default: "running"
      add :result, :string
      add :attempt, :integer, default: 1

      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :heartbeat_at, :utc_datetime_usec
      add :duration_ms, :integer

      add :node, :string
      add :error, :text
      add :meta, :map, default: %{}

      timestamps()
    end

    create index(:scheduler_executions, [:job_name])
    create index(:scheduler_executions, [:state])
    create index(:scheduler_executions, [:started_at])
    create index(:scheduler_executions, [:job_name, :started_at])

    # Locks table for unique job enforcement
    create table(:scheduler_locks, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :key, :string, null: false
      add :owner, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:scheduler_locks, [:key])
    create index(:scheduler_locks, [:expires_at])

    # Peers table for cluster tracking
    create table(:scheduler_peers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :node, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create unique_index(:scheduler_peers, [:name])
    create index(:scheduler_peers, [:expires_at])

    # Workflow definitions table
    create table(:workflow_definitions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :version, :integer, default: 1
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

    create unique_index(:workflow_definitions, [:name, :version])
    create index(:workflow_definitions, [:name])
    create index(:workflow_definitions, [:enabled])
    create index(:workflow_definitions, [:trigger_type])

    # Workflow executions table
    create table(:workflow_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_name, :string, null: false
      add :workflow_version, :integer, default: 1
      add :state, :string, default: "pending"
      add :trigger_type, :string, default: "manual"

      add :context, :map, default: %{}
      add :result, :map

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      add :current_step, :string
      add :completed_steps, {:array, :string}, default: []
      add :failed_step, :string
      add :error, :text

      add :node, :string
      add :parent_execution_id, :uuid
      add :meta, :map, default: %{}

      timestamps()
    end

    create index(:workflow_executions, [:workflow_name])
    create index(:workflow_executions, [:state])
    create index(:workflow_executions, [:started_at])
    create index(:workflow_executions, [:workflow_name, :state])

    # Workflow step executions table
    create table(:workflow_step_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :execution_id, references(:workflow_executions, type: :uuid, on_delete: :delete_all),
        null: false
      add :step_name, :string, null: false
      add :state, :string, default: "pending"
      add :attempt, :integer, default: 1

      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :duration_ms, :integer

      add :input, :map
      add :output, :map
      add :error, :text

      timestamps()
    end

    create index(:workflow_step_executions, [:execution_id])
    create index(:workflow_step_executions, [:step_name])
    create index(:workflow_step_executions, [:state])
    create index(:workflow_step_executions, [:execution_id, :step_name])
  end

  def down do
    drop table(:workflow_step_executions)
    drop table(:workflow_executions)
    drop table(:workflow_definitions)
    drop table(:scheduler_peers)
    drop table(:scheduler_locks)
    drop table(:scheduler_executions)
    drop table(:scheduler_jobs)
  end
end
