defmodule OmScheduler.Workflow.TelemetryTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Workflow.Telemetry

  @prefix [:events, :scheduler, :workflow]

  setup do
    # Attach handler to capture telemetry events
    test_pid = self()

    :telemetry.attach_many(
      "workflow-telemetry-test-#{:erlang.unique_integer()}",
      [
        @prefix ++ [:start],
        @prefix ++ [:stop],
        @prefix ++ [:exception],
        @prefix ++ [:pause],
        @prefix ++ [:resume],
        @prefix ++ [:cancel],
        @prefix ++ [:fail],
        @prefix ++ [:step, :start],
        @prefix ++ [:step, :stop],
        @prefix ++ [:step, :exception],
        @prefix ++ [:step, :skip],
        @prefix ++ [:step, :retry],
        @prefix ++ [:step, :cancel],
        @prefix ++ [:rollback, :start],
        @prefix ++ [:rollback, :stop],
        @prefix ++ [:rollback, :exception],
        @prefix ++ [:graft, :expand]
      ],
      fn event, measurements, meta, _config ->
        send(test_pid, {:telemetry_event, event, measurements, meta})
      end,
      nil
    )

    :ok
  end

  describe "workflow events" do
    test "emits workflow_start" do
      Telemetry.workflow_start(:test_workflow, "exec-123", %{trigger_type: :manual})

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :start], %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        trigger_type: :manual
                      }}
    end

    test "emits workflow_stop" do
      Telemetry.workflow_stop(:test_workflow, "exec-123", 1_000_000, %{state: :completed})

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :stop],
                      %{duration: 1_000_000, monotonic_time: _},
                      %{workflow_name: :test_workflow, execution_id: "exec-123", state: :completed}}
    end

    test "emits workflow_exception" do
      Telemetry.workflow_exception(:test_workflow, "exec-123", 500_000, :error, %RuntimeError{}, [])

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :exception],
                      %{duration: 500_000, monotonic_time: _},
                      %{workflow_name: :test_workflow, execution_id: "exec-123", kind: :error}}
    end

    test "emits workflow_pause" do
      Telemetry.workflow_pause(:test_workflow, "exec-123", :await_approval)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :pause], %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        awaiting_step: :await_approval
                      }}
    end

    test "emits workflow_resume" do
      Telemetry.workflow_resume(:test_workflow, "exec-123")

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :resume],
                      %{system_time: _}, %{workflow_name: :test_workflow, execution_id: "exec-123"}}
    end

    test "emits workflow_cancel" do
      Telemetry.workflow_cancel(:test_workflow, "exec-123", :user_requested)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :cancel],
                      %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        cancel_reason: :user_requested
                      }}
    end

    test "emits workflow_fail" do
      Telemetry.workflow_fail(:test_workflow, "exec-123", :some_error, :step_b)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :fail], %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        error: :some_error,
                        error_step: :step_b
                      }}
    end
  end

  describe "step events" do
    test "emits step_start" do
      Telemetry.step_start(:test_workflow, "exec-123", :step_a, 1)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :start],
                      %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        step_name: :step_a,
                        attempt: 1
                      }}
    end

    test "emits step_stop" do
      Telemetry.step_stop(:test_workflow, "exec-123", :step_a, 100_000, {:ok, %{result: "done"}})

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :stop],
                      %{duration: 100_000, monotonic_time: _},
                      %{
                        workflow_name: :test_workflow,
                        step_name: :step_a,
                        result: {:ok, %{result: "done"}}
                      }}
    end

    test "emits step_exception" do
      Telemetry.step_exception(
        :test_workflow,
        "exec-123",
        :step_a,
        50_000,
        :error,
        %RuntimeError{},
        []
      )

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :exception],
                      %{duration: 50_000, monotonic_time: _},
                      %{workflow_name: :test_workflow, step_name: :step_a, kind: :error}}
    end

    test "emits step_skip" do
      Telemetry.step_skip(:test_workflow, "exec-123", :step_a, :condition_false)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :skip],
                      %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        step_name: :step_a,
                        skip_reason: :condition_false
                      }}
    end

    test "emits step_retry" do
      Telemetry.step_retry(:test_workflow, "exec-123", :step_a, 2, :timeout, 5_000)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :retry],
                      %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        step_name: :step_a,
                        attempt: 2,
                        error: :timeout,
                        delay_ms: 5_000
                      }}
    end

    test "emits step_cancel" do
      Telemetry.step_cancel(:test_workflow, "exec-123", :step_a)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :cancel],
                      %{system_time: _}, %{workflow_name: :test_workflow, step_name: :step_a}}
    end
  end

  describe "rollback events" do
    test "emits rollback_start" do
      Telemetry.rollback_start(:test_workflow, "exec-123", [:step_b, :step_a])

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :rollback, :start],
                      %{system_time: _},
                      %{workflow_name: :test_workflow, steps: [:step_b, :step_a], step_count: 2}}
    end

    test "emits rollback_stop" do
      Telemetry.rollback_stop(:test_workflow, "exec-123", 200_000)

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :rollback, :stop],
                      %{duration: 200_000, monotonic_time: _},
                      %{workflow_name: :test_workflow, execution_id: "exec-123"}}
    end

    test "emits rollback_exception" do
      Telemetry.rollback_exception(:test_workflow, "exec-123", :step_a, :error, %RuntimeError{}, [])

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :rollback, :exception],
                      %{system_time: _},
                      %{workflow_name: :test_workflow, step_name: :step_a, kind: :error}}
    end
  end

  describe "graft events" do
    test "emits graft_expand" do
      Telemetry.graft_expand(:test_workflow, "exec-123", :process_items, [:item_1, :item_2, :item_3])

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :graft, :expand],
                      %{system_time: _},
                      %{
                        workflow_name: :test_workflow,
                        graft_name: :process_items,
                        expanded_steps: [:item_1, :item_2, :item_3],
                        step_count: 3
                      }}
    end
  end

  describe "spans" do
    test "workflow_span emits start and stop" do
      result =
        Telemetry.workflow_span(:test_workflow, "exec-123", %{}, fn ->
          :workflow_result
        end)

      assert result == :workflow_result

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :start], %{system_time: _},
                      %{workflow_name: :test_workflow, execution_id: "exec-123"}}

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :stop],
                      %{duration: _, monotonic_time: _},
                      %{
                        workflow_name: :test_workflow,
                        execution_id: "exec-123",
                        result: :workflow_result
                      }}
    end

    test "workflow_span emits start and exception on error" do
      assert_raise RuntimeError, fn ->
        Telemetry.workflow_span(:test_workflow, "exec-123", %{}, fn ->
          raise "boom"
        end)
      end

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :start], %{system_time: _},
                      %{workflow_name: :test_workflow, execution_id: "exec-123"}}

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :exception],
                      %{duration: _, monotonic_time: _},
                      %{workflow_name: :test_workflow, kind: :error, reason: %RuntimeError{}}}
    end

    test "step_span emits start and stop" do
      result =
        Telemetry.step_span(:test_workflow, "exec-123", :step_a, 1, %{}, fn ->
          :step_result
        end)

      assert result == :step_result

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :start],
                      %{system_time: _},
                      %{workflow_name: :test_workflow, step_name: :step_a, attempt: 1}}

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :step, :stop],
                      %{duration: _, monotonic_time: _},
                      %{workflow_name: :test_workflow, step_name: :step_a, result: :step_result}}
    end

    test "rollback_span emits start and stop" do
      result =
        Telemetry.rollback_span(:test_workflow, "exec-123", [:step_b, :step_a], %{}, fn ->
          :rollback_done
        end)

      assert result == :rollback_done

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :rollback, :start],
                      %{system_time: _},
                      %{workflow_name: :test_workflow, steps: [:step_b, :step_a]}}

      assert_receive {:telemetry_event, [:events, :scheduler, :workflow, :rollback, :stop],
                      %{duration: _, monotonic_time: _}, %{workflow_name: :test_workflow}}
    end
  end
end
