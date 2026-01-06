defmodule Events.Data.Repo.Migrations.AddUserSecurityFields do
  @moduledoc """
  Adds security audit fields and user defaults to the users table.

  Security fields track login history, failed attempts, and account lockout.
  Default fields allow users to specify their preferred account and role.
  """

  use OmMigration

  def change do
    alter table(:users) do
      # Security audit fields
      add :last_login_at, :utc_datetime_usec
      add :last_login_ip, :string
      add :login_count, :integer, default: 0, null: false
      add :failed_login_attempts, :integer, default: 0, null: false
      add :locked_at, :utc_datetime_usec
      add :lock_reason, :string
      add :password_changed_at, :utc_datetime_usec

      # User defaults - nullable FKs with nilify on delete
      add :default_account_id, references(:accounts, type: :uuid, on_delete: :nilify_all)
      add :default_role_id, references(:roles, type: :uuid, on_delete: :nilify_all)
    end

    # Indexes for common queries
    create index(:users, [:last_login_at])
    create index(:users, [:locked_at], where: "locked_at IS NOT NULL")
    create index(:users, [:default_account_id])
    create index(:users, [:default_role_id])
  end
end
