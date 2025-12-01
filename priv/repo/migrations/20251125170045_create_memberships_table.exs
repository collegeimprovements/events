defmodule Events.Repo.Migrations.CreateMembershipsTable do
  use Events.Migration

  alias Events.Repo.MigrationConstants, as: C

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Foreign keys
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        null: false,
        default: fragment("'#{C.default_account_id()}'::uuid")

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      # Core fields
      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec

      # Standard fields
      add :type, :citext
      add :subtype, :citext
      add :metadata, :jsonb, default: fragment("'{}'"), null: false
      add :assets, :jsonb, default: fragment("'{}'"), null: false

      # Audit fields (FK added later via migration after user_role_mappings exists)
      add :created_by_urm_id, :uuid, default: fragment("'#{C.system_urm_id()}'::uuid")
      add :updated_by_urm_id, :uuid, default: fragment("'#{C.system_urm_id()}'::uuid")

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint - user can only be in account once
    create unique_index(:memberships, [:account_id, :user_id])

    # FK indexes
    create index(:memberships, [:account_id])
    create index(:memberships, [:user_id])

    # Standard indexes
    create index(:memberships, [:status])
    create index(:memberships, [:type])
    create index(:memberships, [:subtype])
    create index(:memberships, [:created_by_urm_id])
    create index(:memberships, [:updated_by_urm_id])
    create index(:memberships, [:inserted_at])
    create index(:memberships, [:updated_at])
  end
end
