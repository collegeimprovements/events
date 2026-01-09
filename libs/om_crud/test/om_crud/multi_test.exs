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

  describe "names/1" do
    test "returns empty list for new multi" do
      multi = Multi.new()

      assert Multi.names(multi) == []
    end
  end

  describe "operation_count/1" do
    test "returns 0 for new multi" do
      multi = Multi.new()

      assert Multi.operation_count(multi) == 0
    end
  end

  describe "empty?/1" do
    test "returns true for new multi" do
      multi = Multi.new()

      assert Multi.empty?(multi) == true
    end
  end

  describe "has_operation?/2" do
    test "returns false for non-existent operation" do
      multi = Multi.new()

      assert Multi.has_operation?(multi, :some_op) == false
    end
  end

  describe "append/2" do
    test "combines two multi tokens" do
      multi1 = Multi.new()
      multi2 = Multi.new()

      combined = Multi.append(multi1, multi2)

      assert %Multi{} = combined
    end
  end

  describe "prepend/2" do
    test "prepends operations from second multi" do
      multi1 = Multi.new()
      multi2 = Multi.new()

      combined = Multi.prepend(multi1, multi2)

      assert %Multi{} = combined
    end
  end
end
