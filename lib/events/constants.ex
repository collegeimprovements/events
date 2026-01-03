defmodule Events.Constants do
  @moduledoc """
  System-wide constants for bootstrap/seed data.

  These UUIDs are valid UUIDv7 with sequential suffixes, used for:
  - Default account (for single-tenant deployments)
  - System user (for automated operations)
  - System role (super_admin)
  - System URM (for audit field defaults)

  ## Usage

  Runtime access:
      Events.Constants.default_account_id()
      Events.Constants.system_user_id()

  Compile-time access (for migrations and module attributes):
      import Events.Constants
      @default_account default_account_id_const()
  """

  @default_account_id "01936d77-0000-7000-8000-000000000000"
  @system_user_id "01936d77-0000-7000-8000-000000000001"
  @system_role_id "01936d77-0000-7000-8000-000000000002"
  @system_urm_id "01936d77-0000-7000-8000-000000000003"

  @doc "Default account UUID for single-tenant deployments"
  def default_account_id, do: @default_account_id

  @doc "System user UUID (cannot login directly)"
  def system_user_id, do: @system_user_id

  @doc "System super_admin role UUID"
  def system_role_id, do: @system_role_id

  @doc "System URM UUID (used for audit field defaults)"
  def system_urm_id, do: @system_urm_id

  # Compile-time access for use in migrations and module attributes
  defmacro default_account_id_const, do: @default_account_id
  defmacro system_user_id_const, do: @system_user_id
  defmacro system_role_id_const, do: @system_role_id
  defmacro system_urm_id_const, do: @system_urm_id
end
