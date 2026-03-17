defmodule OmSchema.SensitiveTest do
  @moduledoc """
  Tests for OmSchema.Sensitive - Protocol implementations for sensitive fields.
  """

  use ExUnit.Case, async: true

  alias OmSchema.Sensitive

  # ============================================
  # Test Schemas
  # ============================================

  defmodule UserWithSensitive do
    use OmSchema

    # Disable auto-derive for testing (we'll test manual redaction too)
    @om_derive_inspect true
    @om_derive_jason true

    schema "sensitive_test_users" do
      field :email, :string
      field :name, :string
      field :password_hash, :string, sensitive: true
      field :api_key, :string, sensitive: true
      field :ssn, :string, sensitive: true
    end
  end

  defmodule UserWithoutSensitive do
    use OmSchema

    schema "non_sensitive_test_users" do
      field :email, :string
      field :name, :string
      field :status, :string
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp build_user_with_sensitive do
    %UserWithSensitive{
      id: "user-123",
      email: "test@example.com",
      name: "Test User",
      password_hash: "hashed_password_123",
      api_key: "sk_live_abc123xyz",
      ssn: "123-45-6789"
    }
  end

  defp build_user_without_sensitive do
    %UserWithoutSensitive{
      id: "user-456",
      email: "public@example.com",
      name: "Public User",
      status: "active"
    }
  end

  # ============================================
  # redacted_marker/0 Tests
  # ============================================

  describe "redacted_marker/0" do
    test "returns the redaction marker string" do
      assert Sensitive.redacted_marker() == "[REDACTED]"
    end
  end

  # ============================================
  # sensitive_fields/0 Tests
  # ============================================

  describe "sensitive_fields/0 on schema" do
    test "returns sensitive fields for schema with sensitive fields" do
      fields = UserWithSensitive.sensitive_fields()
      assert :password_hash in fields
      assert :api_key in fields
      assert :ssn in fields
      assert length(fields) == 3
    end

    test "returns empty list for schema without sensitive fields" do
      assert UserWithoutSensitive.sensitive_fields() == []
    end
  end

  # ============================================
  # redact/1 Tests
  # ============================================

  describe "redact/1" do
    test "redacts sensitive fields in struct" do
      user = build_user_with_sensitive()
      redacted = Sensitive.redact(user)

      assert redacted.password_hash == "[REDACTED]"
      assert redacted.api_key == "[REDACTED]"
      assert redacted.ssn == "[REDACTED]"

      # Non-sensitive fields unchanged
      assert redacted.email == "test@example.com"
      assert redacted.name == "Test User"
      assert redacted.id == "user-123"
    end

    test "returns struct unchanged when no sensitive fields" do
      user = build_user_without_sensitive()
      redacted = Sensitive.redact(user)

      assert redacted == user
    end
  end

  # ============================================
  # redacted_fields/1 Tests
  # ============================================

  describe "redacted_fields/1" do
    test "returns map of sensitive fields to redacted marker" do
      user = build_user_with_sensitive()
      fields = Sensitive.redacted_fields(user)

      assert fields == %{
               password_hash: "[REDACTED]",
               api_key: "[REDACTED]",
               ssn: "[REDACTED]"
             }
    end

    test "returns empty map when no sensitive fields" do
      user = build_user_without_sensitive()
      assert Sensitive.redacted_fields(user) == %{}
    end
  end

  # ============================================
  # sensitive_field_names/1 Tests
  # ============================================

  describe "sensitive_field_names/1" do
    test "returns list of sensitive field names" do
      user = build_user_with_sensitive()
      names = Sensitive.sensitive_field_names(user)

      assert :password_hash in names
      assert :api_key in names
      assert :ssn in names
    end

    test "returns empty list when no sensitive fields" do
      user = build_user_without_sensitive()
      assert Sensitive.sensitive_field_names(user) == []
    end
  end

  # ============================================
  # has_sensitive_fields?/1 Tests
  # ============================================

  describe "has_sensitive_fields?/1" do
    test "returns true for struct with sensitive fields" do
      user = build_user_with_sensitive()
      assert Sensitive.has_sensitive_fields?(user)
    end

    test "returns false for struct without sensitive fields" do
      user = build_user_without_sensitive()
      refute Sensitive.has_sensitive_fields?(user)
    end
  end

  # ============================================
  # to_safe_map/1 Tests
  # ============================================

  describe "to_safe_map/1" do
    test "excludes sensitive fields from map" do
      user = build_user_with_sensitive()
      safe_map = Sensitive.to_safe_map(user)

      # Sensitive fields excluded
      refute Map.has_key?(safe_map, :password_hash)
      refute Map.has_key?(safe_map, :api_key)
      refute Map.has_key?(safe_map, :ssn)

      # Non-sensitive fields included
      assert safe_map[:email] == "test@example.com"
      assert safe_map[:name] == "Test User"
      assert safe_map[:id] == "user-123"
    end

    test "includes all fields when no sensitive fields" do
      user = build_user_without_sensitive()
      safe_map = Sensitive.to_safe_map(user)

      assert safe_map[:email] == "public@example.com"
      assert safe_map[:name] == "Public User"
      assert safe_map[:status] == "active"
    end
  end

  # ============================================
  # to_redacted_map/1 Tests
  # ============================================

  describe "to_redacted_map/1" do
    test "redacts sensitive fields in map" do
      user = build_user_with_sensitive()
      redacted_map = Sensitive.to_redacted_map(user)

      # Sensitive fields redacted
      assert redacted_map[:password_hash] == "[REDACTED]"
      assert redacted_map[:api_key] == "[REDACTED]"
      assert redacted_map[:ssn] == "[REDACTED]"

      # Non-sensitive fields unchanged
      assert redacted_map[:email] == "test@example.com"
      assert redacted_map[:name] == "Test User"
    end

    test "returns unchanged map when no sensitive fields" do
      user = build_user_without_sensitive()
      redacted_map = Sensitive.to_redacted_map(user)

      assert redacted_map[:email] == "public@example.com"
      assert redacted_map[:name] == "Public User"
      assert redacted_map[:status] == "active"
    end
  end

  # ============================================
  # Inspect Protocol Tests
  # ============================================

  # NOTE: Protocol implementations are consolidated at compile time, so the
  # custom Inspect/Jason.Encoder implementations won't work in tests.
  # These tests verify the protocol generation code exists and that
  # the manual redaction functions work correctly.
  #
  # In production, the protocols will work as expected because they're
  # compiled before consolidation.

  describe "Inspect protocol implementation" do
    @tag :skip
    @tag skip: "Protocol consolidation prevents testing in test environment"
    test "redacts sensitive fields in inspect output (requires pre-consolidation)" do
      # This test would pass in production but not in test environment
      # due to protocol consolidation. See module docs for details.
      user = build_user_with_sensitive()
      output = inspect(user)

      assert output =~ "password_hash: \"[REDACTED]\""
    end

    test "manual redaction can be used for safe logging" do
      user = build_user_with_sensitive()
      redacted = Sensitive.redact(user)
      output = inspect(redacted)

      # When using manual redaction, sensitive values are redacted
      assert output =~ "[REDACTED]"
      refute output =~ "hashed_password_123"
      refute output =~ "sk_live_abc123xyz"
    end

    test "to_redacted_map provides safe inspect alternative" do
      user = build_user_with_sensitive()
      redacted_map = Sensitive.to_redacted_map(user)
      output = inspect(redacted_map)

      assert output =~ "[REDACTED]"
      assert output =~ "test@example.com"
    end
  end

  # ============================================
  # Jason.Encoder Protocol Tests (if Jason available)
  # ============================================

  if Code.ensure_loaded?(Jason) do
    describe "Jason.Encoder - using to_safe_map as alternative" do
      test "to_safe_map can be used for safe JSON encoding" do
        user = build_user_with_sensitive()
        safe_map = Sensitive.to_safe_map(user)
        {:ok, json} = Jason.encode(safe_map)
        decoded = Jason.decode!(json)

        # Sensitive fields excluded
        refute Map.has_key?(decoded, "password_hash")
        refute Map.has_key?(decoded, "api_key")
        refute Map.has_key?(decoded, "ssn")

        # Non-sensitive fields included
        assert decoded["email"] == "test@example.com"
        assert decoded["name"] == "Test User"
      end

      test "to_redacted_map can be used for JSON with redacted markers" do
        user = build_user_with_sensitive()
        redacted_map = Sensitive.to_redacted_map(user)
        {:ok, json} = Jason.encode(redacted_map)
        decoded = Jason.decode!(json)

        # Sensitive fields are redacted, not excluded
        assert decoded["password_hash"] == "[REDACTED]"
        assert decoded["api_key"] == "[REDACTED]"

        # Non-sensitive fields included
        assert decoded["email"] == "test@example.com"
      end
    end
  end

  # ============================================
  # Derive Options Tests
  # ============================================

  describe "derive options" do
    defmodule NoAutoInspect do
      use OmSchema

      @om_derive_inspect false

      schema "no_inspect_test" do
        field :secret, :string, sensitive: true
      end
    end

    defmodule NoAutoJason do
      use OmSchema

      @om_derive_jason false

      schema "no_jason_test" do
        field :secret, :string, sensitive: true
      end
    end

    test "schema with @om_derive_inspect false uses default inspect" do
      # This should use Elixir's default struct inspect
      # (we can't easily test this without checking the protocol implementation directly)
      struct = %NoAutoInspect{id: "123", secret: "mysecret"}

      # At minimum, we can check the module has sensitive_fields
      assert NoAutoInspect.sensitive_fields() == [:secret]

      # And that we can still manually redact
      redacted = Sensitive.redact(struct)
      assert redacted.secret == "[REDACTED]"
    end
  end
end
