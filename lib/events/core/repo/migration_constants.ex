defmodule Events.Core.Repo.MigrationConstants do
  @moduledoc """
  Well-known UUIDs for bootstrap data in migrations.

  These constants are used to create the initial system user, role, account,
  and user-role mapping that form the foundation of the audit system.

  All UUIDs are deterministic (UUIDv5) to ensure consistency across environments.
  """

  @doc """
  Returns the UUID for the default/system account.
  """
  def default_account_id do
    # Deterministic UUID: namespace + "default-account"
    "00000000-0000-0000-0000-000000000001"
  end

  @doc """
  Returns the UUID for the system user.
  This user cannot log in (no password) and is used for system operations.
  """
  def system_user_id do
    # Deterministic UUID: namespace + "system-user"
    "00000000-0000-0000-0000-000000000002"
  end

  @doc """
  Returns the UUID for the system/super_admin role.
  """
  def system_role_id do
    # Deterministic UUID: namespace + "system-role"
    "00000000-0000-0000-0000-000000000003"
  end

  @doc """
  Returns the UUID for the system user-role mapping.
  This is the primary audit reference for system operations.
  """
  def system_urm_id do
    # Deterministic UUID: namespace + "system-urm"
    "00000000-0000-0000-0000-000000000004"
  end
end
