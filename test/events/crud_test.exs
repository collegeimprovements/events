defmodule OmCrudIntegrationTest do
  use ExUnit.Case, async: true

  # Testing OmCrud integration in Events
  alias OmCrud.{Multi, Merge}

  # Test schema for Multi/Merge tests
  defmodule TestSchema do
    use Ecto.Schema

    schema "test" do
      field(:name, :string)
    end

    def changeset(struct, attrs), do: Ecto.Changeset.change(struct, attrs)
    def custom_changeset(struct, attrs), do: Ecto.Changeset.change(struct, attrs)
  end

  # ─────────────────────────────────────────────────────────────
  # Multi Module Tests
  # ─────────────────────────────────────────────────────────────

  describe "Multi.new/0" do
    test "creates empty multi" do
      multi = Multi.new()
      assert multi.operations == []
      assert MapSet.size(multi.names) == 0
    end
  end

  describe "Multi.new/1" do
    test "creates multi with schema" do
      multi = Multi.new(TestSchema)
      assert multi.schema == TestSchema
    end
  end

  describe "Multi.create/5" do
    test "adds create operation" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, %{name: "Test"})

      assert length(multi.operations) == 1
      assert {:user, {:insert, TestSchema, %{name: "Test"}, []}} in multi.operations
      assert MapSet.member?(multi.names, :user)
    end

    test "adds create operation with options" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, %{name: "Test"}, changeset: :custom_changeset)

      [{:user, {:insert, TestSchema, %{name: "Test"}, opts}}] = multi.operations
      assert opts[:changeset] == :custom_changeset
    end

    test "supports function for dynamic attrs" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, fn _results -> %{name: "Dynamic"} end)

      [{:user, {:insert, TestSchema, attrs_fn, []}}] = multi.operations
      assert is_function(attrs_fn, 1)
    end

    test "raises on duplicate name" do
      assert_raise ArgumentError, ~r/already exists/, fn ->
        Multi.new()
        |> Multi.create(:user, TestSchema, %{})
        |> Multi.create(:user, TestSchema, %{})
      end
    end
  end

  describe "Multi.update/5" do
    test "adds update operation with struct" do
      struct = %__MODULE__.TestSchema{id: 1, name: "Old"}

      multi =
        Multi.new()
        |> Multi.update(:user, struct, %{name: "New"})

      assert length(multi.operations) == 1
      assert {:user, {:update, ^struct, %{name: "New"}, []}} = hd(multi.operations)
    end

    test "adds update operation with {schema, id}" do
      multi =
        Multi.new()
        |> Multi.update(:user, {__MODULE__.TestSchema, "uuid-123"}, %{name: "New"})

      [{:user, {:update, {__MODULE__.TestSchema, "uuid-123"}, %{name: "New"}, []}}] =
        multi.operations
    end

    test "adds update operation with function" do
      multi =
        Multi.new()
        |> Multi.update(:confirm, fn %{user: u} -> u end, %{confirmed: true})

      [{:confirm, {:update, fun, %{confirmed: true}, []}}] = multi.operations
      assert is_function(fun, 1)
    end
  end

  describe "Multi.delete/4" do
    test "adds delete operation with struct" do
      struct = %__MODULE__.TestSchema{id: 1, name: "Test"}

      multi =
        Multi.new()
        |> Multi.delete(:user, struct)

      assert {:user, {:delete, ^struct, []}} = hd(multi.operations)
    end
  end

  describe "Multi introspection" do
    test "names/1 returns all operation names" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, %{})
        |> Multi.create(:account, TestSchema, %{})

      names = Multi.names(multi)
      assert :user in names
      assert :account in names
    end

    test "operation_count/1 returns count" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, %{})
        |> Multi.create(:account, TestSchema, %{})

      assert Multi.operation_count(multi) == 2
    end

    test "has_operation?/2 checks for name" do
      multi = Multi.new() |> Multi.create(:user, TestSchema, %{})

      assert Multi.has_operation?(multi, :user)
      refute Multi.has_operation?(multi, :account)
    end

    test "empty?/1 checks if empty" do
      assert Multi.empty?(Multi.new())
      refute Multi.empty?(Multi.new() |> Multi.create(:user, TestSchema, %{}))
    end
  end

  describe "Multi.append/2 and prepend/2" do
    test "append combines multis" do
      multi1 = Multi.new() |> Multi.create(:user, TestSchema, %{})
      multi2 = Multi.new() |> Multi.create(:account, TestSchema, %{})

      combined = Multi.append(multi1, multi2)

      assert Multi.operation_count(combined) == 2
      names = Multi.names(combined)
      assert :user in names
      assert :account in names
    end

    test "prepend combines multis" do
      multi1 = Multi.new() |> Multi.create(:user, TestSchema, %{})
      multi2 = Multi.new() |> Multi.create(:account, TestSchema, %{})

      combined = Multi.prepend(multi1, multi2)

      assert Multi.operation_count(combined) == 2
      # Order should be: account first, then user
      [{first_name, _}, {second_name, _}] = combined.operations
      assert first_name == :account
      assert second_name == :user
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Merge Module Tests
  # ─────────────────────────────────────────────────────────────

  describe "Merge.new/1" do
    test "creates merge with schema" do
      merge = Merge.new(TestSchema)
      assert merge.schema == TestSchema
    end
  end

  describe "Merge.new/2" do
    test "creates merge with schema and source data" do
      data = [%{name: "Test1"}, %{name: "Test2"}]
      merge = Merge.new(TestSchema, data)
      assert merge.schema == TestSchema
      assert merge.source == data
    end
  end

  describe "Merge.source/2" do
    test "sets source data" do
      data = [%{name: "Test"}]

      merge =
        Merge.new(TestSchema)
        |> Merge.source(data)

      assert merge.source == data
    end
  end

  describe "Merge.match_on/2" do
    test "sets single match column" do
      merge =
        Merge.new(TestSchema)
        |> Merge.match_on(:email)

      assert merge.match_on == [:email]
    end

    test "sets multiple match columns" do
      merge =
        Merge.new(TestSchema)
        |> Merge.match_on([:org_id, :email])

      assert merge.match_on == [:org_id, :email]
    end
  end

  describe "Merge.when_matched/2" do
    test "adds update all clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_matched(:update)

      assert [{:always, :update}] = merge.when_matched
    end

    test "adds update specific fields clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_matched(:update, [:name, :updated_at])

      assert [{:always, {:update, [:name, :updated_at]}}] = merge.when_matched
    end

    test "adds delete clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_matched(:delete)

      assert [{:always, :delete}] = merge.when_matched
    end

    test "adds nothing clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_matched(:nothing)

      assert [{:always, :nothing}] = merge.when_matched
    end

    test "adds conditional clause" do
      condition = fn _row -> true end

      merge =
        Merge.new(TestSchema)
        |> Merge.when_matched(condition, :update)

      assert [{^condition, :update}] = merge.when_matched
    end
  end

  describe "Merge.when_not_matched/2" do
    test "adds insert clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_not_matched(:insert)

      assert [{:always, :insert}] = merge.when_not_matched
    end

    test "adds insert clause with defaults" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_not_matched(:insert, %{status: :pending})

      assert [{:always, {:insert, %{status: :pending}}}] = merge.when_not_matched
    end

    test "adds nothing clause" do
      merge =
        Merge.new(TestSchema)
        |> Merge.when_not_matched(:nothing)

      assert [{:always, :nothing}] = merge.when_not_matched
    end

    test "adds conditional clause" do
      condition = fn _row -> true end

      merge =
        Merge.new(TestSchema)
        |> Merge.when_not_matched(condition, :insert)

      assert [{^condition, :insert}] = merge.when_not_matched
    end
  end

  describe "Merge.returning/2" do
    test "sets returning fields" do
      merge =
        Merge.new(TestSchema)
        |> Merge.returning([:id, :email])

      assert merge.returning == [:id, :email]
    end

    test "sets returning to true for all" do
      merge =
        Merge.new(TestSchema)
        |> Merge.returning(true)

      assert merge.returning == true
    end

    test "sets returning to false" do
      merge =
        Merge.new(TestSchema)
        |> Merge.returning(false)

      assert merge.returning == false
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Protocol Tests
  # ─────────────────────────────────────────────────────────────

  describe "Validatable protocol for Multi" do
    alias OmCrud.Validatable

    test "returns error for empty multi" do
      assert {:error, errors} = Validatable.validate(Multi.new())
      assert "Multi has no operations" in errors
    end

    test "validates multi with operations as ok" do
      multi = Multi.new() |> Multi.create(:user, TestSchema, %{})
      assert Validatable.validate(multi) == :ok
    end
  end

  describe "Validatable protocol for Merge" do
    alias OmCrud.Validatable

    test "validates complete merge as ok" do
      merge =
        Merge.new(TestSchema, [%{name: "Test"}])
        |> Merge.match_on(:email)
        |> Merge.when_matched(:update)
        |> Merge.when_not_matched(:insert)

      assert Validatable.validate(merge) == :ok
    end

    test "returns error when source is missing" do
      merge =
        Merge.new(TestSchema)
        |> Merge.match_on(:email)
        |> Merge.when_matched(:update)

      assert {:error, errors} = Validatable.validate(merge)
      assert "Merge must have a source" in errors
    end

    test "returns error when match_on is missing" do
      merge =
        Merge.new(TestSchema, [%{name: "Test"}])
        |> Merge.when_matched(:update)

      assert {:error, errors} = Validatable.validate(merge)
      assert "Merge must specify match_on columns" in errors
    end

    test "returns error when no clauses defined" do
      merge =
        Merge.new(TestSchema, [%{name: "Test"}])
        |> Merge.match_on(:email)

      assert {:error, errors} = Validatable.validate(merge)
      assert "Merge must have at least one WHEN clause" in errors
    end
  end

  describe "Debuggable protocol for Multi" do
    alias OmCrud.Debuggable

    test "returns debug info" do
      multi =
        Multi.new()
        |> Multi.create(:user, TestSchema, %{name: "Test"})
        |> Multi.create(:account, TestSchema, %{})

      debug = Debuggable.to_debug(multi)

      assert debug.type == :multi
      assert debug.count == 2
      assert :user in debug.operations
      assert :account in debug.operations
    end
  end

  describe "Debuggable protocol for Merge" do
    alias OmCrud.Debuggable

    test "returns debug info" do
      merge =
        Merge.new(TestSchema, [%{name: "Test"}])
        |> Merge.match_on([:org_id, :email])
        |> Merge.when_matched(:update)
        |> Merge.when_not_matched(:insert)

      debug = Debuggable.to_debug(merge)

      assert debug.type == :merge
      assert debug.schema == TestSchema
      assert debug.match_on == [:org_id, :email]
      assert debug.when_matched_count == 1
      assert debug.when_not_matched_count == 1
    end
  end
end
