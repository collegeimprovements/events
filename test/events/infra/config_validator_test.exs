defmodule Events.Infra.ConfigValidatorTest do
  use ExUnit.Case, async: false

  alias Events.Infra.ConfigValidator

  describe "validate_all/0" do
    test "returns categorized results" do
      results = ConfigValidator.validate_all()

      assert is_map(results)
      assert Map.has_key?(results, :ok)
      assert Map.has_key?(results, :warnings)
      assert Map.has_key?(results, :errors)
      assert Map.has_key?(results, :disabled)

      assert is_list(results.ok)
      assert is_list(results.warnings)
      assert is_list(results.errors)
      assert is_list(results.disabled)
    end

    test "returns database validation" do
      results = ConfigValidator.validate_all()

      # Database should be valid in test environment
      database_result =
        Enum.find(results.ok ++ results.warnings ++ results.errors, &(&1.service == :database))

      assert database_result != nil
      assert database_result.critical == true
    end

    test "returns cache validation" do
      results = ConfigValidator.validate_all()

      cache_result =
        Enum.find(results.ok ++ results.warnings ++ results.errors, &(&1.service == :cache))

      assert cache_result != nil
      assert cache_result.critical == false
    end
  end

  describe "validate_critical/0" do
    test "returns ok with valid critical services" do
      assert {:ok, results} = ConfigValidator.validate_critical()
      assert is_list(results)

      # Database should be in the list
      assert Enum.any?(results, &(&1.service == :database))
    end

    test "only validates critical services" do
      {:ok, results} = ConfigValidator.validate_critical()

      # All results should be critical services
      assert Enum.all?(results, & &1.critical)
    end
  end

  describe "validate_service/1" do
    test "validates specific service" do
      result = ConfigValidator.validate_service(:database)

      assert match?({:ok, _}, result) or match?({:error, _}, result) or
               match?({:warning, _, _}, result)
    end

    test "returns error for unknown service" do
      assert {:error, _reason} = ConfigValidator.validate_service(:unknown_service)
    end
  end

  describe "validate_database/0" do
    test "returns ok with valid config in test" do
      assert {:ok, metadata} = ConfigValidator.validate_database()

      assert Map.has_key?(metadata, :pool_size)
      assert is_integer(metadata.pool_size)
    end
  end

  describe "validate_cache/0" do
    test "returns ok or warning with cache config" do
      result = ConfigValidator.validate_cache()

      assert match?({:ok, _}, result) or match?({:warning, _, _}, result)
    end
  end

  describe "validate_scheduler/0" do
    test "validates scheduler config" do
      result = ConfigValidator.validate_scheduler()

      # Scheduler might be disabled in test, so we accept multiple outcomes
      assert match?({:ok, _}, result) or match?({:error, _}, result) or
               match?({:disabled, _}, result)
    end
  end

  describe "validate_email/0" do
    test "returns ok with test adapter" do
      result = ConfigValidator.validate_email()

      # In test environment, should have Swoosh.Adapters.Test
      assert {:ok, metadata} = result
      assert metadata.adapter =~ "Test"
    end
  end

  describe "validate_stripe/0" do
    test "returns disabled when not configured" do
      # Stripe is optional, so should be disabled without API key
      result = ConfigValidator.validate_stripe()

      assert match?({:ok, _}, result) or match?({:disabled, _}, result)
    end
  end
end
