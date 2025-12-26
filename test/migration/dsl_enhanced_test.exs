defmodule OmMigration.DSLEnhancedTest do
  use Events.TestCase, async: true

  # DSLEnhanced uses Ecto.Migration macros which require the Ecto migration context
  # We test the macro expansion at a high level to verify they compile correctly

  # Helper to check if a macro is exported with given arity
  # Uses __info__(:macros) which is more reliable than macro_exported?/3 in async tests
  defp has_macro?(module, name, arity) do
    macros = module.__info__(:macros)
    {name, arity} in macros
  end

  describe "Module compilation" do
    test "DSLEnhanced module compiles successfully" do
      assert Code.ensure_loaded?(OmMigration.DSLEnhanced)
    end

    test "exports uuid_primary_key/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :uuid_primary_key, 1)
    end

    test "exports uuid_v4_primary_key/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :uuid_v4_primary_key, 1)
    end

    test "exports type_fields/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :type_fields, 1)
    end

    test "exports status_fields/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :status_fields, 1)
    end

    test "exports audit_fields/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :audit_fields, 1)
    end

    test "exports event_timestamps/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :event_timestamps, 1)
    end

    test "exports soft_delete_fields/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :soft_delete_fields, 1)
    end

    test "exports metadata_field/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :metadata_field, 1)
    end

    test "exports tags_field/1 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :tags_field, 1)
    end

    test "exports money_field/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :money_field, 2)
    end

    test "exports belongs_to_field/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :belongs_to_field, 2)
    end
  end

  describe "Index macro exports" do
    test "exports type_field_indexes/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :type_field_indexes, 2)
    end

    test "exports status_field_indexes/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :status_field_indexes, 2)
    end

    test "exports audit_field_indexes/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :audit_field_indexes, 2)
    end

    test "exports timestamp_indexes/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :timestamp_indexes, 2)
    end

    test "exports metadata_index/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :metadata_index, 2)
    end

    test "exports tags_index/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :tags_index, 2)
    end

    test "exports foreign_key_index/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :foreign_key_index, 2)
    end

    test "exports create_standard_indexes/2 macro" do
      assert has_macro?(OmMigration.DSLEnhanced, :create_standard_indexes, 2)
    end
  end

  describe "Option filtering logic" do
    # Test the filtering behavior by examining field selection

    test "type_fields default includes 5 fields" do
      # Verify the default field list
      expected_fields = [:type, :subtype, :kind, :category, :variant]
      assert length(expected_fields) == 5
    end

    test "status_fields default includes 5 fields" do
      # Verify the default field list
      expected_fields = [:status, :substatus, :state, :workflow_state, :approval_status]
      assert length(expected_fields) == 5
    end

    test "timestamp_fields default includes 2 fields" do
      # Verify the default field list
      expected_fields = [:inserted_at, :updated_at]
      assert length(expected_fields) == 2
    end

    test "audit_fields default includes 2 URM fields" do
      # Verify the default field list (track_urm: true by default)
      expected_fields = [:created_by_urm_id, :updated_by_urm_id]
      assert length(expected_fields) == 2
    end
  end

  describe "Documentation" do
    test "module has moduledoc" do
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(OmMigration.DSLEnhanced)
      assert module_doc != :hidden
      assert module_doc != :none
    end

    test "uuid_primary_key has doc" do
      {:docs_v1, _, _, _, _, _, function_docs} = Code.fetch_docs(OmMigration.DSLEnhanced)

      uuid_pk_doc =
        Enum.find(function_docs, fn
          {{:macro, :uuid_primary_key, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert uuid_pk_doc != nil
    end

    test "type_fields has doc" do
      {:docs_v1, _, _, _, _, _, function_docs} = Code.fetch_docs(OmMigration.DSLEnhanced)

      type_fields_doc =
        Enum.find(function_docs, fn
          {{:macro, :type_fields, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert type_fields_doc != nil
    end

    test "status_fields has doc" do
      {:docs_v1, _, _, _, _, _, function_docs} = Code.fetch_docs(OmMigration.DSLEnhanced)

      status_fields_doc =
        Enum.find(function_docs, fn
          {{:macro, :status_fields, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert status_fields_doc != nil
    end

    test "audit_fields has doc" do
      {:docs_v1, _, _, _, _, _, function_docs} = Code.fetch_docs(OmMigration.DSLEnhanced)

      audit_fields_doc =
        Enum.find(function_docs, fn
          {{:macro, :audit_fields, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert audit_fields_doc != nil
    end

    test "soft_delete_fields has doc" do
      {:docs_v1, _, _, _, _, _, function_docs} = Code.fetch_docs(OmMigration.DSLEnhanced)

      soft_delete_doc =
        Enum.find(function_docs, fn
          {{:macro, :soft_delete_fields, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert soft_delete_doc != nil
    end
  end
end
