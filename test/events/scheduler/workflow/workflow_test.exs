defmodule Events.Infra.Scheduler.WorkflowTest do
  use ExUnit.Case, async: true

  alias Events.Infra.Scheduler.Workflow
  alias Events.Infra.Scheduler.Workflow.Step

  describe "new/2" do
    test "creates workflow with name" do
      workflow = Workflow.new(:user_onboarding)
      assert workflow.name == :user_onboarding
    end

    test "creates workflow with default options" do
      workflow = Workflow.new(:test)
      assert workflow.version == 1
      assert workflow.state == :pending
      assert workflow.trigger_type == :manual
      assert workflow.max_retries == 0
      assert workflow.step_max_retries == 3
      assert workflow.dead_letter == false
      assert workflow.steps == %{}
      assert workflow.tags == []
    end

    test "creates workflow with custom timeout" do
      workflow = Workflow.new(:test, timeout: {1, :hour})
      assert workflow.timeout == :timer.hours(1)
    end

    test "creates workflow with custom step defaults" do
      workflow =
        Workflow.new(:test,
          step_timeout: {10, :minutes},
          step_max_retries: 5,
          step_retry_delay: {2, :seconds}
        )

      assert workflow.step_timeout == :timer.minutes(10)
      assert workflow.step_max_retries == 5
      assert workflow.step_retry_delay == :timer.seconds(2)
    end

    test "creates workflow with handlers" do
      workflow =
        Workflow.new(:test,
          on_failure: :cleanup,
          on_success: :celebrate,
          on_cancel: :abort
        )

      assert workflow.on_failure == :cleanup
      assert workflow.on_success == :celebrate
      assert workflow.on_cancel == :abort
    end

    test "creates workflow with dead letter config" do
      workflow =
        Workflow.new(:test,
          dead_letter: true,
          dead_letter_ttl: {30, :days}
        )

      assert workflow.dead_letter == true
      assert workflow.dead_letter_ttl == :timer.hours(24 * 30)
    end

    test "creates workflow with tags and metadata" do
      workflow =
        Workflow.new(:test,
          tags: ["critical", "daily"],
          metadata: %{owner: "team_a"}
        )

      assert workflow.tags == ["critical", "daily"]
      assert workflow.metadata == %{owner: "team_a"}
    end
  end

  describe "step/4" do
    test "adds step to workflow" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ctx -> {:ok, %{data: 42}} end)

      assert Map.has_key?(workflow.steps, :fetch)
      assert %Step{name: :fetch} = workflow.steps[:fetch]
    end

    test "adds step with dependencies" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:first, fn _ -> :ok end)
        |> Workflow.step(:second, fn _ -> :ok end, after: :first)

      assert workflow.adjacency[:second] == [:first]
    end

    test "adds step with multiple dependencies" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end)
        |> Workflow.step(:c, fn _ -> :ok end, after: [:a, :b])

      assert :a in workflow.adjacency[:c]
      assert :b in workflow.adjacency[:c]
    end

    test "adds step with after_any dependencies" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end)
        |> Workflow.step(:c, fn _ -> :ok end, after_any: [:a, :b])

      step = workflow.steps[:c]
      assert step.depends_on_any == [:a, :b]
    end

    test "adds step to group" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:upload_s3, fn _ -> :ok end, group: :uploads)
        |> Workflow.step(:upload_gcs, fn _ -> :ok end, group: :uploads)

      assert :upload_s3 in workflow.groups[:uploads]
      assert :upload_gcs in workflow.groups[:uploads]
    end

    test "adds step with condition" do
      condition = fn ctx -> ctx.enabled end

      workflow =
        Workflow.new(:test)
        |> Workflow.step(:conditional, fn _ -> :ok end, when: condition)

      step = workflow.steps[:conditional]
      assert step.condition == condition
    end

    test "adds step with rollback" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:charge, fn _ -> :ok end, rollback: :refund)

      step = workflow.steps[:charge]
      assert step.rollback == :refund
    end

    test "adds step with custom timeout" do
      workflow =
        Workflow.new(:test, step_timeout: {5, :minutes})
        |> Workflow.step(:slow, fn _ -> :ok end, timeout: {30, :minutes})

      step = workflow.steps[:slow]
      assert step.timeout == :timer.minutes(30)
    end

    test "adds step with custom retry config" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:flaky, fn _ -> :ok end,
          max_retries: 10,
          retry_delay: 500,
          retry_backoff: :linear
        )

      step = workflow.steps[:flaky]
      assert step.max_retries == 10
      assert step.retry_delay == 500
      assert step.retry_backoff == :linear
    end

    test "adds step with on_error setting" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:optional, fn _ -> :ok end, on_error: :skip)

      step = workflow.steps[:optional]
      assert step.on_error == :skip
    end

    test "step inherits workflow defaults" do
      workflow =
        Workflow.new(:test,
          step_timeout: {10, :minutes},
          step_max_retries: 5
        )
        |> Workflow.step(:inherits, fn _ -> :ok end)

      step = workflow.steps[:inherits]
      assert step.timeout == :timer.minutes(10)
      assert step.max_retries == 5
    end
  end

  describe "parallel/4" do
    test "adds multiple parallel steps" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ -> :ok end)
        |> Workflow.parallel(:fetch, [
          {:upload_s3, fn _ -> :ok end},
          {:upload_gcs, fn _ -> :ok end}
        ])

      assert Map.has_key?(workflow.steps, :upload_s3)
      assert Map.has_key?(workflow.steps, :upload_gcs)
      assert :fetch in workflow.adjacency[:upload_s3]
      assert :fetch in workflow.adjacency[:upload_gcs]
    end

    test "creates parallel group" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ -> :ok end)
        |> Workflow.parallel(:fetch, [
          {:a, fn _ -> :ok end},
          {:b, fn _ -> :ok end}
        ])

      # parallel creates a group named :parallel_<after_step>
      assert workflow.groups[:parallel_fetch] == [:b, :a]
    end

    test "parallel with custom group name" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ -> :ok end)
        |> Workflow.parallel(
          :fetch,
          [
            {:a, fn _ -> :ok end},
            {:b, fn _ -> :ok end}
          ],
          group: :custom_group
        )

      assert workflow.groups[:custom_group] == [:b, :a]
    end
  end

  describe "fan_out/4" do
    test "creates fan-out pattern" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:transform, fn _ -> :ok end)
        |> Workflow.fan_out(:transform, [
          {:s3, fn _ -> :ok end},
          {:gcs, fn _ -> :ok end}
        ])

      assert :transform in workflow.adjacency[:s3]
      assert :transform in workflow.adjacency[:gcs]
    end
  end

  describe "fan_in/5" do
    test "creates fan-in pattern" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end)
        |> Workflow.fan_in([:a, :b], :join, fn _ -> :ok end)

      assert :a in workflow.adjacency[:join]
      assert :b in workflow.adjacency[:join]
    end
  end

  describe "branch/3" do
    test "creates conditional branches" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:check, fn _ -> :ok end)
        |> Workflow.branch(:check, [
          {:yes, condition: fn ctx -> ctx.answer end, job: fn _ -> :ok end},
          {:no, condition: fn ctx -> !ctx.answer end, job: fn _ -> :ok end}
        ])

      assert Map.has_key?(workflow.steps, :yes)
      assert Map.has_key?(workflow.steps, :no)
      assert :check in workflow.adjacency[:yes]
      assert :check in workflow.adjacency[:no]
      assert workflow.steps[:yes].condition != nil
      assert workflow.steps[:no].condition != nil
    end
  end

  describe "add_graft/3" do
    test "adds graft placeholder" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ -> :ok end)
        |> Workflow.add_graft(:process_batch, deps: :fetch)

      assert Map.has_key?(workflow.grafts, :process_batch)
      assert workflow.grafts[:process_batch].deps == [:fetch]
      assert workflow.grafts[:process_batch].expanded == false
    end
  end

  describe "add_workflow/4" do
    test "adds nested workflow reference" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:create, fn _ -> :ok end)
        |> Workflow.add_workflow(:notify, :send_notification, after: :create)

      assert workflow.nested_workflows[:notify] == :send_notification
      assert Map.has_key?(workflow.steps, :notify)
      assert workflow.steps[:notify].job == {:workflow, :send_notification}
    end
  end

  describe "schedule/2" do
    test "sets cron schedule" do
      workflow =
        Workflow.new(:test)
        |> Workflow.schedule(cron: "0 6 * * *")

      assert workflow.schedule == [cron: "0 6 * * *"]
      assert workflow.trigger_type == :scheduled
    end

    test "sets interval schedule" do
      workflow =
        Workflow.new(:test)
        |> Workflow.schedule(every: {30, :minutes})

      assert workflow.schedule == [every: {30, :minutes}]
      assert workflow.trigger_type == :scheduled
    end

    test "sets event trigger" do
      workflow =
        Workflow.new(:test)
        |> Workflow.schedule(on_event: "user.created")

      assert workflow.trigger_type == :event
      assert "user.created" in workflow.event_triggers
    end

    test "sets multiple event triggers" do
      workflow =
        Workflow.new(:test)
        |> Workflow.schedule(on_event: ["order.placed", "order.updated"])

      assert "order.placed" in workflow.event_triggers
      assert "order.updated" in workflow.event_triggers
    end
  end

  describe "on_event/2" do
    test "adds event trigger" do
      workflow =
        Workflow.new(:test)
        |> Workflow.on_event("user.signed_up")

      assert workflow.trigger_type == :event
      assert "user.signed_up" in workflow.event_triggers
    end
  end

  describe "on_failure/2" do
    test "sets failure handler" do
      workflow =
        Workflow.new(:test)
        |> Workflow.on_failure(:cleanup)

      assert workflow.on_failure == :cleanup
    end
  end

  describe "on_success/2" do
    test "sets success handler" do
      workflow =
        Workflow.new(:test)
        |> Workflow.on_success(:celebrate)

      assert workflow.on_success == :celebrate
    end
  end

  describe "on_cancel/2" do
    test "sets cancel handler" do
      workflow =
        Workflow.new(:test)
        |> Workflow.on_cancel(:abort)

      assert workflow.on_cancel == :abort
    end
  end

  describe "build/1" do
    test "builds valid sequential workflow" do
      {:ok, workflow} =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.step(:b, fn _ -> :ok end, after: :a)
        |> Workflow.step(:c, fn _ -> :ok end, after: :b)
        |> Workflow.build()

      assert workflow.execution_order == [:c, :b, :a]
      assert workflow.state == :pending
    end

    test "builds valid parallel workflow" do
      {:ok, workflow} =
        Workflow.new(:test)
        |> Workflow.step(:fetch, fn _ -> :ok end)
        |> Workflow.step(:a, fn _ -> :ok end, after: :fetch)
        |> Workflow.step(:b, fn _ -> :ok end, after: :fetch)
        |> Workflow.step(:join, fn _ -> :ok end, after: [:a, :b])
        |> Workflow.build()

      # join depends on a and b, so comes first in topo sort
      assert :join in workflow.execution_order
      assert :fetch in workflow.execution_order
    end

    test "fails on cycle" do
      result =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, after: :b)
        |> Workflow.step(:b, fn _ -> :ok end, after: :a)
        |> Workflow.build()

      assert {:error, {:cycle_detected, _}} = result
    end

    test "fails on missing dependency" do
      result =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, after: :nonexistent)
        |> Workflow.build()

      assert {:error, {:missing_dependencies, [:nonexistent]}} = result
    end
  end

  describe "build!/1" do
    test "builds valid workflow" do
      workflow =
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end)
        |> Workflow.build!()

      assert workflow.execution_order == [:a]
    end

    test "raises on invalid workflow" do
      assert_raise ArgumentError, ~r/Invalid workflow/, fn ->
        Workflow.new(:test)
        |> Workflow.step(:a, fn _ -> :ok end, after: :nonexistent)
        |> Workflow.build!()
      end
    end
  end

  describe "cancelled?/0 and cancellation_reason/0" do
    test "returns false when not cancelled" do
      refute Workflow.cancelled?()
      assert Workflow.cancellation_reason() == nil
    end

    test "returns true when cancelled flag is set" do
      Process.put(:__workflow_cancelled__, true)
      Process.put(:__workflow_cancellation_reason__, :user_requested)

      assert Workflow.cancelled?()
      assert Workflow.cancellation_reason() == :user_requested
    after
      Process.delete(:__workflow_cancelled__)
      Process.delete(:__workflow_cancellation_reason__)
    end
  end
end
