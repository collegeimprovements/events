defmodule Events.CRUDTest do
  use ExUnit.Case, async: true

  describe "token composition" do
    test "creates empty token" do
      token = Events.CRUD.Token.new()
      assert token.operations == []
      assert token.validated == false
      assert token.optimized == false
    end

    test "creates token with schema" do
      token = Events.CRUD.Token.new(SomeSchema)
      assert token.operations == [{:schema, SomeSchema}]
    end

    test "adds operations" do
      token =
        Events.CRUD.Token.new()
        |> Events.CRUD.Token.add({:where, {:status, :eq, "active", []}})
        |> Events.CRUD.Token.add({:order, {:created_at, :desc, []}})

      assert length(token.operations) == 2

      assert token.operations == [
               {:where, {:status, :eq, "active", []}},
               {:order, {:created_at, :desc, []}}
             ]
    end

    test "removes operations" do
      token =
        Events.CRUD.Token.new()
        |> Events.CRUD.Token.add({:where, {:status, :eq, "active", []}})
        |> Events.CRUD.Token.add({:order, {:created_at, :desc, []}})
        |> Events.CRUD.Token.remove(:where)

      assert length(token.operations) == 1
      assert token.operations == [{:order, {:created_at, :desc, []}}]
    end
  end

  describe "result shapes" do
    test "success result" do
      result = Events.CRUD.Result.success([1, 2, 3], %{custom: "data"})
      assert result.success == true
      assert result.data == [1, 2, 3]
      assert result.metadata.pagination.type == nil
      assert result.metadata.timing.total_time == 0
    end

    test "error result" do
      result = Events.CRUD.Result.error(:not_found, %{custom: "data"})
      assert result.success == false
      assert result.error == :not_found
      assert result.metadata.pagination.has_more == false
    end
  end
end
