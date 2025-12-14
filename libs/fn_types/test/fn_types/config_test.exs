defmodule FnTypes.ConfigTest do
  use ExUnit.Case, async: false

  alias FnTypes.Config

  # We need async: false because we're manipulating System environment

  setup do
    # Clean up any test env vars after each test
    on_exit(fn ->
      System.delete_env("TEST_VAR")
      System.delete_env("TEST_VAR1")
      System.delete_env("TEST_VAR2")
      System.delete_env("TEST_VAR3")
      System.delete_env("TEST_PORT")
      System.delete_env("TEST_ENABLED")
      System.delete_env("TEST_LEVEL")
      System.delete_env("TEST_RATE")
      System.delete_env("TEST_HOSTS")
      System.delete_env("TEST_URL")
      System.delete_env("CACHE_ADAPTER")
      System.delete_env("REDIS_HOST")
      System.delete_env("REDIS_PORT")
    end)

    :ok
  end

  # ============================================
  # String Tests
  # ============================================

  describe "string/2" do
    test "returns env value when set" do
      System.put_env("TEST_VAR", "hello")
      assert Config.string("TEST_VAR") == "hello"
    end

    test "returns nil when not set and no default" do
      assert Config.string("TEST_VAR") == nil
    end

    test "returns default when not set" do
      assert Config.string("TEST_VAR", "default") == "default"
    end

    test "returns nil for empty string" do
      System.put_env("TEST_VAR", "")
      assert Config.string("TEST_VAR") == nil
    end

    test "returns default for empty string" do
      System.put_env("TEST_VAR", "")
      assert Config.string("TEST_VAR", "default") == "default"
    end

    test "trims whitespace from values" do
      System.put_env("TEST_VAR", "  hello world  ")
      assert Config.string("TEST_VAR") == "hello world"
    end

    test "returns nil for whitespace-only string" do
      System.put_env("TEST_VAR", "   ")
      assert Config.string("TEST_VAR") == nil
    end

    test "returns default for whitespace-only string" do
      System.put_env("TEST_VAR", "  \t\n  ")
      assert Config.string("TEST_VAR", "default") == "default"
    end

    test "supports fallback chain - first found" do
      System.put_env("TEST_VAR1", "first")
      System.put_env("TEST_VAR2", "second")
      assert Config.string(["TEST_VAR1", "TEST_VAR2"], "default") == "first"
    end

    test "supports fallback chain - second found" do
      System.put_env("TEST_VAR2", "second")
      assert Config.string(["TEST_VAR1", "TEST_VAR2"], "default") == "second"
    end

    test "supports fallback chain - falls through to default" do
      assert Config.string(["TEST_VAR1", "TEST_VAR2"], "default") == "default"
    end

    test "supports fallback chain - skips empty strings" do
      System.put_env("TEST_VAR1", "")
      System.put_env("TEST_VAR2", "second")
      assert Config.string(["TEST_VAR1", "TEST_VAR2"], "default") == "second"
    end
  end

  describe "string!/1-2" do
    test "returns value when set" do
      System.put_env("TEST_VAR", "hello")
      assert Config.string!("TEST_VAR") == "hello"
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required.*TEST_VAR/, fn ->
        Config.string!("TEST_VAR")
      end
    end

    test "raises with custom message" do
      assert_raise RuntimeError, "Custom error message", fn ->
        Config.string!("TEST_VAR", message: "Custom error message")
      end
    end

    test "raises when empty" do
      System.put_env("TEST_VAR", "")

      assert_raise RuntimeError, ~r/Missing required.*TEST_VAR/, fn ->
        Config.string!("TEST_VAR")
      end
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "found")
      assert Config.string!(["TEST_VAR1", "TEST_VAR2"]) == "found"
    end

    test "raises with all names in error for fallback chain" do
      assert_raise RuntimeError, ~r/TEST_VAR1 or TEST_VAR2/, fn ->
        Config.string!(["TEST_VAR1", "TEST_VAR2"])
      end
    end
  end

  # ============================================
  # Integer Tests
  # ============================================

  describe "integer/2" do
    test "parses integer string" do
      System.put_env("TEST_PORT", "8080")
      assert Config.integer("TEST_PORT") == 8080
    end

    test "parses trimmed integer string" do
      System.put_env("TEST_PORT", "  8080  ")
      assert Config.integer("TEST_PORT") == 8080
    end

    test "returns default when not set" do
      assert Config.integer("TEST_PORT", 4000) == 4000
    end

    test "returns nil when not set and no default" do
      assert Config.integer("TEST_PORT") == nil
    end

    test "returns default for invalid integer" do
      System.put_env("TEST_PORT", "invalid")
      assert Config.integer("TEST_PORT", 4000) == 4000
    end

    test "returns default for partial integer" do
      System.put_env("TEST_PORT", "80abc")
      assert Config.integer("TEST_PORT", 4000) == 4000
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "9000")
      assert Config.integer(["TEST_VAR1", "TEST_VAR2"], 4000) == 9000
    end
  end

  describe "integer!/1-2" do
    test "returns value when valid" do
      System.put_env("TEST_PORT", "8080")
      assert Config.integer!("TEST_PORT") == 8080
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required.*TEST_PORT/, fn ->
        Config.integer!("TEST_PORT")
      end
    end

    test "raises for invalid integer" do
      System.put_env("TEST_PORT", "invalid")

      assert_raise RuntimeError, ~r/Invalid integer/, fn ->
        Config.integer!("TEST_PORT")
      end
    end
  end

  # ============================================
  # Boolean Tests
  # ============================================

  describe "boolean/2" do
    test "returns true for truthy values" do
      for value <- ["1", "true", "yes", "y", "on", "TRUE", "Yes", "Y", "ON", "✓", "✅"] do
        System.put_env("TEST_ENABLED", value)
        assert Config.boolean("TEST_ENABLED") == true, "Expected #{value} to be truthy"
      end
    end

    test "returns true for truthy values with whitespace" do
      for value <- ["  true  ", " 1 ", "\tyes\n", "  y  ", " ✓ ", " ✅ "] do
        System.put_env("TEST_ENABLED", value)
        assert Config.boolean("TEST_ENABLED") == true, "Expected #{inspect(value)} to be truthy after trimming"
      end
    end

    test "returns false for falsy values" do
      for value <- ["0", "false", "no", "off", "anything", "yep", "nope"] do
        System.put_env("TEST_ENABLED", value)
        assert Config.boolean("TEST_ENABLED") == false, "Expected #{value} to be falsy"
      end
    end

    test "returns default when not set" do
      assert Config.boolean("TEST_ENABLED", true) == true
      assert Config.boolean("TEST_ENABLED", false) == false
    end

    test "returns nil when not set and no default" do
      assert Config.boolean("TEST_ENABLED") == nil
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "true")
      assert Config.boolean(["TEST_VAR1", "TEST_VAR2"], false) == true
    end
  end

  describe "boolean!/1-2" do
    test "returns value when set" do
      System.put_env("TEST_ENABLED", "true")
      assert Config.boolean!("TEST_ENABLED") == true
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required/, fn ->
        Config.boolean!("TEST_ENABLED")
      end
    end
  end

  # ============================================
  # Atom Tests
  # ============================================

  describe "atom/2" do
    test "converts to existing atom" do
      System.put_env("TEST_LEVEL", "info")
      assert Config.atom("TEST_LEVEL") == :info
    end

    test "returns default when not set" do
      assert Config.atom("TEST_LEVEL", :debug) == :debug
    end

    test "returns nil when not set and no default" do
      assert Config.atom("TEST_LEVEL") == nil
    end

    test "raises for non-existing atom" do
      System.put_env("TEST_LEVEL", "nonexistent_atom_xyz123")

      assert_raise ArgumentError, fn ->
        Config.atom("TEST_LEVEL")
      end
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "warning")
      assert Config.atom(["TEST_VAR1", "TEST_VAR2"], :info) == :warning
    end
  end

  describe "atom!/1-2" do
    test "returns value when valid" do
      System.put_env("TEST_LEVEL", "error")
      assert Config.atom!("TEST_LEVEL") == :error
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required/, fn ->
        Config.atom!("TEST_LEVEL")
      end
    end
  end

  # ============================================
  # Float Tests
  # ============================================

  describe "float/2" do
    test "parses float string" do
      System.put_env("TEST_RATE", "1.5")
      assert Config.float("TEST_RATE") == 1.5
    end

    test "parses integer string as float" do
      System.put_env("TEST_RATE", "10")
      assert Config.float("TEST_RATE") == 10.0
    end

    test "returns default when not set" do
      assert Config.float("TEST_RATE", 0.5) == 0.5
    end

    test "returns default for invalid float" do
      System.put_env("TEST_RATE", "invalid")
      assert Config.float("TEST_RATE", 1.0) == 1.0
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "2.5")
      assert Config.float(["TEST_VAR1", "TEST_VAR2"], 1.0) == 2.5
    end
  end

  describe "float!/1-2" do
    test "returns value when valid" do
      System.put_env("TEST_RATE", "3.14")
      assert Config.float!("TEST_RATE") == 3.14
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required/, fn ->
        Config.float!("TEST_RATE")
      end
    end

    test "raises for invalid float" do
      System.put_env("TEST_RATE", "invalid")

      assert_raise RuntimeError, ~r/Invalid float/, fn ->
        Config.float!("TEST_RATE")
      end
    end
  end

  # ============================================
  # List Tests
  # ============================================

  describe "list/3" do
    test "splits by comma by default" do
      System.put_env("TEST_HOSTS", "a,b,c")
      assert Config.list("TEST_HOSTS") == ["a", "b", "c"]
    end

    test "splits by custom delimiter" do
      System.put_env("TEST_HOSTS", "a:b:c")
      assert Config.list("TEST_HOSTS", ":") == ["a", "b", "c"]
    end

    test "returns default when not set" do
      assert Config.list("TEST_HOSTS", ",", ["default"]) == ["default"]
    end

    test "trims empty values" do
      System.put_env("TEST_HOSTS", "a,,b,,c")
      assert Config.list("TEST_HOSTS") == ["a", "b", "c"]
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "x,y,z")
      assert Config.list(["TEST_VAR1", "TEST_VAR2"]) == ["x", "y", "z"]
    end
  end

  # ============================================
  # URL Tests
  # ============================================

  describe "url/1" do
    test "parses valid URL" do
      System.put_env("TEST_URL", "http://localhost:8080")
      uri = Config.url("TEST_URL")
      assert %URI{} = uri
      assert uri.scheme == "http"
      assert uri.host == "localhost"
      assert uri.port == 8080
    end

    test "returns nil when not set" do
      assert Config.url("TEST_URL") == nil
    end

    test "supports fallback chain" do
      System.put_env("TEST_VAR2", "https://example.com")
      uri = Config.url(["TEST_VAR1", "TEST_VAR2"])
      assert uri.host == "example.com"
    end
  end

  describe "url!/1-2" do
    test "returns URI when valid" do
      System.put_env("TEST_URL", "https://example.com")
      assert %URI{} = Config.url!("TEST_URL")
    end

    test "raises when not set" do
      assert_raise RuntimeError, ~r/Missing required/, fn ->
        Config.url!("TEST_URL")
      end
    end
  end

  # ============================================
  # from_app Tests
  # ============================================

  describe "from_app/2" do
    test "reads simple key from app config" do
      Application.put_env(:fn_types, :test_key, "app_value")

      assert Config.from_app(:fn_types, :test_key) == "app_value"

      Application.delete_env(:fn_types, :test_key)
    end

    test "returns nil for missing key" do
      assert Config.from_app(:fn_types, :nonexistent_key) == nil
    end

    test "reads nested path from app config" do
      Application.put_env(:fn_types, :parent, [child: "nested_value"])

      assert Config.from_app(:fn_types, [:parent, :child]) == "nested_value"

      Application.delete_env(:fn_types, :parent)
    end
  end

  # ============================================
  # first_of Tests
  # ============================================

  describe "first_of/1" do
    test "returns first non-nil value" do
      assert Config.first_of([nil, nil, "third"]) == "third"
      assert Config.first_of(["first", "second", "third"]) == "first"
      assert Config.first_of([nil, "second", nil]) == "second"
    end

    test "returns nil if all values are nil" do
      assert Config.first_of([nil, nil, nil]) == nil
    end

    test "works with env vars and app config" do
      Application.put_env(:fn_types, :test_key, "app_value")

      # Env not set, should get app value
      result = Config.first_of([
        Config.string("TEST_VAR"),
        Config.from_app(:fn_types, :test_key),
        "default"
      ])
      assert result == "app_value"

      # Env set, should get env value
      System.put_env("TEST_VAR", "env_value")
      result = Config.first_of([
        Config.string("TEST_VAR"),
        Config.from_app(:fn_types, :test_key),
        "default"
      ])
      assert result == "env_value"

      Application.delete_env(:fn_types, :test_key)
    end

    test "returns default when nothing is set" do
      result = Config.first_of([
        Config.string("TEST_VAR"),
        Config.from_app(:fn_types, :nonexistent),
        "default"
      ])
      assert result == "default"
    end

    test "works with boolean env vars" do
      System.put_env("TEST_ENABLED", "true")

      result = Config.first_of([
        Config.boolean("TEST_ENABLED"),
        false
      ])
      assert result == true
    end

    test "supports lazy evaluation with functions" do
      # Track which functions were called
      test_pid = self()

      result = Config.first_of([
        fn ->
          send(test_pid, :first_called)
          "first_value"
        end,
        fn ->
          send(test_pid, :second_called)
          "second_value"
        end
      ])

      assert result == "first_value"
      assert_received :first_called
      refute_received :second_called
    end

    test "lazy functions are only called until non-nil found" do
      test_pid = self()

      result = Config.first_of([
        fn ->
          send(test_pid, :first_called)
          nil
        end,
        fn ->
          send(test_pid, :second_called)
          "found"
        end,
        fn ->
          send(test_pid, :third_called)
          "never_reached"
        end
      ])

      assert result == "found"
      assert_received :first_called
      assert_received :second_called
      refute_received :third_called
    end

    test "mixed values and functions" do
      test_pid = self()

      # First value is nil, so function should be called
      result = Config.first_of([
        nil,
        fn ->
          send(test_pid, :function_called)
          "from_function"
        end,
        "default"
      ])

      assert result == "from_function"
      assert_received :function_called
    end

    test "skips function if earlier value is non-nil" do
      test_pid = self()

      result = Config.first_of([
        "immediate_value",
        fn ->
          send(test_pid, :should_not_call)
          "from_function"
        end
      ])

      assert result == "immediate_value"
      refute_received :should_not_call
    end
  end

  # ============================================
  # Presence Check Tests
  # ============================================

  describe "present?/1" do
    test "returns true when set" do
      System.put_env("TEST_VAR", "value")
      assert Config.present?("TEST_VAR") == true
    end

    test "returns false when not set" do
      assert Config.present?("TEST_VAR") == false
    end

    test "returns false for empty string" do
      System.put_env("TEST_VAR", "")
      assert Config.present?("TEST_VAR") == false
    end

    test "returns true if any in fallback chain is present" do
      System.put_env("TEST_VAR2", "value")
      assert Config.present?(["TEST_VAR1", "TEST_VAR2"]) == true
    end

    test "returns false if none in fallback chain is present" do
      assert Config.present?(["TEST_VAR1", "TEST_VAR2"]) == false
    end
  end

end
