defmodule FnTypes.Protocols.IdentifiableTest do
  use ExUnit.Case, async: true

  alias FnTypes.Protocols.Identifiable

  # ============================================
  # Fallback Implementation Tests (Any)
  # ============================================

  describe "entity_type/1 for unknown types" do
    test "returns :unknown for arbitrary values" do
      assert Identifiable.entity_type(:some_atom) == :unknown
      assert Identifiable.entity_type("string") == :unknown
      assert Identifiable.entity_type(123) == :unknown
    end
  end

  describe "id/1 for unknown types" do
    test "returns nil for atoms" do
      assert Identifiable.id(:some_atom) == nil
    end

    test "returns nil for strings" do
      assert Identifiable.id("string") == nil
    end

    test "extracts :id from maps" do
      assert Identifiable.id(%{id: 123}) == 123
      assert Identifiable.id(%{id: "abc"}) == "abc"
    end

    test "returns nil for maps without :id" do
      assert Identifiable.id(%{other_field: "value"}) == nil
    end
  end

  describe "identity/1 for unknown types" do
    test "returns {:unknown, nil} for values without id" do
      assert Identifiable.identity(:some_atom) == {:unknown, nil}
      assert Identifiable.identity("string") == {:unknown, nil}
    end

    test "returns {:unknown, id} for maps with id" do
      assert Identifiable.identity(%{id: 123}) == {:unknown, 123}
    end
  end

  # ============================================
  # Error Struct Tests
  # ============================================

  describe "Error struct implementation" do
    test "extracts identity from Error" do
      error = FnTypes.Error.new(:validation, :test_error)

      {type, id} = Identifiable.identity(error)

      # Error identity uses the error type, not :error
      assert type == :validation
      assert is_binary(id)
      assert String.starts_with?(id, "err_")
    end

    test "returns error type as entity_type for Error" do
      error = FnTypes.Error.new(:validation, :test)

      # Uses the error's type (:validation, :not_found, etc.)
      assert Identifiable.entity_type(error) == :validation
    end

    test "returns different entity_types for different error types" do
      validation_error = FnTypes.Error.new(:validation, :test)
      not_found_error = FnTypes.Error.new(:not_found, :test)

      assert Identifiable.entity_type(validation_error) == :validation
      assert Identifiable.entity_type(not_found_error) == :not_found
    end

    test "returns error id for Error" do
      error = FnTypes.Error.new(:validation, :test)

      id = Identifiable.id(error)
      assert is_binary(id)
      assert String.starts_with?(id, "err_")
    end
  end
end
