defmodule EffectTest do
  @moduledoc """
  Tests for Effect - Composable effects with dependencies, rollback, and retry.

  Effect provides a powerful system for building multi-step workflows with
  error handling, automatic rollback, parallel execution, and checkpointing.

  ## Use Cases

  - **Order processing**: Validate → Reserve Inventory → Charge → Ship (with rollback)
  - **User onboarding**: Create Account → Send Email → Setup Defaults (with retry)
  - **Data imports**: Parse → Validate → Transform → Load (with checkpoints)
  - **API orchestration**: Fetch A || Fetch B → Merge → Process (parallel + sequential)

  ## Pattern: Effect Composition

      Effect.new(:checkout)
      |> Effect.step(:validate, &validate_order/1)
      |> Effect.step(:reserve, &reserve_inventory/1, rollback: &release_inventory/1)
      |> Effect.step(:charge, &charge_payment/1, rollback: &refund_payment/1)
      |> Effect.step(:ship, &initiate_shipping/1, after: :charge)
      |> Effect.run(initial_context)

  Effects support: dependencies, rollback, retry, parallel, branch, race, embed,
  middleware, services, checkpoints, and visualization.
  """

  use ExUnit.Case, async: true

  describe "Effect.new/2" do
    test "creates an effect with name" do
      effect = Effect.new(:test)
      assert effect.name == :test
      assert effect.steps == []
    end

    test "accepts options" do
      effect = Effect.new(:test, label: "Test Effect", tags: [:critical])
      assert effect.label == "Test Effect"
      assert effect.tags == [:critical]
    end
  end

  describe "Effect.step/4" do
    test "adds a step to the effect" do
      effect =
        Effect.new(:test)
        |> Effect.step(:first, fn _ctx -> {:ok, %{value: 1}} end)

      assert length(effect.steps) == 1
      assert hd(effect.steps).name == :first
    end

    test "preserves step order" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end)
        |> Effect.step(:c, fn _ -> {:ok, %{}} end)

      assert Effect.step_names(effect) == [:a, :b, :c]
    end
  end

  describe "Effect.assign/3" do
    test "adds static value assignment" do
      effect =
        Effect.new(:test)
        |> Effect.assign(:value, 42)

      assert length(effect.steps) == 1
    end

    test "adds computed value assignment" do
      effect =
        Effect.new(:test)
        |> Effect.assign(:doubled, fn ctx -> ctx.value * 2 end)

      assert length(effect.steps) == 1
    end
  end

  describe "Effect.require/5" do
    test "adds a require step" do
      effect =
        Effect.new(:test)
        |> Effect.require(:auth, fn ctx -> ctx.authenticated end, :unauthorized)

      assert length(effect.steps) == 1
      assert hd(effect.steps).type == :require
    end
  end

  describe "Effect.validate/1" do
    test "validates correct effect" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end, after: :a)

      assert Effect.validate(effect) == :ok
    end
  end

  describe "Effect.run/3" do
    test "executes steps in order" do
      effect =
        Effect.new(:test)
        |> Effect.step(:first, fn _ -> {:ok, %{first: true}} end)
        |> Effect.step(:second, fn _ -> {:ok, %{second: true}} end)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.first == true
      assert ctx.second == true
    end

    test "accumulates context" do
      effect =
        Effect.new(:test)
        |> Effect.step(:add_a, fn _ -> {:ok, %{a: 1}} end)
        |> Effect.step(:add_b, fn ctx -> {:ok, %{b: ctx.a + 1}} end)
        |> Effect.step(:add_c, fn ctx -> {:ok, %{c: ctx.b + 1}} end)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx == %{a: 1, b: 2, c: 3}
    end

    test "respects dependencies" do
      order = :ets.new(:order, [:public, :set])
      :ets.insert(order, {:counter, 0})

      record_order = fn name ->
        [{:counter, n}] = :ets.lookup(order, :counter)
        :ets.insert(order, {:counter, n + 1})
        :ets.insert(order, {name, n})
      end

      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ ->
          record_order.(:a)
          {:ok, %{}}
        end)
        |> Effect.step(:b, fn _ ->
          record_order.(:b)
          {:ok, %{}}
        end, after: :a)
        |> Effect.step(:c, fn _ ->
          record_order.(:c)
          {:ok, %{}}
        end, after: :b)

      assert {:ok, _} = Effect.run(effect, %{})

      [{:a, a_order}] = :ets.lookup(order, :a)
      [{:b, b_order}] = :ets.lookup(order, :b)
      [{:c, c_order}] = :ets.lookup(order, :c)

      assert a_order < b_order
      assert b_order < c_order

      :ets.delete(order)
    end

    test "handles errors" do
      effect =
        Effect.new(:test)
        |> Effect.step(:success, fn _ -> {:ok, %{done: true}} end)
        |> Effect.step(:fail, fn _ -> {:error, :something_wrong} end)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :fail
      assert error.reason == :something_wrong
    end

    test "handles halt" do
      effect =
        Effect.new(:test)
        |> Effect.step(:check, fn _ -> {:halt, :stopped_early} end)
        |> Effect.step(:never, fn _ -> {:ok, %{reached: true}} end)

      assert {:halted, :stopped_early} = Effect.run(effect, %{})
    end

    test "skips steps when condition is false" do
      effect =
        Effect.new(:test)
        |> Effect.step(:always, fn _ -> {:ok, %{always: true}} end)
        |> Effect.step(:conditional, fn _ -> {:ok, %{conditional: true}} end,
          when: fn ctx -> ctx.run_conditional end
        )

      assert {:ok, ctx} = Effect.run(effect, %{run_conditional: false})
      assert ctx.always == true
      refute Map.has_key?(ctx, :conditional)
    end

    test "returns report when requested" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end)

      assert {{:ok, _ctx}, report} = Effect.run(effect, %{}, report: true)
      assert report.effect_name == :test
      assert report.status == :ok
      assert report.steps_completed == 2
    end
  end

  describe "Effect.run!/3" do
    test "returns context on success" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{value: 42}} end)

      ctx = Effect.run!(effect, %{})
      assert ctx.value == 42
    end

    test "raises on error" do
      effect =
        Effect.new(:test)
        |> Effect.step(:fail, fn _ -> {:error, :boom} end)

      assert_raise RuntimeError, fn ->
        Effect.run!(effect, %{})
      end
    end
  end

  describe "rollback" do
    test "step stores rollback function" do
      rollback_fn = fn _ -> :ok end
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end, rollback: rollback_fn)

      step = hd(effect.steps)
      assert step.rollback == rollback_fn
    end

    test "executes rollbacks in reverse order on error" do
      rollback_order = :ets.new(:rollbacks, [:public, :ordered_set])

      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{a: true}} end,
          rollback: fn _ ->
            :ets.insert(rollback_order, {System.monotonic_time(), :a})
            :ok
          end
        )
        |> Effect.step(:b, fn _ -> {:ok, %{b: true}} end,
          rollback: fn _ ->
            :ets.insert(rollback_order, {System.monotonic_time(), :b})
            :ok
          end
        )
        |> Effect.step(:c, fn _ -> {:error, :fail} end)

      assert {:error, _} = Effect.run(effect, %{})

      rollbacks = :ets.tab2list(rollback_order) |> Enum.map(fn {_, name} -> name end)
      # b should rollback before a (reverse order)
      assert rollbacks == [:b, :a]

      :ets.delete(rollback_order)
    end

    test "collects rollback errors" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end,
          rollback: fn _ -> {:error, :rollback_failed} end
        )
        |> Effect.step(:b, fn _ -> {:error, :fail} end)

      assert {:error, error} = Effect.run(effect, %{})
      assert length(error.rollback_errors) == 1
      assert hd(error.rollback_errors).step == :a
    end
  end

  describe "middleware" do
    test "wraps step execution" do
      calls = :ets.new(:calls, [:public, :bag])

      effect =
        Effect.new(:test)
        |> Effect.middleware(fn step, _ctx, next ->
          :ets.insert(calls, {:before, step})
          result = next.()
          :ets.insert(calls, {:after, step})
          result
        end)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)

      assert {:ok, _} = Effect.run(effect, %{})

      records = :ets.tab2list(calls)
      assert {:before, :a} in records
      assert {:after, :a} in records

      :ets.delete(calls)
    end
  end

  describe "services" do
    test "passes services to 2-arity steps" do
      defmodule TestService do
        def call, do: :service_called
      end

      effect =
        Effect.new(:test, services: %{test: TestService})
        |> Effect.step(:use_service, fn _ctx, services ->
          {:ok, %{result: services.test.call()}}
        end)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.result == :service_called
    end
  end

  describe "parallel" do
    test "executes steps concurrently" do
      results = :ets.new(:results, [:public, :set])

      effect =
        Effect.new(:test)
        |> Effect.parallel(:concurrent, [
          {:a, fn _ ->
            :ets.insert(results, {:a_started, System.monotonic_time(:millisecond)})
            Process.sleep(50)
            :ets.insert(results, {:a_ended, System.monotonic_time(:millisecond)})
            {:ok, %{a: 1}}
          end},
          {:b, fn _ ->
            :ets.insert(results, {:b_started, System.monotonic_time(:millisecond)})
            Process.sleep(50)
            :ets.insert(results, {:b_ended, System.monotonic_time(:millisecond)})
            {:ok, %{b: 2}}
          end}
        ])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.a == 1
      assert ctx.b == 2

      # Verify concurrent execution (both should start around the same time)
      [{:a_started, a_start}] = :ets.lookup(results, :a_started)
      [{:b_started, b_start}] = :ets.lookup(results, :b_started)
      assert abs(a_start - b_start) < 20  # Should start within 20ms of each other

      :ets.delete(results)
    end

    test "merges results left-to-right (last writer wins)" do
      effect =
        Effect.new(:test)
        |> Effect.parallel(:merge_test, [
          {:first, fn _ -> {:ok, %{x: 1, shared: :first}} end},
          {:second, fn _ -> {:ok, %{y: 2, shared: :second}} end}
        ])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.x == 1
      assert ctx.y == 2
      assert ctx.shared == :second  # Second wins
    end

    test "fail_fast stops on first error" do
      counter = :ets.new(:counter, [:public, :set])
      :ets.insert(counter, {:completed, 0})

      effect =
        Effect.new(:test)
        |> Effect.parallel(:checks, [
          {:fast_fail, fn _ ->
            {:error, :immediate_fail}
          end},
          {:slow, fn _ ->
            Process.sleep(100)
            [{:completed, n}] = :ets.lookup(counter, :completed)
            :ets.insert(counter, {:completed, n + 1})
            {:ok, %{slow: true}}
          end}
        ], on_error: :fail_fast)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :fast_fail
      assert error.reason == :immediate_fail

      :ets.delete(counter)
    end

    test "respects after dependency" do
      order = :ets.new(:order, [:public, :ordered_set])

      effect =
        Effect.new(:test)
        |> Effect.step(:first, fn _ ->
          :ets.insert(order, {System.monotonic_time(:nanosecond), :first})
          {:ok, %{first: true}}
        end)
        |> Effect.parallel(:parallel_group, [
          {:a, fn _ ->
            :ets.insert(order, {System.monotonic_time(:nanosecond), :a})
            {:ok, %{a: true}}
          end},
          {:b, fn _ ->
            :ets.insert(order, {System.monotonic_time(:nanosecond), :b})
            {:ok, %{b: true}}
          end}
        ], after: :first)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.first == true
      assert ctx.a == true
      assert ctx.b == true

      # Verify first ran before parallel group
      execution_order = :ets.tab2list(order) |> Enum.map(fn {_, name} -> name end)
      assert hd(execution_order) == :first

      :ets.delete(order)
    end

    test "triggers rollback on parallel failure" do
      rollback_calls = :ets.new(:rollbacks, [:public, :bag])

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ ->
            :ets.insert(rollback_calls, {:rollback, :setup})
            :ok
          end
        )
        |> Effect.parallel(:checks, [
          {:good, fn _ -> {:ok, %{good: true}} end},
          {:bad, fn _ -> {:error, :parallel_fail} end}
        ], after: :setup)

      assert {:error, _} = Effect.run(effect, %{})

      rollbacks = :ets.tab2list(rollback_calls)
      assert {:rollback, :setup} in rollbacks

      :ets.delete(rollback_calls)
    end
  end

  describe "retry" do
    test "retries failing step until success" do
      counter = :ets.new(:counter, [:public, :set])
      :ets.insert(counter, {:attempts, 0})

      effect =
        Effect.new(:test)
        |> Effect.step(:flaky, fn _ ->
          [{:attempts, n}] = :ets.lookup(counter, :attempts)
          :ets.insert(counter, {:attempts, n + 1})

          if n < 2 do
            {:error, :temporary_failure}
          else
            {:ok, %{succeeded_on_attempt: n + 1}}
          end
        end, retry: [max: 5, delay: 1, backoff: :fixed])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.succeeded_on_attempt == 3

      :ets.delete(counter)
    end

    test "fails after max retries exhausted" do
      counter = :ets.new(:counter, [:public, :set])
      :ets.insert(counter, {:attempts, 0})

      effect =
        Effect.new(:test)
        |> Effect.step(:always_fail, fn _ ->
          [{:attempts, n}] = :ets.lookup(counter, :attempts)
          :ets.insert(counter, {:attempts, n + 1})
          {:error, :persistent_failure}
        end, retry: [max: 3, delay: 1, backoff: :fixed])

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :always_fail
      assert error.reason == :persistent_failure
      assert error.attempts == 3

      [{:attempts, final}] = :ets.lookup(counter, :attempts)
      assert final == 3

      :ets.delete(counter)
    end

    test "respects retry when predicate" do
      counter = :ets.new(:counter, [:public, :set])
      :ets.insert(counter, {:attempts, 0})

      effect =
        Effect.new(:test)
        |> Effect.step(:selective_retry, fn _ ->
          [{:attempts, n}] = :ets.lookup(counter, :attempts)
          :ets.insert(counter, {:attempts, n + 1})

          if n == 0 do
            {:error, :retryable}
          else
            {:error, :not_retryable}
          end
        end, retry: [
          max: 5,
          delay: 1,
          backoff: :fixed,
          when: fn
            :retryable -> true
            _ -> false
          end
        ])

      assert {:error, error} = Effect.run(effect, %{})
      assert error.reason == :not_retryable
      # Should have tried twice: first got :retryable (retry), second got :not_retryable (stop)
      assert error.attempts == 2

      :ets.delete(counter)
    end

    test "tracks attempts in report" do
      counter = :ets.new(:counter, [:public, :set])
      :ets.insert(counter, {:attempts, 0})

      effect =
        Effect.new(:test)
        |> Effect.step(:retry_step, fn _ ->
          [{:attempts, n}] = :ets.lookup(counter, :attempts)
          :ets.insert(counter, {:attempts, n + 1})

          if n < 1 do
            {:error, :fail}
          else
            {:ok, %{done: true}}
          end
        end, retry: [max: 3, delay: 1, backoff: :fixed])

      assert {{:ok, _ctx}, report} = Effect.run(effect, %{}, report: true)
      step_report = Enum.find(report.steps, &(&1.name == :retry_step))
      assert step_report.attempts == 2

      :ets.delete(counter)
    end
  end

  describe "branch" do
    test "selects correct branch based on context" do
      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{order_type: :digital}} end)
        |> Effect.branch(:fulfill, & &1.order_type, %{
          digital: fn _ -> {:ok, %{fulfilled: :email_sent}} end,
          physical: fn _ -> {:ok, %{fulfilled: :shipped}} end
        }, after: :setup)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.fulfilled == :email_sent
    end

    test "uses default when no match" do
      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{order_type: :unknown}} end)
        |> Effect.branch(:fulfill, & &1.order_type, %{
          digital: fn _ -> {:ok, %{fulfilled: :email_sent}} end,
          default: fn _ -> {:ok, %{fulfilled: :manual_review}} end
        }, after: :setup)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.fulfilled == :manual_review
    end

    test "errors when no match and no default" do
      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{order_type: :unknown}} end)
        |> Effect.branch(:fulfill, & &1.order_type, %{
          digital: fn _ -> {:ok, %{fulfilled: :email_sent}} end
        }, after: :setup)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :fulfill
      assert {:no_matching_branch, :unknown} = error.reason
    end
  end

  describe "embed" do
    test "executes nested effect" do
      nested = Effect.new(:nested)
        |> Effect.step(:inner, fn _ -> {:ok, %{inner_result: 42}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end)
        |> Effect.embed(:nested_step, nested, after: :setup)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.setup == true
      assert ctx.inner_result == 42
    end

    test "transforms context for nested effect" do
      nested = Effect.new(:nested)
        |> Effect.step(:process, fn ctx -> {:ok, %{doubled: ctx.value * 2}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{data: 10}} end)
        |> Effect.embed(:transform, nested,
          after: :setup,
          context: fn ctx -> %{value: ctx.data} end
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.doubled == 20
    end

    test "propagates errors from nested effect" do
      nested = Effect.new(:nested)
        |> Effect.step(:fail, fn _ -> {:error, :nested_failure} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ -> :ok end
        )
        |> Effect.embed(:nested_step, nested, after: :setup)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :nested_step
      assert {:nested_effect_failed, :nested_failure} = error.reason
    end
  end

  describe "each" do
    test "iterates over collection sequentially" do
      item_effect = Effect.new(:item)
        |> Effect.step(:process, fn ctx -> {:ok, %{processed: ctx.item * 2}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{items: [1, 2, 3]}} end)
        |> Effect.each(:process_all, & &1.items, item_effect, after: :setup)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.process_all == [%{processed: 2}, %{processed: 4}, %{processed: 6}]
    end

    test "handles empty collection" do
      item_effect = Effect.new(:item)
        |> Effect.step(:process, fn ctx -> {:ok, %{processed: ctx.item}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{items: []}} end)
        |> Effect.each(:process_all, & &1.items, item_effect, after: :setup)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.process_all == []
    end

    test "supports custom item key" do
      item_effect = Effect.new(:item)
        |> Effect.step(:process, fn ctx -> {:ok, %{result: ctx.current * 10}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{numbers: [1, 2]}} end)
        |> Effect.each(:multiply, & &1.numbers, item_effect,
          after: :setup,
          as: :current,
          collect: :results
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.results == [%{result: 10}, %{result: 20}]
    end

    test "stops on first error" do
      item_effect = Effect.new(:item)
        |> Effect.step(:process, fn ctx ->
          if ctx.item == 2 do
            {:error, :bad_item}
          else
            {:ok, %{processed: ctx.item}}
          end
        end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{items: [1, 2, 3]}} end)
        |> Effect.each(:process_all, & &1.items, item_effect, after: :setup)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :process_all
      assert {:iteration_failed, 1, :bad_item} = error.reason
    end
  end

  describe "race" do
    test "returns first successful result" do
      slow = Effect.new(:slow)
        |> Effect.step(:wait, fn _ ->
          Process.sleep(100)
          {:ok, %{winner: :slow}}
        end)

      fast = Effect.new(:fast)
        |> Effect.step(:quick, fn _ ->
          {:ok, %{winner: :fast}}
        end)

      effect =
        Effect.new(:test)
        |> Effect.race(:fetch, [slow, fast])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.winner == :fast
    end

    test "fails if all contestants fail" do
      fail1 = Effect.new(:fail1)
        |> Effect.step(:err, fn _ -> {:error, :first_error} end)

      fail2 = Effect.new(:fail2)
        |> Effect.step(:err, fn _ -> {:error, :second_error} end)

      effect =
        Effect.new(:test)
        |> Effect.race(:fetch, [fail1, fail2])

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :fetch
      assert {:race_all_failed, _failures} = error.reason
    end
  end

  # ============================================
  # Phase 5: Visualization
  # ============================================

  describe "visualization" do
    test "to_ascii generates ASCII representation" do
      effect =
        Effect.new(:workflow)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end, after: :a)

      ascii = Effect.to_ascii(effect)
      assert is_binary(ascii)
      assert ascii =~ "workflow"
    end

    test "to_mermaid generates Mermaid diagram" do
      effect =
        Effect.new(:workflow)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end, after: :a)

      mermaid = Effect.to_mermaid(effect)
      assert is_binary(mermaid)
      assert mermaid =~ "graph"
      assert mermaid =~ "a"
      assert mermaid =~ "b"
    end

    test "summary returns effect structure info" do
      effect =
        Effect.new(:workflow)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end)
        |> Effect.parallel(:checks, [
          {:c1, fn _ -> {:ok, %{}} end},
          {:c2, fn _ -> {:ok, %{}} end}
        ])

      summary = Effect.summary(effect)
      assert summary.name == :workflow
      assert summary.step_count == 3
      assert :a in summary.steps
      assert :b in summary.steps
      assert :checks in summary.steps
      assert summary.has_parallel == true
    end
  end

  # ============================================
  # Telemetry
  # ============================================

  describe "telemetry" do
    test "emits span events" do
      test_pid = self()

      # Attach handler
      :telemetry.attach(
        "test-span",
        [:test, :span, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Run span
      result = Effect.Telemetry.span([:test, :span], %{key: :value}, fn ->
        {:ok, :result}
      end)

      assert result == {:ok, :result}

      # Verify event received
      assert_receive {:telemetry, [:test, :span, :stop], measurements, metadata}, 1000
      assert is_integer(measurements.duration)
      assert metadata.key == :value
      assert metadata.result == :ok

      # Cleanup
      :telemetry.detach("test-span")
    end

    test "emit_run_start emits run start event" do
      test_pid = self()

      :telemetry.attach(
        "test-run-start",
        [:effect, :run, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Effect.Telemetry.emit_run_start([:effect], :test_effect, "exec-123", %{a: 1})

      assert_receive {:telemetry, [:effect, :run, :start], _measurements, metadata}, 1000
      assert metadata.effect_name == :test_effect
      assert metadata.execution_id == "exec-123"
      assert :a in metadata.context_keys

      :telemetry.detach("test-run-start")
    end

    test "prefix returns correct event prefix" do
      assert Effect.Telemetry.prefix(nil) == [:effect]
      assert Effect.Telemetry.prefix(:order) == [:effect, :order]
      assert Effect.Telemetry.prefix([:app, :workflow]) == [:app, :workflow]
    end
  end

  # ============================================
  # Resource Management (using)
  # ============================================

  describe "using" do
    test "acquires, uses, and releases resource" do
      test_pid = self()

      body_effect =
        Effect.new(:body)
        |> Effect.step(:work, fn ctx ->
          send(test_pid, {:work, ctx.resource})
          {:ok, %{result: ctx.resource * 2}}
        end)

      effect =
        Effect.new(:test)
        |> Effect.using(:res, [
          acquire: fn _ctx ->
            send(test_pid, :acquired)
            {:ok, %{resource: 42}}
          end,
          release: fn _ctx, _result ->
            send(test_pid, :released)
          end,
          body: body_effect
        ])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.result == 84

      # Verify lifecycle
      assert_received :acquired
      assert_received {:work, 42}
      assert_received :released
    end

    test "releases resource even on body error" do
      test_pid = self()

      body_effect =
        Effect.new(:body)
        |> Effect.step(:fail, fn _ctx -> {:error, :body_failed} end)

      effect =
        Effect.new(:test)
        |> Effect.using(:res, [
          acquire: fn _ctx ->
            send(test_pid, :acquired)
            {:ok, %{resource: 123}}
          end,
          release: fn _ctx, _result ->
            send(test_pid, :released)
          end,
          body: body_effect
        ])

      assert {:error, _error} = Effect.run(effect, %{})

      # Release should still be called
      assert_received :acquired
      assert_received :released
    end

    test "handles acquire failure" do
      effect =
        Effect.new(:test)
        |> Effect.using(:res, [
          acquire: fn _ctx -> {:error, :resource_unavailable} end,
          release: fn _ctx, _result -> :ok end,
          body: Effect.new(:body) |> Effect.step(:work, fn _ -> {:ok, %{}} end)
        ])

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :res
      assert {:acquire_failed, :resource_unavailable} = error.reason
    end
  end

  # ============================================
  # Testing Utilities
  # ============================================

  describe "Effect.Testing" do
    import Effect.Testing

    test "mock_step replaces step function" do
      effect =
        Effect.new(:test)
        |> Effect.step(:original, fn _ -> {:ok, %{value: 1}} end)

      mocked = mock_step(effect, :original, fn _ -> {:ok, %{value: 999}} end)

      assert {:ok, ctx} = Effect.run(mocked, %{})
      assert ctx.value == 999
    end

    test "run_with_report returns execution report" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end)

      report = run_with_report(effect, %{})
      assert report.status == :ok
      assert :a in Effect.Report.executed_steps(report)
      assert :b in Effect.Report.executed_steps(report)
    end

    test "flaky_step fails specified number of times" do
      flaky = flaky_step(2, {:ok, %{result: :success}})

      # First two calls fail
      assert {:error, {:attempt_failed, 1}} = flaky.(%{})
      assert {:error, {:attempt_failed, 2}} = flaky.(%{})

      # Third call succeeds
      assert {:ok, %{result: :success}} = flaky.(%{})
    end

    test "assert_steps_executed verifies step order" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{}} end)

      report = run_with_report(effect, %{})
      assert_steps_executed(report, [:a, :b])
    end
  end

  # ============================================
  # Checkpoint/Resume
  # ============================================

  describe "checkpoint" do
    setup do
      # Initialize in-memory checkpoint store
      Effect.Checkpoint.InMemory.clear()
      :ok
    end

    test "pauses execution at checkpoint and stores state" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{step_a: :done}} end)
        |> Effect.checkpoint(:pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:b, fn _ -> {:ok, %{step_b: :done}} end)

      result = Effect.run(effect, %{initial: true})

      # Should pause at checkpoint
      assert {:checkpoint, exec_id, :pause, ctx} = result
      assert ctx.step_a == :done
      assert ctx.initial == true
      refute Map.has_key?(ctx, :step_b)

      # Verify state was stored
      {:ok, state} = Effect.Checkpoint.InMemory.load(exec_id)
      assert state.checkpoint == :pause
      assert state.effect_name == :test
    end

    test "resumes execution from checkpoint" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{step_a: :done}} end)
        |> Effect.checkpoint(:pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:b, fn _ -> {:ok, %{step_b: :done}} end)

      # First run pauses at checkpoint
      {:checkpoint, exec_id, :pause, _ctx} = Effect.run(effect, %{initial: true})

      # Resume execution
      {:ok, final_ctx} = Effect.resume(effect, exec_id)

      # Should have results from both steps
      assert final_ctx.step_a == :done
      assert final_ctx.step_b == :done
      assert final_ctx.initial == true
    end

    test "resume returns error for unknown execution_id" do
      effect =
        Effect.new(:test)
        |> Effect.checkpoint(:pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )

      {:error, error} = Effect.resume(effect, "unknown_id")
      assert error.step == :resume
      assert {:checkpoint_not_found, "unknown_id"} = error.reason
    end

    test "double resume returns already_resumed error" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{step_a: :done}} end)
        |> Effect.checkpoint(:pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:b, fn _ -> {:ok, %{step_b: :done}} end)

      # First run pauses at checkpoint
      {:checkpoint, exec_id, :pause, _ctx} = Effect.run(effect, %{initial: true})

      # First resume succeeds
      {:ok, final_ctx} = Effect.resume(effect, exec_id)
      assert final_ctx.step_b == :done

      # Second resume fails with already_resumed
      {:error, error} = Effect.resume(effect, exec_id)
      assert error.step == :resume
      assert {:already_resumed, ^exec_id} = error.reason
    end

    test "checkpoint state is cleaned up after successful resume" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{step_a: :done}} end)
        |> Effect.checkpoint(:pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:b, fn _ -> {:ok, %{step_b: :done}} end)

      {:checkpoint, exec_id, :pause, _ctx} = Effect.run(effect, %{})
      {:ok, _} = Effect.resume(effect, exec_id)

      # Checkpoint state should be marked as completed
      {:ok, state} = Effect.Checkpoint.InMemory.load(exec_id)
      assert state.status == :completed
    end

    test "multiple checkpoints in one effect" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{step_a: :done}} end)
        |> Effect.checkpoint(:first_pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:b, fn _ -> {:ok, %{step_b: :done}} end)
        |> Effect.checkpoint(:second_pause,
          store: &Effect.Checkpoint.InMemory.store/2,
          load: &Effect.Checkpoint.InMemory.load/1
        )
        |> Effect.step(:c, fn _ -> {:ok, %{step_c: :done}} end)

      # First run pauses at first checkpoint
      {:checkpoint, exec_id_1, :first_pause, ctx1} = Effect.run(effect, %{})
      assert ctx1.step_a == :done
      refute Map.has_key?(ctx1, :step_b)

      # Resume hits second checkpoint
      {:checkpoint, exec_id_2, :second_pause, ctx2} = Effect.resume(effect, exec_id_1)
      assert ctx2.step_a == :done
      assert ctx2.step_b == :done
      refute Map.has_key?(ctx2, :step_c)

      # Resume from second checkpoint completes
      {:ok, final_ctx} = Effect.resume(effect, exec_id_2)
      assert final_ctx.step_a == :done
      assert final_ctx.step_b == :done
      assert final_ctx.step_c == :done
    end
  end

  # ============================================
  # Step validation
  # ============================================

  describe "step validation" do
    test "raises on invalid step function" do
      assert_raise ArgumentError, ~r/expected step function/, fn ->
        Effect.new(:test)
        |> Effect.step(:bad, "not a function")
      end
    end

    test "raises on wrong arity function" do
      assert_raise ArgumentError, ~r/expected step function/, fn ->
        Effect.new(:test)
        |> Effect.step(:bad, fn _a, _b, _c -> :ok end)
      end
    end
  end

  # ============================================
  # Error stacktrace preservation
  # ============================================

  describe "stacktrace preservation" do
    test "preserves stacktrace when step raises" do
      effect =
        Effect.new(:test)
        |> Effect.step(:raise_step, fn _ -> raise "boom" end)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :raise_step
      assert %RuntimeError{message: "boom"} = error.reason
      assert is_list(error.stacktrace)
      assert length(error.stacktrace) > 0
    end
  end

  # ============================================
  # Parallel edge cases
  # ============================================

  describe "parallel edge cases" do
    test "on_error: :continue collects all errors" do
      effect =
        Effect.new(:test)
        |> Effect.parallel(:checks, [
          {:a, fn _ -> {:error, :fail_a} end},
          {:b, fn _ -> {:error, :fail_b} end},
          {:c, fn _ -> {:ok, %{c: true}} end}
        ], on_error: :continue)

      assert {:error, error} = Effect.run(effect, %{})
      # Should report the first error encountered
      assert error.step in [:a, :b]
    end

    test "parallel triggers rollback of prior steps" do
      rollbacks = :ets.new(:rollbacks, [:public, :bag])

      effect =
        Effect.new(:test)
        |> Effect.step(:setup_a, fn _ -> {:ok, %{a: true}} end,
          rollback: fn _ ->
            :ets.insert(rollbacks, {:rollback, :setup_a})
            :ok
          end
        )
        |> Effect.step(:setup_b, fn _ -> {:ok, %{b: true}} end,
          rollback: fn _ ->
            :ets.insert(rollbacks, {:rollback, :setup_b})
            :ok
          end
        )
        |> Effect.parallel(:failing_group, [
          {:good, fn _ -> {:ok, %{}} end},
          {:bad, fn _ -> {:error, :parallel_boom} end}
        ], after: :setup_b)

      assert {:error, _} = Effect.run(effect, %{})

      rolled_back = :ets.tab2list(rollbacks) |> Enum.map(fn {_, name} -> name end)
      assert :setup_a in rolled_back
      assert :setup_b in rolled_back

      :ets.delete(rollbacks)
    end
  end

  # ============================================
  # Per-step timeout
  # ============================================

  describe "per-step timeout" do
    test "step succeeds within timeout" do
      effect =
        Effect.new(:test)
        |> Effect.step(:fast, fn _ ->
          Process.sleep(10)
          {:ok, %{done: true}}
        end, timeout: 5_000)

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.done == true
    end

    test "step fails when exceeding timeout" do
      effect =
        Effect.new(:test)
        |> Effect.step(:slow, fn _ ->
          Process.sleep(500)
          {:ok, %{done: true}}
        end, timeout: 50)

      assert {:error, error} = Effect.run(effect, %{})
      assert error.step == :slow
      assert {:step_timeout, :slow, 50} = error.reason
    end

    test "timeout triggers rollback of prior steps" do
      test_pid = self()

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ ->
            send(test_pid, :setup_rolled_back)
            :ok
          end
        )
        |> Effect.step(:slow, fn _ ->
          Process.sleep(500)
          {:ok, %{}}
        end, timeout: 50, after: :setup)

      assert {:error, _} = Effect.run(effect, %{})
      assert_received :setup_rolled_back
    end
  end

  # ============================================
  # Total execution timeout
  # ============================================

  describe "total execution timeout" do
    test "completes within timeout" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ -> {:ok, %{a: true}} end)
        |> Effect.step(:b, fn _ -> {:ok, %{b: true}} end)

      assert {:ok, ctx} = Effect.run(effect, %{}, timeout: 5_000)
      assert ctx.a == true
      assert ctx.b == true
    end

    test "fails when total execution exceeds timeout" do
      effect =
        Effect.new(:test)
        |> Effect.step(:a, fn _ ->
          Process.sleep(200)
          {:ok, %{a: true}}
        end)

      assert {:error, error} = Effect.run(effect, %{}, timeout: 50)
      assert error.step == :timeout
      assert {:execution_timeout, 50} = error.reason
    end
  end

  # ============================================
  # Catch handler
  # ============================================

  describe "catch handler" do
    test "catches error and recovers" do
      effect =
        Effect.new(:test)
        |> Effect.step(:risky, fn _ -> {:error, :boom} end,
          catch: fn reason, _ctx ->
            {:ok, %{recovered: true, original_error: reason}}
          end
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.recovered == true
      assert ctx.original_error == :boom
    end

    test "catch handler can still error" do
      effect =
        Effect.new(:test)
        |> Effect.step(:risky, fn _ -> {:error, :first_error} end,
          catch: fn _reason, _ctx ->
            {:error, :catch_also_failed}
          end
        )

      assert {:error, error} = Effect.run(effect, %{})
      assert error.reason == :catch_also_failed
    end

    test "catch handler receives context" do
      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{user_id: 42}} end)
        |> Effect.step(:risky, fn _ -> {:error, :oops} end,
          catch: fn _reason, ctx ->
            {:ok, %{fallback_for: ctx.user_id}}
          end
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.fallback_for == 42
    end

    test "catch handles raised exceptions" do
      effect =
        Effect.new(:test)
        |> Effect.step(:raise_step, fn _ -> raise "kaboom" end,
          catch: fn reason, _ctx ->
            {:ok, %{caught: reason}}
          end
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert %RuntimeError{message: "kaboom"} = ctx.caught
    end

    test "does not apply to successful steps" do
      effect =
        Effect.new(:test)
        |> Effect.step(:ok_step, fn _ -> {:ok, %{value: 1}} end,
          catch: fn _reason, _ctx ->
            {:ok, %{value: 999}}
          end
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.value == 1
    end
  end

  # ============================================
  # Fallback
  # ============================================

  describe "fallback" do
    test "uses fallback on error" do
      effect =
        Effect.new(:test)
        |> Effect.step(:optional, fn _ -> {:error, :not_found} end,
          fallback: %{data: nil, source: :fallback}
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.data == nil
      assert ctx.source == :fallback
    end

    test "does not use fallback on success" do
      effect =
        Effect.new(:test)
        |> Effect.step(:ok_step, fn _ -> {:ok, %{data: :real}} end,
          fallback: %{data: :fallback}
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.data == :real
    end

    test "fallback_when restricts which errors trigger fallback" do
      effect =
        Effect.new(:test)
        |> Effect.step(:selective, fn _ -> {:error, :not_found} end,
          fallback: %{data: nil},
          fallback_when: [:not_found, :timeout]
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.data == nil
    end

    test "fallback_when does not trigger for non-matching errors" do
      effect =
        Effect.new(:test)
        |> Effect.step(:selective, fn _ -> {:error, :permission_denied} end,
          fallback: %{data: nil},
          fallback_when: [:not_found, :timeout]
        )

      assert {:error, error} = Effect.run(effect, %{})
      assert error.reason == :permission_denied
    end

    test "catch takes precedence over fallback" do
      effect =
        Effect.new(:test)
        |> Effect.step(:both, fn _ -> {:error, :oops} end,
          catch: fn _reason, _ctx -> {:ok, %{from: :catch}} end,
          fallback: %{from: :fallback}
        )

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.from == :catch
    end
  end

  # ============================================
  # Rollback after compound steps
  # ============================================

  describe "rollback after compound steps" do
    test "rollback after successful parallel" do
      test_pid = self()

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ -> send(test_pid, {:rollback, :setup}); :ok end
        )
        |> Effect.parallel(:group, [
          {:a, fn _ -> {:ok, %{a: 1}} end},
          {:b, fn _ -> {:ok, %{b: 2}} end}
        ], after: :setup)
        |> Effect.step(:fail_after, fn _ -> {:error, :boom} end, after: :group)

      assert {:error, _} = Effect.run(effect, %{})
      assert_received {:rollback, :setup}
    end

    test "rollback after successful embed" do
      test_pid = self()

      nested = Effect.new(:nested)
        |> Effect.step(:inner, fn _ -> {:ok, %{inner: true}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ -> send(test_pid, {:rollback, :setup}); :ok end
        )
        |> Effect.embed(:nested_step, nested, after: :setup)
        |> Effect.step(:fail_after, fn _ -> {:error, :boom} end, after: :nested_step)

      assert {:error, _} = Effect.run(effect, %{})
      assert_received {:rollback, :setup}
    end

    test "rollback after successful race" do
      test_pid = self()

      fast = Effect.new(:fast)
        |> Effect.step(:quick, fn _ -> {:ok, %{winner: :fast}} end)

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{setup: true}} end,
          rollback: fn _ -> send(test_pid, {:rollback, :setup}); :ok end
        )
        |> Effect.race(:fetch, [fast], after: :setup)
        |> Effect.step(:fail_after, fn _ -> {:error, :boom} end, after: :fetch)

      assert {:error, _} = Effect.run(effect, %{})
      assert_received {:rollback, :setup}
    end

    test "rollback after successful branch" do
      test_pid = self()

      effect =
        Effect.new(:test)
        |> Effect.step(:setup, fn _ -> {:ok, %{type: :a, setup: true}} end,
          rollback: fn _ -> send(test_pid, {:rollback, :setup}); :ok end
        )
        |> Effect.branch(:route, & &1.type, %{
          a: fn _ -> {:ok, %{routed: true}} end
        }, after: :setup)
        |> Effect.step(:fail_after, fn _ -> {:error, :boom} end, after: :route)

      assert {:error, _} = Effect.run(effect, %{})
      assert_received {:rollback, :setup}
    end

    test "parallel error includes completed substep names in metadata" do
      effect =
        Effect.new(:test)
        |> Effect.parallel(:checks, [
          {:good, fn _ -> {:ok, %{good: true}} end},
          {:bad, fn _ -> {:error, :fail} end}
        ])

      assert {:error, error} = Effect.run(effect, %{})
      assert error.metadata.parallel_group == :checks
    end
  end

  # ============================================
  # Race edge cases
  # ============================================

  describe "race edge cases" do
    test "remaining tasks are terminated after winner" do
      test_pid = self()

      slow = Effect.new(:slow)
        |> Effect.step(:wait, fn _ ->
          # Register that we started
          send(test_pid, :slow_started)
          Process.sleep(500)
          send(test_pid, :slow_completed)
          {:ok, %{winner: :slow}}
        end)

      fast = Effect.new(:fast)
        |> Effect.step(:quick, fn _ ->
          {:ok, %{winner: :fast}}
        end)

      effect =
        Effect.new(:test)
        |> Effect.race(:fetch, [slow, fast])

      assert {:ok, ctx} = Effect.run(effect, %{})
      assert ctx.winner == :fast

      # Give a moment for any straggler messages
      Process.sleep(50)

      # Slow task should have been killed - should not complete
      refute_received :slow_completed
    end
  end
end
