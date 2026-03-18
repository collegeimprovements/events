defmodule OmSchema.ValidatorRegistryTest do
  @moduledoc """
  Tests for OmSchema.ValidatorRegistry - Agent-based type-to-validator mapping.

  Validates registration, lookup, unregistration, defaults, and fallback
  behavior when the Agent is not started.

  Uses `async: false` because the registry is a named Agent (global state).
  """

  use ExUnit.Case, async: false

  alias OmSchema.ValidatorRegistry
  alias OmSchema.Validators

  # ============================================
  # Test Helpers
  # ============================================

  # A mock validator module that implements the required validate/3 callback
  defmodule MockValidator do
    def validate(changeset, _field, _opts), do: changeset
  end

  defmodule AnotherMockValidator do
    def validate(changeset, _field, _opts), do: changeset
  end

  # Module that does NOT implement validate/3
  defmodule InvalidValidator do
    def not_validate, do: :nope
  end

  # ============================================
  # With Agent Running
  # ============================================

  describe "with Agent started" do
    setup do
      # Stop existing agent if running (from previous test)
      case Process.whereis(ValidatorRegistry) do
        nil -> :ok
        pid -> Agent.stop(pid)
      end

      {:ok, pid} = ValidatorRegistry.start_link([])

      on_exit(fn ->
        if Process.alive?(pid), do: Agent.stop(pid)
      end)

      %{pid: pid}
    end

    # ============================================
    # start_link/1
    # ============================================

    test "starts the registry as a named Agent" do
      assert Process.whereis(ValidatorRegistry) != nil
    end

    # ============================================
    # get/1 - built-in types
    # ============================================

    test "get/1 returns String validator for :string" do
      assert ValidatorRegistry.get(:string) == Validators.String
    end

    test "get/1 returns String validator for :citext" do
      assert ValidatorRegistry.get(:citext) == Validators.String
    end

    test "get/1 returns Number validator for :integer" do
      assert ValidatorRegistry.get(:integer) == Validators.Number
    end

    test "get/1 returns Number validator for :float" do
      assert ValidatorRegistry.get(:float) == Validators.Number
    end

    test "get/1 returns Number validator for :decimal" do
      assert ValidatorRegistry.get(:decimal) == Validators.Number
    end

    test "get/1 returns Boolean validator for :boolean" do
      assert ValidatorRegistry.get(:boolean) == Validators.Boolean
    end

    test "get/1 returns Map validator for :map" do
      assert ValidatorRegistry.get(:map) == Validators.Map
    end

    test "get/1 returns DateTime validator for :utc_datetime" do
      assert ValidatorRegistry.get(:utc_datetime) == Validators.DateTime
    end

    test "get/1 returns DateTime validator for :utc_datetime_usec" do
      assert ValidatorRegistry.get(:utc_datetime_usec) == Validators.DateTime
    end

    test "get/1 returns DateTime validator for :naive_datetime" do
      assert ValidatorRegistry.get(:naive_datetime) == Validators.DateTime
    end

    test "get/1 returns DateTime validator for :naive_datetime_usec" do
      assert ValidatorRegistry.get(:naive_datetime_usec) == Validators.DateTime
    end

    test "get/1 returns DateTime validator for :date" do
      assert ValidatorRegistry.get(:date) == Validators.DateTime
    end

    test "get/1 returns DateTime validator for :time" do
      assert ValidatorRegistry.get(:time) == Validators.DateTime
    end

    # ============================================
    # get/1 - special tuple types
    # ============================================

    test "get/1 returns Array validator for {:array, :string}" do
      assert ValidatorRegistry.get({:array, :string}) == Validators.Array
    end

    test "get/1 returns Array validator for {:array, :integer}" do
      assert ValidatorRegistry.get({:array, :integer}) == Validators.Array
    end

    test "get/1 returns Map validator for {:map, :string}" do
      assert ValidatorRegistry.get({:map, :string}) == Validators.Map
    end

    test "get/1 returns String validator for {:parameterized, Ecto.Enum, _}" do
      assert ValidatorRegistry.get({:parameterized, Ecto.Enum, %{}}) == Validators.String
    end

    # ============================================
    # get/1 - unknown types
    # ============================================

    test "get/1 returns nil for unknown atom type" do
      assert ValidatorRegistry.get(:unknown_type) == nil
    end

    test "get/1 returns nil for non-atom non-tuple types" do
      assert ValidatorRegistry.get("string") == nil
      assert ValidatorRegistry.get(123) == nil
    end

    # ============================================
    # register/2
    # ============================================

    test "register/2 registers a custom validator" do
      :ok = ValidatorRegistry.register(:money, MockValidator)
      assert ValidatorRegistry.get(:money) == MockValidator
    end

    test "register/2 overrides an existing built-in validator" do
      :ok = ValidatorRegistry.register(:string, MockValidator)
      assert ValidatorRegistry.get(:string) == MockValidator
    end

    test "register/2 raises for module without validate/3" do
      assert_raise ArgumentError, ~r/must implement validate\/3/, fn ->
        ValidatorRegistry.register(:custom, InvalidValidator)
      end
    end

    # ============================================
    # unregister/1
    # ============================================

    test "unregister/1 removes a custom type" do
      :ok = ValidatorRegistry.register(:custom_type, MockValidator)
      assert ValidatorRegistry.get(:custom_type) == MockValidator

      :ok = ValidatorRegistry.unregister(:custom_type)
      assert ValidatorRegistry.get(:custom_type) == nil
    end

    test "unregister/1 reverts built-in type to default" do
      # Override string validator
      :ok = ValidatorRegistry.register(:string, MockValidator)
      assert ValidatorRegistry.get(:string) == MockValidator

      # Unregister should revert to default
      :ok = ValidatorRegistry.unregister(:string)
      assert ValidatorRegistry.get(:string) == Validators.String
    end

    test "unregister/1 is no-op for unregistered type" do
      assert :ok = ValidatorRegistry.unregister(:never_registered)
    end

    # ============================================
    # all/0
    # ============================================

    test "all/0 returns all registered validators" do
      result = ValidatorRegistry.all()

      assert is_map(result)
      assert result[:string] == Validators.String
      assert result[:integer] == Validators.Number
      assert result[:boolean] == Validators.Boolean
      assert result[:map] == Validators.Map
    end

    test "all/0 includes custom registrations" do
      :ok = ValidatorRegistry.register(:money, MockValidator)
      result = ValidatorRegistry.all()

      assert result[:money] == MockValidator
    end

    # ============================================
    # defaults/0
    # ============================================

    test "defaults/0 returns default validators regardless of registrations" do
      :ok = ValidatorRegistry.register(:money, MockValidator)
      :ok = ValidatorRegistry.register(:string, MockValidator)

      defaults = ValidatorRegistry.defaults()

      # defaults/0 should return the compile-time defaults, not current state
      assert defaults[:string] == Validators.String
      refute Map.has_key?(defaults, :money)
    end

    # ============================================
    # registered?/1
    # ============================================

    test "registered?/1 returns true for built-in types" do
      assert ValidatorRegistry.registered?(:string)
      assert ValidatorRegistry.registered?(:integer)
      assert ValidatorRegistry.registered?(:boolean)
    end

    test "registered?/1 returns false for unknown types" do
      refute ValidatorRegistry.registered?(:unknown_type)
    end

    test "registered?/1 returns true for custom registered types" do
      :ok = ValidatorRegistry.register(:money, MockValidator)
      assert ValidatorRegistry.registered?(:money)
    end

    test "registered?/1 returns true for tuple types" do
      assert ValidatorRegistry.registered?({:array, :string})
      assert ValidatorRegistry.registered?({:map, :string})
    end

    # ============================================
    # reset/0
    # ============================================

    test "reset/0 reverts to default validators" do
      :ok = ValidatorRegistry.register(:money, MockValidator)
      :ok = ValidatorRegistry.register(:string, MockValidator)

      assert ValidatorRegistry.get(:money) == MockValidator
      assert ValidatorRegistry.get(:string) == MockValidator

      :ok = ValidatorRegistry.reset()

      assert ValidatorRegistry.get(:money) == nil
      assert ValidatorRegistry.get(:string) == Validators.String
    end

    test "reset/0 removes all custom registrations" do
      :ok = ValidatorRegistry.register(:type_a, MockValidator)
      :ok = ValidatorRegistry.register(:type_b, AnotherMockValidator)

      :ok = ValidatorRegistry.reset()

      refute ValidatorRegistry.registered?(:type_a)
      refute ValidatorRegistry.registered?(:type_b)
    end
  end

  # ============================================
  # Without Agent Running (fallback behavior)
  # ============================================

  describe "without Agent started" do
    setup do
      # Make sure the agent is not running
      case Process.whereis(ValidatorRegistry) do
        nil -> :ok
        pid -> Agent.stop(pid)
      end

      :ok
    end

    test "get/1 falls back to default validators for known types" do
      assert ValidatorRegistry.get(:string) == Validators.String
      assert ValidatorRegistry.get(:integer) == Validators.Number
      assert ValidatorRegistry.get(:boolean) == Validators.Boolean
    end

    test "get/1 returns nil for unknown types" do
      assert ValidatorRegistry.get(:unknown) == nil
    end

    test "get/1 handles tuple types via pattern matching (no Agent needed)" do
      assert ValidatorRegistry.get({:array, :string}) == Validators.Array
      assert ValidatorRegistry.get({:map, :integer}) == Validators.Map
      assert ValidatorRegistry.get({:parameterized, Ecto.Enum, %{}}) == Validators.String
    end

    test "all/0 returns default validators" do
      result = ValidatorRegistry.all()

      assert result[:string] == Validators.String
      assert result[:integer] == Validators.Number
    end

    test "register/2 raises RuntimeError" do
      assert_raise RuntimeError, ~r/ValidatorRegistry not started/, fn ->
        ValidatorRegistry.register(:money, MockValidator)
      end
    end

    test "unregister/1 returns :ok silently" do
      assert :ok = ValidatorRegistry.unregister(:string)
    end

    test "reset/0 returns :ok silently" do
      assert :ok = ValidatorRegistry.reset()
    end

    test "registered?/1 uses defaults" do
      assert ValidatorRegistry.registered?(:string)
      refute ValidatorRegistry.registered?(:nonexistent)
    end

    test "defaults/0 still works" do
      defaults = ValidatorRegistry.defaults()
      assert is_map(defaults)
      assert defaults[:string] == Validators.String
    end
  end
end
