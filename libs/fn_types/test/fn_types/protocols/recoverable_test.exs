defmodule FnTypes.Protocols.RecoverableTest do
  use ExUnit.Case, async: true

  alias FnTypes.Protocols.Recoverable

  # ============================================
  # Fallback Implementation Tests (Any)
  # ============================================

  describe "recoverable?/1 for unknown types" do
    test "returns false for unknown atoms" do
      refute Recoverable.recoverable?(:some_unknown_error)
    end

    test "returns false for arbitrary maps" do
      refute Recoverable.recoverable?(%{error: "something"})
    end

    test "returns false for strings" do
      refute Recoverable.recoverable?("error message")
    end
  end

  # ============================================
  # Strategy Tests
  # ============================================

  describe "strategy/1 for unknown types" do
    test "returns :fail_fast for unknown types" do
      assert Recoverable.strategy(:unknown_error) == :fail_fast
    end
  end

  # ============================================
  # Retry Delay Tests
  # ============================================

  describe "retry_delay/2 for unknown types" do
    test "returns 0 for unknown types" do
      assert Recoverable.retry_delay(:unknown_error, 1) == 0
      assert Recoverable.retry_delay(:unknown_error, 5) == 0
    end
  end

  # ============================================
  # Max Attempts Tests
  # ============================================

  describe "max_attempts/1 for unknown types" do
    test "returns 1 for unknown types" do
      assert Recoverable.max_attempts(:unknown_error) == 1
    end
  end

  # ============================================
  # Circuit Breaker Tests
  # ============================================

  describe "trips_circuit?/1 for unknown types" do
    test "returns false for unknown types" do
      refute Recoverable.trips_circuit?(:unknown_error)
    end
  end

  # ============================================
  # Severity Tests
  # ============================================

  describe "severity/1 for unknown types" do
    test "returns :permanent for unknown types" do
      assert Recoverable.severity(:unknown_error) == :permanent
    end
  end

  # ============================================
  # Fallback Tests
  # ============================================

  describe "fallback/1 for unknown types" do
    test "returns nil for unknown types" do
      assert Recoverable.fallback(:unknown_error) == nil
    end
  end
end
