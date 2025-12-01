defmodule Events.Core.Repo.MigrationConstants do
  @moduledoc """
  Shared constants for database migrations.

  These UUIDs are valid UUIDv7 format with sequential suffixes for bootstrap data.
  They are used across multiple migrations to ensure consistency.
  """

  @default_account_id "01936d77-0000-7000-8000-000000000000"
  @system_user_id "01936d77-0000-7000-8000-000000000001"
  @system_role_id "01936d77-0000-7000-8000-000000000002"
  @system_urm_id "01936d77-0000-7000-8000-000000000003"

  def default_account_id, do: @default_account_id
  def system_user_id, do: @system_user_id
  def system_role_id, do: @system_role_id
  def system_urm_id, do: @system_urm_id
end
