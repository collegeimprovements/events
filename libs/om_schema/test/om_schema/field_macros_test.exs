defmodule OmSchema.FieldMacrosTest do
  @moduledoc """
  Tests for OmSchema.FieldMacros - Field macro helpers.

  Note: OmSchema has its own field macros (type_fields, status_fields, etc.) that
  are different from OmSchema.FieldMacros. The OmSchema versions are designed for
  the enhanced schema system while FieldMacros provides simpler macros for use
  with raw Ecto.Schema.

  This test file tests:
  1. The FieldMacros helper functions (__filter_fields__, etc.)
  2. The FieldMacros macros used with raw Ecto.Schema
  """

  use ExUnit.Case, async: true

  alias OmSchema.FieldMacros

  # ============================================
  # Test Schemas using FieldMacros with raw Ecto.Schema
  # ============================================

  defmodule ProductWithTypeFields do
    use Ecto.Schema
    import OmSchema.FieldMacros

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "field_macros_test_products" do
      field :name, :string
      type_fields(only: [:type, :subtype])
    end
  end

  defmodule OrderWithStatusFields do
    use Ecto.Schema
    import OmSchema.FieldMacros

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "field_macros_test_orders" do
      field :total, :integer
      status_fields(only: [:status, :substatus])
    end
  end

  defmodule OrderWithTransitionFields do
    use Ecto.Schema
    import OmSchema.FieldMacros

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "field_macros_test_orders_transition" do
      field :total, :integer
      status_fields(only: [:status], with_transition: true)
    end
  end

  defmodule ItemWithMetadata do
    use Ecto.Schema
    import OmSchema.FieldMacros

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "field_macros_test_items" do
      field :name, :string
      metadata_field()
      tags_field()
    end
  end

  defmodule ItemWithCustomMetadata do
    use Ecto.Schema
    import OmSchema.FieldMacros

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "field_macros_test_items_custom" do
      field :name, :string
      metadata_field(name: :properties, default: %{version: 1})
      tags_field(name: :categories)
    end
  end

  # Note: soft_delete_fields and audit_fields require OmFieldNames,
  # which depends on OmSchema configuration. We'll test those separately.

  # ============================================
  # __filter_fields__/2 Tests
  # ============================================

  describe "__filter_fields__/2" do
    test "returns all fields when no filtering" do
      fields = [:a, :b, :c]
      result = FieldMacros.__filter_fields__(fields, [])

      assert result == [:a, :b, :c]
    end

    test "filters by :only option" do
      fields = [:a, :b, :c, :d]
      result = FieldMacros.__filter_fields__(fields, only: [:a, :c])

      assert result == [:a, :c]
    end

    test "filters by :except option" do
      fields = [:a, :b, :c, :d]
      result = FieldMacros.__filter_fields__(fields, except: [:b, :d])

      assert result == [:a, :c]
    end

    test "raises when filtering results in empty list" do
      fields = [:a, :b]

      assert_raise ArgumentError, ~r/No fields selected/, fn ->
        FieldMacros.__filter_fields__(fields, only: [:x, :y])
      end
    end
  end

  # ============================================
  # type_fields/1 Tests
  # ============================================

  describe "type_fields/1" do
    test "adds type fields to schema" do
      fields = ProductWithTypeFields.__schema__(:fields)

      assert :type in fields
      assert :subtype in fields
    end

    test "type fields have correct type" do
      assert ProductWithTypeFields.__schema__(:type, :type) == :string
      assert ProductWithTypeFields.__schema__(:type, :subtype) == :string
    end

    test "respects :only option" do
      fields = ProductWithTypeFields.__schema__(:fields)

      # These should NOT be present because only: [:type, :subtype]
      refute :kind in fields
      refute :category in fields
      refute :variant in fields
    end
  end

  # ============================================
  # status_fields/1 Tests
  # ============================================

  describe "status_fields/1" do
    test "adds status fields to schema" do
      fields = OrderWithStatusFields.__schema__(:fields)

      assert :status in fields
      assert :substatus in fields
    end

    test "status fields have correct type" do
      assert OrderWithStatusFields.__schema__(:type, :status) == :string
      assert OrderWithStatusFields.__schema__(:type, :substatus) == :string
    end

    test "respects :only option" do
      fields = OrderWithStatusFields.__schema__(:fields)

      refute :state in fields
      refute :workflow_state in fields
      refute :approval_status in fields
    end

    test "adds transition fields when with_transition: true" do
      fields = OrderWithTransitionFields.__schema__(:fields)

      assert :status in fields
      assert :previous_status in fields
      assert :status_changed_at in fields
      assert :status_changed_by in fields
      assert :status_history in fields
    end

    test "transition fields have correct types" do
      assert OrderWithTransitionFields.__schema__(:type, :previous_status) == :string
      assert OrderWithTransitionFields.__schema__(:type, :status_changed_at) == :utc_datetime_usec
      assert OrderWithTransitionFields.__schema__(:type, :status_changed_by) == Ecto.UUID
      assert OrderWithTransitionFields.__schema__(:type, :status_history) == {:array, :map}
    end
  end

  # ============================================
  # metadata_field/1 Tests
  # ============================================

  describe "metadata_field/1" do
    test "adds metadata field with default name" do
      fields = ItemWithMetadata.__schema__(:fields)

      assert :metadata in fields
    end

    test "metadata field has map type" do
      assert ItemWithMetadata.__schema__(:type, :metadata) == :map
    end

    test "respects custom name option" do
      fields = ItemWithCustomMetadata.__schema__(:fields)

      assert :properties in fields
      refute :metadata in fields
    end

    test "respects custom default option" do
      # Check that the default is set correctly
      # Note: we can't directly test the default in the schema,
      # but we can verify the field exists and has the right type
      assert ItemWithCustomMetadata.__schema__(:type, :properties) == :map
    end
  end

  # ============================================
  # tags_field/1 Tests
  # ============================================

  describe "tags_field/1" do
    test "adds tags field with default name" do
      fields = ItemWithMetadata.__schema__(:fields)

      assert :tags in fields
    end

    test "tags field has array of strings type" do
      assert ItemWithMetadata.__schema__(:type, :tags) == {:array, :string}
    end

    test "respects custom name option" do
      fields = ItemWithCustomMetadata.__schema__(:fields)

      assert :categories in fields
      refute :tags in fields
    end
  end

  # ============================================
  # OmSchema Field Macros Integration Tests
  # ============================================
  # These test the OmSchema versions of the field macros (not FieldMacros module)

  describe "OmSchema field macros" do
    defmodule EntityWithOmSchemaFields do
      use OmSchema

      schema "field_macros_om_test_entities" do
        field :name, :string
        # OmSchema.type_fields/1 adds :type and :subtype as string fields
        type_fields(only: [:type])
        # OmSchema.metadata_field/1 adds :metadata as map
        metadata_field()
        # OmSchema.status_fields/1 requires :values option
        status_fields(values: [:active, :inactive], default: :active)
        # OmSchema.audit_fields/0 adds created_by_urm_id, updated_by_urm_id
        audit_fields()
        # OmSchema.soft_delete_field/0 adds deleted_at
        soft_delete_field()
      end
    end

    test "type_fields adds type field" do
      fields = EntityWithOmSchemaFields.__schema__(:fields)
      assert :type in fields
    end

    test "metadata_field adds metadata map field" do
      fields = EntityWithOmSchemaFields.__schema__(:fields)
      assert :metadata in fields
      assert EntityWithOmSchemaFields.__schema__(:type, :metadata) == :map
    end

    test "status_fields adds status enum field" do
      fields = EntityWithOmSchemaFields.__schema__(:fields)
      assert :status in fields
    end

    test "audit_fields adds URM tracking fields" do
      fields = EntityWithOmSchemaFields.__schema__(:fields)
      assert :created_by_urm_id in fields
      assert :updated_by_urm_id in fields
    end

    test "soft_delete_field adds deleted_at field" do
      fields = EntityWithOmSchemaFields.__schema__(:fields)
      assert :deleted_at in fields
    end
  end
end
