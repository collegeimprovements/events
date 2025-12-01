defmodule Events.Repo.Migrations.CreateUserRoleMappingsTable do
  use Events.Migration

  alias Events.Repo.MigrationConstants, as: C

  def change do
    create table(:user_role_mappings, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Foreign keys
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :role_id, references(:roles, type: :uuid, on_delete: :delete_all), null: false

      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        null: false,
        default: fragment("'#{C.default_account_id()}'::uuid")

      # Standard fields
      add :type, :citext
      add :subtype, :citext
      add :metadata, :jsonb, default: fragment("'{}'"), null: false
      add :assets, :jsonb, default: fragment("'{}'"), null: false

      # Audit fields (self-referencing - FK added later)
      add :created_by_urm_id, :uuid, default: fragment("'#{C.system_urm_id()}'::uuid")
      add :updated_by_urm_id, :uuid, default: fragment("'#{C.system_urm_id()}'::uuid")

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint - user can only have a specific role once per account
    create unique_index(:user_role_mappings, [:user_id, :role_id, :account_id])

    # FK indexes
    create index(:user_role_mappings, [:user_id])
    create index(:user_role_mappings, [:role_id])
    create index(:user_role_mappings, [:account_id])

    # Composite indexes for common queries
    create index(:user_role_mappings, [:user_id, :account_id])
    create index(:user_role_mappings, [:account_id, :role_id])

    # Standard indexes
    create index(:user_role_mappings, [:type])
    create index(:user_role_mappings, [:subtype])
    create index(:user_role_mappings, [:created_by_urm_id])
    create index(:user_role_mappings, [:updated_by_urm_id])
    create index(:user_role_mappings, [:inserted_at])
    create index(:user_role_mappings, [:updated_at])
  end
end
