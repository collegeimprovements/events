defmodule FnTypes.PipelineTest do
  @moduledoc """
  Tests for FnTypes.Pipeline - Multi-step workflow orchestration.

  Pipeline is for complex operations with multiple steps, context passing,
  rollback support, and conditional branching. Unlike simple Result chaining,
  Pipeline provides:

  - Named steps for debugging and telemetry
  - Accumulated context across steps
  - Automatic rollback on failure
  - Conditional step execution
  - Retry with backoff
  - Timeout support

  ## When to Use Pipeline vs Result

  - Use Result for simple chains of 2-3 operations
  - Use Pipeline for complex workflows with 4+ steps, rollbacks, or branching

  ## Pattern: Railway-Oriented Programming with State

      Pipeline.new(%{user_id: 123})
      |> Pipeline.step(:fetch_user, &fetch_user/1)
      |> Pipeline.step(:validate, &validate_permissions/1)
      |> Pipeline.step(:execute, &perform_action/1)
      |> Pipeline.run()

  Each step receives the accumulated context and can add to it.
  """

  use ExUnit.Case, async: true

  alias FnTypes.Pipeline

  # ============================================================================
  # USE CASE: User Registration Workflow
  # ============================================================================

  describe "Use Case: User registration workflow" do
    # A typical multi-step workflow: validate input, create resources,
    # send notifications. Each step can fail independently.

    test "successful registration with all steps" do
      result =
        Pipeline.new(%{email: "alice@example.com", name: "Alice", plan: :starter})
        |> Pipeline.validate(:email_format, fn ctx ->
          if String.contains?(ctx.email, "@"), do: :ok, else: {:error, :invalid_email}
        end)
        |> Pipeline.step(:check_availability, fn ctx ->
          taken = ["admin@example.com"]
          if ctx.email in taken, do: {:error, :email_taken}, else: {:ok, %{}}
        end)
        |> Pipeline.step(:create_user, fn ctx ->
          {:ok, %{user: %{id: 1, email: ctx.email, name: ctx.name}}}
        end)
        |> Pipeline.step(:setup_defaults, fn ctx ->
          {:ok, %{settings: %{user_id: ctx.user.id, theme: "light", plan: ctx.plan}}}
        end)
        |> Pipeline.tap(:log_registration, fn ctx ->
          # Side effect: log the successful registration
          _ = "User #{ctx.user.id} registered"
          :ok
        end)
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.user.email == "alice@example.com"
      assert ctx.settings.user_id == 1
    end

    test "validation failure stops workflow early" do
      result =
        Pipeline.new(%{email: "invalid-email"})
        |> Pipeline.validate(:email_format, fn ctx ->
          if String.contains?(ctx.email, "@"), do: :ok, else: {:error, :invalid_email}
        end)
        |> Pipeline.step(:never_reached, fn _ctx ->
          raise "Should not be called"
        end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :email_format, :invalid_email}} = result
    end
  end

  # ============================================================================
  # USE CASE: E-commerce Order Processing with Rollback
  # ============================================================================

  describe "Use Case: Order processing with rollback on payment failure" do
    # When payment fails after inventory is reserved, we need to release
    # the inventory. Pipeline.run_with_rollback handles this automatically.

    test "successful order completes all steps" do
      result =
        Pipeline.new(%{order_id: "ORD-123", items: ["item1"], amount: 99.99})
        |> Pipeline.step(:validate_order, fn ctx ->
          if length(ctx.items) > 0, do: {:ok, %{}}, else: {:error, :empty_order}
        end)
        |> Pipeline.step(:reserve_inventory, fn ctx ->
          {:ok, %{reservation_id: "RES-#{ctx.order_id}"}}
        end)
        |> Pipeline.step(:process_payment, fn ctx ->
          {:ok, %{payment_id: "PAY-#{ctx.order_id}", amount_charged: ctx.amount}}
        end)
        |> Pipeline.step(:confirm_order, fn ctx ->
          {:ok, %{confirmed: true, order_id: ctx.order_id}}
        end)
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.confirmed == true
      assert ctx.payment_id == "PAY-ORD-123"
    end

    test "payment failure triggers inventory rollback" do
      inventory_state = Agent.start_link(fn -> %{available: 10, reserved: 0} end) |> elem(1)

      reserve = fn _ctx ->
        Agent.update(inventory_state, fn s ->
          %{s | available: s.available - 1, reserved: s.reserved + 1}
        end)

        {:ok, %{reserved: true}}
      end

      release = fn _ctx ->
        Agent.update(inventory_state, fn s ->
          %{s | available: s.available + 1, reserved: s.reserved - 1}
        end)

        :ok
      end

      result =
        Pipeline.new(%{order_id: "ORD-456"})
        |> Pipeline.step(:reserve_inventory, reserve, rollback: release)
        |> Pipeline.step(:process_payment, fn _ctx ->
          {:error, :insufficient_funds}
        end)
        |> Pipeline.run_with_rollback()

      # Pipeline failed
      assert {:error, _} = result

      # But inventory was restored via rollback
      state = Agent.get(inventory_state, & &1)
      assert state.available == 10
      assert state.reserved == 0

      Agent.stop(inventory_state)
    end
  end

  # ============================================================================
  # USE CASE: Conditional Processing Based on User Type
  # ============================================================================

  describe "Use Case: Different processing paths based on user type" do
    # Premium users get different treatment than standard users.
    # Pipeline.branch and Pipeline.step_if handle conditional logic.

    test "premium user gets discount applied" do
      result =
        Pipeline.new(%{user_type: :premium, base_price: 100.0})
        |> Pipeline.branch(:user_type, %{
          premium: fn p ->
            Pipeline.step(p, :apply_discount, fn ctx ->
              {:ok, %{final_price: ctx.base_price * 0.8, discount: 0.2}}
            end)
          end,
          standard: fn p ->
            Pipeline.step(p, :no_discount, fn ctx ->
              {:ok, %{final_price: ctx.base_price, discount: 0.0}}
            end)
          end
        })
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.final_price == 80.0
      assert ctx.discount == 0.2
    end

    test "standard user pays full price" do
      result =
        Pipeline.new(%{user_type: :standard, base_price: 100.0})
        |> Pipeline.branch(:user_type, %{
          premium: fn p ->
            Pipeline.step(p, :apply_discount, fn ctx ->
              {:ok, %{final_price: ctx.base_price * 0.8}}
            end)
          end,
          standard: fn p ->
            Pipeline.step(p, :no_discount, fn ctx ->
              {:ok, %{final_price: ctx.base_price}}
            end)
          end
        })
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.final_price == 100.0
    end

    test "step_if conditionally adds steps" do
      result =
        Pipeline.new(%{is_admin: true, user_id: 123})
        |> Pipeline.step_if(:setup_admin_features, fn ctx -> ctx.is_admin end, fn _ctx ->
          {:ok, %{admin_dashboard: true, audit_logging: true}}
        end)
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.admin_dashboard == true
    end
  end

  # ============================================================================
  # USE CASE: External API Call with Retry
  # ============================================================================

  describe "Use Case: Calling external API with retry on transient failures" do
    # External APIs may have transient failures. Pipeline.step_with_retry
    # handles automatic retry with configurable backoff.

    test "succeeds after transient failures" do
      attempt_counter = Agent.start_link(fn -> 0 end) |> elem(1)

      result =
        Pipeline.new(%{api_endpoint: "/users"})
        |> Pipeline.step_with_retry(
          :call_api,
          fn _ctx ->
            count = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

            # Fail first 2 attempts, succeed on 3rd
            if count < 2 do
              {:error, :service_unavailable}
            else
              {:ok, %{response: %{status: 200, data: "success"}}}
            end
          end,
          max_attempts: 5,
          delay: 1
        )
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.response.status == 200
      assert Agent.get(attempt_counter, & &1) == 3

      Agent.stop(attempt_counter)
    end

    test "fails after exhausting all retries" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(
          :call_api,
          fn _ctx -> {:error, :always_fails} end,
          max_attempts: 3,
          delay: 1
        )
        |> Pipeline.run()

      assert {:error, {:step_failed, :call_api, :always_fails}} = result
    end
  end

  # ============================================================================
  # USE CASE: Authorization Guards
  # ============================================================================

  describe "Use Case: Authorization guards in workflows" do
    # Guards check conditions and halt the pipeline with an error if not met.

    test "guard passes and workflow continues" do
      result =
        Pipeline.new(%{user_role: :admin, resource_id: 123})
        |> Pipeline.guard(:admin_only, fn ctx -> ctx.user_role == :admin end, :unauthorized)
        |> Pipeline.step(:delete_resource, fn ctx ->
          {:ok, %{deleted: ctx.resource_id}}
        end)
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.deleted == 123
    end

    test "guard fails and halts workflow" do
      result =
        Pipeline.new(%{user_role: :viewer, resource_id: 123})
        |> Pipeline.guard(:admin_only, fn ctx -> ctx.user_role == :admin end, :unauthorized)
        |> Pipeline.step(:delete_resource, fn _ctx ->
          raise "Should not be called"
        end)
        |> Pipeline.run()

      assert {:error, {:step_failed, :admin_only, :unauthorized}} = result
    end

    test "guard with context-aware error message" do
      result =
        Pipeline.new(%{user_id: 456, required_permission: :write})
        |> Pipeline.guard(
          :has_permission,
          fn _ctx -> false end,
          fn ctx -> {:error, {:missing_permission, ctx.required_permission, ctx.user_id}} end
        )
        |> Pipeline.run()

      assert {:error, {:step_failed, :has_permission, {:missing_permission, :write, 456}}} = result
    end
  end

  # ============================================================================
  # Core API Tests
  # ============================================================================

  describe "Pipeline.new/2" do
    test "creates pipeline with initial context" do
      pipeline = Pipeline.new(%{user_id: 123})
      assert Pipeline.context(pipeline) == %{user_id: 123}
    end

    test "creates pipeline with empty context by default" do
      pipeline = Pipeline.new()
      assert Pipeline.context(pipeline) == %{}
    end

    test "accepts telemetry prefix option" do
      pipeline = Pipeline.new(%{}, telemetry_prefix: [:my_app, :signup])
      assert pipeline.telemetry_prefix == [:my_app, :signup]
    end

    test "accepts metadata option" do
      pipeline = Pipeline.new(%{}, metadata: %{request_id: "abc123"})
      assert pipeline.metadata == %{request_id: "abc123"}
    end
  end

  describe "Pipeline.from_result/2" do
    test "creates pipeline from ok result" do
      pipeline = Pipeline.from_result({:ok, 42}, :value)
      assert Pipeline.context(pipeline) == %{value: 42}
      assert not Pipeline.halted?(pipeline)
    end

    test "creates halted pipeline from error result" do
      pipeline = Pipeline.from_result({:error, :not_found}, :value)
      assert Pipeline.halted?(pipeline)
      assert Pipeline.error(pipeline) == :not_found
    end
  end

  describe "Pipeline.step/4" do
    test "adds step and executes successfully" do
      result =
        Pipeline.new(%{x: 5})
        |> Pipeline.step(:double, fn ctx -> {:ok, %{result: ctx.x * 2}} end)
        |> Pipeline.run()

      assert result == {:ok, %{x: 5, result: 10}}
    end

    test "chains multiple steps" do
      result =
        Pipeline.new(%{value: 1})
        |> Pipeline.step(:add_ten, fn ctx -> {:ok, %{value: ctx.value + 10}} end)
        |> Pipeline.step(:double, fn ctx -> {:ok, %{value: ctx.value * 2}} end)
        |> Pipeline.run()

      assert result == {:ok, %{value: 22}}
    end

    test "halts on error" do
      result =
        Pipeline.new(%{value: 1})
        |> Pipeline.step(:add_ten, fn ctx -> {:ok, %{value: ctx.value + 10}} end)
        |> Pipeline.step(:fail, fn _ctx -> {:error, :failed} end)
        |> Pipeline.step(:double, fn ctx -> {:ok, %{value: ctx.value * 2}} end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :fail, :failed}}
    end

    test "skips steps after halt" do
      {:ok, pid} = Agent.start_link(fn -> false end)

      Pipeline.new(%{})
      |> Pipeline.step(:fail, fn _ctx -> {:error, :failed} end)
      |> Pipeline.step(:never_called, fn _ctx ->
        Agent.update(pid, fn _ -> true end)
        {:ok, %{}}
      end)
      |> Pipeline.run()

      assert Agent.get(pid, & &1) == false
      Agent.stop(pid)
    end
  end

  describe "Pipeline.transform/4" do
    test "transforms a source key to target key" do
      result =
        Pipeline.new(%{name: "alice"})
        |> Pipeline.transform(:name, :upper_name, fn name -> {:ok, String.upcase(name)} end)
        |> Pipeline.run()

      assert result == {:ok, %{name: "alice", upper_name: "ALICE"}}
    end

    test "returns error when source key missing" do
      result =
        Pipeline.new(%{})
        |> Pipeline.transform(:missing, :target, fn x -> {:ok, x} end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :target, {:missing_key, :missing}}}
    end
  end

  describe "Pipeline.assign/3" do
    test "assigns static value" do
      result =
        Pipeline.new(%{})
        |> Pipeline.assign(:timestamp, ~U[2024-01-01 00:00:00Z])
        |> Pipeline.run()

      assert result == {:ok, %{timestamp: ~U[2024-01-01 00:00:00Z]}}
    end

    test "assigns computed value from function" do
      result =
        Pipeline.new(%{x: 5})
        |> Pipeline.assign(:doubled, fn ctx -> ctx.x * 2 end)
        |> Pipeline.run()

      assert result == {:ok, %{x: 5, doubled: 10}}
    end
  end

  describe "Pipeline.step_if/5" do
    test "runs step when condition is true" do
      result =
        Pipeline.new(%{admin: true})
        |> Pipeline.step_if(:admin_setup, fn ctx -> ctx.admin end, fn _ctx ->
          {:ok, %{setup: :admin}}
        end)
        |> Pipeline.run()

      assert result == {:ok, %{admin: true, setup: :admin}}
    end

    test "skips step when condition is false" do
      result =
        Pipeline.new(%{admin: false})
        |> Pipeline.step_if(:admin_setup, fn ctx -> ctx.admin end, fn _ctx ->
          {:ok, %{setup: :admin}}
        end)
        |> Pipeline.run()

      assert result == {:ok, %{admin: false}}
    end
  end

  describe "Pipeline.validate/3" do
    test "passes validation when ok" do
      result =
        Pipeline.new(%{value: 10})
        |> Pipeline.validate(:positive, fn ctx ->
          if ctx.value > 0, do: :ok, else: {:error, :not_positive}
        end)
        |> Pipeline.run()

      assert result == {:ok, %{value: 10}}
    end

    test "fails validation when error" do
      result =
        Pipeline.new(%{value: -5})
        |> Pipeline.validate(:positive, fn ctx ->
          if ctx.value > 0, do: :ok, else: {:error, :not_positive}
        end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :positive, :not_positive}}
    end
  end

  # ============================================
  # Side Effects
  # ============================================

  describe "Pipeline.tap/3" do
    test "executes side effect and continues" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      result =
        Pipeline.new(%{value: 42})
        |> Pipeline.tap(:log, fn ctx ->
          Agent.update(pid, fn _ -> ctx.value end)
          :ok
        end)
        |> Pipeline.run()

      assert result == {:ok, %{value: 42}}
      assert Agent.get(pid, & &1) == 42
      Agent.stop(pid)
    end

    test "halts on tap error" do
      result =
        Pipeline.new(%{})
        |> Pipeline.tap(:fail, fn _ctx -> {:error, :tap_failed} end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :fail, :tap_failed}}
    end
  end

  describe "Pipeline.tap_always/3" do
    test "always succeeds regardless of return value" do
      result =
        Pipeline.new(%{value: 42})
        |> Pipeline.tap_always(:log, fn _ctx -> :ignored_return end)
        |> Pipeline.run()

      assert result == {:ok, %{value: 42}}
    end
  end

  # ============================================
  # Guards
  # ============================================

  describe "Pipeline.guard/4" do
    test "continues when condition passes" do
      result =
        Pipeline.new(%{admin: true})
        |> Pipeline.guard(:authorized, fn ctx -> ctx.admin end, :unauthorized)
        |> Pipeline.run()

      assert result == {:ok, %{admin: true}}
    end

    test "halts when condition fails" do
      result =
        Pipeline.new(%{admin: false})
        |> Pipeline.guard(:authorized, fn ctx -> ctx.admin end, :unauthorized)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :authorized, :unauthorized}}
    end

    test "accepts error tuple directly" do
      result =
        Pipeline.new(%{admin: false})
        |> Pipeline.guard(:authorized, fn ctx -> ctx.admin end, {:error, :unauthorized})
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :authorized, :unauthorized}}
    end

    test "accepts error function" do
      result =
        Pipeline.new(%{admin: false, user_id: 123})
        |> Pipeline.guard(:authorized, fn ctx -> ctx.admin end, fn ctx ->
          {:error, {:unauthorized, ctx.user_id}}
        end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :authorized, {:unauthorized, 123}}}
    end
  end

  # ============================================
  # Execution
  # ============================================

  describe "Pipeline.run/1" do
    test "returns ok with final context on success" do
      result =
        Pipeline.new(%{x: 1})
        |> Pipeline.step(:add, fn ctx -> {:ok, %{y: ctx.x + 1}} end)
        |> Pipeline.run()

      assert result == {:ok, %{x: 1, y: 2}}
    end

    test "returns error on failure" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step(:fail, fn _ctx -> {:error, :boom} end)
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :fail, :boom}}
    end

    test "runs empty pipeline successfully" do
      result = Pipeline.new(%{value: 42}) |> Pipeline.run()
      assert result == {:ok, %{value: 42}}
    end
  end

  describe "Pipeline.run!/1" do
    test "returns context on success" do
      ctx =
        Pipeline.new(%{x: 1})
        |> Pipeline.step(:add, fn ctx -> {:ok, %{y: ctx.x + 1}} end)
        |> Pipeline.run!()

      assert ctx == %{x: 1, y: 2}
    end

    test "raises on failure" do
      assert_raise RuntimeError, ~r/Pipeline failed/, fn ->
        Pipeline.new(%{})
        |> Pipeline.step(:fail, fn _ctx -> {:error, :boom} end)
        |> Pipeline.run!()
      end
    end
  end

  # ============================================
  # Rollback
  # ============================================

  describe "Pipeline.run_with_rollback/1" do
    test "executes rollback on failure" do
      {:ok, pid} = Agent.start_link(fn -> [] end)

      Pipeline.new(%{})
      |> Pipeline.step(
        :step1,
        fn _ctx ->
          Agent.update(pid, &[:step1_executed | &1])
          {:ok, %{}}
        end,
        rollback: fn _ctx ->
          Agent.update(pid, &[:step1_rollback | &1])
          :ok
        end
      )
      |> Pipeline.step(:step2, fn _ctx -> {:error, :boom} end)
      |> Pipeline.run_with_rollback()

      events = Agent.get(pid, & &1)
      assert :step1_rollback in events
      assert :step1_executed in events
      Agent.stop(pid)
    end

    test "returns success without rollback" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ctx -> {:ok, %{done: true}} end,
          rollback: fn _ctx -> raise "should not be called" end
        )
        |> Pipeline.run_with_rollback()

      assert result == {:ok, %{done: true}}
    end
  end

  # ============================================
  # Retry
  # ============================================

  describe "Pipeline.step_with_retry/4" do
    test "succeeds on first try" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(:fetch, fn _ctx -> {:ok, %{data: "success"}} end,
          max_attempts: 3
        )
        |> Pipeline.run()

      assert result == {:ok, %{data: "success"}}
    end

    test "retries on failure and eventually succeeds" do
      {:ok, pid} = Agent.start_link(fn -> 0 end)

      result =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(
          :fetch,
          fn _ctx ->
            count = Agent.get_and_update(pid, fn c -> {c, c + 1} end)

            if count < 2 do
              {:error, :retry_me}
            else
              {:ok, %{data: "success"}}
            end
          end,
          max_attempts: 5,
          delay: 1
        )
        |> Pipeline.run()

      assert result == {:ok, %{data: "success"}}
      assert Agent.get(pid, & &1) == 3
      Agent.stop(pid)
    end

    test "fails after max attempts" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step_with_retry(:fetch, fn _ctx -> {:error, :always_fail} end,
          max_attempts: 3,
          delay: 1
        )
        |> Pipeline.run()

      assert result == {:error, {:step_failed, :fetch, :always_fail}}
    end
  end

  # ============================================
  # Context Manipulation
  # ============================================

  describe "Pipeline.map_context/2" do
    test "transforms entire context" do
      result =
        Pipeline.new(%{a: 1, b: 2, c: 3})
        |> Pipeline.map_context(fn ctx -> Map.take(ctx, [:a, :b]) end)
        |> Pipeline.run()

      assert result == {:ok, %{a: 1, b: 2}}
    end
  end

  describe "Pipeline.merge_context/2" do
    test "merges additional context" do
      result =
        Pipeline.new(%{a: 1})
        |> Pipeline.merge_context(%{b: 2})
        |> Pipeline.run()

      assert result == {:ok, %{a: 1, b: 2}}
    end
  end

  describe "Pipeline.drop_context/2" do
    test "drops keys from context" do
      result =
        Pipeline.new(%{a: 1, b: 2, c: 3})
        |> Pipeline.drop_context([:b, :c])
        |> Pipeline.run()

      assert result == {:ok, %{a: 1}}
    end
  end

  # ============================================
  # Checkpoints
  # ============================================

  describe "Pipeline.checkpoint/2" do
    test "creates checkpoint" do
      pipeline =
        Pipeline.new(%{value: 1})
        |> Pipeline.step(:step1, fn ctx -> {:ok, %{value: ctx.value + 1}} end)
        |> Pipeline.checkpoint(:after_step1)

      assert Pipeline.checkpoints(pipeline) == [:after_step1]
    end
  end

  describe "Pipeline.rollback_to/2" do
    test "restores to checkpoint state" do
      pipeline =
        Pipeline.new(%{value: 1})
        |> Pipeline.checkpoint(:initial)
        |> Pipeline.merge_context(%{value: 100})

      restored = Pipeline.rollback_to(pipeline, :initial)
      assert Pipeline.context(restored) == %{value: 1}
    end

    test "returns error for missing checkpoint" do
      pipeline = Pipeline.new(%{})
      restored = Pipeline.rollback_to(pipeline, :missing)
      assert Pipeline.halted?(restored)
      assert Pipeline.error(restored) == {:checkpoint_not_found, :missing}
    end
  end

  # ============================================
  # Composition
  # ============================================

  describe "Pipeline.compose/2" do
    test "combines two pipelines" do
      pipeline1 =
        Pipeline.new(%{value: 1})
        |> Pipeline.step(:step1, fn ctx -> {:ok, %{value: ctx.value + 1}} end)

      pipeline2 =
        Pipeline.new()
        |> Pipeline.step(:step2, fn ctx -> {:ok, %{value: ctx.value * 2}} end)

      result =
        Pipeline.compose(pipeline1, pipeline2)
        |> Pipeline.run()

      assert result == {:ok, %{value: 4}}
    end
  end

  describe "Pipeline.segment/1" do
    test "creates reusable pipeline segment" do
      validation_segment =
        Pipeline.segment([
          {:validate_positive, fn ctx ->
             if ctx.value > 0, do: {:ok, %{}}, else: {:error, :not_positive}
           end}
        ])

      result =
        Pipeline.new(%{value: 5})
        |> Pipeline.include(validation_segment)
        |> Pipeline.run()

      assert result == {:ok, %{value: 5}}
    end
  end

  # ============================================
  # Branching
  # ============================================

  describe "Pipeline.branch/4" do
    test "executes matching branch" do
      result =
        Pipeline.new(%{type: :premium})
        |> Pipeline.branch(:type, %{
          premium: fn p -> Pipeline.step(p, :apply_discount, fn _ctx -> {:ok, %{discount: 0.2}} end) end,
          standard: fn p -> Pipeline.step(p, :no_discount, fn _ctx -> {:ok, %{discount: 0}} end) end
        })
        |> Pipeline.run()

      assert result == {:ok, %{type: :premium, discount: 0.2}}
    end

    test "uses default branch when no match" do
      result =
        Pipeline.new(%{type: :unknown})
        |> Pipeline.branch(
          :type,
          %{
            premium: fn p -> Pipeline.step(p, :premium, fn _ctx -> {:ok, %{level: :premium}} end) end
          },
          default: fn p -> Pipeline.step(p, :default, fn _ctx -> {:ok, %{level: :basic}} end) end
        )
        |> Pipeline.run()

      assert result == {:ok, %{type: :unknown, level: :basic}}
    end

    test "fails when no branch matches and no default" do
      result =
        Pipeline.new(%{type: :unknown})
        |> Pipeline.branch(:type, %{
          premium: fn p -> Pipeline.step(p, :premium, fn _ctx -> {:ok, %{}} end) end
        })
        |> Pipeline.run()

      assert {:error, {:step_failed, _, {:no_branch_for, :type, :unknown}}} = result
    end
  end

  describe "Pipeline.when_true/3" do
    test "executes when condition is true" do
      result =
        Pipeline.new(%{admin: true})
        |> Pipeline.when_true(true, fn p ->
          Pipeline.step(p, :admin_setup, fn _ctx -> {:ok, %{setup: :admin}} end)
        end)
        |> Pipeline.run()

      assert result == {:ok, %{admin: true, setup: :admin}}
    end

    test "skips when condition is false" do
      result =
        Pipeline.new(%{admin: false})
        |> Pipeline.when_true(false, fn p ->
          Pipeline.step(p, :admin_setup, fn _ctx -> {:ok, %{setup: :admin}} end)
        end)
        |> Pipeline.run()

      assert result == {:ok, %{admin: false}}
    end

    test "accepts condition function" do
      result =
        Pipeline.new(%{admin: true})
        |> Pipeline.when_true(
          fn ctx -> ctx.admin end,
          fn p -> Pipeline.step(p, :admin_setup, fn _ctx -> {:ok, %{setup: :done}} end) end
        )
        |> Pipeline.run()

      assert result == {:ok, %{admin: true, setup: :done}}
    end
  end

  # ============================================
  # Inspection
  # ============================================

  describe "Pipeline.dry_run/1" do
    test "returns step names without executing" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ctx -> {:ok, %{}} end)
        |> Pipeline.step(:step2, fn _ctx -> {:ok, %{}} end)
        |> Pipeline.step(:step3, fn _ctx -> {:ok, %{}} end)

      assert Pipeline.dry_run(pipeline) == [:step1, :step2, :step3]
    end
  end

  describe "Pipeline.inspect_steps/1" do
    test "returns step details" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ctx -> {:ok, %{}} end, rollback: fn _ctx -> :ok end)
        |> Pipeline.step(:step2, fn _ctx -> {:ok, %{}} end)

      steps = Pipeline.inspect_steps(pipeline)

      assert length(steps) == 2
      assert Enum.at(steps, 0).name == :step1
      assert Enum.at(steps, 0).has_rollback == true
      assert Enum.at(steps, 1).name == :step2
      assert Enum.at(steps, 1).has_rollback == false
    end
  end

  describe "Pipeline.completed_steps/1" do
    test "returns empty list before run" do
      pipeline = Pipeline.new(%{})
      assert Pipeline.completed_steps(pipeline) == []
    end
  end

  describe "Pipeline.pending_steps/1" do
    test "returns all step names before run" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:a, fn _ctx -> {:ok, %{}} end)
        |> Pipeline.step(:b, fn _ctx -> {:ok, %{}} end)

      assert Pipeline.pending_steps(pipeline) == [:a, :b]
    end
  end

  describe "Pipeline.halted?/1" do
    test "returns false before run" do
      pipeline = Pipeline.new(%{})
      assert Pipeline.halted?(pipeline) == false
    end
  end

  describe "Pipeline.error/1" do
    test "returns nil when no error" do
      pipeline = Pipeline.new(%{})
      assert Pipeline.error(pipeline) == nil
    end
  end

  describe "Pipeline.to_string/1" do
    test "returns string representation" do
      pipeline =
        Pipeline.new(%{})
        |> Pipeline.step(:step1, fn _ctx -> {:ok, %{}} end)
        |> Pipeline.step(:step2, fn _ctx -> {:ok, %{}} end)

      str = Pipeline.to_string(pipeline)
      assert str =~ "Pipeline [2 steps]"
      assert str =~ "step1"
      assert str =~ "step2"
    end
  end

  # ============================================
  # Timeout
  # ============================================

  describe "Pipeline.run_with_timeout/2" do
    test "completes within timeout" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step(:quick, fn _ctx -> {:ok, %{done: true}} end)
        |> Pipeline.run_with_timeout(5000)

      assert result == {:ok, %{done: true}}
    end

    test "returns timeout error when exceeded" do
      result =
        Pipeline.new(%{})
        |> Pipeline.step(:slow, fn _ctx ->
          Process.sleep(1000)
          {:ok, %{done: true}}
        end)
        |> Pipeline.run_with_timeout(10)

      assert result == {:error, :timeout}
    end
  end

  # ============================================
  # Ensure (Cleanup)
  # ============================================

  describe "Pipeline.ensure/3" do
    test "runs cleanup after success" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      Pipeline.new(%{value: 42})
      |> Pipeline.step(:process, fn _ctx -> {:ok, %{processed: true}} end)
      |> Pipeline.ensure(:cleanup, fn ctx, _result ->
        Agent.update(pid, fn _ -> ctx.value end)
      end)
      |> Pipeline.run_with_ensure()

      assert Agent.get(pid, & &1) == 42
      Agent.stop(pid)
    end

    test "runs cleanup after failure" do
      {:ok, pid} = Agent.start_link(fn -> nil end)

      Pipeline.new(%{value: 42})
      |> Pipeline.step(:fail, fn _ctx -> {:error, :boom} end)
      |> Pipeline.ensure(:cleanup, fn ctx, _result ->
        Agent.update(pid, fn _ -> ctx.value end)
      end)
      |> Pipeline.run_with_ensure()

      assert Agent.get(pid, & &1) == 42
      Agent.stop(pid)
    end
  end

  # ============================================
  # Complex Workflows
  # ============================================

  describe "complex workflow scenarios" do
    test "user registration workflow" do
      result =
        Pipeline.new(%{email: "test@example.com", name: "Alice"})
        |> Pipeline.validate(:email_valid, fn ctx ->
          if String.contains?(ctx.email, "@"), do: :ok, else: {:error, :invalid_email}
        end)
        |> Pipeline.step(:create_user, fn ctx ->
          {:ok, %{user: %{id: 1, email: ctx.email, name: ctx.name}}}
        end)
        |> Pipeline.step(:send_welcome, fn ctx ->
          {:ok, %{email_sent: ctx.user.email}}
        end)
        |> Pipeline.run()

      assert {:ok, ctx} = result
      assert ctx.user.id == 1
      assert ctx.email_sent == "test@example.com"
    end

    test "order processing with rollback" do
      {:ok, inventory} = Agent.start_link(fn -> %{item1: 10} end)
      {:ok, payments} = Agent.start_link(fn -> %{} end)

      reserve_inventory = fn ctx ->
        Agent.update(inventory, fn inv -> Map.update!(inv, :item1, &(&1 - ctx.quantity)) end)
        {:ok, %{reserved: true}}
      end

      release_inventory = fn ctx ->
        Agent.update(inventory, fn inv -> Map.update!(inv, :item1, &(&1 + ctx.quantity)) end)
        :ok
      end

      charge_payment = fn _ctx ->
        # Simulate payment failure
        {:error, :payment_declined}
      end

      Pipeline.new(%{quantity: 3})
      |> Pipeline.step(:reserve, reserve_inventory, rollback: release_inventory)
      |> Pipeline.step(:charge, charge_payment)
      |> Pipeline.run_with_rollback()

      # Inventory should be restored after rollback
      assert Agent.get(inventory, fn inv -> inv.item1 end) == 10

      Agent.stop(inventory)
      Agent.stop(payments)
    end
  end
end
