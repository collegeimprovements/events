defmodule OmScheduler.Workflow.ExecutionTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Workflow.Execution

  describe "new/3" do
    test "creates execution with workflow name" do
      exec = Execution.new(:user_onboarding)
      assert exec.workflow_name == :user_onboarding
      assert is_binary(exec.id)
      # UUID format
      assert String.length(exec.id) == 36
    end

    test "creates execution with initial context" do
      exec = Execution.new(:test, %{user_id: 123})
      assert exec.context == %{user_id: 123}
      assert exec.initial_context == %{user_id: 123}
    end

    test "creates execution with default state" do
      exec = Execution.new(:test)
      assert exec.state == :pending
      assert exec.step_states == %{}
      assert exec.step_results == %{}
      assert exec.step_errors == %{}
      assert exec.completed_steps == []
      assert exec.running_steps == []
      assert exec.pending_steps == []
      assert exec.skipped_steps == []
      assert exec.cancelled_steps == []
      assert exec.timeline == []
    end

    test "creates execution with version" do
      exec = Execution.new(:test, %{}, version: 2)
      assert exec.workflow_version == 2
    end

    test "creates execution with scheduled_at" do
      scheduled = DateTime.utc_now()
      exec = Execution.new(:test, %{}, scheduled_at: scheduled)
      assert exec.scheduled_at == scheduled
    end

    test "creates execution with max_attempts" do
      exec = Execution.new(:test, %{}, max_attempts: 3)
      assert exec.max_attempts == 3
    end

    test "creates execution with parent_execution_id" do
      exec = Execution.new(:test, %{}, parent_execution_id: "parent-123")
      assert exec.parent_execution_id == "parent-123"
    end

    test "creates execution with metadata" do
      exec = Execution.new(:test, %{}, metadata: %{source: "api"})
      assert exec.metadata == %{source: "api"}
    end

    test "sets manual trigger by default" do
      exec = Execution.new(:test)
      assert exec.trigger.type == :manual
      assert exec.trigger.source == nil
    end

    test "sets scheduled trigger when scheduled_at provided" do
      exec = Execution.new(:test, %{}, scheduled_at: DateTime.utc_now())
      assert exec.trigger.type == :scheduled
    end

    test "sets event trigger when event provided" do
      exec = Execution.new(:test, %{}, event: "user.created")
      assert exec.trigger.type == :event
    end

    test "records node" do
      exec = Execution.new(:test)
      assert exec.node == node()
    end
  end

  describe "start/2" do
    test "transitions to running state" do
      exec = Execution.new(:test) |> Execution.start([:a, :b, :c])
      assert exec.state == :running
      assert %DateTime{} = exec.started_at
    end

    test "initializes step states" do
      exec = Execution.new(:test) |> Execution.start([:a, :b, :c])
      assert exec.step_states == %{a: :pending, b: :pending, c: :pending}
    end

    test "initializes step attempts" do
      exec = Execution.new(:test) |> Execution.start([:a, :b])
      assert exec.step_attempts == %{a: 0, b: 0}
    end

    test "sets pending steps" do
      exec = Execution.new(:test) |> Execution.start([:a, :b, :c])
      assert exec.pending_steps == [:a, :b, :c]
    end
  end

  describe "step_started/2" do
    test "records step as running" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)

      assert exec.step_states[:a] == :running
      assert exec.current_step == :a
    end

    test "increments attempt counter" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)

      assert exec.step_attempts[:a] == 1
    end

    test "moves step from pending to running" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)

      assert :a in exec.running_steps
      refute :a in exec.pending_steps
    end

    test "adds timeline entry" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)

      [entry] = exec.timeline
      assert entry.name == :a
      assert entry.state == :running
      assert entry.started_at != nil
      assert entry.attempt == 1
    end
  end

  describe "step_completed/3" do
    test "marks step as completed" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, %{result: 42})

      assert exec.step_states[:a] == :completed
      assert exec.step_results[:a] == %{result: 42}
    end

    test "merges result into context" do
      exec =
        Execution.new(:test, %{existing: 1})
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, %{new: 2})

      assert exec.context == %{existing: 1, new: 2}
    end

    test "moves step from running to completed" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      assert :a in exec.completed_steps
      refute :a in exec.running_steps
    end

    test "clears current step" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      assert exec.current_step == nil
    end

    test "updates timeline entry" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      [entry] = exec.timeline
      assert entry.state == :completed
      assert entry.completed_at != nil
      assert entry.duration_ms != nil
    end

    test "handles non-map result without merging context" do
      exec =
        Execution.new(:test, %{original: true})
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)

      assert exec.context == %{original: true}
      assert exec.step_results[:a] == :ok
    end
  end

  describe "step_failed/4" do
    test "marks step as failed" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :timeout)

      assert exec.step_states[:a] == :failed
      assert exec.step_errors[:a] == :timeout
    end

    test "records error details" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :timeout, "stack trace here")

      assert exec.error == :timeout
      assert exec.error_step == :a
      assert exec.stacktrace == "stack trace here"
    end

    test "removes step from running" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)

      refute :a in exec.running_steps
    end

    test "updates timeline entry with error" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :boom)

      [entry] = exec.timeline
      assert entry.state == :failed
      assert entry.error == :boom
    end
  end

  describe "step_skipped/3" do
    test "marks step as skipped" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_skipped(:a, :condition_false)

      assert exec.step_states[:a] == :skipped
      assert exec.step_results[:a] == {:skipped, :condition_false}
      assert :a in exec.skipped_steps
      refute :a in exec.pending_steps
    end

    test "adds timeline entry for skipped step" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_skipped(:a)

      [entry] = exec.timeline
      assert entry.state == :skipped
      assert entry.duration_ms == 0
    end
  end

  describe "step_awaiting/3" do
    test "marks step as awaiting" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_awaiting(:a, notify: :email)

      assert exec.step_states[:a] == :awaiting
      assert exec.state == :paused
      assert %DateTime{} = exec.paused_at
      assert exec.metadata[:await_opts] == [notify: :email]
    end

    test "removes step from running" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_awaiting(:a, [])

      refute :a in exec.running_steps
    end
  end

  describe "step_cancelled/2" do
    test "marks step as cancelled" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_cancelled(:a)

      assert exec.step_states[:a] == :cancelled
      assert :a in exec.cancelled_steps
      refute :a in exec.running_steps
    end
  end

  describe "complete/1" do
    test "transitions to completed state" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.complete()

      assert exec.state == :completed
      assert %DateTime{} = exec.completed_at
      assert is_integer(exec.duration_ms)
      assert exec.current_step == nil
    end
  end

  describe "fail/3" do
    test "transitions to failed state" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :error)
        |> Execution.fail(:error, :a)

      assert exec.state == :failed
      assert %DateTime{} = exec.completed_at
      assert exec.error == :error
      assert exec.error_step == :a
    end

    test "cancels any running steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)
        |> Execution.step_started(:b)
        |> Execution.fail(:error)

      assert exec.step_states[:a] == :cancelled
      assert exec.step_states[:b] == :cancelled
      assert exec.running_steps == []
      assert :a in exec.cancelled_steps
      assert :b in exec.cancelled_steps
    end
  end

  describe "cancel/2" do
    test "transitions to cancelled state" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)
        |> Execution.cancel(:user_requested)

      assert exec.state == :cancelled
      assert exec.cancellation_reason == :user_requested
      assert %DateTime{} = exec.completed_at
    end

    test "cancels running and pending steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b, :c])
        |> Execution.step_started(:a)
        |> Execution.cancel()

      # a was running, b and c were pending
      assert exec.step_states[:a] == :cancelled
      assert exec.step_states[:b] == :cancelled
      assert exec.step_states[:c] == :cancelled
      assert exec.running_steps == []
      assert exec.pending_steps == []
    end
  end

  describe "pause/1 and resume/2" do
    test "pause transitions to paused state" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.pause()

      assert exec.state == :paused
      assert %DateTime{} = exec.paused_at
    end

    test "resume transitions back to running" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.pause()
        |> Execution.resume()

      assert exec.state == :running
      assert exec.paused_at == nil
    end

    test "resume merges additional context" do
      exec =
        Execution.new(:test, %{original: true})
        |> Execution.start([:a])
        |> Execution.pause()
        |> Execution.resume(%{approved: true})

      assert exec.context == %{original: true, approved: true}
    end

    test "resume moves awaiting steps back to pending" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_awaiting(:a, [])
        |> Execution.resume()

      assert exec.step_states[:a] == :pending
      assert :a in exec.pending_steps
    end
  end

  describe "record_graft_expansion/3" do
    test "records graft expansion" do
      exec =
        Execution.new(:test)
        |> Execution.start([:prepare])
        |> Execution.record_graft_expansion(:batch, [:item_1, :item_2, :item_3])

      assert exec.graft_expansions[:batch] == [:item_1, :item_2, :item_3]
    end

    test "adds expanded steps to pending" do
      exec =
        Execution.new(:test)
        |> Execution.start([:prepare])
        |> Execution.record_graft_expansion(:batch, [:item_1, :item_2])

      assert :item_1 in exec.pending_steps
      assert :item_2 in exec.pending_steps
    end

    test "initializes step states for expanded steps" do
      exec =
        Execution.new(:test)
        |> Execution.start([:prepare])
        |> Execution.record_graft_expansion(:batch, [:item_1, :item_2])

      assert exec.step_states[:item_1] == :pending
      assert exec.step_states[:item_2] == :pending
      assert exec.step_attempts[:item_1] == 0
      assert exec.step_attempts[:item_2] == 0
    end
  end

  describe "add_child_execution/2" do
    test "records child execution" do
      exec =
        Execution.new(:test)
        |> Execution.add_child_execution("child-123")
        |> Execution.add_child_execution("child-456")

      assert "child-123" in exec.child_executions
      assert "child-456" in exec.child_executions
    end
  end

  describe "progress/1" do
    test "returns progress tuple" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b, :c, :d])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_skipped(:b)

      {completed, total} = Execution.progress(exec)
      # a completed + b skipped
      assert completed == 2
      assert total == 4
    end
  end

  describe "error_context/1" do
    test "builds error context map" do
      exec =
        Execution.new(:test, %{user_id: 123})
        |> Execution.start([:a])
        |> Execution.step_started(:a)
        |> Execution.step_failed(:a, :boom, "stack")

      error_ctx = Execution.error_context(exec)

      assert error_ctx.user_id == 123
      assert error_ctx.__error__ == :boom
      assert error_ctx.__error_step__ == :a
      assert error_ctx.__attempts__ == 1
      assert error_ctx.__stacktrace__ == "stack"
    end
  end

  describe "terminal?/1" do
    test "completed is terminal" do
      exec = Execution.new(:test) |> Map.put(:state, :completed)
      assert Execution.terminal?(exec)
    end

    test "failed is terminal" do
      exec = Execution.new(:test) |> Map.put(:state, :failed)
      assert Execution.terminal?(exec)
    end

    test "cancelled is terminal" do
      exec = Execution.new(:test) |> Map.put(:state, :cancelled)
      assert Execution.terminal?(exec)
    end

    test "pending is not terminal" do
      exec = Execution.new(:test)
      refute Execution.terminal?(exec)
    end

    test "running is not terminal" do
      exec = Execution.new(:test) |> Execution.start([:a])
      refute Execution.terminal?(exec)
    end

    test "paused is not terminal" do
      exec = Execution.new(:test) |> Execution.start([:a]) |> Execution.pause()
      refute Execution.terminal?(exec)
    end
  end

  describe "get_timeline/1" do
    test "returns timeline in chronological order" do
      exec =
        Execution.new(:test)
        |> Execution.start([:a, :b])
        |> Execution.step_started(:a)
        |> Execution.step_completed(:a, :ok)
        |> Execution.step_started(:b)
        |> Execution.step_completed(:b, :ok)

      timeline = Execution.get_timeline(exec)

      # Timeline should be in chronological order (oldest first)
      [first, second | _] = timeline
      assert first.name == :a
      assert second.name == :b
    end
  end
end
