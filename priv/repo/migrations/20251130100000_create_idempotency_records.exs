defmodule Events.Repo.Migrations.CreateIdempotencyRecords do
  use Events.Core.Migration

  @moduledoc """
  Creates the idempotency_records table for tracking idempotent operations.

  This table stores:
  - Idempotency keys with optional scope
  - Operation state (pending, processing, completed, failed, expired)
  - Cached responses for completed operations
  - Optimistic locking version for concurrent access
  - Expiration timestamps for cleanup
  """

  def change do
    create table(:idempotency_records, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Core fields
      add :key, :string, null: false, size: 255
      add :scope, :string, size: 100
      add :state, :string, null: false, default: "pending", size: 20
      add :version, :integer, null: false, default: 1

      # Response/Error storage
      add :response, :map
      add :error, :map
      add :metadata, :map, default: %{}

      # Timing fields
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :locked_until, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint on key + scope
    create unique_index(:idempotency_records, [:key, :scope],
             name: :idempotency_records_key_scope_index
           )

    # Query optimization indexes
    create index(:idempotency_records, [:state])
    create index(:idempotency_records, [:expires_at])

    # Partial index for finding stale processing records
    create index(:idempotency_records, [:locked_until],
             where: "state = 'processing'",
             name: :idempotency_records_stale_processing_index
           )
  end
end
