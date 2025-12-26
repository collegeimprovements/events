defmodule OmScheduler.Workflow.StateMachineTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Workflow
  alias OmScheduler.Workflow.{Step, Execution, StateMachine}

  # Helper to create a test workflow
  defp build_workflow(steps_spec) do
    Enum.reduce(steps_spec, Workflow.new(:test), fn
      {name, opts}, acc ->
        Workflow.step(acc, name, fn _ -> :ok end, opts)

      name, acc when is_atom(name) ->
        Workflow.step(acc, name, fn _ -> :ok end)
    end)
    |> Workflow.build!()
  end

  # Helper to start execution with a workflow
  defp start_execution(workflow) do
    step_names = Map.keys(workflow.steps)
    Execution.new(workflow.name) |> Execution.start(step_names)
  end

  describe "transition_workflow/2" do
    test "pending can transition to running" do
      exec = Execution.new(:test)
      assert {:ok, %{state: :running}} = StateMachine.transition_workflow(exec, :running)
    end

    test "pending can transition to cancelled" do
      exec = Execution.new(:test)
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_workflow(exec, :cancelled)
    end

    test "running can transition to completed" do
      exec = %{Execution.new(:test) | state: :running}
      assert {:ok, %{state: :completed}} = StateMachine.transition_workflow(exec, :completed)
    end

    test "running can transition to failed" do
      exec = %{Execution.new(:test) | state: :running}
      assert {:ok, %{state: :failed}} = StateMachine.transition_workflow(exec, :failed)
    end

    test "running can transition to cancelled" do
      exec = %{Execution.new(:test) | state: :running}
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_workflow(exec, :cancelled)
    end

    test "running can transition to paused" do
      exec = %{Execution.new(:test) | state: :running}
      assert {:ok, %{state: :paused}} = StateMachine.transition_workflow(exec, :paused)
    end

    test "paused can transition to running" do
      exec = %{Execution.new(:test) | state: :paused}
      assert {:ok, %{state: :running}} = StateMachine.transition_workflow(exec, :running)
    end

    test "paused can transition to cancelled" do
      exec = %{Execution.new(:test) | state: :paused}
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_workflow(exec, :cancelled)
    end

    test "completed is terminal" do
      exec = %{Execution.new(:test) | state: :completed}

      assert {:error, {:invalid_transition, :completed, :running}} =
               StateMachine.transition_workflow(exec, :running)
    end

    test "failed is terminal" do
      exec = %{Execution.new(:test) | state: :failed}

      assert {:error, {:invalid_transition, :failed, :running}} =
               StateMachine.transition_workflow(exec, :running)
    end

    test "cancelled is terminal" do
      exec = %{Execution.new(:test) | state: :cancelled}

      assert {:error, {:invalid_transition, :cancelled, :running}} =
               StateMachine.transition_workflow(exec, :running)
    end
  end

  describe "transition_step/2" do
    test "pending can transition to ready" do
      step = Step.new(:test, fn _ -> :ok end)
      assert {:ok, %{state: :ready}} = StateMachine.transition_step(step, :ready)
    end

    test "pending can transition to running" do
      step = Step.new(:test, fn _ -> :ok end)
      assert {:ok, %{state: :running}} = StateMachine.transition_step(step, :running)
    end

    test "pending can transition to skipped" do
      step = Step.new(:test, fn _ -> :ok end)
      assert {:ok, %{state: :skipped}} = StateMachine.transition_step(step, :skipped)
    end

    test "pending can transition to cancelled" do
      step = Step.new(:test, fn _ -> :ok end)
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_step(step, :cancelled)
    end

    test "ready can transition to running" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :ready}
      assert {:ok, %{state: :running}} = StateMachine.transition_step(step, :running)
    end

    test "running can transition to completed" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      assert {:ok, %{state: :completed}} = StateMachine.transition_step(step, :completed)
    end

    test "running can transition to failed" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      assert {:ok, %{state: :failed}} = StateMachine.transition_step(step, :failed)
    end

    test "running can transition to cancelled" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_step(step, :cancelled)
    end

    test "running can transition to awaiting" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      assert {:ok, %{state: :awaiting}} = StateMachine.transition_step(step, :awaiting)
    end

    test "awaiting can transition back to running" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :awaiting}
      assert {:ok, %{state: :running}} = StateMachine.transition_step(step, :running)
    end

    test "awaiting can transition to cancelled" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :awaiting}
      assert {:ok, %{state: :cancelled}} = StateMachine.transition_step(step, :cancelled)
    end

    test "awaiting can transition back to pending (for resume)" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :awaiting}
      assert {:ok, %{state: :pending}} = StateMachine.transition_step(step, :pending)
    end

    test "failed can transition to pending (for retry)" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :failed}
      assert {:ok, %{state: :pending}} = StateMachine.transition_step(step, :pending)
    end

    test "completed is terminal" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :completed}

      assert {:error, {:invalid_transition, :completed, :running}} =
               StateMachine.transition_step(step, :running)
    end

    test "skipped is terminal" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :skipped}

      assert {:error, {:invalid_transition, :skipped, :running}} =
               StateMachine.transition_step(step, :running)
    end

    test "cancelled is terminal" do
      step = %{Step.new(:test, fn _ -> :ok end) | state: :cancelled}

      assert {:error, {:invalid_transition, :cancelled, :running}} =
               StateMachine.transition_step(step, :running)
    end
  end

  describe "get_ready_steps/2" do
    test "returns steps with no dependencies" do
      workflow = build_workflow([:a, :b, :c])
      exec = start_execution(workflow)

      ready = StateMachine.get_ready_steps(workflow, exec)

      assert :a in ready
      assert :b in ready
      assert :c in ready
    end

    test "returns steps with satisfied dependencies" do
      workflow =
        build_workflow([
          :a,
          {:b, after: :a},
          {:c, after: :b}
        ])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      ready = StateMachine.get_ready_steps(workflow, exec)

      assert :b in ready
      refute :c in ready
    end

    test "returns steps with all dependencies satisfied" do
      workflow =
        build_workflow([
          :a,
          :b,
          {:c, after: [:a, :b]}
        ])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      ready = StateMachine.get_ready_steps(workflow, exec)

      # c is not ready because b is not completed
      refute :c in ready
      assert :b in ready
    end

    test "handles after_any dependencies" do
      # after_any uses depends_on_any which is set on the Step struct directly,
      # not via adjacency list dependencies. The StateMachine checks this separately.
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end)
        |> Workflow.step(:c, fn _ -> :ok end, after_any: [:a, :b])
        |> Workflow.build!()

      # When both a and b are pending, c should not be ready
      exec = start_execution(workflow)
      ready = StateMachine.get_ready_steps(workflow, exec)
      refute :c in ready

      # When a is completed, c should be ready (after_any satisfied)
      exec =
        exec
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      ready = StateMachine.get_ready_steps(workflow, exec)

      # c is ready because a is completed (after_any)
      assert :c in ready
    end

    test "excludes non-pending steps" do
      workflow = build_workflow([:a, :b, :c])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)

      ready = StateMachine.get_ready_steps(workflow, exec)

      # running
      refute :a in ready
      # pending
      assert :b in ready
      # pending
      assert :c in ready
    end

    test "handles group dependencies" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, group: :parallel)
        |> Workflow.step(:b, fn _ -> :ok end, group: :parallel)
        |> Workflow.step(:c, fn _ -> :ok end, after_group: :parallel)
        |> Workflow.build!()

      # Start with only :a completed
      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      ready = StateMachine.get_ready_steps(workflow, exec)
      # group not fully completed
      refute :c in ready

      # Now complete :b too
      exec =
        exec
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)

      ready = StateMachine.get_ready_steps(workflow, exec)
      # group fully completed
      assert :c in ready
    end
  end

  describe "get_completed_groups/2" do
    test "returns empty map when no groups" do
      workflow = build_workflow([:a, :b])
      exec = start_execution(workflow)

      groups = StateMachine.get_completed_groups(workflow, exec)
      assert groups == %{}
    end

    test "returns false for incomplete group" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, group: :uploads)
        |> Workflow.step(:b, fn _ -> :ok end, group: :uploads)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      groups = StateMachine.get_completed_groups(workflow, exec)
      assert groups[:uploads] == false
    end

    test "returns true for completed group" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, group: :uploads)
        |> Workflow.step(:b, fn _ -> :ok end, group: :uploads)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)

      groups = StateMachine.get_completed_groups(workflow, exec)
      assert groups[:uploads] == true
    end

    test "counts skipped steps as completed for group" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, group: :uploads)
        |> Workflow.step(:b, fn _ -> :ok end, group: :uploads)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_skipped(:b)

      groups = StateMachine.get_completed_groups(workflow, exec)
      assert groups[:uploads] == true
    end
  end

  describe "workflow_complete?/2" do
    test "returns false when steps are pending" do
      workflow = build_workflow([:a, :b])
      exec = start_execution(workflow)

      refute StateMachine.workflow_complete?(workflow, exec)
    end

    test "returns false when steps are running" do
      workflow = build_workflow([:a, :b])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)

      refute StateMachine.workflow_complete?(workflow, exec)
    end

    test "returns true when all steps completed" do
      workflow = build_workflow([:a, :b])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)

      assert StateMachine.workflow_complete?(workflow, exec)
    end

    test "returns true when all steps in terminal state" do
      workflow = build_workflow([:a, :b, :c])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_skipped(:b)
        |> Execution.step_cancelled(:c)

      assert StateMachine.workflow_complete?(workflow, exec)
    end

    test "considers graft expansions" do
      # Build a simple workflow with just prepare step
      workflow = build_workflow([:prepare])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:prepare)
        |> Execution.step_completed(:prepare, :ok)
        |> Execution.record_graft_expansion(:batch, [:item_1, :item_2])

      # Not complete - expanded steps pending
      refute StateMachine.workflow_complete?(workflow, exec)

      # Complete expanded steps
      exec =
        exec
        |> Execution.step_started(:item_1)
        |> Execution.step_completed(:item_1, :ok)
        |> Execution.step_started(:item_2)
        |> Execution.step_completed(:item_2, :ok)

      assert StateMachine.workflow_complete?(workflow, exec)
    end
  end

  describe "has_failures?/1" do
    test "returns false when no failures" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      refute StateMachine.has_failures?(exec)
    end

    test "returns true when step failed" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      assert StateMachine.has_failures?(exec)
    end
  end

  describe "get_failed_steps/1" do
    test "returns empty list when no failures" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      assert StateMachine.get_failed_steps(exec) == []
    end

    test "returns list of failed steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b, :c])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)
        |> Execution.step_started(:c)
        |> Execution.step_failed(:c, :timeout)

      failed = StateMachine.get_failed_steps(exec)
      assert :a in failed
      assert :c in failed
      refute :b in failed
    end
  end

  describe "should_fail?/2" do
    test "returns true when failed step has on_error: :fail" do
      workflow = build_workflow([{:a, on_error: :fail}])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      assert StateMachine.should_fail?(workflow, exec)
    end

    test "returns false when failed step has on_error: :skip" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, on_error: :skip)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      refute StateMachine.should_fail?(workflow, exec)
    end

    test "returns false when failed step has on_error: :continue" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, on_error: :continue)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      refute StateMachine.should_fail?(workflow, exec)
    end
  end

  describe "is_awaiting?/1" do
    test "returns false when not paused or awaiting" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])

      refute StateMachine.is_awaiting?(exec)
    end

    test "returns true when workflow is paused" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.pause()

      assert StateMachine.is_awaiting?(exec)
    end

    test "returns true when step is awaiting" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_awaiting(:a, [])

      assert StateMachine.is_awaiting?(exec)
    end
  end

  describe "get_awaiting_steps/1" do
    test "returns empty list when no awaiting steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])

      assert StateMachine.get_awaiting_steps(exec) == []
    end

    test "returns list of awaiting steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)
        |> Execution.step_awaiting(:a, [])

      awaiting = StateMachine.get_awaiting_steps(exec)
      assert :a in awaiting
    end
  end

  describe "get_rollback_order/2" do
    test "returns empty list when no completed steps with rollback" do
      workflow = build_workflow([:a, :b])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      assert StateMachine.get_rollback_order(workflow, exec) == []
    end

    test "returns steps with rollback in reverse order" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, rollback: :undo_a)
        |> Workflow.step(:b, fn _ -> :ok end, after: :a, rollback: :undo_b)
        # no rollback
        |> Workflow.step(:c, fn _ -> :ok end, after: :b)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)
        |> Execution.step_started(:c)
        |> Execution.step_completed(:c, :ok)

      rollback_order = StateMachine.get_rollback_order(workflow, exec)

      # The completed_steps list prepends (most recent first), then gets reversed.
      # Execution order: a complete, b complete, c complete
      # completed_steps stored: [:c, :b, :a] (most recent first)
      # Enum.reverse gives: [:a, :b, :c]
      # Filtered to only rollback steps: [:a, :b]
      assert rollback_order == [:a, :b]
    end
  end

  describe "evaluate_condition/2" do
    test "returns true when no condition" do
      step = Step.new(:test, fn _ -> :ok end)
      assert StateMachine.evaluate_condition(step, %{})
    end

    test "returns condition result" do
      step = Step.new(:test, fn _ -> :ok end, when: fn ctx -> ctx.enabled end)
      assert StateMachine.evaluate_condition(step, %{enabled: true})
      refute StateMachine.evaluate_condition(step, %{enabled: false})
    end

    test "returns false on condition error" do
      step = Step.new(:test, fn _ -> :ok end, when: fn _ -> raise "boom" end)
      refute StateMachine.evaluate_condition(step, %{})
    end
  end

  describe "get_skippable_steps/2" do
    test "returns steps where condition is false" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:always, fn _ -> :ok end)
        |> Workflow.step(:conditional, fn _ -> :ok end, when: fn ctx -> ctx.enabled end)
        |> Workflow.build!()

      exec =
        start_execution(workflow)
        |> Map.put(:context, %{enabled: false})

      skippable = StateMachine.get_skippable_steps(workflow, exec)
      assert :conditional in skippable
      refute :always in skippable
    end
  end

  describe "progress_percentage/2" do
    test "returns 100 when no steps" do
      workflow = %{Workflow.new(:test) | steps: %{}}
      exec = Execution.new(:test)

      assert StateMachine.progress_percentage(workflow, exec) == 100.0
    end

    test "returns 0 when no steps completed" do
      workflow = build_workflow([:a, :b, :c, :d])
      exec = start_execution(workflow)

      assert StateMachine.progress_percentage(workflow, exec) == 0.0
    end

    test "calculates correct percentage" do
      workflow = build_workflow([:a, :b, :c, :d])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_skipped(:b)

      # 2 out of 4 = 50%
      assert StateMachine.progress_percentage(workflow, exec) == 50.0
    end
  end

  describe "current_step/1" do
    test "returns nil when no running steps" do
      exec = Execution.new(:test)
      assert StateMachine.current_step(exec) == nil
    end

    test "returns first running step" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)

      assert StateMachine.current_step(exec) == :a
    end
  end

  describe "can_proceed?/2" do
    test "returns false when not running" do
      workflow = build_workflow([:a])
      exec = Execution.new(:test)

      refute StateMachine.can_proceed?(workflow, exec)
    end

    test "returns false when paused" do
      workflow = build_workflow([:a])
      exec = start_execution(workflow) |> Execution.pause()

      refute StateMachine.can_proceed?(workflow, exec)
    end

    test "returns false when complete" do
      workflow = build_workflow([:a])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      refute StateMachine.can_proceed?(workflow, exec)
    end

    test "returns false when should fail" do
      workflow = build_workflow([{:a, on_error: :fail}])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      refute StateMachine.can_proceed?(workflow, exec)
    end

    test "returns true when ready steps exist" do
      workflow = build_workflow([:a, :b])
      exec = start_execution(workflow)

      assert StateMachine.can_proceed?(workflow, exec)
    end

    test "returns true when steps are running" do
      workflow =
        build_workflow([
          :a,
          {:b, after: :a}
        ])

      exec =
        start_execution(workflow)
        |> Execution.step_started(:a)

      # a is running, b is pending but not ready
      assert StateMachine.can_proceed?(workflow, exec)
    end
  end
end
