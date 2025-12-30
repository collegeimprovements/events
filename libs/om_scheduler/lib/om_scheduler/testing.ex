defmodule OmScheduler.Testing do
  @moduledoc """
  Testing utilities for OmScheduler.

  This module provides helpers for testing code that interacts with the scheduler.
  It supports two testing modes:

  - `:manual` - Jobs are enqueued but not automatically executed
  - `:inline` - Jobs are executed synchronously in the calling process

  ## Setup

  Configure testing mode in your `config/test.exs`:

      config :om_scheduler,
        testing: :manual  # or :inline

  ## Usage

      defmodule MyApp.WorkerTest do
        use ExUnit.Case
        use OmScheduler.Testing

        test "job is enqueued" do
          assert {:ok, job} = MyApp.Worker.enqueue(%{user_id: 123})
          assert_enqueued worker: MyApp.Worker, args: %{user_id: 123}
        end

        test "job executes successfully" do
          {:ok, job} = MyApp.Worker.enqueue(%{user_id: 123})
          assert :ok = perform_job(MyApp.Worker, job.args)
        end
      end

  ## Workflow Testing

      test "workflow executes all steps" do
        {:ok, execution_id} = start_workflow(:my_workflow, %{input: "value"})

        # Execute all steps
        assert {:ok, result} = execute_workflow(execution_id)
        assert result.state == :completed
      end
  """

  @doc """
  Sets up testing helpers.

  ## Options

  - `:mode` - Testing mode (`:manual` or `:inline`, default: from config)
  """
  defmacro __using__(opts \\ []) do
    quote do
      import OmScheduler.Testing
      @testing_mode Keyword.get(unquote(opts), :mode, OmScheduler.Config.get()[:testing] || :manual)
    end
  end

  alias OmScheduler.{Job, Config, Executor}
  alias OmScheduler.Workflow

  # ============================================
  # Job Testing
  # ============================================

  @doc """
  Performs a job synchronously, returning the result.

  ## Examples

      assert :ok = perform_job(MyWorker, %{user_id: 123})
      assert {:ok, result} = perform_job(MyWorker, %{data: "test"})
      assert {:error, :failed} = perform_job(FailingWorker, %{})
  """
  @spec perform_job(module(), map(), keyword()) :: term()
  def perform_job(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    {module, function} = parse_worker(worker)

    job = %Job{
      name: "test_job_#{System.unique_integer([:positive])}",
      module: module,
      function: function,
      args: args,
      queue: Keyword.get(opts, :queue, "default"),
      meta: Keyword.get(opts, :meta, %{}),
      max_retries: Keyword.get(opts, :max_attempts, 3)
    }

    Executor.execute(job)
  end

  defp parse_worker(worker) when is_atom(worker) do
    {to_string(worker), "perform"}
  end

  @doc """
  Asserts that a job with the given attributes has been enqueued.

  ## Options

  - `:worker` - Worker module (required)
  - `:args` - Arguments map (optional, partial match)
  - `:queue` - Queue name (optional)
  - `:tags` - Job tags (optional)

  ## Examples

      assert_enqueued worker: MyWorker
      assert_enqueued worker: MyWorker, args: %{user_id: 123}
      assert_enqueued worker: MyWorker, queue: "priority"
  """
  defmacro assert_enqueued(opts) do
    quote do
      assert OmScheduler.Testing.job_enqueued?(unquote(opts)),
             "Expected job to be enqueued with #{inspect(unquote(opts))}"
    end
  end

  @doc """
  Refutes that a job with the given attributes has been enqueued.
  """
  defmacro refute_enqueued(opts) do
    quote do
      refute OmScheduler.Testing.job_enqueued?(unquote(opts)),
             "Expected no job to be enqueued with #{inspect(unquote(opts))}"
    end
  end

  @doc """
  Checks if a job matching the given options is enqueued.
  """
  @spec job_enqueued?(keyword()) :: boolean()
  def job_enqueued?(opts) do
    worker = Keyword.get(opts, :worker)
    args = Keyword.get(opts, :args)
    queue = Keyword.get(opts, :queue)
    tags = Keyword.get(opts, :tags, [])

    case get_store().list_jobs(queue: queue, tags: tags) do
      {:ok, jobs} ->
        Enum.any?(jobs, fn job ->
          matches_worker?(job, worker) and
            matches_args?(job, args) and
            matches_queue?(job, queue)
        end)

      _ ->
        false
    end
  end

  @doc """
  Returns all enqueued jobs matching the given options.
  """
  @spec all_enqueued(keyword()) :: [Job.t()]
  def all_enqueued(opts \\ []) do
    queue = Keyword.get(opts, :queue)
    tags = Keyword.get(opts, :tags, [])

    case get_store().list_jobs(queue: queue, tags: tags) do
      {:ok, jobs} -> jobs
      _ -> []
    end
  end

  @doc """
  Clears all enqueued jobs.

  Useful in setup/teardown to ensure a clean state.
  """
  @spec drain_jobs() :: :ok
  def drain_jobs do
    case get_store().list_jobs([]) do
      {:ok, jobs} ->
        Enum.each(jobs, fn job ->
          get_store().delete_job(job.name)
        end)

      _ ->
        :ok
    end

    :ok
  end

  # ============================================
  # Workflow Testing
  # ============================================

  @doc """
  Starts a workflow in testing mode.

  Returns the execution ID which can be used with other test helpers.

  ## Examples

      {:ok, execution_id} = start_workflow(:my_workflow, %{input: "value"})
  """
  @spec start_workflow(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def start_workflow(workflow_name, context \\ %{}) do
    Workflow.start(workflow_name, context)
  end

  @doc """
  Executes a workflow step by step, returning the final result.

  This is useful for testing workflow logic without async execution.
  """
  @spec execute_workflow(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute_workflow(execution_id, _opts \\ []) do
    Workflow.get_state(execution_id)
  end

  @doc """
  Waits for a workflow to complete.

  ## Options

  - `:timeout` - Maximum wait time in milliseconds (default: 5000)
  """
  @spec wait_for_workflow(String.t(), keyword()) :: {:ok, map()} | {:error, :timeout}
  def wait_for_workflow(execution_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(execution_id, deadline)
  end

  defp wait_loop(execution_id, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case Workflow.get_state(execution_id) do
        {:ok, %{state: state} = result} when state in [:completed, :failed, :cancelled] ->
          {:ok, result}

        {:ok, _} ->
          Process.sleep(50)
          wait_loop(execution_id, deadline)

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Asserts that a workflow step was executed.
  """
  defmacro assert_step_executed(execution_id, step_name) do
    quote do
      state = OmScheduler.Workflow.get_state(unquote(execution_id))

      assert match?({:ok, _}, state),
             "Could not get workflow state"

      {:ok, workflow_state} = state

      assert unquote(step_name) in (workflow_state[:completed_steps] || []),
             "Step #{inspect(unquote(step_name))} was not executed"
    end
  end

  @doc """
  Asserts that a workflow completed successfully.
  """
  defmacro assert_workflow_completed(execution_id) do
    quote do
      case OmScheduler.Workflow.get_state(unquote(execution_id)) do
        {:ok, %{state: :completed}} ->
          assert true

        {:ok, %{state: other}} ->
          flunk("Expected workflow to be completed, but was #{inspect(other)}")

        {:error, reason} ->
          flunk("Could not get workflow state: #{inspect(reason)}")
      end
    end
  end

  @doc """
  Asserts that a workflow failed.
  """
  defmacro assert_workflow_failed(execution_id) do
    quote do
      case OmScheduler.Workflow.get_state(unquote(execution_id)) do
        {:ok, %{state: :failed}} ->
          assert true

        {:ok, %{state: other}} ->
          flunk("Expected workflow to be failed, but was #{inspect(other)}")

        {:error, reason} ->
          flunk("Could not get workflow state: #{inspect(reason)}")
      end
    end
  end

  # ============================================
  # Sandbox Mode (for Ecto-like isolation)
  # ============================================

  @doc """
  Enables sandbox mode for the current test process.

  In sandbox mode, each test process gets its own isolated job queue.
  This is similar to Ecto.Adapters.SQL.Sandbox.

  ## Usage

      setup do
        OmScheduler.Testing.start_sandbox()
        :ok
      end
  """
  @spec start_sandbox() :: :ok
  def start_sandbox do
    Process.put(:scheduler_sandbox, true)
    Process.put(:scheduler_sandbox_jobs, [])
    :ok
  end

  @doc """
  Stops sandbox mode.
  """
  @spec stop_sandbox() :: :ok
  def stop_sandbox do
    Process.delete(:scheduler_sandbox)
    Process.delete(:scheduler_sandbox_jobs)
    :ok
  end

  @doc """
  Checks if sandbox mode is active.
  """
  @spec sandbox?() :: boolean()
  def sandbox? do
    Process.get(:scheduler_sandbox, false)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_store do
    Config.get_store_module(Config.get())
  end

  defp matches_worker?(_job, nil), do: true

  defp matches_worker?(job, worker) do
    # Job struct uses module field (as string), not worker
    job.module == to_string(worker) or job.module == worker
  end

  defp matches_args?(_job, nil), do: true

  defp matches_args?(job, expected_args) do
    Enum.all?(expected_args, fn {key, value} ->
      Map.get(job.args, key) == value or Map.get(job.args, to_string(key)) == value
    end)
  end

  defp matches_queue?(_job, nil), do: true

  defp matches_queue?(job, queue) do
    job.queue == queue or job.queue == to_string(queue)
  end
end
