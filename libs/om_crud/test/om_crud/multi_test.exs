defmodule OmCrud.MultiTest do
  @moduledoc """
  Tests for OmCrud.Multi - Transactional composition for CRUD operations.

  Multi allows composing multiple database operations into a single atomic
  transaction. All operations succeed or none do - perfect for complex workflows.

  ## Use Cases

  - **User registration**: Create user + account + settings atomically
  - **Order processing**: Update inventory + create order + charge payment
  - **Data migration**: Transform and move data between tables safely
  - **Cascading updates**: Update parent and all related children together

  ## Pattern: Transaction Composition

      Multi.new()
      |> Multi.create(:user, User, user_attrs)
      |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
      |> Multi.update(:settings, fn %{user: u} -> {u.settings, settings_attrs} end)
      |> OmCrud.run()

  Operations can depend on previous results via function callbacks.
  """

  use ExUnit.Case, async: true

  alias OmCrud.Multi

  describe "new/0" do
    test "creates an empty multi token" do
      multi = Multi.new()

      assert %Multi{} = multi
      assert multi.operations == []
      assert multi.names == MapSet.new()
    end
  end

  describe "new/1" do
    test "creates multi with schema context" do
      multi = Multi.new(SomeSchema)

      assert %Multi{} = multi
      assert multi.schema == SomeSchema
    end
  end

  describe "create/5" do
    test "adds insert operation with static attrs" do
      multi =
        Multi.new()
        |> Multi.create(:user, SomeSchema, %{name: "test"})

      assert Multi.names(multi) == [:user]
      assert Multi.operation_count(multi) == 1
      assert Multi.has_operation?(multi, :user)
    end

    test "adds insert operation with dynamic attrs" do
      multi =
        Multi.new()
        |> Multi.create(:user, SomeSchema, fn _results -> %{name: "test"} end)

      assert Multi.names(multi) == [:user]
    end

    test "raises on duplicate operation names" do
      assert_raise ArgumentError, ~r/already exists/, fn ->
        Multi.new()
        |> Multi.create(:user, SomeSchema, %{name: "a"})
        |> Multi.create(:user, SomeSchema, %{name: "b"})
      end
    end
  end

  describe "update/5" do
    test "accepts {schema, binary_id} tuple" do
      multi =
        Multi.new()
        |> Multi.update(:user, {SomeSchema, "uuid-123"}, %{name: "updated"})

      assert Multi.has_operation?(multi, :user)
    end

    test "accepts {schema, integer_id} tuple" do
      multi =
        Multi.new()
        |> Multi.update(:user, {SomeSchema, 42}, %{name: "updated"})

      assert Multi.has_operation?(multi, :user)
    end

    test "accepts function for dynamic struct resolution" do
      multi =
        Multi.new()
        |> Multi.update(:user, fn _results -> :some_struct end, %{name: "updated"})

      assert Multi.has_operation?(multi, :user)
    end
  end

  describe "delete/4" do
    test "accepts {schema, binary_id} tuple" do
      multi =
        Multi.new()
        |> Multi.delete(:user, {SomeSchema, "uuid-123"})

      assert Multi.has_operation?(multi, :user)
    end

    test "accepts {schema, integer_id} tuple" do
      multi =
        Multi.new()
        |> Multi.delete(:user, {SomeSchema, 42})

      assert Multi.has_operation?(multi, :user)
    end
  end

  describe "names/1" do
    test "returns empty list for new multi" do
      multi = Multi.new()

      assert Multi.names(multi) == []
    end

    test "returns operation names in order" do
      multi =
        Multi.new()
        |> Multi.create(:first, SomeSchema, %{})
        |> Multi.create(:second, OtherSchema, %{})
        |> Multi.run(:third, fn _ -> {:ok, nil} end)

      assert Multi.names(multi) == [:first, :second, :third]
    end
  end

  describe "operation_count/1" do
    test "returns 0 for new multi" do
      multi = Multi.new()

      assert Multi.operation_count(multi) == 0
    end

    test "counts all operations" do
      multi =
        Multi.new()
        |> Multi.create(:a, SomeSchema, %{})
        |> Multi.create(:b, SomeSchema, %{})
        |> Multi.run(:c, fn _ -> {:ok, nil} end)

      assert Multi.operation_count(multi) == 3
    end
  end

  describe "empty?/1" do
    test "returns true for new multi" do
      multi = Multi.new()

      assert Multi.empty?(multi) == true
    end

    test "returns false when operations exist" do
      multi = Multi.new() |> Multi.create(:a, SomeSchema, %{})

      assert Multi.empty?(multi) == false
    end
  end

  describe "has_operation?/2" do
    test "returns false for non-existent operation" do
      multi = Multi.new()

      assert Multi.has_operation?(multi, :some_op) == false
    end

    test "returns true for existing operation" do
      multi = Multi.new() |> Multi.create(:user, SomeSchema, %{})

      assert Multi.has_operation?(multi, :user) == true
    end
  end

  describe "append/2" do
    test "combines two multi tokens" do
      multi1 = Multi.new() |> Multi.create(:first, SomeSchema, %{})
      multi2 = Multi.new() |> Multi.create(:second, OtherSchema, %{})

      combined = Multi.append(multi1, multi2)

      assert Multi.names(combined) == [:first, :second]
      assert Multi.operation_count(combined) == 2
    end
  end

  describe "prepend/2" do
    test "prepends operations from second multi" do
      multi1 = Multi.new() |> Multi.create(:first, SomeSchema, %{})
      multi2 = Multi.new() |> Multi.create(:second, OtherSchema, %{})

      combined = Multi.prepend(multi1, multi2)

      assert Multi.names(combined) == [:second, :first]
    end
  end

  describe "embed/3" do
    test "embeds with prefix to avoid name collisions" do
      inner = Multi.new() |> Multi.create(:record, SomeSchema, %{})

      multi =
        Multi.new()
        |> Multi.create(:main, SomeSchema, %{})
        |> Multi.embed(inner, prefix: :user)

      assert Multi.has_operation?(multi, :user_record)
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "when_ok/3" do
    test "adds a dynamic operation" do
      multi =
        Multi.new()
        |> Multi.create(:user, SomeSchema, %{})
        |> Multi.when_ok(:setup, fn _results ->
          Multi.new()
          |> Multi.create(:settings, OtherSchema, %{})
        end)

      assert Multi.has_operation?(multi, :setup)
      assert Multi.operation_count(multi) == 2
    end

    test "uses {:dynamic, fun} operation type for Ecto.Multi.merge conversion" do
      multi =
        Multi.new()
        |> Multi.when_ok(:setup, fn _results -> Multi.new() end)

      [{:setup, {:dynamic, fun}}] = multi.operations
      assert is_function(fun, 1)
    end
  end

  describe "when_cond/3" do
    test "includes operations when static condition is true" do
      multi =
        Multi.new()
        |> Multi.when_cond(true, fn multi ->
          Multi.create(multi, :user, SomeSchema, %{})
        end)

      assert Multi.has_operation?(multi, :user)
    end

    test "skips operations when static condition is false" do
      multi =
        Multi.new()
        |> Multi.when_cond(false, fn multi ->
          Multi.create(multi, :user, SomeSchema, %{})
        end)

      assert Multi.empty?(multi)
    end

    test "dynamic condition uses {:dynamic, fun} operation type" do
      multi =
        Multi.new()
        |> Multi.when_cond(fn _results -> true end, fn multi, _results ->
          Multi.create(multi, :user, SomeSchema, %{})
        end)

      assert Multi.operation_count(multi) == 1
      [{_name, {:dynamic, fun}}] = multi.operations
      assert is_function(fun, 1)
    end
  end

  describe "unless/3" do
    test "includes operations when condition is false" do
      multi =
        Multi.new()
        |> Multi.unless(false, fn multi ->
          Multi.create(multi, :user, SomeSchema, %{})
        end)

      assert Multi.has_operation?(multi, :user)
    end

    test "skips operations when condition is true" do
      multi =
        Multi.new()
        |> Multi.unless(true, fn multi ->
          Multi.create(multi, :user, SomeSchema, %{})
        end)

      assert Multi.empty?(multi)
    end
  end

  describe "branch/4" do
    test "uses {:dynamic, fun} operation type" do
      multi =
        Multi.new()
        |> Multi.branch(
          fn _results -> true end,
          fn multi, _results -> Multi.create(multi, :a, SomeSchema, %{}) end,
          fn multi, _results -> Multi.create(multi, :b, SomeSchema, %{}) end
        )

      assert Multi.operation_count(multi) == 1
      [{_name, {:dynamic, fun}}] = multi.operations
      assert is_function(fun, 1)
    end
  end

  describe "each/4" do
    test "static list expands at build time" do
      multi =
        Multi.new()
        |> Multi.each(:items, ["a", "b", "c"], fn multi, item, index, _results ->
          Multi.create(multi, :"item_#{index}", SomeSchema, %{name: item})
        end)

      assert Multi.operation_count(multi) == 3
      assert Multi.names(multi) == [:item_0, :item_1, :item_2]
    end

    test "dynamic list uses {:dynamic, fun} operation type" do
      multi =
        Multi.new()
        |> Multi.each(:items, fn _results -> ["a", "b"] end, fn multi, item, index, _results ->
          Multi.create(multi, :"item_#{index}", SomeSchema, %{name: item})
        end)

      assert Multi.operation_count(multi) == 1
      [{:items, {:dynamic, fun}}] = multi.operations
      assert is_function(fun, 1)

      # Verify the dynamic function builds proper inner multi
      inner_multi = fun.(%{})
      assert Multi.operation_count(inner_multi) == 2
      assert Multi.names(inner_multi) == [:item_0, :item_1]
    end
  end

  describe "when_value/4" do
    test "delegates to when_cond with value check" do
      multi =
        Multi.new()
        |> Multi.run(:check, fn _ -> {:ok, :proceed} end)
        |> Multi.when_value(:check, :proceed, fn multi, _results ->
          Multi.create(multi, :record, SomeSchema, %{})
        end)

      assert Multi.operation_count(multi) == 2
    end
  end

  describe "when_match/4" do
    test "delegates to when_cond with matcher function" do
      multi =
        Multi.new()
        |> Multi.run(:fetch, fn _ -> {:ok, %{role: :admin}} end)
        |> Multi.when_match(:fetch, &match?(%{role: :admin}, &1), fn multi, _results ->
          Multi.create(multi, :audit, SomeSchema, %{})
        end)

      assert Multi.operation_count(multi) == 2
    end
  end

  describe "run/3" do
    test "adds a custom run function" do
      multi =
        Multi.new()
        |> Multi.run(:custom, fn _results -> {:ok, :done} end)

      assert Multi.has_operation?(multi, :custom)
    end
  end

  describe "run/5 with module function" do
    test "adds an MFA-based run operation" do
      multi =
        Multi.new()
        |> Multi.run(:custom, Kernel, :is_atom, [:test])

      assert Multi.has_operation?(multi, :custom)
    end
  end

  describe "inspect_results/3" do
    test "adds a debug operation that always succeeds" do
      multi =
        Multi.new()
        |> Multi.inspect_results(:debug, fn results -> results end)

      assert Multi.has_operation?(multi, :debug)
    end
  end

  describe "to_ecto_multi/1" do
    test "converts empty multi" do
      ecto_multi = Multi.new() |> Multi.to_ecto_multi()

      assert %Ecto.Multi{} = ecto_multi
    end

    test "converts multi with run operations" do
      ecto_multi =
        Multi.new()
        |> Multi.run(:step, fn _ -> {:ok, :done} end)
        |> Multi.to_ecto_multi()

      assert %Ecto.Multi{} = ecto_multi
    end

    test "converts multi with dynamic operations to Ecto.Multi.merge" do
      ecto_multi =
        Multi.new()
        |> Multi.when_ok(:setup, fn _results -> Multi.new() end)
        |> Multi.to_ecto_multi()

      assert %Ecto.Multi{} = ecto_multi
    end
  end

  describe "Inspect protocol" do
    test "formats empty multi" do
      assert inspect(Multi.new()) == "#OmCrud.Multi<>"
    end

    test "formats multi with operations" do
      multi =
        Multi.new()
        |> Multi.create(:user, SomeSchema, %{})
        |> Multi.create(:account, OtherSchema, %{})

      assert inspect(multi) == "#OmCrud.Multi<user, account>"
    end
  end

  describe "Validatable protocol" do
    test "empty multi is invalid" do
      assert {:error, ["Multi has no operations"]} = OmCrud.Validatable.validate(Multi.new())
    end

    test "non-empty multi is valid" do
      multi = Multi.new() |> Multi.create(:a, SomeSchema, %{})
      assert :ok = OmCrud.Validatable.validate(multi)
    end
  end
end
