defmodule Events.FieldNames do
  @moduledoc """
  Canonical field names for Schema and Migration systems.

  This module provides a single source of truth for all field names
  used across the Events framework, ensuring consistency between
  Schema definitions and Migration field builders.

  ## Usage

      alias Events.FieldNames

      # Get individual field names
      FieldNames.created_by_urm_id()  # => :created_by_urm_id

      # Get lists of related fields
      FieldNames.audit_fields()       # => [:created_by_urm_id, :updated_by_urm_id]

  ## Field Naming Convention

  - `*_urm_id` - User Role Mapping ID (primary tracking mechanism)
  - `*_user_id` - Direct User ID (optional, when `track_user: true`)
  - `*_at` - Timestamps
  """

  # ============================================
  # Audit Fields
  # ============================================

  @doc "Creator tracking via user role mapping"
  @spec created_by_urm_id() :: :created_by_urm_id
  def created_by_urm_id, do: :created_by_urm_id

  @doc "Updater tracking via user role mapping"
  @spec updated_by_urm_id() :: :updated_by_urm_id
  def updated_by_urm_id, do: :updated_by_urm_id

  @doc "Creator tracking via direct user ID (optional)"
  @spec created_by_user_id() :: :created_by_user_id
  def created_by_user_id, do: :created_by_user_id

  @doc "Updater tracking via direct user ID (optional)"
  @spec updated_by_user_id() :: :updated_by_user_id
  def updated_by_user_id, do: :updated_by_user_id

  # ============================================
  # Soft Delete Fields
  # ============================================

  @doc "Soft delete timestamp"
  @spec deleted_at() :: :deleted_at
  def deleted_at, do: :deleted_at

  @doc "Deleter tracking via user role mapping"
  @spec deleted_by_urm_id() :: :deleted_by_urm_id
  def deleted_by_urm_id, do: :deleted_by_urm_id

  @doc "Deleter tracking via direct user ID (optional)"
  @spec deleted_by_user_id() :: :deleted_by_user_id
  def deleted_by_user_id, do: :deleted_by_user_id

  @doc "Reason for deletion (optional)"
  @spec deletion_reason() :: :deletion_reason
  def deletion_reason, do: :deletion_reason

  # ============================================
  # Timestamp Fields
  # ============================================

  @doc "Record creation timestamp"
  @spec inserted_at() :: :inserted_at
  def inserted_at, do: :inserted_at

  @doc "Record last update timestamp"
  @spec updated_at() :: :updated_at
  def updated_at, do: :updated_at

  # ============================================
  # IP Tracking Fields (Migration only)
  # ============================================

  @doc "IP address at record creation"
  @spec created_from_ip() :: :created_from_ip
  def created_from_ip, do: :created_from_ip

  @doc "IP address at last update"
  @spec updated_from_ip() :: :updated_from_ip
  def updated_from_ip, do: :updated_from_ip

  # ============================================
  # Session Tracking Fields (Migration only)
  # ============================================

  @doc "Session ID at record creation"
  @spec created_session_id() :: :created_session_id
  def created_session_id, do: :created_session_id

  @doc "Session ID at last update"
  @spec updated_session_id() :: :updated_session_id
  def updated_session_id, do: :updated_session_id

  # ============================================
  # Change Tracking Fields (Migration only)
  # ============================================

  @doc "History of changes to the record"
  @spec change_history() :: :change_history
  def change_history, do: :change_history

  @doc "Record version counter"
  @spec version() :: :version
  def version, do: :version

  # ============================================
  # Field Lists
  # ============================================

  @doc """
  Returns the standard audit field names.

  These are always added by `audit_fields()` macros.
  """
  @spec audit_fields() :: [:created_by_urm_id | :updated_by_urm_id]
  def audit_fields, do: [:created_by_urm_id, :updated_by_urm_id]

  @doc """
  Returns the optional user tracking audit fields.

  Added when `track_user: true`.
  """
  @spec audit_user_fields() :: [:created_by_user_id | :updated_by_user_id]
  def audit_user_fields, do: [:created_by_user_id, :updated_by_user_id]

  @doc """
  Returns the optional IP tracking fields.

  Added when `track_ip: true` (Migration only).
  """
  @spec ip_tracking_fields() :: [:created_from_ip | :updated_from_ip]
  def ip_tracking_fields, do: [:created_from_ip, :updated_from_ip]

  @doc """
  Returns the optional session tracking fields.

  Added when `track_session: true` (Migration only).
  """
  @spec session_tracking_fields() :: [:created_session_id | :updated_session_id]
  def session_tracking_fields, do: [:created_session_id, :updated_session_id]

  @doc """
  Returns the optional change tracking fields.

  Added when `track_changes: true` (Migration only).
  """
  @spec change_tracking_fields() :: [:change_history | :version]
  def change_tracking_fields, do: [:change_history, :version]

  @doc """
  Returns the core soft delete fields.

  `:deleted_at` is always added. `:deleted_by_urm_id` is added when `track_urm: true` (default).
  """
  @spec soft_delete_fields() :: [:deleted_at | :deleted_by_urm_id]
  def soft_delete_fields, do: [:deleted_at, :deleted_by_urm_id]

  @doc """
  Returns the standard timestamp fields.
  """
  @spec timestamp_fields() :: [:inserted_at | :updated_at]
  def timestamp_fields, do: [:inserted_at, :updated_at]
end
