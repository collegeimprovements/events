defmodule Events.Repo.Migrations.CreateErrorsTable do
  use Ecto.Migration

  import Events.Repo.MigrationMacros,
    only: [
      type_fields: 0,
      metadata_field: 0,
      audit_fields: 1,
      type_indexes: 1,
      audit_indexes: 1,
      timestamp_indexes: 2,
      metadata_index: 1
    ]

  def change do
    create table(:errors, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")
      # Error identification
      add :error_type, :citext, null: false
      add :code, :citext, null: false
      add :message, :text, null: false
      add :source, :citext

      # Error details (JSONB for flexibility)
      add :error_details, :jsonb, default: fragment("'{}'"), null: false
      add :stacktrace, :text

      # Grouping & analytics
      add :fingerprint, :string, null: false
      add :count, :integer, default: 1, null: false
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false

      # Resolution tracking
      add :resolved_at, :utc_datetime_usec
      # TODO: Add FK constraint when user_role_mappings table is created
      # add :resolved_by_urm_id, references(:user_role_mappings, type: :uuid, on_delete: :nilify_all)
      add :resolved_by_urm_id, :uuid

      # Standard fields from events_schema
      type_fields()
      metadata_field()
      # TODO: Enable references: true when user_role_mappings table is created
      audit_fields(references: false)
      timestamps(type: :utc_datetime_usec)
    end

    # Primary indexes for error identification
    create index(:errors, [:error_type])
    create index(:errors, [:code])
    create index(:errors, [:source])

    # Unique index on fingerprint for deduplication
    create unique_index(:errors, [:fingerprint])

    # Temporal indexes
    create index(:errors, [:first_seen_at])
    create index(:errors, [:last_seen_at])
    create index(:errors, [:resolved_at])

    # Resolution tracking index
    create index(:errors, [:resolved_by_urm_id])

    # Composite indexes for common query patterns
    create index(:errors, [:error_type, :code])
    create index(:errors, [:error_type, :resolved_at])
    create index(:errors, [:source, :error_type])

    # Partial index for unresolved errors (most common query)
    create index(:errors, [:error_type, :last_seen_at], where: "resolved_at IS NULL")

    # GIN indexes for JSONB fields (for advanced querying)
    create index(:errors, [:error_details], using: :gin)
    metadata_index(:errors)

    # Standard indexes from migration macros
    type_indexes(:errors)
    audit_indexes(:errors)
    timestamp_indexes(:errors, only: :inserted_at)
  end
end
