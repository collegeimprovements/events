defmodule Events.Infra.Scheduler.Workflow.Step.ExecutableTest do
  use ExUnit.Case, async: true

  alias Events.Infra.Scheduler.Workflow.Step.Executable

  # Test module implementing perform/1
  defmodule TestWorker do
    def perform(%{value: v}) do
      {:ok, %{result: v * 2}}
    end

    def perform(%{fail: reason}) do
      {:error, reason}
    end
  end

  # Test module with rollback
  defmodule TestWorkerWithRollback do
    def perform(ctx) do
      {:ok, %{processed: true, input: ctx.input}}
    end

    def rollback(_ctx) do
      :ok
    end
  end

  # Test module that raises
  defmodule RaisingWorker do
    def perform(_ctx) do
      raise "intentional error"
    end
  end

  # Test module that throws
  defmodule ThrowingWorker do
    def perform(_ctx) do
      throw(:thrown_value)
    end
  end

  # Test module that exits
  defmodule ExitingWorker do
    def perform(_ctx) do
      exit(:exit_reason)
    end
  end

  # Test module without perform/1
  defmodule IncompleteWorker do
    def other_function(_ctx), do: :ok
  end

  describe "Function implementation" do
    test "executes anonymous function" do
      fun = fn ctx -> {:ok, %{result: ctx.input * 2}} end
      assert {:ok, %{result: 10}} = Executable.execute(fun, %{input: 5})
    end

    test "returns :ok from function" do
      fun = fn _ctx -> :ok end
      assert :ok = Executable.execute(fun, %{})
    end

    test "returns error from function" do
      fun = fn _ctx -> {:error, :something_wrong} end
      assert {:error, :something_wrong} = Executable.execute(fun, %{})
    end

    test "catches exceptions in function" do
      fun = fn _ctx -> raise "boom" end
      assert {:error, {:exception, %RuntimeError{}, _stacktrace}} = Executable.execute(fun, %{})
    end

    test "catches throws in function" do
      fun = fn _ctx -> throw(:thrown) end
      assert {:error, {:throw, :thrown}} = Executable.execute(fun, %{})
    end

    test "catches exits in function" do
      fun = fn _ctx -> exit(:exited) end
      assert {:error, {:exit, :exited}} = Executable.execute(fun, %{})
    end

    test "rollback returns :ok for functions" do
      fun = fn _ctx -> :ok end
      assert :ok = Executable.rollback(fun, %{})
    end

    test "has_rollback? returns false for functions" do
      fun = fn _ctx -> :ok end
      refute Executable.has_rollback?(fun)
    end
  end

  describe "Atom (Module) implementation" do
    test "executes module with perform/1" do
      assert {:ok, %{result: 20}} = Executable.execute(TestWorker, %{value: 10})
    end

    test "returns error from module" do
      assert {:error, :bad_input} = Executable.execute(TestWorker, %{fail: :bad_input})
    end

    test "catches exceptions in module" do
      assert {:error, {:exception, %RuntimeError{}, _}} = Executable.execute(RaisingWorker, %{})
    end

    test "catches throws in module" do
      assert {:error, {:throw, :thrown_value}} = Executable.execute(ThrowingWorker, %{})
    end

    test "catches exits in module" do
      assert {:error, {:exit, :exit_reason}} = Executable.execute(ExitingWorker, %{})
    end

    test "returns error for module without perform/1" do
      assert {:error, {:undefined_function, {IncompleteWorker, :perform, 1}}} =
               Executable.execute(IncompleteWorker, %{})
    end

    test "rollback executes module rollback/1" do
      assert :ok = Executable.rollback(TestWorkerWithRollback, %{})
    end

    test "rollback returns :ok when no rollback function" do
      assert :ok = Executable.rollback(TestWorker, %{})
    end

    test "has_rollback? returns true when module has rollback/1" do
      assert Executable.has_rollback?(TestWorkerWithRollback)
    end

    test "has_rollback? returns false when module lacks rollback/1" do
      refute Executable.has_rollback?(TestWorker)
    end
  end

  describe "Tuple implementation" do
    test "executes {:function, module, function_name}" do
      defmodule TupleTestModule do
        def my_step(ctx), do: {:ok, %{doubled: ctx.value * 2}}
      end

      result = Executable.execute({:function, TupleTestModule, :my_step}, %{value: 5})
      assert {:ok, %{doubled: 10}} = result
    end

    test "catches exceptions in {:function, ...} tuple" do
      defmodule RaisingTupleModule do
        def failing_step(_ctx), do: raise("boom")
      end

      result = Executable.execute({:function, RaisingTupleModule, :failing_step}, %{})
      assert {:error, {:exception, %RuntimeError{}, _}} = result
    end

    test "executes {module, function} tuple" do
      defmodule MFModule do
        def process(ctx), do: {:ok, %{processed: ctx.input}}
      end

      result = Executable.execute({MFModule, :process}, %{input: "test"})
      assert {:ok, %{processed: "test"}} = result
    end

    test "executes {module, function, args} tuple" do
      defmodule MFAModule do
        def process(ctx, multiplier, offset) do
          {:ok, %{result: ctx.value * multiplier + offset}}
        end
      end

      result = Executable.execute({MFAModule, :process, [2, 10]}, %{value: 5})
      assert {:ok, %{result: 20}} = result
    end

    test "rollback returns :ok for {:function, ...} tuple" do
      assert :ok = Executable.rollback({:function, TestWorker, :perform}, %{})
    end

    test "rollback returns :ok for {:nested_workflow, ...} tuple" do
      assert :ok =
               Executable.rollback(
                 {:nested_workflow, :some_workflow, SomeModule, :get_context},
                 %{}
               )
    end

    test "rollback returns :ok for {:workflow, ...} tuple" do
      assert :ok = Executable.rollback({:workflow, :some_workflow}, %{})
    end

    test "rollback delegates to module for {module, function} tuple" do
      result = Executable.rollback({TestWorkerWithRollback, :perform}, %{})
      assert :ok = result
    end

    test "rollback delegates to module for {module, function, args} tuple" do
      result = Executable.rollback({TestWorkerWithRollback, :perform, []}, %{})
      assert :ok = result
    end

    test "has_rollback? returns false for {:function, ...}" do
      refute Executable.has_rollback?({:function, TestWorker, :perform})
    end

    test "has_rollback? returns false for {:nested_workflow, ...}" do
      refute Executable.has_rollback?({:nested_workflow, :wf, Mod, :fn})
    end

    test "has_rollback? returns false for {:workflow, ...}" do
      refute Executable.has_rollback?({:workflow, :wf})
    end

    test "has_rollback? delegates to module for {module, function}" do
      assert Executable.has_rollback?({TestWorkerWithRollback, :perform})
      refute Executable.has_rollback?({TestWorker, :perform})
    end

    test "has_rollback? delegates to module for {module, function, args}" do
      assert Executable.has_rollback?({TestWorkerWithRollback, :perform, []})
      refute Executable.has_rollback?({TestWorker, :perform, []})
    end
  end

  describe "return values" do
    test "handles {:ok, map} return" do
      fun = fn _ctx -> {:ok, %{key: "value"}} end
      assert {:ok, %{key: "value"}} = Executable.execute(fun, %{})
    end

    test "handles :ok return" do
      fun = fn _ctx -> :ok end
      assert :ok = Executable.execute(fun, %{})
    end

    test "handles {:error, reason} return" do
      fun = fn _ctx -> {:error, :bad_request} end
      assert {:error, :bad_request} = Executable.execute(fun, %{})
    end

    test "handles {:skip, reason} return" do
      fun = fn _ctx -> {:skip, :condition_not_met} end
      assert {:skip, :condition_not_met} = Executable.execute(fun, %{})
    end

    test "handles {:await, opts} return" do
      fun = fn _ctx -> {:await, notify: :email, timeout: 3600} end
      assert {:await, notify: :email, timeout: 3600} = Executable.execute(fun, %{})
    end

    test "handles {:expand, steps} return" do
      fun = fn ctx ->
        expansions =
          Enum.map(ctx.items, fn item ->
            {:"process_#{item}", fn _ -> {:ok, %{item: item}} end}
          end)

        {:expand, expansions}
      end

      result = Executable.execute(fun, %{items: [1, 2, 3]})
      assert {:expand, expansions} = result
      assert length(expansions) == 3
    end

    test "handles {:snooze, duration} return" do
      fun = fn _ctx -> {:snooze, {30, :minutes}} end
      assert {:snooze, {30, :minutes}} = Executable.execute(fun, %{})
    end
  end

  describe "context passing" do
    test "passes full context to function" do
      context = %{user_id: 123, order_id: 456, data: %{items: [1, 2, 3]}}

      fun = fn ctx ->
        assert ctx == context
        :ok
      end

      Executable.execute(fun, context)
    end

    test "passes full context to module" do
      defmodule ContextCheckModule do
        def perform(ctx) do
          send(self(), {:received_context, ctx})
          :ok
        end
      end

      context = %{user: "test", amount: 100}
      Executable.execute(ContextCheckModule, context)

      assert_receive {:received_context, ^context}
    end
  end
end
