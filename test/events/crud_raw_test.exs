defmodule Events.CRUD.RawTest do
  use ExUnit.Case, async: true

  describe "named placeholders" do
    test "processes simple named placeholders" do
      sql = "SELECT * FROM users WHERE status = :status AND age >= :min_age"
      params = %{status: "active", min_age: 18}

      {processed_sql, positional_params} = Events.CRUD.NamedPlaceholders.process(sql, params)

      assert processed_sql == "SELECT * FROM users WHERE status = ? AND age >= ?"
      assert positional_params == ["active", 18]
    end

    test "validates required parameters" do
      sql = "SELECT * FROM users WHERE status = :status AND age >= :min_age"
      # missing min_age
      params = %{status: "active"}

      assert {:error, "Missing required parameters: min_age"} =
               Events.CRUD.NamedPlaceholders.validate_params(
                 ["status", "min_age"],
                 Map.keys(params)
               )
    end

    test "handles repeated parameters" do
      sql = "SELECT * FROM users WHERE age BETWEEN :min_age AND :max_age"
      params = %{min_age: 18, max_age: 65}

      {processed_sql, positional_params} = Events.CRUD.NamedPlaceholders.process(sql, params)

      assert processed_sql == "SELECT * FROM users WHERE age BETWEEN ? AND ?"
      assert positional_params == [18, 65]
    end
  end

  describe "raw operations" do
    test "raw SQL operation validation" do
      # Valid raw SQL
      assert :ok = Events.CRUD.Operations.Raw.validate_spec({:sql, "SELECT 1", %{}})

      # Invalid type
      assert {:error, "Raw type must be :sql or :fragment"} =
               Events.CRUD.Operations.Raw.validate_spec({:invalid, "SELECT 1", %{}})
    end
  end
end
