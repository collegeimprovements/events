defmodule FnTypes.Protocols.NormalizableTest do
  use ExUnit.Case, async: true

  alias FnTypes.Protocols.Normalizable
  alias FnTypes.Error

  # ============================================
  # Atom Normalization Tests
  # ============================================

  describe "normalize/2 for atoms" do
    test "normalizes :not_found to error struct" do
      error = Normalizable.normalize(:not_found, [])

      assert %Error{} = error
      assert error.type == :not_found
      assert error.code == :not_found
    end

    test "normalizes :unauthorized to error struct" do
      error = Normalizable.normalize(:unauthorized, [])

      assert %Error{} = error
      assert error.type == :unauthorized
      assert error.code == :unauthorized
    end

    test "normalizes :timeout as recoverable" do
      error = Normalizable.normalize(:timeout, [])

      assert %Error{} = error
      assert error.type == :timeout
      assert error.recoverable == true
    end

    test "normalizes unknown atoms" do
      error = Normalizable.normalize(:some_custom_error, [])

      assert %Error{} = error
      assert error.type == :internal
      assert error.code == :some_custom_error
    end
  end

  # ============================================
  # Map Normalization Tests
  # ============================================

  describe "normalize/2 for maps" do
    test "extracts message and code from map" do
      error = Normalizable.normalize(%{message: "Something went wrong", code: :custom_code})

      assert %Error{} = error
      assert error.message == "Something went wrong"
      assert error.code == :custom_code
    end

    test "handles string keys" do
      error = Normalizable.normalize(%{"message" => "String key message", "code" => "string_code"})

      assert %Error{} = error
      assert error.message == "String key message"
    end

    test "preserves additional details" do
      error = Normalizable.normalize(%{
        message: "Error",
        code: :test,
        extra_field: "value"
      })

      assert %Error{} = error
      assert error.details.extra_field == "value"
    end
  end

  # ============================================
  # Exception Normalization Tests
  # ============================================

  describe "normalize/2 for exceptions" do
    test "normalizes RuntimeError" do
      exception = %RuntimeError{message: "Something broke"}
      error = Normalizable.normalize(exception, [])

      assert %Error{} = error
      assert error.type == :internal
      assert error.code == :runtime_error
      assert error.message == "Something broke"
    end

    test "normalizes ArgumentError" do
      exception = %ArgumentError{message: "Invalid argument"}
      error = Normalizable.normalize(exception, [])

      assert %Error{} = error
      assert error.type == :validation
      assert error.code == :argument_error
    end

    test "normalizes KeyError" do
      exception = %KeyError{key: :missing_key, term: %{}}
      error = Normalizable.normalize(exception, [])

      assert %Error{} = error
      assert error.type == :internal
      assert error.code == :key_error
    end
  end

  # ============================================
  # Error Tuple Normalization Tests
  # ============================================

  describe "normalize/2 for error tuples" do
    test "unwraps {:error, reason} tuples" do
      error = Normalizable.normalize({:error, :not_found})

      assert %Error{} = error
      assert error.type == :not_found
    end
  end

  # ============================================
  # String Normalization Tests
  # ============================================

  describe "normalize/2 for strings" do
    test "uses string as message" do
      error = Normalizable.normalize("Error message string", [])

      assert %Error{} = error
      assert error.message == "Error message string"
      assert error.code == :string_error
    end
  end

  # ============================================
  # Options Tests
  # ============================================

  describe "normalize/2 with options" do
    test "accepts context option" do
      error = Normalizable.normalize(:not_found, context: %{user_id: 123})

      assert error.context.user_id == 123
    end

    test "accepts step option" do
      error = Normalizable.normalize(:not_found, step: :validate)

      assert error.step == :validate
    end

    test "accepts message override" do
      error = Normalizable.normalize(:not_found, message: "Custom message")

      assert error.message == "Custom message"
    end
  end

  # ============================================
  # Error Struct Passthrough Tests
  # ============================================

  describe "normalize/2 for Error structs" do
    test "normalizes Error struct to itself" do
      original = Error.new(:validation, :test_code, message: "Test")
      normalized = Normalizable.normalize(original, [])

      # Should normalize to an Error (may add fields)
      assert %Error{} = normalized
      assert normalized.type == :validation
      assert normalized.code == :test_code
    end
  end
end
