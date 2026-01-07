defmodule Events.Repo.Migrations.CreateRolesTable do
  use OmMigration

  alias Events.Core.Repo.MigrationConstants, as: C

  def change do
    create table(:roles, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Foreign key (nullable for global roles)
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all),
        default: fragment("'#{C.default_account_id()}'::uuid")

      # Core fields
      add :name, :citext, null: false
      add :slug, :citext, null: false
      add :description, :text
      add :permissions, :jsonb, default: fragment("'{}'"), null: false
      add :status, :string, null: false, default: "active"
      add :is_system, :boolean, null: false, default: false

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

    # Unique indexes
    create unique_index(:roles, [:slug])
    create unique_index(:roles, [:account_id, :name])

    # FK index
    create index(:roles, [:account_id])

    # Standard indexes
    create index(:roles, [:status])
    create index(:roles, [:is_system])
    create index(:roles, [:type])
    create index(:roles, [:subtype])
    create index(:roles, [:created_by_urm_id])
    create index(:roles, [:updated_by_urm_id])
    create index(:roles, [:inserted_at])
    create index(:roles, [:updated_at])
  end
end
