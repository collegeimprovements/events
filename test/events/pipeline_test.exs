defmodule Events.Types.PipelineTest do
  use ExUnit.Case, async: true

  alias Events.Types.Pipeline

  describe "new/2" do
    test "creates pipeline with initial context" do
      pipeline = Pipeline.new(%{user_id: 123})
      assert Pipeline.context(pipeline) == %{user_id: 123}
    end

    test "creates pipeline with default empty context" do
      pipeline = Pipeline.new()
      assert Pipeline.context(pipeline) == %{}
    end

    test "accepts telemetry_prefix option" do
      pipeline = Pipeline.new(%{}, telemetry_prefix: [:my_app, :users])
      assert pipeline.telemetry_prefix == [:my_app, :users]
    end
  end

  describe "from_result/2" do
    test "creates pipeline from ok result" do
      pipeline = Pipeline.from_result({:ok, %{id: 1, name: "Test"}}, :user)
      assert Pipeline.context(pipeline) == %{user: %{id: 1, name: "Test"}}
    end

    test "creates halted pipeline from error result" do
      pipeline = Pipeline.from_result({:error, :not_found}, :user)
      assert Pipeline.halted?(pipeline)
      assert Pipeline.error(pipeline) == :not_found
    end
  end

  describe "step/4" do
    test "adds step to pipeline" do
      pipeline =
        Pipeline.new()
        |> Pipeline.step(:fetch, fn _ -> {:ok, %{data: 42}} end)

      assert Pipeline.dry_run(pipeline) == [:fetch]
    end

    test "does not add step to halted pipeline" do
      # Use from_result to create a halted pipeline
      halted = Pipeline.from_result({:error, :bad}, :x)
      result = Pipeline.step(halted, :new_step, fn _ -> {:ok, %{}} end)
      assert Pipeline.halted?(result)
    end

    test "step merges returned map into context" do
      {:ok, context} =
        Pipeline.new(%{a: 1})
        |> Pipeline.step(:add_b, fn _ -> {:ok, %{b: 2}} end)
        |> Pipeline.run()

      assert context == %{a: 1, b: 2}
    end
  end

  describe "transform/4" do
    test "transforms a context key" do
      {:ok, context} =
        Pipeline.new(%{name: "alice"})
        |> Pipeline.transform(:name, :upper_name, fn name -> {:ok, String.upcase(name)} end)
        |> Pipeline.run()

      assert context.upper_name == "ALICE"
    end

    test "fails if source key is missing" do
      result =
        Pipeline.new(%{})
        |> Pipeline.transform(:missing, :result, fn _ -> {:ok, "value"} end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :result, {:missing_key, :missing}}} = result
    end
  end

  describe "assign/3" do
    test "assigns static value" do
      {:ok, context} =
        Pipeline.new()
        |> Pipeline.assign(:timestamp, ~U[2024-01-15 12:00:00Z])
        |> Pipeline.run()

      assert context.timestamp == ~U[2024-01-15 12:00:00Z]
    end

    test "assigns computed value from function" do
      {:ok, context} =
        Pipeline.new(%{x: 5})
        |> Pipeline.assign(:double_x, fn ctx -> ctx.x * 2 end)
        |> Pipeline.run()

      assert context.double_x == 10
    end
  end

  describe "step_if/5" do
    test "executes step when condition is true" do
      {:ok, context} =
        Pipeline.new(%{should_run: true})
        |> Pipeline.step_if(:conditional, fn ctx -> ctx.should_run end, fn _ ->
          {:ok, %{ran: true}}
        end)
        |> Pipeline.run()

      assert context.ran == true
    end

    test "skips step when condition is false" do
      {:ok, context} =
        Pipeline.new(%{should_run: false})
        |> Pipeline.step_if(:conditional, fn ctx -> ctx.should_run end, fn _ ->
          {:ok, %{ran: true}}
        end)
        |> Pipeline.run()

      refute Map.has_key?(context, :ran)
    end
  end

  describe "validate/2" do
    test "passes when validator returns :ok" do
      {:ok, _} =
        Pipeline.new(%{value: 10})
        |> Pipeline.validate(:check_positive, fn ctx ->
          if ctx.value > 0, do: :ok, else: {:error, :not_positive}
        end)
        |> Pipeline.run()
    end

    test "fails when validator returns error" do
      result =
        Pipeline.new(%{value: -5})
        |> Pipeline.validate(:check_positive, fn ctx ->
          if ctx.value > 0, do: :ok, else: {:error, :not_positive}
        end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :check_positive, :not_positive}} = result
    end
  end

  describe "branch/4" do
    test "executes matching branch" do
      {:ok, context} =
        Pipeline.new(%{type: :premium})
        |> Pipeline.branch(:type, %{
          premium: fn p -> Pipeline.assign(p, :discount, 0.2) end,
          standard: fn p -> Pipeline.assign(p, :discount, 0.0) end
        })
        |> Pipeline.run()

      assert context.discount == 0.2
    end

    test "uses default branch when no match" do
      {:ok, context} =
        Pipeline.new(%{type: :unknown})
        |> Pipeline.branch(
          :type,
          %{
            premium: fn p -> Pipeline.assign(p, :discount, 0.2) end
          },
          default: fn p -> Pipeline.assign(p, :discount, 0.0) end
        )
        |> Pipeline.run()

      assert context.discount == 0.0
    end

    test "fails when no branch matches and no default" do
      result =
        Pipeline.new(%{type: :unknown})
        |> Pipeline.branch(:type, %{
          premium: fn p -> Pipeline.assign(p, :discount, 0.2) end
        })
        |> Pipeline.run()

      assert {:error, {:step_failed, :branch_type, {:no_branch_for, :type, :unknown}}} = result
    end
  end

  describe "when_true/3" do
    test "modifies pipeline when condition is true" do
      pipeline =
        Pipeline.new()
        |> Pipeline.when_true(true, fn p ->
          Pipeline.step(p, :added, fn _ -> {:ok, %{added: true}} end)
        end)

      assert :added in Pipeline.dry_run(pipeline)
    end

    test "does not modify pipeline when condition is false" do
      pipeline =
        Pipeline.new()
        |> Pipeline.when_true(false, fn p ->
          Pipeline.step(p, :added, fn _ -> {:ok, %{}} end)
        end)

      assert Pipeline.dry_run(pipeline) == []
    end

    test "accepts function condition" do
      pipeline =
        Pipeline.new(%{flag: true})
        |> Pipeline.when_true(fn ctx -> ctx.flag end, fn p ->
          Pipeline.step(p, :added, fn _ -> {:ok, %{}} end)
        end)

      assert :added in Pipeline.dry_run(pipeline)
    end
  end

  describe "parallel/3" do
    test "executes steps in parallel" do
      {:ok, context} =
        Pipeline.new(%{})
        |> Pipeline.parallel([
          {:fetch_a, fn _ -> {:ok, %{a: 1}} end},
          {:fetch_b, fn _ -> {:ok, %{b: 2}} end}
        ])
        |> Pipeline.run()

      assert context.a == 1
      assert context.b == 2
    end

    test "fails if any parallel step fails" do
      result =
        Pipeline.new(%{})
        |> Pipeline.parallel([
          {:fetch_a, fn _ -> {:ok, %{a: 1}} end},
          {:fetch_b, fn _ -> {:error, :failed} end}
        ])
        |> Pipeline.run()

      assert {:error, {:step_failed, :parallel, {:parallel_failed, :failed}}} = result
    end
  end

  describe "tap/3" do
    test "executes side effect without modifying context" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      {:ok, context} =
        Pipeline.new(%{value: 42})
        |> Pipeline.tap(:log, fn ctx ->
          Agent.update(agent, fn _ -> ctx.value end)
          :ok
        end)
        |> Pipeline.run()

      assert Agent.get(agent, & &1) == 42
      refute Map.has_key?(context, :log)
    end

    test "can fail and halt pipeline" do
      result =
        Pipeline.new(%{})
        |> Pipeline.tap(:check, fn _ -> {:error, :check_failed} end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :check, :check_failed}} = result
    end
  end

  describe "tap_always/3" do
    test "always succeeds even if function returns error" do
      {:ok, _} =
        Pipeline.new(%{})
        |> Pipeline.tap_always(:log, fn _ -> {:error, :ignored} end)
        |> Pipeline.run()
    end
  end

  describe "run/1" do
    test "returns final context on success" do
      {:ok, context} =
        Pipeline.new(%{a: 1})
        |> Pipeline.step(:add_b, fn _ -> {:ok, %{b: 2}} end)
        |> Pipeline.step(:add_c, fn _ -> {:ok, %{c: 3}} end)
        |> Pipeline.run()

      assert context == %{a: 1, b: 2, c: 3}
    end

    test "returns error with failed step info" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ -> {:ok, %{}} end)
        |> Pipeline.step(:step2, fn _ -> {:error, :failed} end)
        |> Pipeline.step(:step3, fn _ -> {:ok, %{}} end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :step2, :failed}} = result
    end
  end

  describe "run_with_rollback/1" do
    test "executes rollbacks on failure" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      result =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ -> {:ok, %{}} end,
          rollback: fn _ ->
            Agent.update(agent, fn list -> [:step1_rolled | list] end)
            :ok
          end
        )
        |> Pipeline.step(:step2, fn _ -> {:error, :failed} end)
        |> Pipeline.run_with_rollback()

      assert {:error, {:step_failed, :step2, :failed}} = result
      assert Agent.get(agent, & &1) == [:step1_rolled]
    end
  end

  describe "run!/1" do
    test "returns context on success" do
      context =
        Pipeline.new(%{a: 1})
        |> Pipeline.step(:add_b, fn _ -> {:ok, %{b: 2}} end)
        |> Pipeline.run!()

      assert context == %{a: 1, b: 2}
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        Pipeline.new(%{})
        |> Pipeline.step(:fail, fn _ -> {:error, :bad} end)
        |> Pipeline.run!()
      end
    end
  end

  describe "compose/2" do
    test "combines two pipelines" do
      p1 =
        Pipeline.new()
        |> Pipeline.step(:a, fn _ -> {:ok, %{a: 1}} end)

      p2 =
        Pipeline.new()
        |> Pipeline.step(:b, fn _ -> {:ok, %{b: 2}} end)

      combined = Pipeline.compose(p1, p2)
      assert Pipeline.dry_run(combined) == [:a, :b]
    end
  end

  describe "segment/1 and include/2" do
    test "creates and includes reusable segments" do
      validation_segment =
        Pipeline.segment([
          {:validate_email, fn _ -> {:ok, %{}} end},
          {:validate_name, fn _ -> {:ok, %{}} end}
        ])

      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:setup, fn _ -> {:ok, %{}} end)
        |> Pipeline.include(validation_segment)

      assert Pipeline.dry_run(pipeline) == [:setup, :validate_email, :validate_name]
    end
  end

  describe "checkpoint/2 and rollback_to/2" do
    test "creates checkpoint and allows rollback" do
      pipeline =
        Pipeline.new(%{initial: true})
        |> Pipeline.step(:step1, fn _ -> {:ok, %{step1: true}} end)
        |> Pipeline.checkpoint(:after_step1)
        |> Pipeline.step(:step2, fn _ -> {:ok, %{step2: true}} end)

      # Run to populate context
      {:ok, context} = Pipeline.run(pipeline)
      assert context.step2 == true

      # Checkpoints should be recorded
      checkpoints = Pipeline.checkpoints(pipeline)
      assert :after_step1 in checkpoints
    end

    test "rollback_to restores checkpoint state" do
      pipeline =
        Pipeline.new(%{initial: true})
        |> Pipeline.checkpoint(:start)

      rolled_back = Pipeline.rollback_to(pipeline, :start)
      assert Pipeline.context(rolled_back) == %{initial: true}
      refute Pipeline.halted?(rolled_back)
    end

    test "rollback_to fails for unknown checkpoint" do
      pipeline = Pipeline.new(%{})
      result = Pipeline.rollback_to(pipeline, :unknown)
      assert Pipeline.halted?(result)
      assert Pipeline.error(result) == {:checkpoint_not_found, :unknown}
    end
  end

  describe "step_with_retry/4" do
    test "succeeds on first attempt" do
      {:ok, context} =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(:fetch, fn _ -> {:ok, %{data: 42}} end)
        |> Pipeline.run()

      assert context.data == 42
    end

    test "retries on failure" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      {:ok, context} =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(
          :flaky,
          fn _ ->
            count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)
            if count < 2, do: {:error, :temp}, else: {:ok, %{success: true}}
          end,
          max_attempts: 5,
          delay: 1
        )
        |> Pipeline.run()

      assert context.success == true
    end

    test "respects should_retry predicate" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(
          :fetch,
          fn _ -> {:error, :permanent} end,
          max_attempts: 3,
          delay: 1,
          should_retry: fn err -> err == :temp end
        )
        |> Pipeline.run()

      assert {:error, {:step_failed, :fetch, :permanent}} = result
    end
  end

  describe "guard/4" do
    test "passes when condition is true" do
      {:ok, _} =
        Pipeline.new(%{admin: true})
        |> Pipeline.guard(:check_admin, fn ctx -> ctx.admin end, :unauthorized)
        |> Pipeline.run()
    end

    test "fails with error when condition is false" do
      result =
        Pipeline.new(%{admin: false})
        |> Pipeline.guard(:check_admin, fn ctx -> ctx.admin end, :unauthorized)
        |> Pipeline.run()

      assert {:error, {:step_failed, :check_admin, :unauthorized}} = result
    end

    test "accepts function for dynamic error" do
      result =
        Pipeline.new(%{user_id: 123, admin: false})
        |> Pipeline.guard(
          :check_admin,
          fn ctx -> ctx.admin end,
          fn ctx -> {:error, {:unauthorized, ctx.user_id}} end
        )
        |> Pipeline.run()

      assert {:error, {:step_failed, :check_admin, {:unauthorized, 123}}} = result
    end
  end

  describe "context manipulation" do
    test "map_context/2 transforms entire context" do
      pipeline =
        Pipeline.new(%{a: 1, b: 2, c: 3})
        |> Pipeline.map_context(fn ctx -> Map.take(ctx, [:a, :b]) end)

      assert Pipeline.context(pipeline) == %{a: 1, b: 2}
    end

    test "merge_context/2 adds to context" do
      pipeline =
        Pipeline.new(%{a: 1})
        |> Pipeline.merge_context(%{b: 2})

      assert Pipeline.context(pipeline) == %{a: 1, b: 2}
    end

    test "drop_context/2 removes keys" do
      pipeline =
        Pipeline.new(%{a: 1, b: 2, c: 3})
        |> Pipeline.drop_context([:b, :c])

      assert Pipeline.context(pipeline) == %{a: 1}
    end
  end

  describe "dry_run/1" do
    test "returns step names without executing" do
      pipeline =
        Pipeline.new()
        |> Pipeline.step(:a, fn _ -> raise "should not run" end)
        |> Pipeline.step(:b, fn _ -> raise "should not run" end)

      assert Pipeline.dry_run(pipeline) == [:a, :b]
    end
  end

  describe "inspect_steps/1" do
    test "returns detailed step info" do
      pipeline =
        Pipeline.new()
        |> Pipeline.step(:with_rollback, fn _ -> {:ok, %{}} end, rollback: fn _ -> :ok end)
        |> Pipeline.step(:simple, fn _ -> {:ok, %{}} end)
        |> Pipeline.step(:conditional, fn _ -> {:ok, %{}} end, condition: fn _ -> true end)

      info = Pipeline.inspect_steps(pipeline)

      assert Enum.find(info, &(&1.name == :with_rollback)).has_rollback == true
      assert Enum.find(info, &(&1.name == :simple)).has_rollback == false
      assert Enum.find(info, &(&1.name == :conditional)).has_condition == true
    end
  end

  describe "to_string/1" do
    test "returns human-readable representation" do
      pipeline =
        Pipeline.new()
        |> Pipeline.step(:fetch, fn _ -> {:ok, %{}} end, rollback: fn _ -> :ok end)
        |> Pipeline.step(:validate, fn _ -> {:ok, %{}} end)

      str = Pipeline.to_string(pipeline)

      assert str =~ "Pipeline [2 steps]"
      assert str =~ "fetch (rollback: yes)"
      assert str =~ "validate"
    end
  end

  describe "inspection functions" do
    test "context/1 returns current context" do
      pipeline = Pipeline.new(%{a: 1})
      assert Pipeline.context(pipeline) == %{a: 1}
    end

    test "completed_steps/1 returns completed steps" do
      # Need to run the pipeline first to have completed steps
      # This is tested through run/1 tests
      pipeline = Pipeline.new()
      assert Pipeline.completed_steps(pipeline) == []
    end

    test "pending_steps/1 returns pending steps" do
      pipeline =
        Pipeline.new()
        |> Pipeline.step(:a, fn _ -> {:ok, %{}} end)
        |> Pipeline.step(:b, fn _ -> {:ok, %{}} end)

      assert Pipeline.pending_steps(pipeline) == [:a, :b]
    end

    test "halted?/1 returns halted status" do
      pipeline = Pipeline.new()
      refute Pipeline.halted?(pipeline)

      halted = Pipeline.from_result({:error, :bad}, :x)
      assert Pipeline.halted?(halted)
    end

    test "error/1 returns error" do
      pipeline = Pipeline.new()
      assert Pipeline.error(pipeline) == nil

      halted = Pipeline.from_result({:error, :bad}, :x)
      assert Pipeline.error(halted) == :bad
    end
  end

  describe "ensure/3 and run_with_ensure/1" do
    test "ensure callback runs on success" do
      {:ok, agent} = Agent.start_link(fn -> false end)

      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:work, fn _ -> {:ok, %{done: true}} end)
        |> Pipeline.ensure(:cleanup, fn _ctx, _result ->
          Agent.update(agent, fn _ -> true end)
        end)

      {:ok, _} = Pipeline.run_with_ensure(pipeline)
      assert Agent.get(agent, & &1) == true
    end

    test "ensure callback runs on failure" do
      {:ok, agent} = Agent.start_link(fn -> false end)

      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:fail, fn _ -> {:error, :boom} end)
        |> Pipeline.ensure(:cleanup, fn _ctx, _result ->
          Agent.update(agent, fn _ -> true end)
        end)

      {:error, _} = Pipeline.run_with_ensure(pipeline)
      assert Agent.get(agent, & &1) == true
    end

    test "ensure callbacks run in LIFO order" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:work, fn _ -> {:ok, %{}} end)
        |> Pipeline.ensure(:first, fn _, _ ->
          Agent.update(agent, fn list -> [:first | list] end)
        end)
        |> Pipeline.ensure(:second, fn _, _ ->
          Agent.update(agent, fn list -> [:second | list] end)
        end)

      Pipeline.run_with_ensure(pipeline)
      assert Agent.get(agent, & &1) == [:first, :second]
    end
  end

  describe "run_with_timeout/2" do
    test "returns result within timeout" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:fast, fn _ -> {:ok, %{value: 42}} end)

      assert {:ok, %{value: 42}} = Pipeline.run_with_timeout(pipeline, 5000)
    end

    test "returns timeout error when exceeded" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:slow, fn _ ->
          Process.sleep(100)
          {:ok, %{}}
        end)

      assert {:error, :timeout} = Pipeline.run_with_timeout(pipeline, 10)
    end
  end

  describe "inspect protocol" do
    test "inspect shows pipeline info" do
      pipeline =
        Pipeline.new(%{user_id: 123})
        |> Pipeline.step(:fetch, fn _ -> {:ok, %{}} end)
        |> Pipeline.step(:validate, fn _ -> {:ok, %{}} end)

      inspected = inspect(pipeline)
      assert inspected =~ "Pipeline"
      assert inspected =~ "2"
      assert inspected =~ "PENDING"
    end

    test "inspect shows halted state" do
      halted = Pipeline.from_result({:error, :bad}, :x)
      inspected = inspect(halted)
      assert inspected =~ "HALTED"
    end
  end

  describe "String.Chars protocol" do
    test "to_string returns readable representation" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ -> {:ok, %{}} end, rollback: fn _ -> :ok end)
        |> Pipeline.step(:step2, fn _ -> {:ok, %{}} end)

      str = to_string(pipeline)
      assert str =~ "Pipeline [2 steps]"
      assert str =~ "step1"
      assert str =~ "step2"
      assert str =~ "rollback: yes"
    end
  end
end
