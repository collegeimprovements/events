defmodule OmScheduler.Workflow.StepTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Workflow.Step

  describe "new/3" do
    test "creates step with name and job" do
      step = Step.new(:fetch, fn _ -> :ok end)
      assert step.name == :fetch
      assert is_function(step.job, 1)
    end

    test "creates step with module job" do
      step = Step.new(:process, MyWorker)
      assert step.name == :process
      assert step.job == MyWorker
    end

    test "creates step with MFA job" do
      step = Step.new(:call, {MyModule, :function, [:arg1]})
      assert step.name == :call
      assert step.job == {MyModule, :function, [:arg1]}
    end

    test "creates step with workflow reference job" do
      step = Step.new(:notify, {:workflow, :send_notification})
      assert step.job == {:workflow, :send_notification}
    end

    test "creates step with default options" do
      step = Step.new(:test, fn _ -> :ok end)
      assert step.state == :pending
      assert step.timeout == :timer.minutes(5)
      assert step.max_retries == 3
      assert step.retry_backoff == :exponential
      assert step.retry_jitter == false
      assert step.on_error == :fail
      assert step.await_approval == false
      assert step.cancellable == true
      assert step.attempt == 0
      assert step.context_key == :test
    end

    test "creates step with dependencies" do
      step = Step.new(:process, fn _ -> :ok end, after: [:fetch, :validate])
      assert step.depends_on == [:fetch, :validate]
    end

    test "creates step with single dependency" do
      step = Step.new(:process, fn _ -> :ok end, after: :fetch)
      assert step.depends_on == [:fetch]
    end

    test "creates step with after_any dependencies" do
      step = Step.new(:notify, fn _ -> :ok end, after_any: [:a, :b])
      assert step.depends_on_any == [:a, :b]
    end

    test "creates step with group" do
      step = Step.new(:upload, fn _ -> :ok end, group: :uploads)
      assert step.group == :uploads
    end

    test "creates step with group dependency" do
      step = Step.new(:summary, fn _ -> :ok end, after_group: :uploads)
      assert step.depends_on_group == :uploads
    end

    test "creates step with graft dependency" do
      step = Step.new(:finalize, fn _ -> :ok end, after_graft: :batch_process)
      assert step.depends_on_graft == :batch_process
    end

    test "creates step with condition" do
      condition = fn ctx -> ctx.enabled end
      step = Step.new(:optional, fn _ -> :ok end, when: condition)
      assert step.condition == condition
    end

    test "creates step with rollback" do
      step = Step.new(:charge, fn _ -> :ok end, rollback: :refund)
      assert step.rollback == :refund
    end

    test "creates step with custom timeout" do
      step = Step.new(:slow, fn _ -> :ok end, timeout: {30, :minutes})
      assert step.timeout == :timer.minutes(30)
    end

    test "creates step with infinity timeout" do
      step = Step.new(:forever, fn _ -> :ok end, timeout: :infinity)
      assert step.timeout == :infinity
    end

    test "creates step with retry configuration" do
      step =
        Step.new(:flaky, fn _ -> :ok end,
          max_retries: 10,
          retry_delay: 2000,
          retry_backoff: :linear,
          retry_max_delay: {5, :minutes},
          retry_jitter: true
        )

      assert step.max_retries == 10
      assert step.retry_delay == 2000
      assert step.retry_backoff == :linear
      assert step.retry_max_delay == :timer.minutes(5)
      assert step.retry_jitter == true
    end

    test "creates step with retry_on patterns" do
      step =
        Step.new(:api_call, fn _ -> :ok end,
          retry_on: [:timeout, :connection_error, {:error, :econnrefused}]
        )

      assert step.retry_on == [:timeout, :connection_error, {:error, :econnrefused}]
    end

    test "creates step with no_retry_on patterns" do
      step = Step.new(:validate, fn _ -> :ok end, no_retry_on: [:validation_error, :not_found])
      assert step.no_retry_on == [:validation_error, :not_found]
    end

    test "creates step with on_error setting" do
      step = Step.new(:optional, fn _ -> :ok end, on_error: :skip)
      assert step.on_error == :skip
    end

    test "creates step with await_approval" do
      step = Step.new(:approve, fn _ -> :ok end, await_approval: true)
      assert step.await_approval == true
    end

    test "creates step with circuit breaker" do
      step =
        Step.new(:external, fn _ -> :ok end,
          circuit_breaker: :external_api,
          circuit_breaker_opts: [failure_threshold: 5, reset_timeout: {30, :seconds}]
        )

      assert step.circuit_breaker == :external_api
      assert step.circuit_breaker_opts == [failure_threshold: 5, reset_timeout: {30, :seconds}]
    end

    test "creates step with custom context_key" do
      step = Step.new(:fetch_user, fn _ -> :ok end, context_key: :user)
      assert step.context_key == :user
    end

    test "creates step with metadata" do
      step = Step.new(:tagged, fn _ -> :ok end, metadata: %{priority: :high})
      assert step.metadata == %{priority: :high}
    end
  end

  describe "ready?/3" do
    test "pending step with no deps is ready" do
      step = Step.new(:first, fn _ -> :ok end)
      assert Step.ready?(step, MapSet.new(), %{})
    end

    test "pending step with satisfied deps is ready" do
      step = Step.new(:second, fn _ -> :ok end, after: [:first])
      assert Step.ready?(step, MapSet.new([:first]), %{})
    end

    test "pending step with unsatisfied deps is not ready" do
      step = Step.new(:second, fn _ -> :ok end, after: [:first])
      refute Step.ready?(step, MapSet.new(), %{})
    end

    test "non-pending step is not ready" do
      step = Step.new(:running, fn _ -> :ok end) |> Step.start()
      refute Step.ready?(step, MapSet.new(), %{})
    end

    test "step with multiple deps needs all satisfied" do
      step = Step.new(:join, fn _ -> :ok end, after: [:a, :b, :c])
      refute Step.ready?(step, MapSet.new([:a, :b]), %{})
      assert Step.ready?(step, MapSet.new([:a, :b, :c]), %{})
    end

    test "step with after_any needs at least one satisfied" do
      step = Step.new(:any, fn _ -> :ok end, after_any: [:a, :b])
      assert Step.ready?(step, MapSet.new([:a]), %{})
      assert Step.ready?(step, MapSet.new([:b]), %{})
    end

    test "step with group dependency needs group completed" do
      step = Step.new(:after_group, fn _ -> :ok end, after_group: :uploads)
      refute Step.ready?(step, MapSet.new(), %{uploads: false})
      assert Step.ready?(step, MapSet.new(), %{uploads: true})
    end

    test "step with graft dependency needs graft completed" do
      step = Step.new(:after_graft, fn _ -> :ok end, after_graft: :batch)
      refute Step.ready?(step, MapSet.new(), %{})
      assert Step.ready?(step, MapSet.new([{:graft, :batch}]), %{})
    end
  end

  describe "condition_satisfied?/2" do
    test "no condition is always satisfied" do
      step = Step.new(:unconditional, fn _ -> :ok end)
      assert Step.condition_satisfied?(step, %{anything: true})
    end

    test "true condition is satisfied" do
      step = Step.new(:conditional, fn _ -> :ok end, when: fn _ -> true end)
      assert Step.condition_satisfied?(step, %{})
    end

    test "false condition is not satisfied" do
      step = Step.new(:conditional, fn _ -> :ok end, when: fn _ -> false end)
      refute Step.condition_satisfied?(step, %{})
    end

    test "condition can access context" do
      step = Step.new(:conditional, fn _ -> :ok end, when: fn ctx -> ctx.enabled end)
      assert Step.condition_satisfied?(step, %{enabled: true})
      refute Step.condition_satisfied?(step, %{enabled: false})
    end

    test "exception in condition returns false" do
      step = Step.new(:bad, fn _ -> :ok end, when: fn _ -> raise "boom" end)
      refute Step.condition_satisfied?(step, %{})
    end
  end

  describe "state transitions" do
    test "transition/2 changes state" do
      step = Step.new(:test, fn _ -> :ok end)
      transitioned = Step.transition(step, :running)
      assert transitioned.state == :running
    end

    test "start/1 transitions to running and increments attempt" do
      step = Step.new(:test, fn _ -> :ok end)
      started = Step.start(step)
      assert started.state == :running
      assert started.attempt == 1
      assert %DateTime{} = started.started_at
    end

    test "start/1 increments attempt on each call" do
      step = Step.new(:test, fn _ -> :ok end)
      started = step |> Step.start() |> Step.reset_for_retry() |> Step.start()
      assert started.attempt == 2
    end

    test "complete/2 transitions to completed with result" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      completed = Step.complete(step, %{data: 42})
      assert completed.state == :completed
      assert completed.result == %{data: 42}
      assert %DateTime{} = completed.completed_at
      assert is_integer(completed.duration_ms)
    end

    test "fail/2 transitions to failed with error" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      failed = Step.fail(step, :timeout)
      assert failed.state == :failed
      assert failed.error == :timeout
      assert %DateTime{} = failed.completed_at
      assert is_integer(failed.duration_ms)
    end

    test "skip/2 transitions to skipped with reason" do
      step = Step.new(:test, fn _ -> :ok end)
      skipped = Step.skip(step, :condition_false)
      assert skipped.state == :skipped
      assert skipped.result == {:skipped, :condition_false}
    end

    test "await/2 transitions to awaiting" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      awaiting = Step.await(step, notify: :email, timeout: 3600)
      assert awaiting.state == :awaiting
      assert awaiting.metadata[:await_opts] == [notify: :email, timeout: 3600]
    end

    test "cancel/1 transitions to cancelled" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      cancelled = Step.cancel(step)
      assert cancelled.state == :cancelled
    end

    test "reset_for_retry/1 resets step for retry" do
      step =
        Step.new(:test, fn _ -> :ok end)
        |> Step.start()
        |> Step.fail(:timeout)
        |> Step.reset_for_retry()

      assert step.state == :pending
      assert step.started_at == nil
      assert step.completed_at == nil
      assert step.duration_ms == nil
      assert step.error == nil
      # attempt is preserved
      assert step.attempt == 1
    end
  end

  describe "can_retry?/1" do
    test "can retry when attempts < max_retries" do
      step =
        Step.new(:test, fn _ -> :ok end, max_retries: 3)
        |> Step.start()
        |> Step.fail(:error)

      assert Step.can_retry?(step)
    end

    test "cannot retry when attempts >= max_retries" do
      step =
        Step.new(:test, fn _ -> :ok end, max_retries: 1)
        |> Step.start()
        |> Step.fail(:error)

      refute Step.can_retry?(step)
    end

    test "cannot retry when max_retries is 0" do
      step = Step.new(:test, fn _ -> :ok end, max_retries: 0)
      refute Step.can_retry?(step)
    end
  end

  describe "should_retry_error?/2" do
    test "retries all errors by default" do
      step = Step.new(:test, fn _ -> :ok end)
      assert Step.should_retry_error?(step, :any_error)
      assert Step.should_retry_error?(step, {:error, :anything})
    end

    test "retries only specified errors when retry_on is set" do
      step = Step.new(:test, fn _ -> :ok end, retry_on: [:timeout, :connection_error])
      assert Step.should_retry_error?(step, :timeout)
      assert Step.should_retry_error?(step, :connection_error)
      refute Step.should_retry_error?(step, :validation_error)
    end

    test "no_retry_on takes precedence over retry_on" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_on: [:timeout],
          no_retry_on: [:timeout]
        )

      refute Step.should_retry_error?(step, :timeout)
    end

    test "matches tuple errors" do
      step = Step.new(:test, fn _ -> :ok end, retry_on: [{:error, :econnrefused}])
      assert Step.should_retry_error?(step, {:error, :econnrefused})
      refute Step.should_retry_error?(step, {:error, :other})
    end

    test "matches struct errors by type" do
      step = Step.new(:test, fn _ -> :ok end, retry_on: [ArgumentError])
      assert Step.should_retry_error?(step, %ArgumentError{message: "test"})
      refute Step.should_retry_error?(step, %RuntimeError{message: "test"})
    end
  end

  describe "calculate_retry_delay/1" do
    test "fixed backoff returns constant delay" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: :fixed
        )

      step = Step.start(step)
      assert Step.calculate_retry_delay(step) == 1000

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 1000
    end

    test "exponential backoff doubles delay" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: :exponential,
          retry_jitter: false
        )

      step = Step.start(step)
      assert Step.calculate_retry_delay(step) == 1000

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 2000

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 4000
    end

    test "linear backoff increases linearly" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: :linear,
          retry_jitter: false
        )

      step = Step.start(step)
      assert Step.calculate_retry_delay(step) == 1000

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 2000

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 3000
    end

    test "retry_max_delay caps the delay" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: :exponential,
          retry_max_delay: 3000,
          retry_jitter: false
        )

      # attempt 3 would be 4000ms but capped at 3000
      step =
        Step.start(step)
        |> Step.reset_for_retry()
        |> Step.start()
        |> Step.reset_for_retry()
        |> Step.start()

      assert Step.calculate_retry_delay(step) == 3000
    end

    test "custom backoff function" do
      custom_fn = fn attempt, base -> base + attempt * 100 end

      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: custom_fn,
          retry_jitter: false
        )

      step = Step.start(step)
      assert Step.calculate_retry_delay(step) == 1100

      step = step |> Step.reset_for_retry() |> Step.start()
      assert Step.calculate_retry_delay(step) == 1200
    end

    test "jitter adds randomness" do
      step =
        Step.new(:test, fn _ -> :ok end,
          retry_delay: 1000,
          retry_backoff: :fixed,
          retry_jitter: true
        )

      step = Step.start(step)

      # With jitter, delay should be between 1000 and 1100 (10% jitter)
      delays = for _ <- 1..100, do: Step.calculate_retry_delay(step)
      assert Enum.all?(delays, &(&1 >= 1000 and &1 <= 1100))
      # Should have some variation
      assert Enum.uniq(delays) |> length() > 1
    end
  end

  describe "get_timeout/2" do
    test "returns static timeout" do
      step = Step.new(:test, fn _ -> :ok end, timeout: 5000)
      assert Step.get_timeout(step, %{}) == 5000
    end

    test "returns infinity timeout" do
      step = Step.new(:test, fn _ -> :ok end, timeout: :infinity)
      assert Step.get_timeout(step, %{}) == :infinity
    end

    test "evaluates dynamic timeout function" do
      timeout_fn = fn ctx -> ctx.data_size * 10 end
      step = Step.new(:test, fn _ -> :ok end, timeout: timeout_fn)
      assert Step.get_timeout(step, %{data_size: 100}) == 1000
      assert Step.get_timeout(step, %{data_size: 500}) == 5000
    end
  end

  describe "has_rollback?/1" do
    test "returns false when no rollback" do
      step = Step.new(:test, fn _ -> :ok end)
      refute Step.has_rollback?(step)
    end

    test "returns true when rollback is set" do
      step = Step.new(:test, fn _ -> :ok end, rollback: :undo)
      assert Step.has_rollback?(step)
    end
  end

  describe "terminal?/1" do
    test "completed is terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start() |> Step.complete(:ok)
      assert Step.terminal?(step)
    end

    test "failed is terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start() |> Step.fail(:error)
      assert Step.terminal?(step)
    end

    test "skipped is terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.skip(:condition)
      assert Step.terminal?(step)
    end

    test "cancelled is terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start() |> Step.cancel()
      assert Step.terminal?(step)
    end

    test "pending is not terminal" do
      step = Step.new(:test, fn _ -> :ok end)
      refute Step.terminal?(step)
    end

    test "running is not terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start()
      refute Step.terminal?(step)
    end

    test "awaiting is not terminal" do
      step = Step.new(:test, fn _ -> :ok end) |> Step.start() |> Step.await()
      refute Step.terminal?(step)
    end
  end
end
