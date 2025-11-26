defmodule Events.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  alias Events.Repo.MigrationConstants, as: C

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuidv7()")

      # Core fields
      add :email, :citext, null: false
      add :username, :citext

      # Auth fields (phx.gen.auth pattern)
      add :hashed_password, :string, redact: true
      add :confirmed_at, :utc_datetime_usec

      # Status
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
    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    # Standard indexes
    create index(:users, [:status])
    create index(:users, [:type])
    create index(:users, [:subtype])
    create index(:users, [:confirmed_at])
    create index(:users, [:created_by_urm_id])
    create index(:users, [:updated_by_urm_id])
    create index(:users, [:inserted_at])
    create index(:users, [:updated_at])
  end
end
