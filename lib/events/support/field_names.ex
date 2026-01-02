defmodule Events.Support.FieldNames do
  @moduledoc """
  Canonical field names for Schema and Migration systems.

  Thin wrapper around `OmSchema.FieldNames` with Events-specific defaults.

  See `OmSchema.FieldNames` for full documentation.
  """

  # Audit Fields
  defdelegate created_by(), to: OmSchema.FieldNames
  defdelegate updated_by(), to: OmSchema.FieldNames
  defdelegate created_by_user(), to: OmSchema.FieldNames
  defdelegate updated_by_user(), to: OmSchema.FieldNames

  # Legacy aliases for backwards compatibility
  defdelegate created_by_urm_id(), to: OmSchema.FieldNames
  defdelegate updated_by_urm_id(), to: OmSchema.FieldNames
  defdelegate created_by_user_id(), to: OmSchema.FieldNames
  defdelegate updated_by_user_id(), to: OmSchema.FieldNames

  # Soft Delete Fields
  defdelegate deleted_at(), to: OmSchema.FieldNames
  defdelegate deleted_by(), to: OmSchema.FieldNames
  defdelegate deleted_by_user(), to: OmSchema.FieldNames
  defdelegate deletion_reason(), to: OmSchema.FieldNames
  defdelegate deleted_by_urm_id(), to: OmSchema.FieldNames
  defdelegate deleted_by_user_id(), to: OmSchema.FieldNames

  # Timestamp Fields
  defdelegate inserted_at(), to: OmSchema.FieldNames
  defdelegate updated_at(), to: OmSchema.FieldNames

  # IP Tracking Fields
  defdelegate created_from_ip(), to: OmSchema.FieldNames
  defdelegate updated_from_ip(), to: OmSchema.FieldNames

  # Session Tracking Fields
  defdelegate created_session_id(), to: OmSchema.FieldNames
  defdelegate updated_session_id(), to: OmSchema.FieldNames

  # Change Tracking Fields
  defdelegate change_history(), to: OmSchema.FieldNames
  defdelegate version(), to: OmSchema.FieldNames

  # Field Lists
  defdelegate audit_fields(), to: OmSchema.FieldNames
  defdelegate audit_user_fields(), to: OmSchema.FieldNames
  defdelegate ip_tracking_fields(), to: OmSchema.FieldNames
  defdelegate session_tracking_fields(), to: OmSchema.FieldNames
  defdelegate change_tracking_fields(), to: OmSchema.FieldNames
  defdelegate soft_delete_fields(), to: OmSchema.FieldNames
  defdelegate timestamp_fields(), to: OmSchema.FieldNames
end
