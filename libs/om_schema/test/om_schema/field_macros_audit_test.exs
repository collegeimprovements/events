defmodule OmSchema.FieldMacrosAuditTest do
  @moduledoc """
  Tests for audit_fields/1 and soft_delete_field/1 macros from OmSchema.

  These macros support extended tracking options (track_urm, track_user,
  track_ip, track_session, track_changes) and use OmSchema.FieldNames
  for configurable field naming.
  """

  use ExUnit.Case, async: true

  # ============================================
  # Test Schemas - audit_fields/1
  # ============================================

  defmodule DefaultAuditSchema do
    use OmSchema

    schema "audit_test_default" do
      field :name, :string
      audit_fields()
    end
  end

  defmodule AuditWithUserTrackingSchema do
    use OmSchema

    schema "audit_test_user_tracking" do
      field :name, :string
      audit_fields(track_user: true)
    end
  end

  defmodule AuditWithIpTrackingSchema do
    use OmSchema

    schema "audit_test_ip_tracking" do
      field :name, :string
      audit_fields(track_ip: true)
    end
  end

  defmodule AuditWithSessionTrackingSchema do
    use OmSchema

    schema "audit_test_session_tracking" do
      field :name, :string
      audit_fields(track_session: true)
    end
  end

  defmodule AuditWithChangeTrackingSchema do
    use OmSchema

    schema "audit_test_change_tracking" do
      field :name, :string
      audit_fields(track_changes: true)
    end
  end

  defmodule AuditAllOptionsSchema do
    use OmSchema

    schema "audit_test_all_options" do
      field :name, :string
      audit_fields(track_urm: true, track_user: true, track_ip: true, track_session: true, track_changes: true)
    end
  end

  defmodule AuditWithOnlyOption do
    use OmSchema

    schema "audit_test_only" do
      field :name, :string
      audit_fields(only: [:created_by_urm_id])
    end
  end

  # ============================================
  # Test Schemas - soft_delete_field/1
  # ============================================

  defmodule DefaultSoftDeleteSchema do
    use OmSchema

    schema "soft_delete_test_default" do
      field :name, :string
      soft_delete_field()
    end
  end

  defmodule SoftDeleteWithUrmSchema do
    use OmSchema

    schema "soft_delete_test_urm" do
      field :name, :string
      soft_delete_field(track_urm: true)
    end
  end

  defmodule SoftDeleteWithUserTrackingSchema do
    use OmSchema

    schema "soft_delete_test_user_tracking" do
      field :name, :string
      soft_delete_field(track_urm: true, track_user: true)
    end
  end

  defmodule SoftDeleteWithReasonSchema do
    use OmSchema

    schema "soft_delete_test_reason" do
      field :name, :string
      soft_delete_field(track_urm: true, track_reason: true)
    end
  end

  defmodule SoftDeleteNoUrmSchema do
    use OmSchema

    schema "soft_delete_test_no_urm" do
      field :name, :string
      soft_delete_field(track_urm: false)
    end
  end

  defmodule SoftDeleteAllOptionsSchema do
    use OmSchema

    schema "soft_delete_test_all_options" do
      field :name, :string
      soft_delete_field(track_urm: true, track_user: true, track_reason: true)
    end
  end

  # ============================================
  # audit_fields/1 Tests
  # ============================================

  describe "audit_fields/1 with defaults" do
    test "adds created_by_urm_id and updated_by_urm_id fields" do
      fields = DefaultAuditSchema.__schema__(:fields)

      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end

    test "URM fields have :binary_id type" do
      assert DefaultAuditSchema.__schema__(:type, :created_by_urm_id) == :binary_id
      assert DefaultAuditSchema.__schema__(:type, :updated_by_urm_id) == :binary_id
    end

    test "does not add user tracking fields by default" do
      fields = DefaultAuditSchema.__schema__(:fields)

      refute :created_by_user_id in fields
      refute :updated_by_user_id in fields
    end

    test "does not add IP tracking fields by default" do
      fields = DefaultAuditSchema.__schema__(:fields)

      refute :created_from_ip in fields
      refute :updated_from_ip in fields
    end

    test "does not add session tracking fields by default" do
      fields = DefaultAuditSchema.__schema__(:fields)

      refute :created_session_id in fields
      refute :updated_session_id in fields
    end

    test "does not add change tracking fields by default" do
      fields = DefaultAuditSchema.__schema__(:fields)

      refute :change_history in fields
      refute :version in fields
    end
  end

  describe "audit_fields/1 with :only option" do
    test "only includes specified URM fields" do
      fields = AuditWithOnlyOption.__schema__(:fields)

      assert :created_by_urm_id in fields
      refute :updated_by_urm_id in fields
    end
  end

  describe "audit_fields/1 with track_user: true" do
    test "adds user tracking fields" do
      fields = AuditWithUserTrackingSchema.__schema__(:fields)

      assert :created_by_user_id in fields
      assert :updated_by_user_id in fields
    end

    test "user tracking fields have :binary_id type" do
      assert AuditWithUserTrackingSchema.__schema__(:type, :created_by_user_id) == :binary_id
      assert AuditWithUserTrackingSchema.__schema__(:type, :updated_by_user_id) == :binary_id
    end

    test "still includes default URM fields" do
      fields = AuditWithUserTrackingSchema.__schema__(:fields)

      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end
  end

  describe "audit_fields/1 with track_ip: true" do
    test "adds IP tracking fields" do
      fields = AuditWithIpTrackingSchema.__schema__(:fields)

      assert :created_from_ip in fields
      assert :updated_from_ip in fields
    end

    test "IP fields have string type" do
      assert AuditWithIpTrackingSchema.__schema__(:type, :created_from_ip) == :string
      assert AuditWithIpTrackingSchema.__schema__(:type, :updated_from_ip) == :string
    end

    test "still includes default URM fields" do
      fields = AuditWithIpTrackingSchema.__schema__(:fields)

      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end
  end

  describe "audit_fields/1 with track_session: true" do
    test "adds session tracking fields" do
      fields = AuditWithSessionTrackingSchema.__schema__(:fields)

      assert :created_session_id in fields
      assert :updated_session_id in fields
    end

    test "session fields have string type" do
      assert AuditWithSessionTrackingSchema.__schema__(:type, :created_session_id) == :string
      assert AuditWithSessionTrackingSchema.__schema__(:type, :updated_session_id) == :string
    end

    test "still includes default URM fields" do
      fields = AuditWithSessionTrackingSchema.__schema__(:fields)

      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end
  end

  describe "audit_fields/1 with track_changes: true" do
    test "adds change_history and version fields" do
      fields = AuditWithChangeTrackingSchema.__schema__(:fields)

      assert :change_history in fields
      assert :version in fields
    end

    test "change_history has array of maps type" do
      assert AuditWithChangeTrackingSchema.__schema__(:type, :change_history) == {:array, :map}
    end

    test "version has integer type" do
      assert AuditWithChangeTrackingSchema.__schema__(:type, :version) == :integer
    end

    test "still includes default URM fields" do
      fields = AuditWithChangeTrackingSchema.__schema__(:fields)

      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end
  end

  describe "audit_fields/1 with all options enabled" do
    test "includes all tracking fields" do
      fields = AuditAllOptionsSchema.__schema__(:fields)

      # URM tracking
      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields

      # User tracking
      assert :created_by_user_id in fields
      assert :updated_by_user_id in fields

      # IP tracking
      assert :created_from_ip in fields
      assert :updated_from_ip in fields

      # Session tracking
      assert :created_session_id in fields
      assert :updated_session_id in fields

      # Change tracking
      assert :change_history in fields
      assert :version in fields
    end
  end

  describe "audit_fields/1 with all tracking disabled" do
    test "raises ArgumentError" do
      assert_raise ArgumentError, ~r/at least one tracking option/, fn ->
        defmodule AuditAllDisabledSchema do
          use OmSchema

          schema "audit_test_all_disabled" do
            field :name, :string
            audit_fields(track_urm: false, track_user: false, track_ip: false, track_session: false, track_changes: false)
          end
        end
      end
    end
  end

  # ============================================
  # soft_delete_field/1 Tests
  # ============================================

  describe "soft_delete_field/1 with defaults" do
    test "adds deleted_at field" do
      fields = DefaultSoftDeleteSchema.__schema__(:fields)

      assert :deleted_at in fields
    end

    test "deleted_at has utc_datetime_usec type" do
      assert DefaultSoftDeleteSchema.__schema__(:type, :deleted_at) == :utc_datetime_usec
    end

    test "does not add deleted_by_urm_id by default" do
      fields = DefaultSoftDeleteSchema.__schema__(:fields)

      refute :deleted_by_urm_id in fields
    end

    test "does not add user tracking field by default" do
      fields = DefaultSoftDeleteSchema.__schema__(:fields)

      refute :deleted_by_user_id in fields
    end

    test "does not add deletion_reason by default" do
      fields = DefaultSoftDeleteSchema.__schema__(:fields)

      refute :deletion_reason in fields
    end
  end

  describe "soft_delete_field/1 with track_urm: true" do
    test "adds deleted_by_urm_id field" do
      fields = SoftDeleteWithUrmSchema.__schema__(:fields)

      assert :deleted_by_urm_id in fields
    end

    test "deleted_by_urm_id has :binary_id type" do
      assert SoftDeleteWithUrmSchema.__schema__(:type, :deleted_by_urm_id) == :binary_id
    end
  end

  describe "soft_delete_field/1 with track_user: true" do
    test "adds deleted_by_user_id field" do
      fields = SoftDeleteWithUserTrackingSchema.__schema__(:fields)

      assert :deleted_by_user_id in fields
    end

    test "deleted_by_user_id has :binary_id type" do
      assert SoftDeleteWithUserTrackingSchema.__schema__(:type, :deleted_by_user_id) == :binary_id
    end

    test "still includes deleted_at and deleted_by_urm_id" do
      fields = SoftDeleteWithUserTrackingSchema.__schema__(:fields)

      assert :deleted_at in fields
      assert :deleted_by_urm_id in fields
    end
  end

  describe "soft_delete_field/1 with track_reason: true" do
    test "adds deletion_reason field" do
      fields = SoftDeleteWithReasonSchema.__schema__(:fields)

      assert :deletion_reason in fields
    end

    test "deletion_reason has string type" do
      assert SoftDeleteWithReasonSchema.__schema__(:type, :deletion_reason) == :string
    end

    test "still includes deleted_at and deleted_by_urm_id" do
      fields = SoftDeleteWithReasonSchema.__schema__(:fields)

      assert :deleted_at in fields
      assert :deleted_by_urm_id in fields
    end
  end

  describe "soft_delete_field/1 with track_urm: false" do
    test "only adds deleted_at" do
      fields = SoftDeleteNoUrmSchema.__schema__(:fields)

      assert :deleted_at in fields
      refute :deleted_by_urm_id in fields
    end

    test "does not add user tracking or reason fields" do
      fields = SoftDeleteNoUrmSchema.__schema__(:fields)

      refute :deleted_by_user_id in fields
      refute :deletion_reason in fields
    end
  end

  describe "soft_delete_field/1 with all options enabled" do
    test "includes all soft delete fields" do
      fields = SoftDeleteAllOptionsSchema.__schema__(:fields)

      assert :deleted_at in fields
      assert :deleted_by_urm_id in fields
      assert :deleted_by_user_id in fields
      assert :deletion_reason in fields
    end
  end
end
