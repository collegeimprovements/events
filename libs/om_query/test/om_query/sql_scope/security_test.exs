defmodule OmQuery.SqlScope.SecurityTest do
  @moduledoc """
  Tests for OmQuery.SqlScope.Security - SQL injection defense.
  """

  use ExUnit.Case, async: true

  alias OmQuery.SqlScope.{Security, SecurityError}

  # ============================================
  # validate_identifier!/1 - Valid identifiers
  # ============================================

  describe "validate_identifier!/1 valid identifiers" do
    test "simple table name" do
      assert Security.validate_identifier!("users") == "users"
    end

    test "column name with underscore" do
      assert Security.validate_identifier!("user_id") == "user_id"
    end

    test "PascalCase name" do
      assert Security.validate_identifier!("UserAccount") == "UserAccount"
    end

    test "atom identifier" do
      assert Security.validate_identifier!(:users) == "users"
    end

    test "atom column identifier" do
      assert Security.validate_identifier!(:email) == "email"
    end

    test "starts with underscore" do
      assert Security.validate_identifier!("_private") == "_private"
    end

    test "CamelCase" do
      assert Security.validate_identifier!("CamelCase") == "CamelCase"
    end

    test "snake_case" do
      assert Security.validate_identifier!("snake_case") == "snake_case"
    end

    test "single character" do
      assert Security.validate_identifier!("a") == "a"
    end

    test "name with numbers" do
      assert Security.validate_identifier!("table_v2") == "table_v2"
    end

    test "all underscores and letters" do
      assert Security.validate_identifier!("__double__under__") == "__double__under__"
    end
  end

  # ============================================
  # validate_identifier!/1 - SQL injection attacks
  # ============================================

  describe "validate_identifier!/1 SQL injection attacks" do
    test "semicolon with DROP TABLE" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("'; DROP TABLE users; --")
      end
    end

    test "starts with number (1=1 tautology)" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("1=1")
      end
    end

    test "semicolon with DELETE" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("users; DELETE FROM users")
      end
    end

    test "newline injection" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("user\nid")
      end
    end

    test "empty string" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("")
      end
    end

    test "identifier exceeding 63 characters" do
      long_name = String.duplicate("a", 64)

      assert_raise SecurityError, ~r/too long/i, fn ->
        Security.validate_identifier!(long_name)
      end
    end

    test "identifier at exactly 63 characters is valid" do
      exact_name = String.duplicate("a", 63)
      assert Security.validate_identifier!(exact_name) == exact_name
    end

    test "embedded quotes" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("table\"name")
      end
    end

    test "SQL line comment" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("user--comment")
      end
    end

    test "SQL block comment" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("name/**/id")
      end
    end

    test "single quote injection" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("name'injection")
      end
    end

    test "space in identifier" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("user name")
      end
    end

    test "dot in identifier" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("schema.table")
      end
    end

    test "equals sign" do
      assert_raise SecurityError, fn ->
        Security.validate_identifier!("a=b")
      end
    end
  end

  # ============================================
  # validate_identifiers!/1
  # ============================================

  describe "validate_identifiers!/1" do
    test "all valid identifiers returns list of strings" do
      assert Security.validate_identifiers!([:users, :id, :email]) == ["users", "id", "email"]
    end

    test "mixed atoms and strings" do
      assert Security.validate_identifiers!([:users, "name", :status]) == ["users", "name", "status"]
    end

    test "one invalid identifier raises" do
      assert_raise SecurityError, fn ->
        Security.validate_identifiers!([:users, "'; DROP TABLE", :email])
      end
    end

    test "empty list returns empty list" do
      assert Security.validate_identifiers!([]) == []
    end

    test "single valid identifier" do
      assert Security.validate_identifiers!([:users]) == ["users"]
    end
  end

  # ============================================
  # quote_identifier/1
  # ============================================

  describe "quote_identifier/1" do
    test "simple name gets double-quoted" do
      assert Security.quote_identifier("users") == "\"users\""
    end

    test "preserves case in quotes" do
      assert Security.quote_identifier("UserAccount") == "\"UserAccount\""
    end

    test "escapes internal double quotes by doubling them" do
      assert Security.quote_identifier("table\"name") == "\"table\"\"name\""
    end

    test "handles name with no special chars" do
      assert Security.quote_identifier("simple") == "\"simple\""
    end

    test "handles multiple internal quotes" do
      assert Security.quote_identifier("a\"b\"c") == "\"a\"\"b\"\"c\""
    end
  end

  # ============================================
  # validate_qualified_identifier!/1
  # ============================================

  describe "validate_qualified_identifier!/1" do
    test "schema.table returns tuple" do
      assert Security.validate_qualified_identifier!("public.users") == {"public", "users"}
    end

    test "table only defaults to public schema" do
      assert Security.validate_qualified_identifier!("users") == {"public", "users"}
    end

    test "custom schema" do
      assert Security.validate_qualified_identifier!("tenant_1.accounts") == {"tenant_1", "accounts"}
    end

    test "three parts raises" do
      assert_raise SecurityError, ~r/Invalid qualified identifier/i, fn ->
        Security.validate_qualified_identifier!("a.b.c")
      end
    end

    test "four parts raises" do
      assert_raise SecurityError, fn ->
        Security.validate_qualified_identifier!("a.b.c.d")
      end
    end

    test "injection in schema part raises" do
      assert_raise SecurityError, fn ->
        Security.validate_qualified_identifier!("'; DROP TABLE.users")
      end
    end

    test "injection in table part raises" do
      assert_raise SecurityError, fn ->
        Security.validate_qualified_identifier!("public.'; DROP TABLE")
      end
    end

    test "empty schema part raises" do
      assert_raise SecurityError, fn ->
        Security.validate_qualified_identifier!(".users")
      end
    end

    test "empty table part raises" do
      assert_raise SecurityError, fn ->
        Security.validate_qualified_identifier!("public.")
      end
    end
  end

  # ============================================
  # validate_sql_fragment!/1
  # ============================================

  describe "validate_sql_fragment!/1" do
    test "safe equality fragment passes" do
      assert Security.validate_sql_fragment!("status = 'active'") == :ok
    end

    test "IS NULL fragment passes" do
      assert Security.validate_sql_fragment!("deleted_at IS NULL") == :ok
    end

    test "comparison fragment passes" do
      assert Security.validate_sql_fragment!("age > 18") == :ok
    end

    test "BETWEEN fragment passes" do
      assert Security.validate_sql_fragment!("created_at BETWEEN '2024-01-01' AND '2024-12-31'") == :ok
    end

    test "semicolon with DROP TABLE raises" do
      assert_raise SecurityError, ~r/Dangerous SQL fragment/i, fn ->
        Security.validate_sql_fragment!("; DROP TABLE users")
      end
    end

    test "semicolon with DELETE raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("; DELETE FROM users")
      end
    end

    test "line comment raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("status = 'active' -- ignore rest")
      end
    end

    test "block comment raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("status = 'active' /* hidden */")
      end
    end

    test "UNION SELECT raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("1=1 UNION SELECT * FROM passwords")
      end
    end

    test "union case insensitive raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("1=1 union select * from passwords")
      end
    end

    test "EXEC command raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("exec sp_executesql 'DROP TABLE users'")
      end
    end

    test "xp_ extended procedure raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("xp_cmdshell('whoami')")
      end
    end

    test "INTO OUTFILE raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("1=1 INTO OUTFILE '/tmp/data'")
      end
    end

    test "LOAD_FILE raises" do
      assert_raise SecurityError, fn ->
        Security.validate_sql_fragment!("LOAD_FILE('/etc/passwd')")
      end
    end

    test "fragment over 1000 characters raises" do
      long_fragment = String.duplicate("a", 1001)

      assert_raise SecurityError, ~r/too long/i, fn ->
        Security.validate_sql_fragment!(long_fragment)
      end
    end

    test "fragment at exactly 1000 characters passes" do
      exact_fragment = String.duplicate("a", 1000)
      assert Security.validate_sql_fragment!(exact_fragment) == :ok
    end
  end

  # ============================================
  # validate_options!/2
  # ============================================

  describe "validate_options!/2" do
    test "known options pass" do
      assert Security.validate_options!([limit: 100, offset: 0], [:limit, :offset, :format]) == :ok
    end

    test "empty options pass" do
      assert Security.validate_options!([], [:limit, :offset]) == :ok
    end

    test "subset of allowed options pass" do
      assert Security.validate_options!([limit: 50], [:limit, :offset, :format]) == :ok
    end

    test "unknown option raises" do
      assert_raise SecurityError, ~r/Unknown options/i, fn ->
        Security.validate_options!([unknown: true], [:limit, :offset])
      end
    end

    test "multiple unknown options raises" do
      assert_raise SecurityError, ~r/Unknown options/i, fn ->
        Security.validate_options!([foo: 1, bar: 2], [:limit])
      end
    end

    test "error message includes allowed options" do
      error =
        assert_raise SecurityError, fn ->
          Security.validate_options!([bad: true], [:limit, :offset])
        end

      assert error.message =~ "Allowed options:"
      assert error.message =~ ":limit"
      assert error.message =~ ":offset"
    end

    test "mix of known and unknown raises for unknown" do
      assert_raise SecurityError, fn ->
        Security.validate_options!([limit: 10, unknown: true], [:limit, :offset])
      end
    end
  end
end
