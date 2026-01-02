defmodule OmSchema.FieldNames do
  @moduledoc """
  Canonical field names for Schema and Migration systems.

  This module provides a single source of truth for all field names
  used across schemas, ensuring consistency between
  Schema definitions and Migration field builders.

  ## Configuration

  Field names can be customized via application config:

      config :om_schema, OmSchema.FieldNames,
        audit_by_field: :updated_by_user_id,
        audit_created_field: :created_by_user_id,
        deleted_at_field: :archived_at

  ## Usage

      alias OmSchema.FieldNames

      # Get individual field names
      FieldNames.created_by()  # => :created_by_urm_id (or configured value)

      # Get lists of related fields
      FieldNames.audit_fields()  # => [:created_by_urm_id, :updated_by_urm_id]

  ## Default Field Naming Convention

  - `*_urm_id` - User Role Mapping ID (primary tracking mechanism)
  - `*_user_id` - Direct User ID (optional, when `track_user: true`)
  - `*_at` - Timestamps
  """

  # ============================================
  # Compile-time defaults (can be overridden via config)
  # ============================================

  @default_created_by :created_by_urm_id
  @default_updated_by :updated_by_urm_id
  @default_created_by_user :created_by_user_id
  @default_updated_by_user :updated_by_user_id
  @default_deleted_at :deleted_at
  @default_deleted_by :deleted_by_urm_id
  @default_deleted_by_user :deleted_by_user_id
  @default_deletion_reason :deletion_reason
  @default_inserted_at :inserted_at
  @default_updated_at :updated_at
  @default_created_from_ip :created_from_ip
  @default_updated_from_ip :updated_from_ip
  @default_created_session_id :created_session_id
  @default_updated_session_id :updated_session_id
  @default_change_history :change_history
  @default_version :version

  # ============================================
  # Audit Fields
  # ============================================

  @doc "Creator tracking field (default: :created_by_urm_id)"
  @spec created_by() :: atom()
  def created_by, do: get_config(:created_by, @default_created_by)

  @doc "Updater tracking field (default: :updated_by_urm_id)"
  @spec updated_by() :: atom()
  def updated_by, do: get_config(:updated_by, @default_updated_by)

  @doc "Creator tracking via direct user ID (optional)"
  @spec created_by_user() :: atom()
  def created_by_user, do: get_config(:created_by_user, @default_created_by_user)

  @doc "Updater tracking via direct user ID (optional)"
  @spec updated_by_user() :: atom()
  def updated_by_user, do: get_config(:updated_by_user, @default_updated_by_user)

  # Legacy aliases for backwards compatibility
  @doc false
  def created_by_urm_id, do: created_by()
  @doc false
  def updated_by_urm_id, do: updated_by()
  @doc false
  def created_by_user_id, do: created_by_user()
  @doc false
  def updated_by_user_id, do: updated_by_user()

  # ============================================
  # Soft Delete Fields
  # ============================================

  @doc "Soft delete timestamp (default: :deleted_at)"
  @spec deleted_at() :: atom()
  def deleted_at, do: get_config(:deleted_at, @default_deleted_at)

  @doc "Deleter tracking field (default: :deleted_by_urm_id)"
  @spec deleted_by() :: atom()
  def deleted_by, do: get_config(:deleted_by, @default_deleted_by)

  @doc "Deleter tracking via direct user ID (optional)"
  @spec deleted_by_user() :: atom()
  def deleted_by_user, do: get_config(:deleted_by_user, @default_deleted_by_user)

  @doc "Reason for deletion (optional)"
  @spec deletion_reason() :: atom()
  def deletion_reason, do: get_config(:deletion_reason, @default_deletion_reason)

  # Legacy aliases
  @doc false
  def deleted_by_urm_id, do: deleted_by()
  @doc false
  def deleted_by_user_id, do: deleted_by_user()

  # ============================================
  # Timestamp Fields
  # ============================================

  @doc "Record creation timestamp (default: :inserted_at)"
  @spec inserted_at() :: atom()
  def inserted_at, do: get_config(:inserted_at, @default_inserted_at)

  @doc "Record last update timestamp (default: :updated_at)"
  @spec updated_at() :: atom()
  def updated_at, do: get_config(:updated_at, @default_updated_at)

  # ============================================
  # IP Tracking Fields (Migration only)
  # ============================================

  @doc "IP address at record creation"
  @spec created_from_ip() :: atom()
  def created_from_ip, do: get_config(:created_from_ip, @default_created_from_ip)

  @doc "IP address at last update"
  @spec updated_from_ip() :: atom()
  def updated_from_ip, do: get_config(:updated_from_ip, @default_updated_from_ip)

  # ============================================
  # Session Tracking Fields (Migration only)
  # ============================================

  @doc "Session ID at record creation"
  @spec created_session_id() :: atom()
  def created_session_id, do: get_config(:created_session_id, @default_created_session_id)

  @doc "Session ID at last update"
  @spec updated_session_id() :: atom()
  def updated_session_id, do: get_config(:updated_session_id, @default_updated_session_id)

  # ============================================
  # Change Tracking Fields (Migration only)
  # ============================================

  @doc "History of changes to the record"
  @spec change_history() :: atom()
  def change_history, do: get_config(:change_history, @default_change_history)

  @doc "Record version counter"
  @spec version() :: atom()
  def version, do: get_config(:version, @default_version)

  # ============================================
  # Field Lists
  # ============================================

  @doc """
  Returns the standard audit field names.

  These are always added by `audit_fields()` macros.
  """
  @spec audit_fields() :: [atom()]
  def audit_fields, do: [created_by(), updated_by()]

  @doc """
  Returns the optional user tracking audit fields.

  Added when `track_user: true`.
  """
  @spec audit_user_fields() :: [atom()]
  def audit_user_fields, do: [created_by_user(), updated_by_user()]

  @doc """
  Returns the optional IP tracking fields.

  Added when `track_ip: true` (Migration only).
  """
  @spec ip_tracking_fields() :: [atom()]
  def ip_tracking_fields, do: [created_from_ip(), updated_from_ip()]

  @doc """
  Returns the optional session tracking fields.

  Added when `track_session: true` (Migration only).
  """
  @spec session_tracking_fields() :: [atom()]
  def session_tracking_fields, do: [created_session_id(), updated_session_id()]

  @doc """
  Returns the optional change tracking fields.

  Added when `track_changes: true` (Migration only).
  """
  @spec change_tracking_fields() :: [atom()]
  def change_tracking_fields, do: [change_history(), version()]

  @doc """
  Returns the core soft delete fields.

  `:deleted_at` is always added. `:deleted_by` is added when `track_urm: true` (default).
  """
  @spec soft_delete_fields() :: [atom()]
  def soft_delete_fields, do: [deleted_at(), deleted_by()]

  @doc """
  Returns the standard timestamp fields.
  """
  @spec timestamp_fields() :: [atom()]
  def timestamp_fields, do: [inserted_at(), updated_at()]

  # ============================================
  # Private Helpers
  # ============================================

  defp get_config(key, default) do
    Application.get_env(:om_schema, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
