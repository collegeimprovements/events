defmodule Events.Infra.Scheduler.Workflow.Registry do
  @moduledoc """
  Registry for workflow definitions and execution tracking.

  This GenServer maintains:
  - Registered workflow definitions (via decorator or builder API)
  - Active workflow executions
  - Execution tracking for introspection

  ## Usage

  The registry is automatically started by the scheduler supervisor.
  Workflows can be registered using:

      # Decorator API (auto-registered at compile time)
      defmodule MyApp.Onboarding do
        use Events.Infra.Scheduler.Workflow, name: :user_onboarding
        # ...
      end

      # Builder API (manual registration)
      Workflow.new(:data_pipeline)
      |> Workflow.step(:fetch, &fetch/1)
      |> Workflow.register()

  ## Querying

      # Get workflow definition
      Registry.get_workflow(:user_onboarding)

      # List all workflows
      Registry.list_workflows()

      # Get execution state
      Registry.get_execution("exec-123")

      # List active executions
      Registry.list_executions(:user_onboarding)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.Workflow
  alias Events.Infra.Scheduler.Workflow.Execution
  alias Events.Infra.Scheduler.Config

  @type workflow_name :: atom()
  @type execution_id :: String.t()

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts the workflow registry.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a workflow definition.
  """
  @spec register_workflow(Workflow.t()) :: {:ok, Workflow.t()} | {:error, term()}
  def register_workflow(%Workflow{} = workflow, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:register_workflow, workflow})
  end

  @doc """
  Gets a workflow definition by name.
  """
  @spec get_workflow(workflow_name()) :: {:ok, Workflow.t()} | {:error, :not_found}
  def get_workflow(workflow_name, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_workflow, workflow_name})
  end

  @doc """
  Lists all registered workflows.
  """
  @spec list_workflows(keyword()) :: [Workflow.t()]
  def list_workflows(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:list_workflows, opts})
  end

  @doc """
  Updates a workflow definition.
  """
  @spec update_workflow(workflow_name(), map()) :: {:ok, Workflow.t()} | {:error, term()}
  def update_workflow(workflow_name, updates, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:update_workflow, workflow_name, updates})
  end

  @doc """
  Deletes a workflow definition.
  """
  @spec delete_workflow(workflow_name()) :: :ok | {:error, term()}
  def delete_workflow(workflow_name, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:delete_workflow, workflow_name})
  end

  @doc """
  Registers a new execution.
  """
  @spec register_execution(Execution.t()) :: {:ok, Execution.t()} | {:error, term()}
  def register_execution(%Execution{} = execution, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:register_execution, execution})
  end

  @doc """
  Gets an execution by ID.
  """
  @spec get_execution(execution_id()) :: {:ok, Execution.t()} | {:error, :not_found}
  def get_execution(execution_id, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:get_execution, execution_id})
  end

  @doc """
  Updates an execution.
  """
  @spec update_execution(execution_id(), Execution.t()) :: {:ok, Execution.t()} | {:error, term()}
  def update_execution(execution_id, %Execution{} = execution, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:update_execution, execution_id, execution})
  end

  @doc """
  Deletes an execution record.
  """
  @spec delete_execution(execution_id()) :: :ok | {:error, term()}
  def delete_execution(execution_id, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:delete_execution, execution_id})
  end

  @doc """
  Lists executions for a workflow.
  """
  @spec list_executions(workflow_name(), keyword()) :: [Execution.t()]
  def list_executions(workflow_name, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:list_executions, workflow_name, opts})
  end

  @doc """
  Lists all running executions.
  """
  @spec list_running_executions(keyword()) :: [Execution.t()]
  def list_running_executions(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:list_running_executions, opts})
  end

  @doc """
  Gets statistics for workflows.
  """
  @spec get_stats() :: map()
  def get_stats(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :get_stats)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    # Create ETS tables for workflows and executions
    workflows_table = :ets.new(:workflow_registry_workflows, [:set, :protected, :named_table])
    executions_table = :ets.new(:workflow_registry_executions, [:set, :protected, :named_table])

    state = %{
      workflows_table: workflows_table,
      executions_table: executions_table,
      conf: Keyword.get(opts, :conf, Config.get())
    }

    Logger.info("[Workflow.Registry] Started")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_workflow, workflow}, _from, state) do
    case :ets.insert_new(state.workflows_table, {workflow.name, workflow}) do
      true ->
        Logger.debug("[Workflow.Registry] Registered workflow: #{workflow.name}")
        {:reply, {:ok, workflow}, state}

      false ->
        # Update existing workflow
        :ets.insert(state.workflows_table, {workflow.name, workflow})
        Logger.debug("[Workflow.Registry] Updated workflow: #{workflow.name}")
        {:reply, {:ok, workflow}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_workflow, workflow_name}, _from, state) do
    case :ets.lookup(state.workflows_table, workflow_name) do
      [{^workflow_name, workflow}] -> {:reply, {:ok, workflow}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_workflows, opts}, _from, state) do
    workflows =
      :ets.tab2list(state.workflows_table)
      |> Enum.map(fn {_name, workflow} -> workflow end)
      |> maybe_filter_by_tags(Keyword.get(opts, :tags))
      |> maybe_filter_by_trigger(Keyword.get(opts, :trigger_type))

    {:reply, workflows, state}
  end

  @impl GenServer
  def handle_call({:update_workflow, workflow_name, updates}, _from, state) do
    case :ets.lookup(state.workflows_table, workflow_name) do
      [{^workflow_name, workflow}] ->
        updated = Map.merge(workflow, updates)
        :ets.insert(state.workflows_table, {workflow_name, updated})
        {:reply, {:ok, updated}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:delete_workflow, workflow_name}, _from, state) do
    :ets.delete(state.workflows_table, workflow_name)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:register_execution, execution}, _from, state) do
    :ets.insert(state.executions_table, {execution.id, execution})
    {:reply, {:ok, execution}, state}
  end

  @impl GenServer
  def handle_call({:get_execution, execution_id}, _from, state) do
    case :ets.lookup(state.executions_table, execution_id) do
      [{^execution_id, execution}] -> {:reply, {:ok, execution}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:update_execution, execution_id, execution}, _from, state) do
    :ets.insert(state.executions_table, {execution_id, execution})
    {:reply, {:ok, execution}, state}
  end

  @impl GenServer
  def handle_call({:delete_execution, execution_id}, _from, state) do
    :ets.delete(state.executions_table, execution_id)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:list_executions, workflow_name, opts}, _from, state) do
    executions =
      :ets.tab2list(state.executions_table)
      |> Enum.map(fn {_id, execution} -> execution end)
      |> Enum.filter(fn exec -> exec.workflow_name == workflow_name end)
      |> maybe_filter_by_state(Keyword.get(opts, :state))
      |> maybe_limit(Keyword.get(opts, :limit))

    {:reply, executions, state}
  end

  @impl GenServer
  def handle_call({:list_running_executions, opts}, _from, state) do
    executions =
      :ets.tab2list(state.executions_table)
      |> Enum.map(fn {_id, execution} -> execution end)
      |> Enum.filter(fn exec -> exec.state == :running end)
      |> maybe_filter_by_workflow(Keyword.get(opts, :workflow))
      |> maybe_limit(Keyword.get(opts, :limit))

    {:reply, executions, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    workflow_count = :ets.info(state.workflows_table, :size)
    execution_count = :ets.info(state.executions_table, :size)

    executions = :ets.tab2list(state.executions_table)

    state_counts =
      executions
      |> Enum.map(fn {_id, exec} -> exec.state end)
      |> Enum.frequencies()

    stats = %{
      workflows: workflow_count,
      executions: %{
        total: execution_count,
        by_state: state_counts
      }
    }

    {:reply, stats, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp maybe_filter_by_tags(workflows, nil), do: workflows
  defp maybe_filter_by_tags(workflows, []), do: workflows

  defp maybe_filter_by_tags(workflows, tags) when is_list(tags) do
    Enum.filter(workflows, fn workflow ->
      Enum.any?(tags, &(&1 in workflow.tags))
    end)
  end

  defp maybe_filter_by_trigger(workflows, nil), do: workflows

  defp maybe_filter_by_trigger(workflows, trigger_type) do
    Enum.filter(workflows, fn workflow -> workflow.trigger_type == trigger_type end)
  end

  defp maybe_filter_by_state(executions, nil), do: executions

  defp maybe_filter_by_state(executions, state) do
    Enum.filter(executions, fn exec -> exec.state == state end)
  end

  defp maybe_filter_by_workflow(executions, nil), do: executions

  defp maybe_filter_by_workflow(executions, workflow_name) do
    Enum.filter(executions, fn exec -> exec.workflow_name == workflow_name end)
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
