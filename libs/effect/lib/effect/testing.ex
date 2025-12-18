defmodule Effect.Testing do
  @moduledoc """
  Testing utilities for Effect workflows.

  Provides helpers for testing effects in isolation, mocking steps,
  and asserting execution behavior.

  ## Usage

      defmodule MyApp.OrderWorkflowTest do
        use ExUnit.Case, async: true
        import Effect.Testing

        test "order workflow completes successfully" do
          effect = OrderWorkflow.build()

          assert_effect_success(effect, %{order_id: 123})
        end

        test "validates required fields" do
          effect = OrderWorkflow.build()

          assert_effect_error(effect, %{}, :validate)
        end
      end

  ## Mocking Steps

      test "with mocked payment step" do
        effect =
          OrderWorkflow.build()
          |> mock_step(:charge, fn ctx -> {:ok, %{payment_id: "mock_123"}} end)

        assert {:ok, ctx} = Effect.run(effect, %{order_id: 123})
        assert ctx.payment_id == "mock_123"
      end
  """

  alias Effect.{Builder, Report}

  @doc """
  Asserts that an effect completes successfully with the given context.

  ## Options

  - `:timeout` - Maximum execution time in milliseconds
  - `:match` - Pattern or function to match against result context

  ## Examples

      assert_effect_success(effect, %{order_id: 123})
      assert_effect_success(effect, ctx, match: &(&1.status == :completed))
  """
  defmacro assert_effect_success(effect, ctx, opts \\ []) do
    quote do
      case Effect.run(unquote(effect), unquote(ctx), unquote(opts)) do
        {:ok, result} ->
          match = Keyword.get(unquote(opts), :match)

          if match do
            case match do
              fun when is_function(fun, 1) ->
                assert fun.(result), "Result did not match predicate"

              pattern ->
                assert result == pattern, "Result did not match pattern"
            end
          end

          result

        {:error, error} ->
          flunk("Expected success but got error at step #{inspect(error.step)}: #{inspect(error.reason)}")

        {:halted, reason} ->
          flunk("Expected success but effect was halted: #{inspect(reason)}")
      end
    end
  end

  @doc """
  Asserts that an effect fails at the expected step.

  ## Examples

      assert_effect_error(effect, %{}, :validate)
      assert_effect_error(effect, ctx, :charge, match: :payment_declined)
  """
  defmacro assert_effect_error(effect, ctx, expected_step, opts \\ []) do
    quote do
      case Effect.run(unquote(effect), unquote(ctx), unquote(opts)) do
        {:ok, _result} ->
          flunk("Expected error at step #{inspect(unquote(expected_step))} but effect succeeded")

        {:error, error} ->
          assert error.step == unquote(expected_step),
                 "Expected error at #{inspect(unquote(expected_step))} but got error at #{inspect(error.step)}"

          match = Keyword.get(unquote(opts), :match)

          if match do
            assert error.reason == match,
                   "Expected error reason #{inspect(match)} but got #{inspect(error.reason)}"
          end

          error

        {:halted, reason} ->
          flunk("Expected error at #{inspect(unquote(expected_step))} but effect was halted: #{inspect(reason)}")
      end
    end
  end

  @doc """
  Asserts that an effect halts with the expected reason.

  ## Examples

      assert_effect_halted(effect, ctx, :early_exit)
  """
  defmacro assert_effect_halted(effect, ctx, expected_reason) do
    quote do
      case Effect.run(unquote(effect), unquote(ctx)) do
        {:ok, _result} ->
          flunk("Expected halt with #{inspect(unquote(expected_reason))} but effect succeeded")

        {:error, error} ->
          flunk("Expected halt but got error at #{inspect(error.step)}")

        {:halted, reason} ->
          assert reason == unquote(expected_reason),
                 "Expected halt reason #{inspect(unquote(expected_reason))} but got #{inspect(reason)}"

          reason
      end
    end
  end

  @doc """
  Replaces a step function in an effect for testing purposes.

  Useful for mocking external calls or simulating specific behaviors.

  ## Examples

      effect
      |> mock_step(:charge, fn ctx -> {:ok, %{payment_id: "mock_123"}} end)
      |> mock_step(:send_email, fn _ctx -> {:ok, %{}} end)  # Skip real email
  """
  @spec mock_step(Builder.t(), atom(), (map() -> term())) :: Builder.t()
  def mock_step(%Builder{steps: steps} = effect, step_name, mock_fn) do
    updated_steps =
      Enum.map(steps, fn step ->
        if step.name == step_name do
          %{step | fun: mock_fn, arity: 1}
        else
          step
        end
      end)

    %{effect | steps: updated_steps}
  end

  @doc """
  Runs an effect and returns the execution report for inspection.

  ## Examples

      report = run_with_report(effect, ctx)
      assert Report.executed_steps(report) == [:validate, :charge, :fulfill]
  """
  @spec run_with_report(Builder.t(), map(), keyword()) :: Report.t()
  def run_with_report(effect, ctx, opts \\ []) do
    case Effect.run(effect, ctx, Keyword.put(opts, :report, true)) do
      {{:ok, _}, report} -> report
      {{:error, _}, report} -> report
      {{:halted, _}, report} -> report
    end
  end

  @doc """
  Asserts that specific steps were executed in the given order.

  ## Examples

      report = run_with_report(effect, ctx)
      assert_steps_executed(report, [:validate, :charge, :fulfill])
  """
  @spec assert_steps_executed(Report.t(), [atom()]) :: :ok | no_return()
  def assert_steps_executed(%Report{} = report, expected_steps) do
    actual_steps = Report.executed_steps(report)

    unless actual_steps == expected_steps do
      raise ExUnit.AssertionError,
        message: "Expected steps #{inspect(expected_steps)} but got #{inspect(actual_steps)}"
    end

    :ok
  end

  @doc """
  Asserts that specific steps were skipped during execution.

  ## Examples

      report = run_with_report(effect, ctx)
      assert_steps_skipped(report, [:optional_notify])
  """
  @spec assert_steps_skipped(Report.t(), [atom()]) :: :ok | no_return()
  def assert_steps_skipped(%Report{} = report, expected_skipped) do
    actual_skipped = Report.skipped_steps(report)

    unless MapSet.new(actual_skipped) == MapSet.new(expected_skipped) do
      raise ExUnit.AssertionError,
        message: "Expected skipped steps #{inspect(expected_skipped)} but got #{inspect(actual_skipped)}"
    end

    :ok
  end

  @doc """
  Creates a stub step function that records calls and returns a canned response.

  ## Examples

      stub = stub_step({:ok, %{payment_id: "123"}})
      effect = mock_step(effect, :charge, stub)
      Effect.run(effect, ctx)
      assert stub_called?(stub, fn ctx -> ctx.amount > 0 end)
  """
  @spec stub_step(term()) :: (map() -> term())
  def stub_step(response) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    fn ctx ->
      Agent.update(agent, fn calls -> [ctx | calls] end)
      response
    end
  end

  @doc """
  Creates a step function that fails a configurable number of times before succeeding.

  Useful for testing retry behavior.

  ## Examples

      # Fails twice, then succeeds
      flaky = flaky_step(2, {:ok, %{result: :success}})
      effect = mock_step(effect, :api_call, flaky)
  """
  @spec flaky_step(pos_integer(), term()) :: (map() -> term())
  def flaky_step(fail_count, success_response) do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fn _ctx ->
      attempt = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if attempt <= fail_count do
        {:error, {:attempt_failed, attempt}}
      else
        success_response
      end
    end
  end

  @doc """
  Creates a step function that records its execution time.

  ## Examples

      {step_fn, get_duration} = timed_step(fn ctx -> {:ok, %{}} end)
      effect = mock_step(effect, :slow_step, step_fn)
      Effect.run(effect, ctx)
      IO.puts("Step took \#{get_duration.()} ms")
  """
  @spec timed_step((map() -> term())) :: {(map() -> term()), (() -> non_neg_integer())}
  def timed_step(inner_fn) do
    {:ok, agent} = Agent.start_link(fn -> nil end)

    wrapped = fn ctx ->
      start = System.monotonic_time(:millisecond)
      result = inner_fn.(ctx)
      duration = System.monotonic_time(:millisecond) - start
      Agent.update(agent, fn _ -> duration end)
      result
    end

    get_duration = fn -> Agent.get(agent, & &1) end

    {wrapped, get_duration}
  end
end
