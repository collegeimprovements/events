defmodule Events.Core.Repo.Migrations.AddSchedulerLifeline do
  use Events.Core.Migration

  def change do
    # Add heartbeat_at to executions for lifeline tracking
    alter table(:scheduler_executions) do
      add :heartbeat_at, :utc_datetime_usec
    end

    # Add rescued state to executions
    # (state enum already handled by Ecto, just need index)

    # Index for finding stuck executions efficiently
    create index(:scheduler_executions, [:heartbeat_at],
             where: "state = 'running'",
             name: :scheduler_executions_heartbeat_index
           )
  end
end
