defmodule OmQuery.ConfigTest do
  @moduledoc """
  Tests for OmQuery.Config - centralized configuration.
  """

  use ExUnit.Case, async: true

  alias OmQuery.Config

  # ============================================
  # repo/1 and repo!/1
  # ============================================

  describe "repo/1" do
    test "returns repo from options when provided" do
      assert Config.repo(repo: SomeModule) == SomeModule
    end

    test "returns default when options empty" do
      # In test env, default_repo may be nil (not configured)
      result = Config.repo([])
      assert is_atom(result)
    end

    test "option takes precedence over default" do
      assert Config.repo(repo: MyApp.CustomRepo) == MyApp.CustomRepo
    end

    test "defaults when called with no args" do
      result = Config.repo()
      assert is_atom(result)
    end
  end

  describe "repo!/1" do
    test "returns repo from options when provided" do
      assert Config.repo!(repo: SomeModule) == SomeModule
    end

    test "raises ArgumentError with helpful message when no repo configured and none passed" do
      # Only raises if default_repo is nil; skip if configured
      case Config.default_repo() do
        nil ->
          error =
            assert_raise ArgumentError, fn ->
              Config.repo!([])
            end

          assert error.message =~ "No repo configured"
          assert error.message =~ ":repo option"
          assert error.message =~ "config :om_query"

        _configured ->
          # Default repo is configured, repo!([]) returns it
          assert is_atom(Config.repo!([]))
      end
    end
  end

  # ============================================
  # timeout/1
  # ============================================

  describe "timeout/1" do
    test "returns timeout from options when provided" do
      assert Config.timeout(timeout: 30_000) == 30_000
    end

    test "returns default when options empty" do
      assert Config.timeout([]) == 15_000
    end

    test "returns default when called with no args" do
      assert Config.timeout() == 15_000
    end

    test "option overrides default" do
      assert Config.timeout(timeout: 60_000) == 60_000
    end

    test "default_timeout/0 returns configured value" do
      assert Config.default_timeout() == 15_000
    end
  end

  # ============================================
  # telemetry_event/1
  # ============================================

  describe "telemetry_event/1" do
    test "atom suffix appended to prefix" do
      event = Config.telemetry_event(:execute)
      prefix = Config.telemetry_prefix()
      assert event == prefix ++ [:execute]
    end

    test "list suffix appended to prefix" do
      event = Config.telemetry_event([:query, :start])
      prefix = Config.telemetry_prefix()
      assert event == prefix ++ [:query, :start]
    end

    test "single atom list suffix" do
      event = Config.telemetry_event([:build])
      prefix = Config.telemetry_prefix()
      assert event == prefix ++ [:build]
    end

    test "telemetry_prefix/0 returns list of atoms" do
      prefix = Config.telemetry_prefix()
      assert is_list(prefix)
      assert Enum.all?(prefix, &is_atom/1)
    end
  end

  # ============================================
  # check_complexity/1
  # ============================================

  describe "check_complexity/1" do
    test "returns :ok for token with few operations" do
      token_struct = struct(OmQuery.Token, operations: [{:filter, {:name, :eq, "test", []}}])
      assert Config.check_complexity(token_struct) == :ok
    end

    test "returns :ok for token with empty operations" do
      token_struct = struct(OmQuery.Token, operations: [])
      assert Config.check_complexity(token_struct) == :ok
    end

    test "returns :ok even with many operations (warnings only)" do
      # check_complexity always returns :ok, it just logs warnings
      operations = for i <- 1..5, do: {:filter, {:"field_#{i}", :eq, i, []}}
      token_struct = struct(OmQuery.Token, operations: operations)
      assert Config.check_complexity(token_struct) == :ok
    end
  end

  # ============================================
  # validate_pagination/1 and validate_pagination!/1
  # ============================================

  describe "validate_pagination/1" do
    test "valid limit and offset" do
      assert Config.validate_pagination(limit: 20, offset: 0) == :ok
    end

    test "valid limit only" do
      assert Config.validate_pagination(limit: 20) == :ok
    end

    test "empty opts are valid" do
      assert Config.validate_pagination([]) == :ok
    end

    test "nil limit is valid" do
      assert Config.validate_pagination(limit: nil) == :ok
    end

    test "nil offset is valid" do
      assert Config.validate_pagination(offset: nil) == :ok
    end

    test "limit of 1 is valid" do
      assert Config.validate_pagination(limit: 1) == :ok
    end

    test "limit at max is valid" do
      max = Config.max_limit()
      assert Config.validate_pagination(limit: max) == :ok
    end

    test "negative limit is invalid" do
      assert {:error, msg} = Config.validate_pagination(limit: -1)
      assert msg =~ "positive integer"
    end

    test "zero limit is invalid" do
      assert {:error, msg} = Config.validate_pagination(limit: 0)
      assert msg =~ "positive integer"
    end

    test "string limit is invalid" do
      assert {:error, msg} = Config.validate_pagination(limit: "abc")
      assert msg =~ "positive integer"
    end

    test "negative offset is invalid" do
      assert {:error, msg} = Config.validate_pagination(offset: -1)
      assert msg =~ "non-negative integer"
    end

    test "string offset is invalid" do
      assert {:error, msg} = Config.validate_pagination(offset: "abc")
      assert msg =~ "non-negative integer"
    end

    test "zero offset is valid" do
      assert Config.validate_pagination(offset: 0) == :ok
    end

    test "limit exceeding max returns limit_exceeded error" do
      over_max = Config.max_limit() + 1
      assert {:error, :limit_exceeded, ^over_max} = Config.validate_pagination(limit: over_max)
    end

    test "limit of 10_000 exceeds default 1000 max" do
      assert {:error, :limit_exceeded, 10_000} = Config.validate_pagination(limit: 10_000)
    end
  end

  describe "validate_pagination!/1" do
    test "valid options return :ok" do
      assert Config.validate_pagination!(limit: 20) == :ok
    end

    test "valid limit and offset return :ok" do
      assert Config.validate_pagination!(limit: 50, offset: 100) == :ok
    end

    test "empty options return :ok" do
      assert Config.validate_pagination!([]) == :ok
    end

    test "raises LimitExceededError for exceeded limits" do
      over_max = Config.max_limit() + 1

      error =
        assert_raise OmQuery.LimitExceededError, fn ->
          Config.validate_pagination!(limit: over_max)
        end

      assert error.requested == over_max
      assert error.max_allowed == Config.max_limit()
    end

    test "LimitExceededError message includes suggestion" do
      error =
        assert_raise OmQuery.LimitExceededError, fn ->
          Config.validate_pagination!(limit: 10_000)
        end

      msg = Exception.message(error)
      assert msg =~ "10000"
      assert msg =~ "1000"
    end

    test "raises PaginationError for negative limit" do
      error =
        assert_raise OmQuery.PaginationError, fn ->
          Config.validate_pagination!(limit: -1)
        end

      assert error.type == :offset
      assert error.reason =~ "positive integer"
    end

    test "raises PaginationError for zero limit" do
      assert_raise OmQuery.PaginationError, fn ->
        Config.validate_pagination!(limit: 0)
      end
    end

    test "raises PaginationError for string limit" do
      assert_raise OmQuery.PaginationError, fn ->
        Config.validate_pagination!(limit: "abc")
      end
    end

    test "raises PaginationError for negative offset" do
      error =
        assert_raise OmQuery.PaginationError, fn ->
          Config.validate_pagination!(offset: -1)
        end

      assert error.type == :offset
      assert error.reason =~ "non-negative integer"
    end

    test "raises PaginationError for string offset" do
      assert_raise OmQuery.PaginationError, fn ->
        Config.validate_pagination!(offset: "abc")
      end
    end

    test "PaginationError includes suggestion" do
      error =
        assert_raise OmQuery.PaginationError, fn ->
          Config.validate_pagination!(limit: -5)
        end

      assert error.suggestion =~ "positive integer"
    end
  end

  # ============================================
  # sql_opts/1 and repo_opts/1
  # ============================================

  describe "sql_opts/1" do
    test "extracts timeout" do
      assert Config.sql_opts(timeout: 5000, custom: true) == [timeout: 5000]
    end

    test "extracts prefix" do
      assert Config.sql_opts(prefix: "tenant_1", other: :val) == [prefix: "tenant_1"]
    end

    test "extracts log" do
      assert Config.sql_opts(log: :debug, foo: :bar) == [log: :debug]
    end

    test "extracts multiple relevant keys" do
      result = Config.sql_opts(timeout: 5000, prefix: "tenant_1", log: false, custom: true)
      assert Keyword.has_key?(result, :timeout)
      assert Keyword.has_key?(result, :prefix)
      assert Keyword.has_key?(result, :log)
      refute Keyword.has_key?(result, :custom)
    end

    test "filters out nil values" do
      result = Config.sql_opts(timeout: nil, prefix: "tenant_1")
      refute Keyword.has_key?(result, :timeout)
      assert result == [prefix: "tenant_1"]
    end

    test "empty opts returns empty list" do
      assert Config.sql_opts([]) == []
    end

    test "no matching keys returns empty list" do
      assert Config.sql_opts(custom: true, other: :val) == []
    end
  end

  describe "repo_opts/1" do
    test "extracts timeout" do
      assert Config.repo_opts(timeout: 5000, custom: true) == [timeout: 5000]
    end

    test "extracts returning" do
      assert Config.repo_opts(returning: true, custom: true) == [returning: true]
    end

    test "extracts all relevant keys" do
      result = Config.repo_opts(timeout: 5000, prefix: "t1", log: :debug, returning: true, custom: :x)
      assert Keyword.has_key?(result, :timeout)
      assert Keyword.has_key?(result, :prefix)
      assert Keyword.has_key?(result, :log)
      assert Keyword.has_key?(result, :returning)
      refute Keyword.has_key?(result, :custom)
    end

    test "filters nil values" do
      result = Config.repo_opts(timeout: nil, returning: true)
      refute Keyword.has_key?(result, :timeout)
      assert result == [returning: true]
    end

    test "empty opts returns empty list" do
      assert Config.repo_opts([]) == []
    end
  end
end
