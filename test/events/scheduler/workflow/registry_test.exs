defmodule Events.Infra.Scheduler.Workflow.RegistryTest do
  use ExUnit.Case, async: false

  alias Events.Infra.Scheduler.Workflow
  alias Events.Infra.Scheduler.Workflow.{Registry, Execution}

  setup do
    # Start a fresh registry for each test
    name = :"registry_#{:erlang.unique_integer()}"
    {:ok, pid} = Registry.start_link(name: name)
    %{registry: name, pid: pid}
  end

  describe "workflow registration" do
    test "registers a workflow", %{registry: reg} do
      workflow =
        Workflow.new(:test_workflow, tags: ["test"])
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      assert {:ok, ^workflow} = Registry.register_workflow(workflow, name: reg)
    end

    test "gets a registered workflow", %{registry: reg} do
      workflow =
        Workflow.new(:test_workflow)
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow, name: reg)

      assert {:ok, retrieved} = Registry.get_workflow(:test_workflow, name: reg)
      assert retrieved.name == :test_workflow
    end

    test "returns error for unknown workflow", %{registry: reg} do
      assert {:error, :not_found} = Registry.get_workflow(:nonexistent, name: reg)
    end

    test "updates existing workflow on re-registration", %{registry: reg} do
      workflow1 =
        Workflow.new(:test_workflow, tags: ["v1"])
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      workflow2 =
        Workflow.new(:test_workflow, tags: ["v2"])
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.step(:step_b, fn _ -> :ok end, after: :step_a)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow1, name: reg)
      {:ok, _} = Registry.register_workflow(workflow2, name: reg)

      {:ok, retrieved} = Registry.get_workflow(:test_workflow, name: reg)
      assert retrieved.tags == ["v2"]
      assert Map.has_key?(retrieved.steps, :step_b)
    end

    test "lists all workflows", %{registry: reg} do
      workflow1 =
        Workflow.new(:workflow_a)
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      workflow2 =
        Workflow.new(:workflow_b)
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow1, name: reg)
      {:ok, _} = Registry.register_workflow(workflow2, name: reg)

      workflows = Registry.list_workflows(name: reg)
      names = Enum.map(workflows, & &1.name)

      assert :workflow_a in names
      assert :workflow_b in names
    end

    test "filters workflows by tags", %{registry: reg} do
      workflow1 =
        Workflow.new(:tagged, tags: ["critical"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      workflow2 =
        Workflow.new(:untagged)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow1, name: reg)
      {:ok, _} = Registry.register_workflow(workflow2, name: reg)

      filtered = Registry.list_workflows(name: reg, tags: ["critical"])
      assert length(filtered) == 1
      assert hd(filtered).name == :tagged
    end

    test "filters workflows by trigger type", %{registry: reg} do
      scheduled =
        Workflow.new(:scheduled_wf)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.schedule(cron: "0 * * * *")
        |> Workflow.build!()

      manual =
        Workflow.new(:manual_wf)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(scheduled, name: reg)
      {:ok, _} = Registry.register_workflow(manual, name: reg)

      filtered = Registry.list_workflows(name: reg, trigger_type: :scheduled)
      assert length(filtered) == 1
      assert hd(filtered).name == :scheduled_wf
    end

    test "deletes a workflow", %{registry: reg} do
      workflow =
        Workflow.new(:to_delete)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow, name: reg)
      assert {:ok, _} = Registry.get_workflow(:to_delete, name: reg)

      assert :ok = Registry.delete_workflow(:to_delete, name: reg)
      assert {:error, :not_found} = Registry.get_workflow(:to_delete, name: reg)
    end

    test "updates workflow fields", %{registry: reg} do
      workflow =
        Workflow.new(:updatable, tags: ["old"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow, name: reg)

      {:ok, updated} = Registry.update_workflow(:updatable, %{tags: ["new"]}, name: reg)
      assert updated.tags == ["new"]

      {:ok, retrieved} = Registry.get_workflow(:updatable, name: reg)
      assert retrieved.tags == ["new"]
    end
  end

  describe "execution tracking" do
    test "registers an execution", %{registry: reg} do
      exec = Execution.new(:test_workflow, %{user_id: 123})

      assert {:ok, registered} = Registry.register_execution(exec, name: reg)
      assert registered.id == exec.id
    end

    test "gets an execution by ID", %{registry: reg} do
      exec = Execution.new(:test_workflow, %{data: "test"})
      {:ok, _} = Registry.register_execution(exec, name: reg)

      assert {:ok, retrieved} = Registry.get_execution(exec.id, name: reg)
      assert retrieved.context == %{data: "test"}
    end

    test "returns error for unknown execution", %{registry: reg} do
      assert {:error, :not_found} = Registry.get_execution("nonexistent-id", name: reg)
    end

    test "updates an execution", %{registry: reg} do
      exec = Execution.new(:test_workflow)
      {:ok, _} = Registry.register_execution(exec, name: reg)

      started_exec = Execution.start(exec, [:step_a, :step_b])
      {:ok, _} = Registry.update_execution(exec.id, started_exec, name: reg)

      {:ok, retrieved} = Registry.get_execution(exec.id, name: reg)
      assert retrieved.state == :running
    end

    test "deletes an execution", %{registry: reg} do
      exec = Execution.new(:test_workflow)
      {:ok, _} = Registry.register_execution(exec, name: reg)

      assert :ok = Registry.delete_execution(exec.id, name: reg)
      assert {:error, :not_found} = Registry.get_execution(exec.id, name: reg)
    end

    test "lists executions for a workflow", %{registry: reg} do
      exec1 = Execution.new(:workflow_a)
      exec2 = Execution.new(:workflow_a)
      exec3 = Execution.new(:workflow_b)

      {:ok, _} = Registry.register_execution(exec1, name: reg)
      {:ok, _} = Registry.register_execution(exec2, name: reg)
      {:ok, _} = Registry.register_execution(exec3, name: reg)

      executions = Registry.list_executions(:workflow_a, name: reg)
      assert length(executions) == 2
      assert Enum.all?(executions, &(&1.workflow_name == :workflow_a))
    end

    test "filters executions by state", %{registry: reg} do
      exec1 = Execution.new(:test_workflow) |> Execution.start([:a])
      exec2 = Execution.new(:test_workflow)

      {:ok, _} = Registry.register_execution(exec1, name: reg)
      {:ok, _} = Registry.register_execution(exec2, name: reg)

      running = Registry.list_executions(:test_workflow, name: reg, state: :running)
      assert length(running) == 1
      assert hd(running).state == :running

      pending = Registry.list_executions(:test_workflow, name: reg, state: :pending)
      assert length(pending) == 1
      assert hd(pending).state == :pending
    end

    test "limits execution results", %{registry: reg} do
      for i <- 1..10 do
        exec = Execution.new(:test_workflow, %{index: i})
        {:ok, _} = Registry.register_execution(exec, name: reg)
      end

      limited = Registry.list_executions(:test_workflow, name: reg, limit: 3)
      assert length(limited) == 3
    end

    test "lists running executions", %{registry: reg} do
      running1 = Execution.new(:workflow_a) |> Execution.start([:a])
      running2 = Execution.new(:workflow_b) |> Execution.start([:a])
      pending = Execution.new(:workflow_a)

      {:ok, _} = Registry.register_execution(running1, name: reg)
      {:ok, _} = Registry.register_execution(running2, name: reg)
      {:ok, _} = Registry.register_execution(pending, name: reg)

      running = Registry.list_running_executions(name: reg)
      assert length(running) == 2
    end

    test "filters running executions by workflow", %{registry: reg} do
      running1 = Execution.new(:workflow_a) |> Execution.start([:a])
      running2 = Execution.new(:workflow_b) |> Execution.start([:a])

      {:ok, _} = Registry.register_execution(running1, name: reg)
      {:ok, _} = Registry.register_execution(running2, name: reg)

      filtered = Registry.list_running_executions(name: reg, workflow: :workflow_a)
      assert length(filtered) == 1
      assert hd(filtered).workflow_name == :workflow_a
    end
  end

  describe "statistics" do
    test "gets stats", %{registry: reg} do
      # Add workflows
      workflow =
        Workflow.new(:stats_test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Registry.register_workflow(workflow, name: reg)

      # Add executions in various states
      pending = Execution.new(:stats_test)
      running = Execution.new(:stats_test) |> Execution.start([:a])

      completed =
        Execution.new(:stats_test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.complete()

      {:ok, _} = Registry.register_execution(pending, name: reg)
      {:ok, _} = Registry.register_execution(running, name: reg)
      {:ok, _} = Registry.register_execution(completed, name: reg)

      stats = Registry.get_stats(name: reg)

      assert stats.workflows == 1
      assert stats.executions.total == 3
      assert stats.executions.by_state[:pending] == 1
      assert stats.executions.by_state[:running] == 1
      assert stats.executions.by_state[:completed] == 1
    end
  end
end
