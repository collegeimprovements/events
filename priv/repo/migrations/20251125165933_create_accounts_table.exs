defmodule Events.Repo.Migrations.CreateAccountsTable do
  use Ecto.Migration

  alias Events.Repo.MigrationConstants, as: C

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Core fields
      add :name, :citext, null: false
      add :slug, :citext, null: false
      add :status, :string, null: false, default: "active"

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
    create unique_index(:accounts, [:slug])

    # Standard indexes
    create index(:accounts, [:status])
    create index(:accounts, [:type])
    create index(:accounts, [:subtype])
    create index(:accounts, [:created_by_urm_id])
    create index(:accounts, [:updated_by_urm_id])
    create index(:accounts, [:inserted_at])
    create index(:accounts, [:updated_at])
  end
end
