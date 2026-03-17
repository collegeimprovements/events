defmodule OmScheduler.Workflow.EffectIntegrationTest do
  use ExUnit.Case, async: true

  alias OmScheduler.Workflow
  alias OmScheduler.Workflow.Step.Executable

  # Only run these tests if Effect is available
  if Code.ensure_loaded?(Effect.Builder) do
    describe "Effect.Builder as Executable" do
      test "executes simple effect and returns context" do
        effect =
          Effect.new(:test_effect)
          |> Effect.step(:add_value, fn _ctx -> {:ok, %{added: 42}} end)

        result = Executable.execute(effect, %{initial: true})

        assert {:ok, context} = result
        assert context.added == 42
        assert context.initial == true
      end

      test "handles effect error" do
        effect =
          Effect.new(:failing_effect)
          |> Effect.step(:fail, fn _ctx -> {:error, :intentional_failure} end)

        result = Executable.execute(effect, %{})

        assert {:error, {:effect_failed, :failing_effect, :intentional_failure}} = result
      end

      test "handles effect halt as skip" do
        effect =
          Effect.new(:halting_effect)
          |> Effect.step(:halt, fn _ctx -> {:halt, :early_exit} end)

        result = Executable.execute(effect, %{})

        assert {:skip, {:effect_halted, :halting_effect, :early_exit}} = result
      end

      test "effect has no external rollback" do
        effect =
          Effect.new(:effect_with_rollback)
          |> Effect.step(:work, fn _ctx -> {:ok, %{}} end, rollback: fn _ctx -> :ok end)

        assert Executable.has_rollback?(effect) == false
        assert Executable.rollback(effect, %{}) == :ok
      end

      test "executes multi-step effect" do
        effect =
          Effect.new(:multi_step)
          |> Effect.step(:step1, fn _ctx -> {:ok, %{step1: "done"}} end)
          |> Effect.step(:step2, fn ctx -> {:ok, %{step2: ctx.step1 <> "_and_step2"}} end)
          |> Effect.step(:step3, fn ctx -> {:ok, %{final: ctx.step2}} end)

        result = Executable.execute(effect, %{})

        assert {:ok, context} = result
        assert context.step1 == "done"
        assert context.step2 == "done_and_step2"
        assert context.final == "done_and_step2"
      end

      test "executes effect with parallel steps" do
        effect =
          Effect.new(:parallel_effect)
          |> Effect.step(:init, fn _ctx -> {:ok, %{init: true}} end)
          |> Effect.parallel(
            :parallel_work,
            [
              {:a, fn _ctx -> {:ok, %{a: 1}} end},
              {:b, fn _ctx -> {:ok, %{b: 2}} end}
            ],
            after: :init
          )

        result = Executable.execute(effect, %{})

        assert {:ok, context} = result
        assert context.init == true
        assert context.a == 1
        assert context.b == 2
      end

      test "effect rollbacks execute on internal failure" do
        # Track rollback execution
        test_pid = self()

        effect =
          Effect.new(:rollback_effect)
          |> Effect.step(:setup, fn _ctx -> {:ok, %{setup: true}} end,
            rollback: fn _ctx ->
              send(test_pid, :setup_rollback)
              :ok
            end
          )
          |> Effect.step(:fail, fn _ctx -> {:error, :boom} end, after: :setup)

        result = Executable.execute(effect, %{})

        assert {:error, {:effect_failed, :rollback_effect, :boom}} = result

        # Effect should have executed its own rollback
        assert_receive :setup_rollback, 1000
      end
    end

    describe "Effect with context transformation" do
      test "transforms context before effect execution" do
        effect =
          Effect.new(:context_test)
          |> Effect.step(:check, fn ctx ->
            {:ok, %{received_amount: ctx.amount, received_extra: ctx.extra}}
          end)

        context_fn = fn ctx -> %{amount: ctx.order_total * 100, extra: "added"} end

        result =
          Executable.execute(
            {:effect_with_context, effect, context_fn},
            %{order_total: 50, other: "data"}
          )

        assert {:ok, context} = result
        # Context fn multiplied by 100
        assert context.received_amount == 5000
        assert context.received_extra == "added"
        # Original context is preserved
        assert context.other == "data"
      end

      test "handles context transformation error" do
        effect =
          Effect.new(:context_error)
          |> Effect.step(:work, fn _ctx -> {:ok, %{}} end)

        context_fn = fn _ctx -> raise "context transform failed" end

        result =
          Executable.execute(
            {:effect_with_context, effect, context_fn},
            %{}
          )

        assert {:error, {:context_transform_failed, %RuntimeError{}, _stacktrace}} = result
      end
    end

    describe "Workflow.effect/4 builder" do
      test "adds effect as workflow step" do
        effect =
          Effect.new(:payment)
          |> Effect.step(:charge, fn ctx -> {:ok, %{charged: ctx.amount}} end)

        workflow =
          Workflow.new(:order)
          |> Workflow.step(:validate, fn _ctx -> {:ok, %{amount: 100}} end)
          |> Workflow.effect(:payment, effect, after: :validate)

        assert workflow.name == :order
        assert Map.has_key?(workflow.steps, :validate)
        assert Map.has_key?(workflow.steps, :payment)

        # Check dependency
        assert :validate in Map.keys(workflow.adjacency)
      end

      test "adds effect with context transformation" do
        effect =
          Effect.new(:notify)
          |> Effect.step(:send, fn ctx -> {:ok, %{notified: ctx.user_id}} end)

        workflow =
          Workflow.new(:order)
          |> Workflow.step(:create_user, fn _ctx -> {:ok, %{user: %{id: 123}}} end)
          |> Workflow.effect(:notify, effect,
            after: :create_user,
            context: fn ctx -> %{user_id: ctx.user.id} end
          )

        assert Map.has_key?(workflow.steps, :notify)

        # The job should be an effect_with_context tuple
        notify_step = workflow.steps[:notify]
        assert {:effect_with_context, %Effect.Builder{}, context_fn} = notify_step.job
        assert is_function(context_fn, 1)
      end
    end
  else
    @tag :skip
    test "Effect not available - skipping integration tests" do
      :ok
    end
  end
end
