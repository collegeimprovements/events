defmodule OmCrud.MultiConditionalTest do
  @moduledoc """
  Tests for OmCrud.Multi conditional operations.

  Tests the conditional helpers: when/3, unless/3, branch/4, each/4,
  when_value/4, and when_match/4.

  ## Use Cases

  - **Conditional creates**: Only create related records when needed
  - **Branching logic**: Different operations based on previous results
  - **Iteration**: Create multiple related records from a list
  - **Pattern matching**: Execute operations based on result patterns
  """

  use ExUnit.Case, async: true

  alias OmCrud.Multi

  describe "when_cond/3 with static boolean" do
    test "executes function when condition is true" do
      multi =
        Multi.new()
        |> Multi.when_cond(true, fn m ->
          Multi.run(m, :executed, fn _ -> {:ok, :yes} end)
        end)

      assert Multi.has_operation?(multi, :executed)
    end

    test "skips function when condition is false" do
      multi =
        Multi.new()
        |> Multi.when_cond(false, fn m ->
          Multi.run(m, :skipped, fn _ -> {:ok, :no} end)
        end)

      refute Multi.has_operation?(multi, :skipped)
    end

    test "handles 2-arity function with true condition" do
      multi =
        Multi.new()
        |> Multi.when_cond(true, fn m, _results ->
          Multi.run(m, :executed, fn _ -> {:ok, :yes} end)
        end)

      assert Multi.has_operation?(multi, :executed)
    end

    test "handles 2-arity function with false condition" do
      multi =
        Multi.new()
        |> Multi.when_cond(false, fn m, _results ->
          Multi.run(m, :skipped, fn _ -> {:ok, :no} end)
        end)

      refute Multi.has_operation?(multi, :skipped)
    end
  end

  describe "when_cond/3 with dynamic condition" do
    test "adds operation when condition function is provided" do
      multi =
        Multi.new()
        |> Multi.run(:check, fn _ -> {:ok, :proceed} end)
        |> Multi.when_cond(
          fn _results -> true end,
          fn m, _results -> Multi.run(m, :after, fn _ -> {:ok, :done} end) end
        )

      # The operation is added (as a :run operation that will evaluate later)
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "unless/3 with static boolean" do
    test "executes function when condition is false" do
      multi =
        Multi.new()
        |> Multi.unless(false, fn m ->
          Multi.run(m, :executed, fn _ -> {:ok, :yes} end)
        end)

      assert Multi.has_operation?(multi, :executed)
    end

    test "skips function when condition is true" do
      multi =
        Multi.new()
        |> Multi.unless(true, fn m ->
          Multi.run(m, :skipped, fn _ -> {:ok, :no} end)
        end)

      refute Multi.has_operation?(multi, :skipped)
    end
  end

  describe "branch/4" do
    test "adds branch operation" do
      multi =
        Multi.new()
        |> Multi.run(:value, fn _ -> {:ok, 10} end)
        |> Multi.branch(
          fn _results -> true end,
          fn m, _results -> Multi.run(m, :true_branch, fn _ -> {:ok, :true} end) end,
          fn m, _results -> Multi.run(m, :false_branch, fn _ -> {:ok, :false} end) end
        )

      # Branch adds a conditional operation
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "each/4 with static list" do
    test "iterates over list and adds operations" do
      multi =
        Multi.new()
        |> Multi.each(:items, [1, 2, 3], fn m, item, index, _results ->
          Multi.run(m, {:item, index}, fn _ -> {:ok, item * 2} end)
        end)

      assert Multi.has_operation?(multi, {:item, 0})
      assert Multi.has_operation?(multi, {:item, 1})
      assert Multi.has_operation?(multi, {:item, 2})
      assert Multi.operation_count(multi) == 3
    end

    test "handles empty list" do
      multi =
        Multi.new()
        |> Multi.each(:items, [], fn m, item, index, _results ->
          Multi.run(m, {:item, index}, fn _ -> {:ok, item} end)
        end)

      assert Multi.operation_count(multi) == 0
    end
  end

  describe "each/4 with dynamic list" do
    test "adds operation for dynamic list generation" do
      multi =
        Multi.new()
        |> Multi.run(:source, fn _ -> {:ok, [1, 2, 3]} end)
        |> Multi.each(:process, fn _results -> [1, 2] end, fn m, item, idx, _results ->
          Multi.run(m, {:processed, idx}, fn _ -> {:ok, item} end)
        end)

      # Dynamic each adds a :run operation
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "when_value/4" do
    test "adds conditional operation based on previous value" do
      multi =
        Multi.new()
        |> Multi.run(:status, fn _ -> {:ok, :active} end)
        |> Multi.when_value(:status, :active, fn m, _results ->
          Multi.run(m, :activated, fn _ -> {:ok, true} end)
        end)

      # Adds the conditional check operation
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "when_match/4" do
    test "adds conditional operation with matcher function" do
      multi =
        Multi.new()
        |> Multi.run(:user, fn _ -> {:ok, %{role: :admin}} end)
        |> Multi.when_match(:user, &(&1.role == :admin), fn m, _results ->
          Multi.run(m, :admin_setup, fn _ -> {:ok, :done} end)
        end)

      # Adds the conditional check operation
      assert Multi.operation_count(multi) == 2
    end
  end

  describe "composition with conditionals" do
    test "can chain multiple conditional operations" do
      send_email? = true
      create_audit? = false

      multi =
        Multi.new()
        |> Multi.run(:user, fn _ -> {:ok, %{id: 1, name: "Test"}} end)
        |> Multi.when_cond(send_email?, fn m ->
          Multi.run(m, :email, fn _ -> {:ok, :sent} end)
        end)
        |> Multi.unless(create_audit?, fn m ->
          Multi.run(m, :skip_audit, fn _ -> {:ok, :skipped} end)
        end)

      assert Multi.has_operation?(multi, :user)
      assert Multi.has_operation?(multi, :email)
      assert Multi.has_operation?(multi, :skip_audit)
    end

    test "conditionals work with other Multi operations" do
      multi =
        Multi.new()
        |> Multi.run(:first, fn _ -> {:ok, 1} end)
        |> Multi.when_cond(true, fn m ->
          Multi.run(m, :second, fn _ -> {:ok, 2} end)
        end)
        |> Multi.run(:third, fn _ -> {:ok, 3} end)

      assert Multi.names(multi) == [:first, :second, :third]
    end
  end
end
