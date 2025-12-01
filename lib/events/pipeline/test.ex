defmodule Events.Pipeline.Test do
  @moduledoc """
  Testing utilities for Pipeline.

  Provides helpers for dry-running pipelines, mocking steps,
  assertions for pipeline state, and utilities for testing
  multi-step workflows.

  ## Usage in Tests

      defmodule MyPipelineTest do
        use ExUnit.Case
        import Events.Pipeline.Test

        test "pipeline has expected steps" do
          pipeline = build_user_pipeline()
          assert_steps(pipeline, [:fetch_user, :validate, :save])
        end

        test "pipeline runs successfully" do
          result =
            build_user_pipeline()
            |> mock_step(:fetch_user, fn _ -> {:ok, %{user: mock_user()}} end)
            |> Pipeline.run()

          assert_pipeline_ok(result)
        end
      end

  ## Dry Run Testing

      test "dry run shows all steps" do
        steps = dry_run(pipeline)
        assert :fetch_user in steps
        assert :validate in steps
        assert :save in steps
      end
  """

  alias Events.Pipeline

  # ============================================
  # Assertions
  # ============================================

  @doc """
  Asserts a pipeline result is ok.

  ## Examples

      result = Pipeline.run(pipeline)
      assert_pipeline_ok(result)
      assert_pipeline_ok(result, fn ctx -> ctx.user.active? end)
  """
  defmacro assert_pipeline_ok(result) do
    quote do
      case unquote(result) do
        {:ok, _context} ->
          :ok

        {:error, {:step_failed, step, reason}} ->
          raise ExUnit.AssertionError,
            message:
              "Expected pipeline success, but step #{inspect(step)} failed: #{inspect(reason)}"

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected pipeline success, got error: #{inspect(reason)}"
      end
    end
  end

  defmacro assert_pipeline_ok(result, predicate) when is_function(predicate) do
    quote do
      case unquote(result) do
        {:ok, context} ->
          pred = unquote(predicate)

          unless pred.(context) do
            raise ExUnit.AssertionError,
              message: "Pipeline succeeded but predicate failed for context: #{inspect(context)}"
          end

        {:error, {:step_failed, step, reason}} ->
          raise ExUnit.AssertionError,
            message:
              "Expected pipeline success, but step #{inspect(step)} failed: #{inspect(reason)}"

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected pipeline success, got error: #{inspect(reason)}"
      end
    end
  end

  @doc """
  Asserts a pipeline result is an error.

  ## Examples

      result = Pipeline.run(pipeline)
      assert_pipeline_error(result)
      assert_pipeline_error(result, :fetch_user)
      assert_pipeline_error(result, :fetch_user, :not_found)
  """
  defmacro assert_pipeline_error(result) do
    quote do
      case unquote(result) do
        {:error, _} ->
          :ok

        {:ok, context} ->
          raise ExUnit.AssertionError,
            message: "Expected pipeline error, got success with context: #{inspect(context)}"
      end
    end
  end

  defmacro assert_pipeline_error(result, expected_step) do
    quote do
      case unquote(result) do
        {:error, {:step_failed, step, _reason}} ->
          assert step == unquote(expected_step),
                 "Expected step #{inspect(unquote(expected_step))} to fail, but #{inspect(step)} failed"

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected step failure, got: #{inspect(reason)}"

        {:ok, context} ->
          raise ExUnit.AssertionError,
            message: "Expected pipeline to fail at #{inspect(unquote(expected_step))}, got success"
      end
    end
  end

  defmacro assert_pipeline_error(result, expected_step, expected_reason) do
    quote do
      case unquote(result) do
        {:error, {:step_failed, step, reason}} ->
          assert step == unquote(expected_step),
                 "Expected step #{inspect(unquote(expected_step))} to fail, but #{inspect(step)} failed"

          assert reason == unquote(expected_reason),
                 "Expected reason #{inspect(unquote(expected_reason))}, got #{inspect(reason)}"

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Expected step failure, got: #{inspect(reason)}"

        {:ok, _} ->
          raise ExUnit.AssertionError,
            message: "Expected pipeline to fail at #{inspect(unquote(expected_step))}"
      end
    end
  end

  @doc """
  Asserts a pipeline has specific steps.

  ## Examples

      assert_steps(pipeline, [:fetch, :validate, :save])
  """
  defmacro assert_steps(pipeline, expected_steps) do
    quote do
      actual_steps = Pipeline.dry_run(unquote(pipeline))
      expected = unquote(expected_steps)

      assert actual_steps == expected,
             "Expected steps #{inspect(expected)}, got #{inspect(actual_steps)}"
    end
  end

  @doc """
  Asserts a pipeline contains specific steps (order-independent).

  ## Examples

      assert_has_steps(pipeline, [:validate, :save])
  """
  defmacro assert_has_steps(pipeline, expected_steps) do
    quote do
      actual_steps = Pipeline.dry_run(unquote(pipeline))
      expected = unquote(expected_steps)

      for step <- expected do
        assert step in actual_steps,
               "Expected step #{inspect(step)} not found in #{inspect(actual_steps)}"
      end
    end
  end

  @doc """
  Asserts a pipeline is halted.

  ## Examples

      assert_halted(pipeline)
  """
  defmacro assert_halted(pipeline) do
    quote do
      assert Pipeline.halted?(unquote(pipeline)), "Expected pipeline to be halted"
    end
  end

  @doc """
  Asserts a pipeline is not halted.

  ## Examples

      refute_halted(pipeline)
  """
  defmacro refute_halted(pipeline) do
    quote do
      refute Pipeline.halted?(unquote(pipeline)), "Expected pipeline to not be halted"
    end
  end

  @doc """
  Asserts pipeline context contains specific keys.

  ## Examples

      assert_context_has(pipeline, [:user, :order])
  """
  defmacro assert_context_has(pipeline, keys) do
    quote do
      context = Pipeline.context(unquote(pipeline))

      for key <- unquote(keys) do
        assert Map.has_key?(context, key), "Expected context to have key #{inspect(key)}"
      end
    end
  end

  # ============================================
  # Dry Run
  # ============================================

  @doc """
  Returns the list of step names without executing.

  Delegates to `Pipeline.dry_run/1`.

  ## Examples

      steps = dry_run(pipeline)
      #=> [:fetch_user, :validate, :save]
  """
  @spec dry_run(Pipeline.t()) :: [atom()]
  def dry_run(pipeline), do: Pipeline.dry_run(pipeline)

  @doc """
  Returns detailed information about steps.

  ## Examples

      info = step_info(pipeline)
      #=> [%{name: :fetch, has_rollback: true}, ...]
  """
  @spec step_info(Pipeline.t()) :: [map()]
  def step_info(pipeline), do: Pipeline.inspect_steps(pipeline)

  @doc """
  Returns a string representation of the pipeline.

  ## Examples

      IO.puts(describe(pipeline))
  """
  @spec describe(Pipeline.t()) :: String.t()
  def describe(pipeline), do: Pipeline.to_string(pipeline)

  # ============================================
  # Step Mocking
  # ============================================

  @doc """
  Replaces a step's function with a mock.

  Returns a new pipeline with the mocked step.

  ## Examples

      pipeline
      |> mock_step(:fetch_user, fn _ -> {:ok, %{user: mock_user()}} end)
      |> Pipeline.run()

      # With conditional mock
      pipeline
      |> mock_step(:fetch_user, fn ctx ->
        if ctx.user_id == 1 do
          {:ok, %{user: %{id: 1, name: "Test"}}}
        else
          {:error, :not_found}
        end
      end)
  """
  @spec mock_step(Pipeline.t(), atom(), Pipeline.step_fun()) :: Pipeline.t()
  def mock_step(%Pipeline{steps: steps} = pipeline, step_name, mock_fun)
      when is_atom(step_name) and is_function(mock_fun, 1) do
    new_steps =
      Enum.map(steps, fn step ->
        if step.name == step_name do
          %{step | fun: mock_fun}
        else
          step
        end
      end)

    %{pipeline | steps: new_steps}
  end

  @doc """
  Replaces multiple steps with mocks.

  ## Examples

      pipeline
      |> mock_steps(%{
        fetch_user: fn _ -> {:ok, %{user: mock_user()}} end,
        save: fn _ -> {:ok, %{}} end
      })
  """
  @spec mock_steps(Pipeline.t(), %{atom() => Pipeline.step_fun()}) :: Pipeline.t()
  def mock_steps(pipeline, mocks) when is_map(mocks) do
    Enum.reduce(mocks, pipeline, fn {step_name, mock_fun}, acc ->
      mock_step(acc, step_name, mock_fun)
    end)
  end

  @doc """
  Creates a mock that always succeeds with given context additions.

  ## Examples

      pipeline
      |> mock_step(:fetch_user, success_mock(%{user: %{id: 1}}))
  """
  @spec success_mock(map()) :: Pipeline.step_fun()
  def success_mock(additions \\ %{}) when is_map(additions) do
    fn _ctx -> {:ok, additions} end
  end

  @doc """
  Creates a mock that always fails with given reason.

  ## Examples

      pipeline
      |> mock_step(:fetch_user, failure_mock(:not_found))
  """
  @spec failure_mock(term()) :: Pipeline.step_fun()
  def failure_mock(reason) do
    fn _ctx -> {:error, reason} end
  end

  @doc """
  Creates a mock that fails on the nth call.

  Useful for testing retry logic.

  ## Examples

      # Fails first 2 times, then succeeds
      pipeline
      |> mock_step(:flaky_step, fail_nth_times(2, :timeout, %{result: "ok"}))
  """
  @spec fail_nth_times(non_neg_integer(), term(), map()) :: Pipeline.step_fun()
  def fail_nth_times(n, error_reason, success_additions \\ %{}) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fn _ctx ->
      count = Agent.get_and_update(counter, fn c -> {c, c + 1} end)

      if count < n do
        {:error, error_reason}
      else
        {:ok, success_additions}
      end
    end
  end

  @doc """
  Creates a mock that tracks calls.

  Returns {mock_fn, get_calls_fn} where get_calls_fn returns all calls made.

  ## Examples

      {mock, get_calls} = tracking_mock(%{user: %{id: 1}})
      pipeline |> mock_step(:fetch, mock) |> Pipeline.run()
      calls = get_calls.()
      assert length(calls) == 1
  """
  @spec tracking_mock(map()) :: {Pipeline.step_fun(), (-> [map()])}
  def tracking_mock(additions \\ %{}) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    mock_fn = fn ctx ->
      Agent.update(agent, fn calls -> [ctx | calls] end)
      {:ok, additions}
    end

    get_calls = fn ->
      Agent.get(agent, fn calls -> Enum.reverse(calls) end)
    end

    {mock_fn, get_calls}
  end

  # ============================================
  # Test Pipeline Builders
  # ============================================

  @doc """
  Creates a simple test pipeline.

  ## Examples

      pipeline = simple_pipeline([:step1, :step2, :step3])
  """
  @spec simple_pipeline([atom()]) :: Pipeline.t()
  def simple_pipeline(step_names) when is_list(step_names) do
    Enum.reduce(step_names, Pipeline.new(), fn name, pipeline ->
      Pipeline.step(pipeline, name, fn _ctx -> {:ok, %{}} end)
    end)
  end

  @doc """
  Creates a test pipeline with initial context.

  ## Examples

      pipeline = test_pipeline(%{user_id: 123}, [:fetch, :validate])
  """
  @spec test_pipeline(map(), [atom()]) :: Pipeline.t()
  def test_pipeline(initial_context, step_names) do
    Enum.reduce(step_names, Pipeline.new(initial_context), fn name, pipeline ->
      Pipeline.step(pipeline, name, fn _ctx -> {:ok, %{}} end)
    end)
  end

  @doc """
  Creates a pipeline that fails at a specific step.

  ## Examples

      pipeline = failing_pipeline(:validate, :invalid_input)
  """
  @spec failing_pipeline(atom(), term()) :: Pipeline.t()
  def failing_pipeline(failing_step, reason) do
    Pipeline.new()
    |> Pipeline.step(:setup, fn _ -> {:ok, %{}} end)
    |> Pipeline.step(failing_step, fn _ -> {:error, reason} end)
    |> Pipeline.step(:after, fn _ -> {:ok, %{}} end)
  end

  # ============================================
  # Context Utilities
  # ============================================

  @doc """
  Extracts context from a pipeline result.

  ## Examples

      {:ok, context} = Pipeline.run(pipeline)
      ctx = extract_context(result)
  """
  @spec extract_context({:ok, map()} | {:error, term()}) :: map() | nil
  def extract_context({:ok, context}), do: context
  def extract_context({:error, _}), do: nil

  @doc """
  Gets a value from pipeline result context.

  ## Examples

      user = get_from_result(result, :user)
  """
  @spec get_from_result({:ok, map()} | {:error, term()}, atom()) :: term() | nil
  def get_from_result({:ok, context}, key), do: Map.get(context, key)
  def get_from_result({:error, _}, _key), do: nil
end
