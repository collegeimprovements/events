defmodule Events.Infra.Scheduler.Workflow.StoreTest do
  use Events.DataCase, async: false

  alias Events.Infra.Scheduler.Workflow
  alias Events.Infra.Scheduler.Workflow.{Execution, Store}

  describe "workflow definition operations" do
    test "saves and retrieves a workflow" do
      workflow =
        Workflow.new(:test_workflow, tags: ["test"])
        |> Workflow.step(:step_a, fn _ -> :ok end)
        |> Workflow.build!()

      assert {:ok, _schema} = Store.save_workflow(workflow)
      assert {:ok, retrieved} = Store.get_workflow(:test_workflow)

      assert retrieved.name == :test_workflow
      assert retrieved.tags == ["test"]
      assert Map.has_key?(retrieved.steps, :step_a)
    end

    test "auto-increments version on re-save" do
      workflow =
        Workflow.new(:versioned_workflow)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, schema1} = Store.save_workflow(workflow)
      {:ok, schema2} = Store.save_workflow(workflow)
      {:ok, schema3} = Store.save_workflow(workflow)

      assert schema1.version == 1
      assert schema2.version == 2
      assert schema3.version == 3
    end

    test "retrieves specific version" do
      workflow1 =
        Workflow.new(:multi_version, tags: ["v1"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      workflow2 =
        Workflow.new(:multi_version, tags: ["v2"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end, after: :a)
        |> Workflow.build!()

      {:ok, _} = Store.save_workflow(workflow1)
      {:ok, _} = Store.save_workflow(workflow2)

      # Latest by default
      {:ok, latest} = Store.get_workflow(:multi_version)
      assert latest.tags == ["v2"]
      assert Map.has_key?(latest.steps, :b)

      # Specific version
      {:ok, v1} = Store.get_workflow(:multi_version, version: 1)
      assert v1.tags == ["v1"]
      refute Map.has_key?(v1.steps, :b)
    end

    test "returns error for unknown workflow" do
      assert {:error, :not_found} = Store.get_workflow(:nonexistent_workflow)
    end

    test "lists workflows with filters" do
      workflow1 =
        Workflow.new(:list_workflow_a, tags: ["critical"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      workflow2 =
        Workflow.new(:list_workflow_b, tags: ["normal"])
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.schedule(cron: "0 * * * *")
        |> Workflow.build!()

      {:ok, _} = Store.save_workflow(workflow1)
      {:ok, _} = Store.save_workflow(workflow2)

      all = Store.list_workflows()
      assert length(all) >= 2

      # Filter by tag
      critical = Store.list_workflows(tags: ["critical"])
      names = Enum.map(critical, & &1.name)
      assert "list_workflow_a" in names

      # Filter by trigger type
      scheduled = Store.list_workflows(trigger_type: :scheduled)
      names = Enum.map(scheduled, & &1.name)
      assert "list_workflow_b" in names
    end

    test "deletes workflow" do
      workflow =
        Workflow.new(:to_delete_workflow)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Store.save_workflow(workflow)
      assert {:ok, _} = Store.get_workflow(:to_delete_workflow)

      {:ok, count} = Store.delete_workflow(:to_delete_workflow)
      assert count == 1

      assert {:error, :not_found} = Store.get_workflow(:to_delete_workflow)
    end
  end

  describe "execution operations" do
    test "creates and retrieves an execution" do
      exec = Execution.new(:exec_test_workflow, %{user_id: 123})

      {:ok, schema} = Store.create_execution(exec)
      {:ok, retrieved} = Store.get_execution(schema.id)

      assert retrieved.id == schema.id
      assert retrieved.workflow_name == :exec_test_workflow
      assert retrieved.context["user_id"] == 123 or retrieved.context[:user_id] == 123
    end

    test "updates an execution" do
      exec = Execution.new(:update_test_workflow)
      {:ok, schema} = Store.create_execution(exec)

      # Update the execution ID to match the database-generated one
      exec_with_id = %{exec | id: schema.id}
      started_exec = exec_with_id |> Execution.start([:step_a, :step_b])
      {:ok, _} = Store.update_execution(started_exec)

      {:ok, retrieved} = Store.get_execution(schema.id)
      assert retrieved.state == :running
    end

    test "deletes an execution" do
      exec = Execution.new(:delete_exec_workflow)
      {:ok, schema} = Store.create_execution(exec)

      assert :ok = Store.delete_execution(schema.id)
      assert {:error, :not_found} = Store.get_execution(schema.id)
    end

    test "lists executions for a workflow" do
      exec1 = Execution.new(:list_exec_workflow, %{index: 1})
      exec2 = Execution.new(:list_exec_workflow, %{index: 2})
      exec3 = Execution.new(:other_workflow, %{index: 3})

      {:ok, _} = Store.create_execution(exec1)
      {:ok, _} = Store.create_execution(exec2)
      {:ok, _} = Store.create_execution(exec3)

      {:ok, execs} = Store.list_executions(:list_exec_workflow)
      assert length(execs) == 2
      assert Enum.all?(execs, &(&1.workflow_name == :list_exec_workflow))
    end

    test "filters executions by state" do
      exec1 = Execution.new(:state_filter_workflow) |> Execution.start([:a])
      exec2 = Execution.new(:state_filter_workflow)

      {:ok, _} = Store.create_execution(exec1)
      {:ok, _} = Store.create_execution(exec2)

      {:ok, running} = Store.list_executions(:state_filter_workflow, state: :running)
      assert length(running) == 1
      assert hd(running).state == :running

      {:ok, pending} = Store.list_executions(:state_filter_workflow, state: :pending)
      assert length(pending) == 1
      assert hd(pending).state == :pending
    end

    test "lists running executions" do
      running1 = Execution.new(:running_a) |> Execution.start([:a])
      running2 = Execution.new(:running_b) |> Execution.start([:a])
      pending = Execution.new(:pending_workflow)

      {:ok, _} = Store.create_execution(running1)
      {:ok, _} = Store.create_execution(running2)
      {:ok, _} = Store.create_execution(pending)

      {:ok, running} = Store.list_running_executions()
      assert length(running) >= 2

      {:ok, filtered} = Store.list_running_executions(workflow: :running_a)
      assert length(filtered) >= 1
      assert Enum.all?(filtered, &(&1.workflow_name == :running_a))
    end

    test "limits execution results" do
      for i <- 1..10 do
        exec = Execution.new(:limit_test_workflow, %{index: i})
        {:ok, _} = Store.create_execution(exec)
      end

      {:ok, limited} = Store.list_executions(:limit_test_workflow, limit: 3)
      assert length(limited) == 3
    end
  end

  describe "step execution operations" do
    test "records step lifecycle" do
      exec = Execution.new(:step_tracking_workflow)
      {:ok, schema} = Store.create_execution(exec)

      # Start step
      {:ok, step1} = Store.record_step_start(schema.id, :first_step, 1)
      assert step1.state == "running"
      assert step1.attempt == 1

      # Complete step
      {:ok, step2} = Store.record_step_complete(schema.id, :first_step, %{result: "done"})
      assert step2.state == "completed"
      assert step2.duration_ms != nil

      # List steps
      {:ok, steps} = Store.list_step_executions(schema.id)
      assert length(steps) == 1
      assert hd(steps).step_name == "first_step"
    end

    test "records step failure" do
      exec = Execution.new(:step_failure_workflow)
      {:ok, schema} = Store.create_execution(exec)

      {:ok, _} = Store.record_step_start(schema.id, :failing_step, 1)

      {:ok, step} =
        Store.record_step_failed(schema.id, :failing_step, :some_error, "stacktrace here")

      assert step.state == "failed"
      assert step.error == "some_error"
      assert step.stacktrace == "stacktrace here"
    end
  end

  describe "statistics" do
    test "returns accurate stats" do
      # Create a workflow
      workflow =
        Workflow.new(:stats_workflow)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      {:ok, _} = Store.save_workflow(workflow)

      # Create executions in different states
      pending = Execution.new(:stats_workflow)
      running = Execution.new(:stats_workflow) |> Execution.start([:a])

      completed =
        Execution.new(:stats_workflow)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.complete()

      {:ok, _} = Store.create_execution(pending)
      {:ok, _} = Store.create_execution(running)
      {:ok, _} = Store.create_execution(completed)

      stats = Store.get_stats(workflow: :stats_workflow)

      assert stats.executions.total >= 3
      assert stats.executions.by_state[:pending] >= 1
      assert stats.executions.by_state[:running] >= 1
      assert stats.executions.by_state[:completed] >= 1
    end
  end
end
