defmodule Events.Repo.Migrations.AddCompoundStatusIndexes do
  @moduledoc """
  Adds compound indexes for common query patterns that filter by status.

  These indexes optimize queries like:
  - `WHERE account_id = ? AND status = 'active'`
  - `WHERE user_id = ? AND status = 'active'`
  - `WHERE role_id = ? AND status = 'active'`

  See lib/events/accounts.ex for the queries these support.
  """
  use OmMigration

  def change do
    # Memberships: Common queries filter by (account_id, status) or (user_id, status)
    # Example: list_accounts_for_user filters by user_id and status = :active
    create index(:memberships, [:account_id, :status])
    create index(:memberships, [:user_id, :status])

    # Roles: Common queries filter by (account_id, status)
    # Example: list_roles_for_account filters by account_id (or nil) and status = :active
    create index(:roles, [:account_id, :status])
  end
end
