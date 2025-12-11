defmodule OmFieldNamesTest do
  use ExUnit.Case, async: true

  doctest OmFieldNames

  describe "individual audit field names" do
    test "created_by_urm_id/0 returns correct atom" do
      assert OmFieldNames.created_by_urm_id() == :created_by_urm_id
    end

    test "updated_by_urm_id/0 returns correct atom" do
      assert OmFieldNames.updated_by_urm_id() == :updated_by_urm_id
    end

    test "created_by_user_id/0 returns correct atom" do
      assert OmFieldNames.created_by_user_id() == :created_by_user_id
    end

    test "updated_by_user_id/0 returns correct atom" do
      assert OmFieldNames.updated_by_user_id() == :updated_by_user_id
    end
  end

  describe "soft delete field names" do
    test "deleted_at/0 returns correct atom" do
      assert OmFieldNames.deleted_at() == :deleted_at
    end

    test "deleted_by_urm_id/0 returns correct atom" do
      assert OmFieldNames.deleted_by_urm_id() == :deleted_by_urm_id
    end

    test "deleted_by_user_id/0 returns correct atom" do
      assert OmFieldNames.deleted_by_user_id() == :deleted_by_user_id
    end

    test "deletion_reason/0 returns correct atom" do
      assert OmFieldNames.deletion_reason() == :deletion_reason
    end
  end

  describe "timestamp field names" do
    test "inserted_at/0 returns correct atom" do
      assert OmFieldNames.inserted_at() == :inserted_at
    end

    test "updated_at/0 returns correct atom" do
      assert OmFieldNames.updated_at() == :updated_at
    end
  end

  describe "IP tracking field names" do
    test "created_from_ip/0 returns correct atom" do
      assert OmFieldNames.created_from_ip() == :created_from_ip
    end

    test "updated_from_ip/0 returns correct atom" do
      assert OmFieldNames.updated_from_ip() == :updated_from_ip
    end
  end

  describe "session tracking field names" do
    test "created_session_id/0 returns correct atom" do
      assert OmFieldNames.created_session_id() == :created_session_id
    end

    test "updated_session_id/0 returns correct atom" do
      assert OmFieldNames.updated_session_id() == :updated_session_id
    end
  end

  describe "change tracking field names" do
    test "change_history/0 returns correct atom" do
      assert OmFieldNames.change_history() == :change_history
    end

    test "version/0 returns correct atom" do
      assert OmFieldNames.version() == :version
    end
  end

  describe "field lists" do
    test "audit_fields/0 returns list of standard audit fields" do
      fields = OmFieldNames.audit_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end

    test "audit_user_fields/0 returns list of user tracking fields" do
      fields = OmFieldNames.audit_user_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :created_by_user_id in fields
      assert :updated_by_user_id in fields
    end

    test "ip_tracking_fields/0 returns list of IP tracking fields" do
      fields = OmFieldNames.ip_tracking_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :created_from_ip in fields
      assert :updated_from_ip in fields
    end

    test "session_tracking_fields/0 returns list of session tracking fields" do
      fields = OmFieldNames.session_tracking_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :created_session_id in fields
      assert :updated_session_id in fields
    end

    test "change_tracking_fields/0 returns list of change tracking fields" do
      fields = OmFieldNames.change_tracking_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :change_history in fields
      assert :version in fields
    end

    test "soft_delete_fields/0 returns list of soft delete fields" do
      fields = OmFieldNames.soft_delete_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :deleted_at in fields
      assert :deleted_by_urm_id in fields
    end

    test "timestamp_fields/0 returns list of timestamp fields" do
      fields = OmFieldNames.timestamp_fields()

      assert is_list(fields)
      assert length(fields) == 2
      assert :inserted_at in fields
      assert :updated_at in fields
    end
  end

  describe "consistency" do
    test "individual field names match their list counterparts" do
      # Audit fields
      assert OmFieldNames.created_by_urm_id() in OmFieldNames.audit_fields()
      assert OmFieldNames.updated_by_urm_id() in OmFieldNames.audit_fields()

      # Audit user fields
      assert OmFieldNames.created_by_user_id() in OmFieldNames.audit_user_fields()
      assert OmFieldNames.updated_by_user_id() in OmFieldNames.audit_user_fields()

      # Soft delete fields
      assert OmFieldNames.deleted_at() in OmFieldNames.soft_delete_fields()
      assert OmFieldNames.deleted_by_urm_id() in OmFieldNames.soft_delete_fields()

      # Timestamp fields
      assert OmFieldNames.inserted_at() in OmFieldNames.timestamp_fields()
      assert OmFieldNames.updated_at() in OmFieldNames.timestamp_fields()

      # IP tracking fields
      assert OmFieldNames.created_from_ip() in OmFieldNames.ip_tracking_fields()
      assert OmFieldNames.updated_from_ip() in OmFieldNames.ip_tracking_fields()

      # Session tracking fields
      assert OmFieldNames.created_session_id() in OmFieldNames.session_tracking_fields()
      assert OmFieldNames.updated_session_id() in OmFieldNames.session_tracking_fields()

      # Change tracking fields
      assert OmFieldNames.change_history() in OmFieldNames.change_tracking_fields()
      assert OmFieldNames.version() in OmFieldNames.change_tracking_fields()
    end

    test "all field names are atoms" do
      all_individual_fields = [
        OmFieldNames.created_by_urm_id(),
        OmFieldNames.updated_by_urm_id(),
        OmFieldNames.created_by_user_id(),
        OmFieldNames.updated_by_user_id(),
        OmFieldNames.deleted_at(),
        OmFieldNames.deleted_by_urm_id(),
        OmFieldNames.deleted_by_user_id(),
        OmFieldNames.deletion_reason(),
        OmFieldNames.inserted_at(),
        OmFieldNames.updated_at(),
        OmFieldNames.created_from_ip(),
        OmFieldNames.updated_from_ip(),
        OmFieldNames.created_session_id(),
        OmFieldNames.updated_session_id(),
        OmFieldNames.change_history(),
        OmFieldNames.version()
      ]

      for field <- all_individual_fields do
        assert is_atom(field), "Expected #{inspect(field)} to be an atom"
      end
    end

    test "field lists contain only atoms" do
      all_field_lists = [
        OmFieldNames.audit_fields(),
        OmFieldNames.audit_user_fields(),
        OmFieldNames.soft_delete_fields(),
        OmFieldNames.timestamp_fields(),
        OmFieldNames.ip_tracking_fields(),
        OmFieldNames.session_tracking_fields(),
        OmFieldNames.change_tracking_fields()
      ]

      for field_list <- all_field_lists do
        for field <- field_list do
          assert is_atom(field), "Expected #{inspect(field)} to be an atom"
        end
      end
    end

    test "no duplicate fields across primary lists" do
      # These are the primary field groups (not including user variants)
      primary_lists = [
        OmFieldNames.audit_fields(),
        OmFieldNames.soft_delete_fields(),
        OmFieldNames.timestamp_fields()
      ]

      all_fields = List.flatten(primary_lists)
      unique_fields = Enum.uniq(all_fields)

      assert length(all_fields) == length(unique_fields),
             "Found duplicate fields: #{inspect(all_fields -- unique_fields)}"
    end
  end

  describe "naming conventions" do
    test "urm_id fields follow *_by_urm_id pattern" do
      urm_fields = [
        OmFieldNames.created_by_urm_id(),
        OmFieldNames.updated_by_urm_id(),
        OmFieldNames.deleted_by_urm_id()
      ]

      for field <- urm_fields do
        field_str = Atom.to_string(field)
        assert String.ends_with?(field_str, "_by_urm_id")
      end
    end

    test "user_id fields follow *_by_user_id pattern" do
      user_fields = [
        OmFieldNames.created_by_user_id(),
        OmFieldNames.updated_by_user_id(),
        OmFieldNames.deleted_by_user_id()
      ]

      for field <- user_fields do
        field_str = Atom.to_string(field)
        assert String.ends_with?(field_str, "_by_user_id")
      end
    end

    test "timestamp fields follow *_at pattern" do
      timestamp_fields = [
        OmFieldNames.deleted_at(),
        OmFieldNames.inserted_at(),
        OmFieldNames.updated_at()
      ]

      for field <- timestamp_fields do
        field_str = Atom.to_string(field)
        assert String.ends_with?(field_str, "_at")
      end
    end
  end
end
