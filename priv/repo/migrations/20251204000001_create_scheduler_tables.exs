defmodule Events.Core.Repo.Migrations.CreateSchedulerTables do
  use Events.Core.Migration

  def change do
    # ============================================
    # Scheduler Jobs Table
    # ============================================
    create table(:scheduler_jobs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :module, :string, null: false
      add :function, :string, null: false
      add :args, :map, default: %{}

      add :schedule_type, :string, null: false, default: "cron"
      add :schedule, :map, null: false, default: %{}
      add :timezone, :string, default: "Etc/UTC"

      add :enabled, :boolean, default: true
      add :paused, :boolean, default: false
      add :state, :string, default: "active"

      add :queue, :string, default: "default"
      add :priority, :integer, default: 0
      add :max_retries, :integer, default: 3
      add :retry_delay, :integer, default: 5000
      add :timeout, :integer, default: 60_000
      add :unique, :boolean, default: false
      add :unique_key, :string

      add :tags, {:array, :string}, default: []

      add :last_run_at, :utc_datetime_usec
      add :next_run_at, :utc_datetime_usec
      add :last_result, :string
      add :last_error, :text
      add :run_count, :integer, default: 0
      add :error_count, :integer, default: 0

      add :meta, :map, default: %{}

      timestamps()
    end

    # Unique job name
    create unique_index(:scheduler_jobs, [:name])

    # Unique key for duplicate prevention
    create unique_index(:scheduler_jobs, [:unique_key],
             where: "unique_key IS NOT NULL",
             name: :scheduler_jobs_unique_key_index
           )

    # Find due jobs efficiently
    create index(:scheduler_jobs, [:next_run_at],
             where: "enabled = true AND paused = false AND state = 'active'",
             name: :scheduler_jobs_due_index
           )

    # Queue-based queries with priority
    create index(:scheduler_jobs, [:queue, :priority, :next_run_at],
             where: "enabled = true AND paused = false",
             name: :scheduler_jobs_queue_priority_index
           )

    # Tag-based filtering
    create index(:scheduler_jobs, [:tags], using: :gin)

    # ============================================
    # Scheduler Executions Table
    # ============================================
    create table(:scheduler_executions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :job_id, references(:scheduler_jobs, type: :uuid, on_delete: :nilify_all)
      add :job_name, :string, null: false
      add :node, :string, null: false
      add :attempt, :integer, default: 1

      add :state, :string, default: "running"
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :scheduled_at, :utc_datetime_usec
      add :queue_time_ms, :integer
      add :duration_ms, :integer

      add :result, :string
      add :error, :text
      add :stacktrace, :text

      add :meta, :map, default: %{}

      timestamps()
    end

    # Query executions by job
    create index(:scheduler_executions, [:job_id])
    create index(:scheduler_executions, [:job_name])

    # Query by time range
    create index(:scheduler_executions, [:started_at])
    create index(:scheduler_executions, [:job_id, :started_at])

    # For pruning old executions
    create index(:scheduler_executions, [:inserted_at])

    # ============================================
    # Scheduler Peers Table (for leader election)
    # ============================================
    create table(:scheduler_peers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :node, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps()
    end

    # Unique peer name
    create unique_index(:scheduler_peers, [:name])

    # Find expired peers
    create index(:scheduler_peers, [:expires_at])

    # ============================================
    # Scheduler Locks Table (for unique job enforcement)
    # ============================================
    create table(:scheduler_locks, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :key, :string, null: false
      add :owner, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:scheduler_locks, [:key])
    create index(:scheduler_locks, [:expires_at])
  end
end
