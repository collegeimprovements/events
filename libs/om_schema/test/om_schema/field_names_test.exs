defmodule OmSchema.FieldNamesTest do
  @moduledoc """
  Tests for OmSchema.FieldNames - Configurable field naming conventions.

  Validates default field names, config overrides via Application.put_env,
  and field list functions. Each test restores config on exit.
  """

  use ExUnit.Case, async: true

  alias OmSchema.FieldNames

  # ============================================
  # Setup / Teardown
  # ============================================

  setup do
    # Capture original config to restore after each test
    original = Application.get_env(:om_schema, OmSchema.FieldNames, [])

    on_exit(fn ->
      if original == [] do
        Application.delete_env(:om_schema, OmSchema.FieldNames)
      else
        Application.put_env(:om_schema, OmSchema.FieldNames, original)
      end
    end)

    :ok
  end

  # ============================================
  # Audit Fields - Defaults
  # ============================================

  describe "audit field defaults" do
    test "created_by/0 defaults to :created_by_urm_id" do
      assert FieldNames.created_by() == :created_by_urm_id
    end

    test "updated_by/0 defaults to :updated_by_urm_id" do
      assert FieldNames.updated_by() == :updated_by_urm_id
    end

    test "created_by_user/0 defaults to :created_by_user_id" do
      assert FieldNames.created_by_user() == :created_by_user_id
    end

    test "updated_by_user/0 defaults to :updated_by_user_id" do
      assert FieldNames.updated_by_user() == :updated_by_user_id
    end
  end

  # ============================================
  # Audit Fields - Config Override
  # ============================================

  describe "audit field config overrides" do
    test "created_by/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, created_by: :creator_id)
      assert FieldNames.created_by() == :creator_id
    end

    test "updated_by/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, updated_by: :modifier_id)
      assert FieldNames.updated_by() == :modifier_id
    end

    test "created_by_user/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, created_by_user: :creator_user_id)
      assert FieldNames.created_by_user() == :creator_user_id
    end

    test "updated_by_user/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, updated_by_user: :modifier_user_id)
      assert FieldNames.updated_by_user() == :modifier_user_id
    end
  end

  # ============================================
  # Legacy Aliases
  # ============================================

  describe "legacy aliases" do
    test "created_by_urm_id/0 delegates to created_by/0" do
      assert FieldNames.created_by_urm_id() == FieldNames.created_by()
    end

    test "updated_by_urm_id/0 delegates to updated_by/0" do
      assert FieldNames.updated_by_urm_id() == FieldNames.updated_by()
    end

    test "created_by_user_id/0 delegates to created_by_user/0" do
      assert FieldNames.created_by_user_id() == FieldNames.created_by_user()
    end

    test "updated_by_user_id/0 delegates to updated_by_user/0" do
      assert FieldNames.updated_by_user_id() == FieldNames.updated_by_user()
    end

    test "deleted_by_urm_id/0 delegates to deleted_by/0" do
      assert FieldNames.deleted_by_urm_id() == FieldNames.deleted_by()
    end

    test "deleted_by_user_id/0 delegates to deleted_by_user/0" do
      assert FieldNames.deleted_by_user_id() == FieldNames.deleted_by_user()
    end
  end

  # ============================================
  # Soft Delete Fields - Defaults
  # ============================================

  describe "soft delete field defaults" do
    test "deleted_at/0 defaults to :deleted_at" do
      assert FieldNames.deleted_at() == :deleted_at
    end

    test "deleted_by/0 defaults to :deleted_by_urm_id" do
      assert FieldNames.deleted_by() == :deleted_by_urm_id
    end

    test "deleted_by_user/0 defaults to :deleted_by_user_id" do
      assert FieldNames.deleted_by_user() == :deleted_by_user_id
    end

    test "deletion_reason/0 defaults to :deletion_reason" do
      assert FieldNames.deletion_reason() == :deletion_reason
    end
  end

  # ============================================
  # Soft Delete Fields - Config Override
  # ============================================

  describe "soft delete field config overrides" do
    test "deleted_at/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, deleted_at: :archived_at)
      assert FieldNames.deleted_at() == :archived_at
    end

    test "deleted_by/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, deleted_by: :archived_by)
      assert FieldNames.deleted_by() == :archived_by
    end

    test "deletion_reason/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, deletion_reason: :archive_reason)
      assert FieldNames.deletion_reason() == :archive_reason
    end
  end

  # ============================================
  # Timestamp Fields - Defaults
  # ============================================

  describe "timestamp field defaults" do
    test "inserted_at/0 defaults to :inserted_at" do
      assert FieldNames.inserted_at() == :inserted_at
    end

    test "updated_at/0 defaults to :updated_at" do
      assert FieldNames.updated_at() == :updated_at
    end
  end

  # ============================================
  # Timestamp Fields - Config Override
  # ============================================

  describe "timestamp field config overrides" do
    test "inserted_at/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, inserted_at: :created_at)
      assert FieldNames.inserted_at() == :created_at
    end

    test "updated_at/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, updated_at: :modified_at)
      assert FieldNames.updated_at() == :modified_at
    end
  end

  # ============================================
  # IP Tracking Fields
  # ============================================

  describe "IP tracking field defaults" do
    test "created_from_ip/0 defaults to :created_from_ip" do
      assert FieldNames.created_from_ip() == :created_from_ip
    end

    test "updated_from_ip/0 defaults to :updated_from_ip" do
      assert FieldNames.updated_from_ip() == :updated_from_ip
    end
  end

  describe "IP tracking field config overrides" do
    test "created_from_ip/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, created_from_ip: :origin_ip)
      assert FieldNames.created_from_ip() == :origin_ip
    end
  end

  # ============================================
  # Session Tracking Fields
  # ============================================

  describe "session tracking field defaults" do
    test "created_session_id/0 defaults to :created_session_id" do
      assert FieldNames.created_session_id() == :created_session_id
    end

    test "updated_session_id/0 defaults to :updated_session_id" do
      assert FieldNames.updated_session_id() == :updated_session_id
    end
  end

  describe "session tracking field config overrides" do
    test "created_session_id/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, created_session_id: :origin_session)
      assert FieldNames.created_session_id() == :origin_session
    end
  end

  # ============================================
  # Change Tracking Fields
  # ============================================

  describe "change tracking field defaults" do
    test "change_history/0 defaults to :change_history" do
      assert FieldNames.change_history() == :change_history
    end

    test "version/0 defaults to :version" do
      assert FieldNames.version() == :version
    end
  end

  describe "change tracking field config overrides" do
    test "change_history/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, change_history: :audit_log)
      assert FieldNames.change_history() == :audit_log
    end

    test "version/0 uses configured value" do
      Application.put_env(:om_schema, OmSchema.FieldNames, version: :revision)
      assert FieldNames.version() == :revision
    end
  end

  # ============================================
  # Field List Functions - Defaults
  # ============================================

  describe "audit_fields/0" do
    test "returns created_by and updated_by" do
      result = FieldNames.audit_fields()
      assert result == [:created_by_urm_id, :updated_by_urm_id]
    end

    test "reflects config overrides" do
      Application.put_env(:om_schema, OmSchema.FieldNames,
        created_by: :creator,
        updated_by: :updater
      )

      assert FieldNames.audit_fields() == [:creator, :updater]
    end
  end

  describe "audit_user_fields/0" do
    test "returns created_by_user and updated_by_user" do
      result = FieldNames.audit_user_fields()
      assert result == [:created_by_user_id, :updated_by_user_id]
    end
  end

  describe "ip_tracking_fields/0" do
    test "returns created_from_ip and updated_from_ip" do
      result = FieldNames.ip_tracking_fields()
      assert result == [:created_from_ip, :updated_from_ip]
    end
  end

  describe "session_tracking_fields/0" do
    test "returns created_session_id and updated_session_id" do
      result = FieldNames.session_tracking_fields()
      assert result == [:created_session_id, :updated_session_id]
    end
  end

  describe "change_tracking_fields/0" do
    test "returns change_history and version" do
      result = FieldNames.change_tracking_fields()
      assert result == [:change_history, :version]
    end
  end

  describe "soft_delete_fields/0" do
    test "returns deleted_at and deleted_by" do
      result = FieldNames.soft_delete_fields()
      assert result == [:deleted_at, :deleted_by_urm_id]
    end

    test "reflects config overrides" do
      Application.put_env(:om_schema, OmSchema.FieldNames,
        deleted_at: :archived_at,
        deleted_by: :archived_by
      )

      assert FieldNames.soft_delete_fields() == [:archived_at, :archived_by]
    end
  end

  describe "timestamp_fields/0" do
    test "returns inserted_at and updated_at" do
      result = FieldNames.timestamp_fields()
      assert result == [:inserted_at, :updated_at]
    end

    test "reflects config overrides" do
      Application.put_env(:om_schema, OmSchema.FieldNames,
        inserted_at: :created_at,
        updated_at: :modified_at
      )

      assert FieldNames.timestamp_fields() == [:created_at, :modified_at]
    end
  end

  # ============================================
  # Multiple Config Keys
  # ============================================

  describe "multiple config overrides" do
    test "supports overriding multiple fields at once" do
      Application.put_env(:om_schema, OmSchema.FieldNames,
        created_by: :author_id,
        updated_by: :editor_id,
        deleted_at: :removed_at,
        inserted_at: :created_at
      )

      assert FieldNames.created_by() == :author_id
      assert FieldNames.updated_by() == :editor_id
      assert FieldNames.deleted_at() == :removed_at
      assert FieldNames.inserted_at() == :created_at

      # Non-overridden fields keep defaults
      assert FieldNames.version() == :version
      assert FieldNames.updated_at() == :updated_at
    end
  end

  # ============================================
  # Edge Cases
  # ============================================

  describe "edge cases" do
    test "missing config key returns default" do
      Application.put_env(:om_schema, OmSchema.FieldNames, [])
      assert FieldNames.created_by() == :created_by_urm_id
    end

    test "nil config falls back to default" do
      Application.delete_env(:om_schema, OmSchema.FieldNames)
      assert FieldNames.created_by() == :created_by_urm_id
    end
  end
end
