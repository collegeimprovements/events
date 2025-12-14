defmodule FnTypes.ErrorTest do
  use ExUnit.Case, async: true

  alias FnTypes.Error

  # ============================================
  # Error Creation Tests
  # ============================================

  describe "new/3" do
    test "creates an error with required fields" do
      error = Error.new(:validation, :invalid_email)

      assert error.type == :validation
      assert error.code == :invalid_email
      assert is_binary(error.id)
      assert %DateTime{} = error.occurred_at
    end

    test "creates an error with custom message" do
      error = Error.new(:validation, :invalid_email, message: "Custom message")

      assert error.message == "Custom message"
    end

    test "creates an error with details" do
      error = Error.new(:validation, :invalid_email, details: %{field: :email, value: "bad"})

      assert error.details == %{field: :email, value: "bad"}
    end

    test "creates an error with context" do
      error = Error.new(:not_found, :user, context: %{user_id: 123})

      assert error.context == %{user_id: 123}
    end

    test "sets recoverable flag" do
      error = Error.new(:timeout, :db_timeout, recoverable: true)

      assert error.recoverable == true
    end

    test "sets step" do
      error = Error.new(:validation, :invalid_email, step: :validate_input)

      assert error.step == :validate_input
    end

    test "sets cause" do
      cause = Error.new(:network, :connection_refused)
      error = Error.new(:external, :api_failed, cause: cause)

      assert error.cause == cause
    end
  end

  # ============================================
  # Error Type Tests
  # ============================================

  describe "error types" do
    test "supports all standard error types" do
      types = [
        :validation,
        :not_found,
        :unauthorized,
        :forbidden,
        :conflict,
        :rate_limited,
        :internal,
        :external,
        :timeout,
        :network,
        :business
      ]

      for type <- types do
        error = Error.new(type, :test_code)
        assert error.type == type
      end
    end
  end

  # ============================================
  # Context Management Tests
  # ============================================

  describe "with_context/2" do
    test "adds context to error" do
      error =
        Error.new(:validation, :invalid_email)
        |> Error.with_context(%{user_id: 123, request_id: "req_abc"})

      assert error.context.user_id == 123
      assert error.context.request_id == "req_abc"
    end

    test "accepts keyword list context" do
      error =
        Error.new(:validation, :invalid_email)
        |> Error.with_context(user_id: 456)

      assert error.context.user_id == 456
    end

    test "merges with existing context" do
      error =
        Error.new(:validation, :invalid_email, context: %{user_id: 123})
        |> Error.with_context(%{request_id: "req_abc"})

      assert error.context.user_id == 123
      assert error.context.request_id == "req_abc"
    end
  end

  describe "with_step/2" do
    test "sets step on error" do
      error =
        Error.new(:validation, :invalid_email)
        |> Error.with_step(:validate_user)

      assert error.step == :validate_user
    end
  end

  describe "with_details/2" do
    test "merges details into error" do
      error =
        Error.new(:validation, :invalid_email, details: %{field: :email})
        |> Error.with_details(%{suggestion: "Check format"})

      assert error.details.field == :email
      assert error.details.suggestion == "Check format"
    end
  end

  # ============================================
  # Error Comparison Tests
  # ============================================

  describe "type?/2" do
    test "checks error type" do
      error = Error.new(:validation, :test)

      assert Error.type?(error, :validation)
      refute Error.type?(error, :not_found)
    end
  end

  # ============================================
  # Error Classification Tests
  # ============================================

  describe "recoverable?/1" do
    test "returns recoverable flag" do
      recoverable = Error.new(:timeout, :db_timeout, recoverable: true)
      not_recoverable = Error.new(:validation, :invalid_email, recoverable: false)

      assert Error.recoverable?(recoverable)
      refute Error.recoverable?(not_recoverable)
    end
  end

  # ============================================
  # Error Conversion Tests
  # ============================================

  describe "to_map/1" do
    test "converts error to map" do
      error = Error.new(:validation, :invalid_email, message: "Bad email")
      map = Error.to_map(error)

      assert map.type == :validation
      assert map.code == :invalid_email
      assert map.message == "Bad email"
    end
  end

  # ============================================
  # Error Formatting Tests
  # ============================================

  describe "format/1" do
    test "returns human-readable string" do
      error = Error.new(:validation, :invalid_email, message: "Email is invalid")
      formatted = Error.format(error)

      assert is_binary(formatted)
      assert formatted =~ "validation"
      # Format shows message, not code
      assert formatted =~ "Email is invalid"
    end
  end

  # ============================================
  # Error Chain Tests
  # ============================================

  describe "root_cause/1" do
    test "finds root cause in error chain" do
      root = Error.new(:network, :connection_refused)
      middle = Error.new(:timeout, :db_timeout, cause: root)
      top = Error.new(:internal, :failed, cause: middle)

      assert Error.root_cause(top) == root
    end

    test "returns error itself if no cause" do
      error = Error.new(:validation, :invalid_email)

      assert Error.root_cause(error) == error
    end
  end

  # ============================================
  # Error Normalization Tests
  # ============================================

  describe "normalize/2" do
    test "passes through existing Error struct" do
      error = Error.new(:validation, :invalid_email)
      result = Error.normalize(error)

      assert result == error
    end

    test "normalizes atom errors" do
      result = Error.normalize(:not_found)

      assert %Error{} = result
      assert result.code == :not_found
    end

    test "normalizes error tuples" do
      result = Error.normalize({:error, :not_found})

      assert %Error{} = result
    end

    test "accepts context option" do
      result = Error.normalize(:not_found, context: %{user_id: 123})

      assert result.context.user_id == 123
    end
  end

  # ============================================
  # Error ID Tests
  # ============================================

  describe "error id" do
    test "generates unique IDs" do
      error1 = Error.new(:validation, :test1)
      error2 = Error.new(:validation, :test2)

      refute error1.id == error2.id
    end

    test "IDs have expected prefix" do
      error = Error.new(:validation, :test)

      assert String.starts_with?(error.id, "err_")
    end
  end

  # ============================================
  # Wrap Function Tests
  # ============================================

  describe "wrap/2" do
    test "returns ok tuple with function result" do
      result = Error.wrap(fn -> 42 end)

      assert {:ok, 42} = result
    end

    test "catches exceptions and returns error" do
      result = Error.wrap(fn -> raise "boom" end)

      assert {:error, %Error{}} = result
    end
  end
end
