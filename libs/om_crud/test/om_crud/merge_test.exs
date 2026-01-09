defmodule OmCrud.MergeTest do
  @moduledoc """
  Tests for OmCrud.Merge - PostgreSQL MERGE operations for complex upserts.

  Merge provides a fluent API for building SQL MERGE statements, enabling
  sophisticated insert/update/delete logic in a single query.

  ## Use Cases

  - **Sync external data**: Match on external_id, update if exists, insert if new
  - **Inventory updates**: Match on SKU, update quantities, insert new products
  - **User imports**: Match on email, update profiles, skip duplicates
  - **Deactivation**: Match on criteria, delete matches, ignore non-matches

  ## Pattern: Fluent MERGE Builder

      User
      |> Merge.new(users_from_api)
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name, :updated_at])
      |> Merge.when_not_matched(:insert)
      |> Merge.returning([:id, :email])
      |> OmCrud.run()

  MERGE is more efficient than separate SELECT + INSERT/UPDATE for bulk syncs.
  """

  use ExUnit.Case, async: true

  alias OmCrud.Merge
  # OmCrud.Merge delegates to OmQuery.Merge, so struct assertions use the underlying type
  alias OmQuery.Merge, as: MergeStruct

  defmodule TestSchema do
    use Ecto.Schema

    schema "test_table" do
      field :name, :string
      field :email, :string
      field :active, :boolean
    end
  end

  describe "new/1" do
    test "creates merge token with schema" do
      merge = Merge.new(TestSchema)

      assert %MergeStruct{} = merge
      assert merge.schema == TestSchema
    end
  end

  describe "new/2" do
    test "creates merge token with schema and source data" do
      source = [%{name: "Alice", email: "alice@test.com"}]
      merge = Merge.new(TestSchema, source)

      assert %MergeStruct{} = merge
      assert merge.schema == TestSchema
      assert merge.source == source
    end
  end

  describe "source/2" do
    test "sets source data on merge token" do
      source = [%{name: "Bob", email: "bob@test.com"}]

      merge =
        TestSchema
        |> Merge.new()
        |> Merge.source(source)

      assert merge.source == source
    end
  end

  describe "match_on/2" do
    test "sets match columns as single atom" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.match_on(:email)

      assert merge.match_on == [:email]
    end

    test "sets match columns as list" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.match_on([:email, :name])

      assert merge.match_on == [:email, :name]
    end
  end

  describe "when_matched/2" do
    test "adds matched clause with :update action" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_matched(:update)

      assert length(merge.when_matched) == 1
    end

    test "adds matched clause with :delete action" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_matched(:delete)

      assert length(merge.when_matched) == 1
    end

    test "adds matched clause with :nothing action" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_matched(:nothing)

      assert length(merge.when_matched) == 1
    end
  end

  describe "when_matched/3" do
    test "adds matched clause with update and specific fields" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_matched(:update, [:name, :active])

      assert length(merge.when_matched) == 1
    end
  end

  describe "when_not_matched/2" do
    test "adds not matched clause with :insert action" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_not_matched(:insert)

      assert length(merge.when_not_matched) == 1
    end

    test "adds not matched clause with :nothing action" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_not_matched(:nothing)

      assert length(merge.when_not_matched) == 1
    end
  end

  describe "returning/2" do
    test "sets returning fields" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.returning([:id, :name])

      assert merge.returning == [:id, :name]
    end

    test "sets returning to true for all fields" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.returning(true)

      assert merge.returning == true
    end
  end

  describe "opts/2" do
    test "sets additional options" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.opts(timeout: 30_000, prefix: "tenant_1")

      assert merge.opts[:timeout] == 30_000
      assert merge.opts[:prefix] == "tenant_1"
    end
  end

  describe "has_matched_clauses?/1" do
    test "returns false for new merge" do
      merge = Merge.new(TestSchema)

      assert Merge.has_matched_clauses?(merge) == false
    end

    test "returns true when matched clause added" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_matched(:update)

      assert Merge.has_matched_clauses?(merge) == true
    end
  end

  describe "has_not_matched_clauses?/1" do
    test "returns false for new merge" do
      merge = Merge.new(TestSchema)

      assert Merge.has_not_matched_clauses?(merge) == false
    end

    test "returns true when not matched clause added" do
      merge =
        TestSchema
        |> Merge.new()
        |> Merge.when_not_matched(:insert)

      assert Merge.has_not_matched_clauses?(merge) == true
    end
  end

  describe "source_count/1" do
    test "returns 0 for merge without source" do
      merge = Merge.new(TestSchema)

      assert Merge.source_count(merge) == 0
    end

    test "returns count of source records" do
      source = [
        %{name: "Alice", email: "alice@test.com"},
        %{name: "Bob", email: "bob@test.com"}
      ]

      merge = Merge.new(TestSchema, source)

      assert Merge.source_count(merge) == 2
    end
  end

  describe "builder pattern" do
    test "supports fluent chaining" do
      source = [%{name: "Alice", email: "alice@test.com"}]

      merge =
        TestSchema
        |> Merge.new(source)
        |> Merge.match_on(:email)
        |> Merge.when_matched(:update, [:name])
        |> Merge.when_not_matched(:insert)
        |> Merge.returning([:id, :name, :email])

      assert merge.schema == TestSchema
      assert merge.source == source
      assert merge.match_on == [:email]
      assert length(merge.when_matched) == 1
      assert length(merge.when_not_matched) == 1
      assert merge.returning == [:id, :name, :email]
    end
  end
end
