defmodule Events.IdentifiableTest do
  use ExUnit.Case, async: true

  alias Events.Identifiable
  alias Events.Identifiable.Helpers

  # =============================================================================
  # Test using real schema modules from the application
  # Since protocols are consolidated, we use actual app schemas
  # =============================================================================

  # =============================================================================
  # Protocol Tests - Any Fallback (plain maps and structs)
  # =============================================================================

  describe "Any fallback implementation with maps" do
    test "entity_type/1 returns :unknown for plain maps" do
      map = %{id: "map_123", name: "test"}
      assert Identifiable.entity_type(map) == :unknown
    end

    test "id/1 extracts :id key from maps" do
      map = %{id: "map_123", name: "test"}
      assert Identifiable.id(map) == "map_123"
    end

    test "id/1 returns nil for maps without :id key" do
      map = %{name: "test", value: 42}
      assert Identifiable.id(map) == nil
    end

    test "identity/1 returns {:unknown, id} for plain maps" do
      map = %{id: "map_123"}
      assert Identifiable.identity(map) == {:unknown, "map_123"}
    end

    test "id/1 returns nil for non-map values" do
      assert Identifiable.id("string") == nil
      assert Identifiable.id(123) == nil
      assert Identifiable.id([1, 2, 3]) == nil
    end
  end

  # =============================================================================
  # Protocol Tests - Events.Error Implementation
  # =============================================================================

  describe "Events.Error implementation" do
    test "entity_type/1 returns the error type" do
      error = Events.Error.new(:validation, :invalid_email)
      assert Identifiable.entity_type(error) == :validation
    end

    test "entity_type/1 varies by error type" do
      validation_error = Events.Error.new(:validation, :invalid)
      not_found_error = Events.Error.new(:not_found, :missing)

      assert Identifiable.entity_type(validation_error) == :validation
      assert Identifiable.entity_type(not_found_error) == :not_found
    end

    test "id/1 returns the error id" do
      error = Events.Error.new(:validation, :invalid_email)
      assert is_binary(Identifiable.id(error))
      assert String.starts_with?(Identifiable.id(error), "err_")
    end

    test "identity/1 returns {error_type, error_id}" do
      error = Events.Error.new(:validation, :invalid_email)
      {type, id} = Identifiable.identity(error)

      assert type == :validation
      assert is_binary(id)
      assert String.starts_with?(id, "err_")
    end

    test "different errors have different identities" do
      error1 = Events.Error.new(:validation, :invalid_email)
      error2 = Events.Error.new(:validation, :invalid_email)

      # Same type but different IDs
      assert Identifiable.entity_type(error1) == Identifiable.entity_type(error2)
      refute Identifiable.id(error1) == Identifiable.id(error2)
      refute Identifiable.identity(error1) == Identifiable.identity(error2)
    end
  end

  # =============================================================================
  # Protocol Tests - Ecto.Changeset Implementation
  # =============================================================================

  describe "Ecto.Changeset implementation with real schemas" do
    test "entity_type/1 derives type from underlying schema" do
      user = %Events.Accounts.User{id: "usr_123"}
      changeset = Ecto.Changeset.change(user, %{})

      assert Identifiable.entity_type(changeset) == :user
    end

    test "id/1 returns id from changeset data" do
      user = %Events.Accounts.User{id: "usr_123"}
      changeset = Ecto.Changeset.change(user, %{})

      assert Identifiable.id(changeset) == "usr_123"
    end

    test "id/1 returns nil for new records" do
      user = %Events.Accounts.User{}
      changeset = Ecto.Changeset.change(user, %{})

      assert Identifiable.id(changeset) == nil
    end

    test "identity/1 works with changesets" do
      user = %Events.Accounts.User{id: "usr_123"}
      changeset = Ecto.Changeset.change(user, %{})

      assert Identifiable.identity(changeset) == {:user, "usr_123"}
    end
  end

  # =============================================================================
  # Helper Tests - Core Helpers (using plain maps to avoid consolidation issues)
  # =============================================================================

  describe "Helpers.cache_key/2 with maps" do
    test "generates type:id format" do
      map = %{id: "map_123"}
      assert Helpers.cache_key(map) == "unknown:map_123"
    end

    test "supports prefix option" do
      map = %{id: "map_123"}
      assert Helpers.cache_key(map, prefix: "v1") == "v1:unknown:map_123"
    end

    test "supports separator option" do
      map = %{id: "map_123"}
      assert Helpers.cache_key(map, separator: "/") == "unknown/map_123"
    end

    test "combines prefix and separator" do
      map = %{id: "map_123"}
      assert Helpers.cache_key(map, prefix: "cache", separator: "_") == "cache_unknown_map_123"
    end

    test "handles nil id" do
      map = %{name: "test"}
      assert Helpers.cache_key(map) == "unknown"
    end
  end

  describe "Helpers.cache_key/2 with errors" do
    test "generates error type:id format" do
      error = Events.Error.new(:validation, :invalid)
      key = Helpers.cache_key(error)
      assert String.starts_with?(key, "validation:err_")
    end
  end

  describe "Helpers.cache_key_tuple/1" do
    test "returns identity tuple directly" do
      map = %{id: "map_123"}
      assert Helpers.cache_key_tuple(map) == {:unknown, "map_123"}
    end
  end

  describe "Helpers.same_entity?/2" do
    test "returns true for same identity" do
      map1 = %{id: "map_123", name: "First"}
      map2 = %{id: "map_123", name: "Updated"}

      assert Helpers.same_entity?(map1, map2)
    end

    test "returns false for different ids" do
      map1 = %{id: "map_123"}
      map2 = %{id: "map_456"}

      refute Helpers.same_entity?(map1, map2)
    end

    test "returns false for different error types (different types)" do
      error1 = Events.Error.new(:validation, :invalid)
      error2 = Events.Error.new(:not_found, :missing)

      refute Helpers.same_entity?(error1, error2)
    end
  end

  describe "Helpers.persisted?/1" do
    test "returns true when id is present" do
      map = %{id: "map_123"}
      assert Helpers.persisted?(map)
    end

    test "returns false when id is nil" do
      map = %{name: "test"}
      refute Helpers.persisted?(map)
    end
  end

  # =============================================================================
  # Helper Tests - Collection Utilities
  # =============================================================================

  describe "Helpers.unique_by_identity/1" do
    test "removes duplicates based on identity" do
      map1 = %{id: "m_1", name: "First"}
      map1_updated = %{id: "m_1", name: "Updated"}
      map2 = %{id: "m_2", name: "Second"}

      result = Helpers.unique_by_identity([map1, map2, map1_updated])

      assert length(result) == 2
      assert map1 in result
      assert map2 in result
      refute map1_updated in result
    end

    test "handles empty list" do
      assert Helpers.unique_by_identity([]) == []
    end
  end

  describe "Helpers.group_by_type/1 with errors" do
    test "groups errors by their type" do
      val_error1 = Events.Error.new(:validation, :invalid)
      val_error2 = Events.Error.new(:validation, :required)
      not_found = Events.Error.new(:not_found, :missing)

      result = Helpers.group_by_type([val_error1, not_found, val_error2])

      assert map_size(result) == 2
      assert length(result[:validation]) == 2
      assert length(result[:not_found]) == 1
    end
  end

  describe "Helpers.partition_persisted/1" do
    test "separates persisted from new entities" do
      persisted = %{id: "map_123"}
      new = %{name: "no id"}

      {persisted_list, new_list} = Helpers.partition_persisted([persisted, new])

      assert persisted_list == [persisted]
      assert new_list == [new]
    end
  end

  describe "Helpers.extract_ids/1" do
    test "extracts non-nil ids" do
      entities = [
        %{id: "m_1"},
        %{name: "no id"},
        %{id: "m_2"}
      ]

      assert Helpers.extract_ids(entities) == ["m_1", "m_2"]
    end
  end

  describe "Helpers.identity_map/1" do
    test "creates lookup map from identity to entity" do
      error1 = Events.Error.new(:validation, :invalid)
      error2 = Events.Error.new(:not_found, :missing)

      map = Helpers.identity_map([error1, error2])

      assert map[Identifiable.identity(error1)] == error1
      assert map[Identifiable.identity(error2)] == error2
    end
  end

  describe "Helpers.find_by_identity/2" do
    test "finds entity by identity tuple" do
      maps = [
        %{id: "m_1", name: "Alice"},
        %{id: "m_2", name: "Bob"}
      ]

      result = Helpers.find_by_identity(maps, {:unknown, "m_2"})

      assert result.name == "Bob"
    end

    test "returns nil when not found" do
      maps = [%{id: "m_1"}]

      assert Helpers.find_by_identity(maps, {:unknown, "nonexistent"}) == nil
    end
  end

  # =============================================================================
  # Helper Tests - GraphQL Global IDs
  # =============================================================================

  describe "Helpers.to_global_id/1" do
    test "encodes identity as base64" do
      error = Events.Error.new(:validation, :invalid)
      global_id = Helpers.to_global_id(error)

      assert is_binary(global_id)
      # Verify it decodes back to original
      {:ok, decoded} = Base.decode64(global_id)
      assert String.starts_with?(decoded, "validation:err_")
    end
  end

  describe "Helpers.from_global_id/1" do
    test "decodes valid global id" do
      error = Events.Error.new(:validation, :invalid)
      global_id = Helpers.to_global_id(error)
      error_id = Identifiable.id(error)

      assert {:ok, {:validation, ^error_id}} = Helpers.from_global_id(global_id)
    end

    test "returns error for invalid base64" do
      assert {:error, :invalid_global_id} = Helpers.from_global_id("not-valid-base64!")
    end

    test "returns error for malformed content" do
      # Valid base64 but wrong format
      invalid = Base.encode64("no_colon_here")
      assert {:error, :invalid_global_id} = Helpers.from_global_id(invalid)
    end

    test "returns error for unknown type atom" do
      # Valid format but atom doesn't exist
      invalid = Base.encode64("nonexistent_type_xyz:123")
      assert {:error, :invalid_global_id} = Helpers.from_global_id(invalid)
    end
  end

  describe "Helpers.from_global_id!/1" do
    test "returns identity on success" do
      error = Events.Error.new(:validation, :invalid)
      global_id = Helpers.to_global_id(error)
      error_id = Identifiable.id(error)

      assert {:validation, ^error_id} = Helpers.from_global_id!(global_id)
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Helpers.from_global_id!("invalid")
      end
    end
  end

  # =============================================================================
  # Helper Tests - Idempotency Keys
  # =============================================================================

  describe "Helpers.idempotency_key/3" do
    test "generates key from identity and operation" do
      error = Events.Error.new(:validation, :invalid)
      error_id = Identifiable.id(error)
      key = Helpers.idempotency_key(error, :send_alert)

      assert key == "validation:#{error_id}:send_alert"
    end

    test "supports namespace option" do
      error = Events.Error.new(:validation, :invalid)
      error_id = Identifiable.id(error)
      key = Helpers.idempotency_key(error, :send_alert, namespace: "v2")

      assert key == "v2:validation:#{error_id}:send_alert"
    end
  end

  # =============================================================================
  # Helper Tests - Formatting
  # =============================================================================

  describe "Helpers.format_identity/1" do
    test "formats error as type:id" do
      error = Events.Error.new(:validation, :invalid)
      formatted = Helpers.format_identity(error)

      assert String.starts_with?(formatted, "validation:err_")
    end

    test "shows <new> for nil id" do
      map = %{name: "no id"}
      assert Helpers.format_identity(map) == "unknown:<new>"
    end
  end

  describe "Helpers.format_identities/1" do
    test "formats multiple identities" do
      error1 = Events.Error.new(:validation, :invalid)
      error2 = Events.Error.new(:not_found, :missing)

      result = Helpers.format_identities([error1, error2])

      # Should contain both formatted identities separated by comma
      assert result =~ "validation:err_"
      assert result =~ "not_found:err_"
      assert result =~ ", "
    end
  end

  describe "Helpers.identity_info/1" do
    test "returns comprehensive identity info" do
      error = Events.Error.new(:validation, :invalid)
      info = Helpers.identity_info(error)

      assert info.type == :validation
      assert is_binary(info.id)
      assert String.starts_with?(info.id, "err_")
      assert info.persisted == true
      assert is_binary(info.cache_key)
      assert is_binary(info.global_id)
    end

    test "handles entities without id" do
      map = %{name: "no id"}
      info = Helpers.identity_info(map)

      assert info.id == nil
      assert info.persisted == false
      assert info.global_id == nil
    end
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  describe "edge cases" do
    test "handles integer ids in maps" do
      map = %{id: 12345}
      assert Identifiable.id(map) == 12345
      assert Identifiable.identity(map) == {:unknown, 12345}
    end

    test "handles empty string ids" do
      map = %{id: ""}
      assert Identifiable.id(map) == ""
      assert Identifiable.identity(map) == {:unknown, ""}
    end

    test "cache_key handles special characters in id" do
      map = %{id: "map:123/456"}
      # The colon in the id creates an ambiguous key, but that's the user's concern
      assert Helpers.cache_key(map) == "unknown:map:123/456"
    end
  end

  # =============================================================================
  # Integration Tests with Real Schemas (if available)
  # =============================================================================

  describe "integration with Events.Accounts.User" do
    test "identity extraction works with User schema" do
      user = %Events.Accounts.User{id: "user_abc123", email: "test@example.com"}

      assert Identifiable.entity_type(user) == :user
      assert Identifiable.id(user) == "user_abc123"
      assert Identifiable.identity(user) == {:user, "user_abc123"}
    end

    test "same_entity? works across different User instances" do
      user1 = %Events.Accounts.User{id: "user_123", email: "old@example.com"}
      user2 = %Events.Accounts.User{id: "user_123", email: "new@example.com"}

      assert Helpers.same_entity?(user1, user2)
    end

    test "cache_key generates correct format for User" do
      user = %Events.Accounts.User{id: "user_abc123"}

      assert Helpers.cache_key(user) == "user:user_abc123"
    end
  end
end
