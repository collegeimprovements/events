defmodule Events.Core.Migration.FieldMacrosTest do
  use Events.TestCase, async: true

  alias Events.Core.Migration.FieldMacros
  alias Events.Core.Migration.Token

  # Helper to create a table token
  defp create_table(name, opts \\ []) do
    Token.new(:table, name, opts)
  end

  describe "with_type_fields/2" do
    test "adds all type fields by default" do
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields()

      assert Token.has_field?(token, :type)
      assert Token.has_field?(token, :subtype)
      assert Token.has_field?(token, :kind)
      assert Token.has_field?(token, :category)
      assert Token.has_field?(token, :variant)
    end

    test "respects :only option" do
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [:type, :subtype])

      assert Token.has_field?(token, :type)
      assert Token.has_field?(token, :subtype)
      refute Token.has_field?(token, :kind)
      refute Token.has_field?(token, :category)
      refute Token.has_field?(token, :variant)
    end

    test "respects :except option" do
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields(except: [:variant, :category])

      assert Token.has_field?(token, :type)
      assert Token.has_field?(token, :subtype)
      assert Token.has_field?(token, :kind)
      refute Token.has_field?(token, :category)
      refute Token.has_field?(token, :variant)
    end

    test "uses :citext type by default" do
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [:type])

      {:type, field_type, _opts} = Token.get_field(token, :type)
      assert field_type == :citext
    end

    test "respects custom :type option" do
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [:type], type: :string)

      {:type, field_type, _opts} = Token.get_field(token, :type)
      assert field_type == :string
    end

    test "raises when no fields selected" do
      assert_raise ArgumentError, ~r/No fields selected/, fn ->
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [:nonexistent])
      end
    end
  end

  describe "with_status_fields/2" do
    test "adds all status fields by default" do
      token =
        create_table(:orders)
        |> FieldMacros.with_status_fields()

      assert Token.has_field?(token, :status)
      assert Token.has_field?(token, :substatus)
      assert Token.has_field?(token, :state)
      assert Token.has_field?(token, :workflow_state)
      assert Token.has_field?(token, :approval_status)
    end

    test "adds status index" do
      token =
        create_table(:orders)
        |> FieldMacros.with_status_fields()

      assert Token.has_index?(token, :status_index)
    end

    test "respects :only option" do
      token =
        create_table(:orders)
        |> FieldMacros.with_status_fields(only: [:status])

      assert Token.has_field?(token, :status)
      refute Token.has_field?(token, :substatus)
      refute Token.has_field?(token, :state)
    end

    test "adds transition fields when with_transition: true" do
      token =
        create_table(:orders)
        |> FieldMacros.with_status_fields(with_transition: true)

      assert Token.has_field?(token, :previous_status)
      assert Token.has_field?(token, :status_changed_at)
      assert Token.has_field?(token, :status_changed_by)
      assert Token.has_field?(token, :status_history)
    end

    test "no transition fields when with_transition: false (default)" do
      token =
        create_table(:orders)
        |> FieldMacros.with_status_fields()

      refute Token.has_field?(token, :previous_status)
      refute Token.has_field?(token, :status_changed_at)
    end
  end

  describe "with_timestamps/2" do
    test "adds inserted_at and updated_at by default" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps()

      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)
    end

    test "uses utc_datetime_usec type by default" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps(only: [:inserted_at])

      {:inserted_at, field_type, _opts} = Token.get_field(token, :inserted_at)
      assert field_type == :utc_datetime_usec
    end

    test "respects :only option" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps(only: [:inserted_at])

      assert Token.has_field?(token, :inserted_at)
      refute Token.has_field?(token, :updated_at)
    end

    test "adds indexes for timestamp fields" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps()

      assert Token.has_index?(token, :inserted_at_index)
      assert Token.has_index?(token, :updated_at_index)
    end

    test "adds deleted_at when with_deleted: true" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps(with_deleted: true)

      assert Token.has_field?(token, :deleted_at)
    end

    test "adds lifecycle timestamps when with_lifecycle: true" do
      token =
        create_table(:articles)
        |> FieldMacros.with_timestamps(with_lifecycle: true)

      assert Token.has_field?(token, :published_at)
      assert Token.has_field?(token, :archived_at)
      assert Token.has_field?(token, :expires_at)
    end
  end

  describe "with_audit_fields/2" do
    test "adds URM audit fields by default" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields()

      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :updated_by_urm_id)
    end

    test "no URM tracking when track_urm: false with another option enabled" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_urm: false, track_user: true)

      refute Token.has_field?(token, :created_by_urm_id)
      refute Token.has_field?(token, :updated_by_urm_id)
      # But user tracking should be there
      assert Token.has_field?(token, :created_by_user_id)
      assert Token.has_field?(token, :updated_by_user_id)
    end

    test "adds user tracking fields when track_user: true" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_user: true)

      assert Token.has_field?(token, :created_by_user_id)
      assert Token.has_field?(token, :updated_by_user_id)
      assert Token.has_index?(token, :created_by_user_index)
      assert Token.has_index?(token, :updated_by_user_index)
    end

    test "no user tracking by default" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields()

      refute Token.has_field?(token, :created_by_user_id)
      refute Token.has_field?(token, :updated_by_user_id)
    end

    test "user tracking only without URM" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_urm: false, track_user: true)

      refute Token.has_field?(token, :created_by_urm_id)
      refute Token.has_field?(token, :updated_by_urm_id)
      assert Token.has_field?(token, :created_by_user_id)
      assert Token.has_field?(token, :updated_by_user_id)
    end

    test "adds IP tracking when track_ip: true" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_ip: true)

      assert Token.has_field?(token, :created_from_ip)
      assert Token.has_field?(token, :updated_from_ip)
    end

    test "adds session tracking when track_session: true" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_session: true)

      assert Token.has_field?(token, :created_session_id)
      assert Token.has_field?(token, :updated_session_id)
    end

    test "adds change tracking when track_changes: true" do
      token =
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_changes: true)

      assert Token.has_field?(token, :change_history)
      assert Token.has_field?(token, :version)
    end

    test "raises when all tracking options are disabled" do
      assert_raise ArgumentError, ~r/requires at least one tracking option/, fn ->
        create_table(:documents)
        |> FieldMacros.with_audit_fields(track_urm: false)
      end
    end

    test "raises with helpful message when no tracking enabled" do
      assert_raise ArgumentError, ~r/remove the audit_fields\(\) call entirely/, fn ->
        create_table(:documents)
        |> FieldMacros.with_audit_fields(
          track_urm: false,
          track_user: false,
          track_ip: false,
          track_session: false,
          track_changes: false
        )
      end
    end
  end

  describe "with_uuid_primary_key/2" do
    test "adds UUIDv7 primary key by default" do
      token =
        create_table(:users)
        |> FieldMacros.with_uuid_primary_key()

      assert Token.has_field?(token, :id)
      {:id, :binary_id, opts} = Token.get_field(token, :id)
      assert opts[:primary_key] == true
      assert opts[:default] == {:fragment, "uuidv7()"}
    end

    test "respects custom name" do
      token =
        create_table(:users)
        |> FieldMacros.with_uuid_primary_key(name: :uuid)

      assert Token.has_field?(token, :uuid)
      refute Token.has_field?(token, :id)
    end

    test "supports uuidv4 type" do
      token =
        create_table(:users)
        |> FieldMacros.with_uuid_primary_key(type: :uuidv4)

      {:id, :binary_id, opts} = Token.get_field(token, :id)
      assert opts[:default] == {:fragment, "uuid_generate_v4()"}
    end

    test "raises for unsupported uuid type" do
      assert_raise RuntimeError, ~r/Unsupported UUID type/, fn ->
        create_table(:users)
        |> FieldMacros.with_uuid_primary_key(type: :invalid)
      end
    end
  end

  describe "filter_fields helper" do
    test "correctly handles only and except combination" do
      # Only takes precedence
      token =
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [:type], except: [:type])

      # :only should win
      assert Token.has_field?(token, :type)
    end

    test "empty only list raises" do
      assert_raise ArgumentError, fn ->
        create_table(:products)
        |> FieldMacros.with_type_fields(only: [])
      end
    end
  end

  describe "Field Composition" do
    test "multiple field macros can be chained" do
      token =
        create_table(:articles)
        |> FieldMacros.with_uuid_primary_key()
        |> FieldMacros.with_type_fields(only: [:type, :category])
        |> FieldMacros.with_status_fields(only: [:status])
        |> FieldMacros.with_audit_fields()
        |> FieldMacros.with_timestamps()

      # Primary key
      assert Token.has_field?(token, :id)

      # Type fields
      assert Token.has_field?(token, :type)
      assert Token.has_field?(token, :category)
      refute Token.has_field?(token, :variant)

      # Status fields
      assert Token.has_field?(token, :status)
      refute Token.has_field?(token, :substatus)

      # Audit fields (URM by default)
      assert Token.has_field?(token, :created_by_urm_id)
      assert Token.has_field?(token, :updated_by_urm_id)

      # Timestamps
      assert Token.has_field?(token, :inserted_at)
      assert Token.has_field?(token, :updated_at)

      # Should be valid
      assert {:ok, _} = Token.validate(token)
    end
  end
end
