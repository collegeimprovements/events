defmodule FnTypes.SideEffectsTest do
  @moduledoc """
  Tests for FnTypes.SideEffects module - side effect annotations and introspection.
  """
  use ExUnit.Case, async: true

  alias FnTypes.SideEffects

  # ============================================
  # Test modules with side effect annotations
  # ============================================

  defmodule TestModule do
    use FnTypes.SideEffects

    @side_effects [:db_read]
    def get_user(id), do: {:ok, %{id: id}}

    @side_effects [:db_write]
    def create_user(attrs), do: {:ok, attrs}

    @side_effects [:db_write, :email]
    def create_and_notify(attrs), do: {:ok, attrs}

    @side_effects [:pure]
    def format_name(name), do: String.upcase(name)

    @side_effects [:http, :external_api]
    def call_api(url), do: {:ok, url}

    # Function without side effects annotation
    def unannotated_function, do: :ok
  end

  defmodule EmptyModule do
    # Module without use FnTypes.SideEffects
    def some_function, do: :ok
  end

  defmodule ModuleWithUnknownEffects do
    use FnTypes.SideEffects

    @side_effects [:db_read, :custom_effect, :another_custom]
    def function_with_unknown_effects, do: :ok
  end

  # ============================================
  # Introspection API Tests
  # ============================================

  describe "get/3" do
    test "returns side effects for annotated function" do
      assert SideEffects.get(TestModule, :get_user, 1) == [:db_read]
    end

    test "returns multiple side effects" do
      assert SideEffects.get(TestModule, :create_and_notify, 1) == [:db_write, :email]
    end

    test "returns nil for unannotated function" do
      assert SideEffects.get(TestModule, :unannotated_function, 0) == nil
    end

    test "returns nil for non-existent function" do
      assert SideEffects.get(TestModule, :non_existent, 0) == nil
    end

    test "returns nil for module without SideEffects" do
      assert SideEffects.get(EmptyModule, :some_function, 0) == nil
    end
  end

  describe "list/1" do
    test "lists all annotated functions" do
      result = SideEffects.list(TestModule)

      assert {:get_user, 1, [:db_read]} in result
      assert {:create_user, 1, [:db_write]} in result
      assert {:create_and_notify, 1, [:db_write, :email]} in result
      assert {:format_name, 1, [:pure]} in result
      assert {:call_api, 1, [:http, :external_api]} in result
    end

    test "does not include unannotated functions" do
      result = SideEffects.list(TestModule)
      refute Enum.any?(result, fn {name, _, _} -> name == :unannotated_function end)
    end

    test "returns empty list for module without SideEffects" do
      assert SideEffects.list(EmptyModule) == []
    end
  end

  describe "with_effect/2" do
    test "finds functions with specific effect" do
      result = SideEffects.with_effect(TestModule, :db_write)
      assert {:create_user, 1} in result
      assert {:create_and_notify, 1} in result
    end

    test "excludes functions without the effect" do
      result = SideEffects.with_effect(TestModule, :db_write)
      refute {:get_user, 1} in result
    end

    test "returns empty list for non-existent effect" do
      assert SideEffects.with_effect(TestModule, :non_existent_effect) == []
    end

    test "returns empty list for module without SideEffects" do
      assert SideEffects.with_effect(EmptyModule, :db_read) == []
    end
  end

  describe "has_effect?/4" do
    test "returns true when function has effect" do
      assert SideEffects.has_effect?(TestModule, :get_user, 1, :db_read)
      assert SideEffects.has_effect?(TestModule, :create_and_notify, 1, :db_write)
      assert SideEffects.has_effect?(TestModule, :create_and_notify, 1, :email)
    end

    test "returns false when function doesn't have effect" do
      refute SideEffects.has_effect?(TestModule, :get_user, 1, :db_write)
      refute SideEffects.has_effect?(TestModule, :create_user, 1, :email)
    end

    test "returns false for unannotated function" do
      refute SideEffects.has_effect?(TestModule, :unannotated_function, 0, :db_read)
    end

    test "returns false for module without SideEffects" do
      refute SideEffects.has_effect?(EmptyModule, :some_function, 0, :db_read)
    end
  end

  describe "pure?/3" do
    test "returns true for function annotated as :pure" do
      assert SideEffects.pure?(TestModule, :format_name, 1)
    end

    test "returns false for function with other effects" do
      refute SideEffects.pure?(TestModule, :get_user, 1)
      refute SideEffects.pure?(TestModule, :create_user, 1)
    end

    test "returns false for unannotated function" do
      refute SideEffects.pure?(TestModule, :unannotated_function, 0)
    end

    test "returns false for module without SideEffects" do
      refute SideEffects.pure?(EmptyModule, :some_function, 0)
    end
  end

  # ============================================
  # Utility Functions Tests
  # ============================================

  describe "known_effects/0" do
    test "returns list of all known effects" do
      effects = SideEffects.known_effects()

      assert :db_read in effects
      assert :db_write in effects
      assert :http in effects
      assert :io in effects
      assert :time in effects
      assert :random in effects
      assert :process in effects
      assert :ets in effects
      assert :cache in effects
      assert :email in effects
      assert :pubsub in effects
      assert :telemetry in effects
      assert :external_api in effects
      assert :pure in effects
    end

    test "returns list of atoms" do
      effects = SideEffects.known_effects()
      assert Enum.all?(effects, &is_atom/1)
    end
  end

  describe "validate/1" do
    test "returns ok for module with only known effects" do
      assert {:ok, []} = SideEffects.validate(TestModule)
    end

    test "returns warnings for unknown effects" do
      assert {:warnings, warnings} = SideEffects.validate(ModuleWithUnknownEffects)

      # Find the warning for our function
      assert Enum.any?(warnings, fn {name, arity, unknown} ->
               name == :function_with_unknown_effects and arity == 0 and
                 :custom_effect in unknown and :another_custom in unknown
             end)
    end

    test "does not warn about known effects" do
      {:warnings, warnings} = SideEffects.validate(ModuleWithUnknownEffects)

      # :db_read is a known effect, should not be in warnings
      refute Enum.any?(warnings, fn {_, _, unknown} ->
               :db_read in unknown
             end)
    end
  end

  # ============================================
  # Effect Composition Tests
  # ============================================

  describe "combine/2" do
    test "combines two effect lists" do
      result = SideEffects.combine([:db_read], [:cache])
      assert :db_read in result
      assert :cache in result
    end

    test "removes duplicates" do
      result = SideEffects.combine([:db_read, :db_write], [:db_read, :email])
      assert length(Enum.filter(result, &(&1 == :db_read))) == 1
    end

    test "removes :pure when combined with other effects" do
      result = SideEffects.combine([:pure], [:db_write])
      assert :db_write in result
      refute :pure in result
    end

    test "keeps :pure when only :pure is present" do
      result = SideEffects.combine([:pure], [])
      assert result == [:pure]
    end

    test "combines empty lists" do
      assert SideEffects.combine([], []) == []
    end

    test "handles empty first list" do
      result = SideEffects.combine([], [:db_read])
      assert result == [:db_read]
    end

    test "handles empty second list" do
      result = SideEffects.combine([:db_write], [])
      assert result == [:db_write]
    end
  end

  describe "classify/1" do
    test "classifies database effects" do
      result = SideEffects.classify([:db_read, :db_write, :email])
      assert result.database == [:db_read, :db_write]
    end

    test "classifies external effects" do
      result = SideEffects.classify([:http, :email, :external_api])
      assert :http in result.external
      assert :email in result.external
      assert :external_api in result.external
    end

    test "puts other effects in other category" do
      result = SideEffects.classify([:io, :time, :random, :process])
      assert :io in result.other
      assert :time in result.other
      assert :random in result.other
      assert :process in result.other
    end

    test "handles mixed effects" do
      result = SideEffects.classify([:db_read, :http, :io, :cache])
      assert result.database == [:db_read]
      assert result.external == [:http]
      assert :io in result.other
      assert :cache in result.other
    end

    test "handles empty list" do
      result = SideEffects.classify([])
      assert result == %{database: [], external: [], other: []}
    end
  end

  # ============================================
  # __using__ macro tests
  # ============================================

  describe "__using__ macro" do
    test "module using SideEffects has __side_effects__/1" do
      assert function_exported?(TestModule, :__side_effects__, 1)
    end

    test "module not using SideEffects does not have __side_effects__/1" do
      refute function_exported?(EmptyModule, :__side_effects__, 1)
    end
  end

  # ============================================
  # Integration tests
  # ============================================

  describe "integration" do
    test "can query effects and use them for filtering" do
      # Find all functions that touch the database
      db_funcs =
        SideEffects.list(TestModule)
        |> Enum.filter(fn {_, _, effects} ->
          :db_read in effects or :db_write in effects
        end)
        |> Enum.map(fn {name, arity, _} -> {name, arity} end)

      assert {:get_user, 1} in db_funcs
      assert {:create_user, 1} in db_funcs
      assert {:create_and_notify, 1} in db_funcs
      refute {:format_name, 1} in db_funcs
    end

    test "can find pure functions for testing" do
      pure_funcs =
        SideEffects.list(TestModule)
        |> Enum.filter(fn {name, arity, _} ->
          SideEffects.pure?(TestModule, name, arity)
        end)
        |> Enum.map(fn {name, arity, _} -> {name, arity} end)

      assert {:format_name, 1} in pure_funcs
      assert length(pure_funcs) == 1
    end

    test "can identify functions requiring mocking in tests" do
      # Functions with external effects need mocking
      external_funcs =
        SideEffects.list(TestModule)
        |> Enum.filter(fn {_, _, effects} ->
          Enum.any?(effects, &(&1 in [:http, :external_api, :email]))
        end)
        |> Enum.map(fn {name, arity, _} -> {name, arity} end)

      assert {:call_api, 1} in external_funcs
      assert {:create_and_notify, 1} in external_funcs
    end
  end
end
