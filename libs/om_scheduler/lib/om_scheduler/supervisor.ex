defmodule OmScheduler.Supervisor do
  @moduledoc """
  Main supervisor for the scheduler system.

  Starts and manages:
  - Store (Memory or Database)
  - Peer election
  - Workflow Registry (workflow definitions and execution tracking)
  - Queue producers
  - Plugins (Cron, Pruner, etc.)

  ## Usage

  Add to your application supervision tree:

      children = [
        # ... other children
        OmScheduler.Supervisor
      ]

  Or with options:

      children = [
        {OmScheduler.Supervisor, name: :my_scheduler}
      ]

  ## Configuration

  Configure in your application config:

      config :om_scheduler,
        enabled: true,
        store: :database,
        repo: OmScheduler.Config.repo(),
        queues: [default: 10, realtime: 20],
        plugins: [
          OmScheduler.Plugins.Cron,
          {OmScheduler.Plugins.Pruner, max_age: {7, :days}}
        ]
  """

  use Supervisor
  require Logger

  alias OmScheduler.{Config, Plugin, DeadLetter}
  alias OmScheduler.Store.{Memory, Database}
  alias OmScheduler.Queue
  alias OmScheduler.Workflow.Registry, as: WorkflowRegistry
  alias OmScheduler.Strategies.StrategyRunner

  @doc """
  Starts the scheduler supervisor.

  ## Options

  - `:name` - Supervisor name (default: __MODULE__)
  - All scheduler config options can be passed here
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @impl Supervisor
  def init(opts) do
    # Get config from opts or application environment
    conf =
      Config.get()
      |> Keyword.merge(opts)
      |> Config.validate!()

    if not conf[:enabled] do
      Logger.info("[Scheduler.Supervisor] Scheduler is disabled")
      :ignore
    else
      children = build_children(conf)

      Logger.info(
        "[Scheduler.Supervisor] Starting with #{length(children)} children, store=#{conf[:store]}"
      )

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_children(conf) do
    store_child = build_store_child(conf)
    peer_child = build_peer_child(conf)
    strategy_runner_child = build_strategy_runner_child(conf)
    dead_letter_child = build_dead_letter_child(conf)
    workflow_registry_child = build_workflow_registry_child(conf)
    queue_child = build_queue_child(conf)
    plugin_children = build_plugin_children(conf)

    [
      store_child,
      peer_child,
      strategy_runner_child,
      dead_letter_child,
      workflow_registry_child,
      queue_child | plugin_children
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp build_store_child(conf) do
    case conf[:store] do
      :memory ->
        {Memory, name: Memory, conf: conf}

      :database ->
        # Database store doesn't need a GenServer
        nil

      module when is_atom(module) ->
        {module, name: module, conf: conf}

      _ ->
        nil
    end
  end

  defp build_peer_child(conf) do
    peer = conf[:peer]

    cond do
      peer == false ->
        nil

      is_atom(peer) and not is_nil(peer) ->
        {peer, name: peer, conf: conf}

      true ->
        nil
    end
  end

  defp build_strategy_runner_child(conf) do
    # StrategyRunner consolidates circuit breaker, rate limiter, and error classifier
    # It's always started but strategies are configured via conf
    {StrategyRunner, conf: conf}
  end

  defp build_dead_letter_child(conf) do
    dlq_config = conf[:dead_letter]

    case dlq_config do
      nil ->
        {DeadLetter, []}

      false ->
        nil

      config when is_list(config) ->
        if Keyword.get(config, :enabled, true) do
          {DeadLetter, config}
        else
          nil
        end
    end
  end

  defp build_workflow_registry_child(conf) do
    workflow_config = conf[:workflow]

    case workflow_config do
      false ->
        nil

      _ ->
        # Workflow registry is enabled by default
        {WorkflowRegistry, conf: conf}
    end
  end

  defp build_queue_child(conf) do
    if conf[:queues] != false do
      {Queue.Supervisor, conf: conf, store: get_store_module(conf)}
    else
      nil
    end
  end

  defp build_plugin_children(conf) do
    plugins = conf[:plugins]

    if plugins == false or is_nil(plugins) do
      []
    else
      Enum.map(plugins, fn plugin ->
        Plugin.child_spec(plugin, conf: conf)
      end)
    end
  end

  defp get_store_module(conf) do
    case conf[:store] do
      :memory -> Memory
      :database -> Database
      module when is_atom(module) -> module
      _ -> Memory
    end
  end
end
