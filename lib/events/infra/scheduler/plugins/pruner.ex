defmodule Events.Infra.Scheduler.Plugins.Pruner do
  @moduledoc """
  Plugin that prunes old execution records.

  Periodically deletes execution history older than the configured age
  to prevent unbounded table growth.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        plugins: [
          {Events.Infra.Scheduler.Plugins.Pruner,
            max_age: {7, :days},
            interval: {1, :hour},
            limit: 10_000}
        ]

  ## Options

  - `:max_age` - Maximum age of execution records (default: 7 days)
  - `:interval` - How often to run pruning (default: 1 hour)
  - `:limit` - Max records to delete per run (default: 10,000)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.{Config, Telemetry}

  @behaviour Events.Infra.Scheduler.Plugin

  @default_max_age {7, :days}
  @default_interval {1, :hour}
  @default_limit 10_000

  # ============================================
  # Plugin Callbacks
  # ============================================

  @impl Events.Infra.Scheduler.Plugin
  def validate(opts) do
    with true <- is_nil(opts[:max_age]) or Config.valid_duration?(opts[:max_age]),
         true <- is_nil(opts[:interval]) or Config.valid_duration?(opts[:interval]),
         true <- is_nil(opts[:limit]) or (is_integer(opts[:limit]) and opts[:limit] > 0) do
      :ok
    else
      _ -> {:error, "invalid Pruner plugin options"}
    end
  end

  @impl Events.Infra.Scheduler.Plugin
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())

    state = %{
      name: Keyword.get(opts, :name, __MODULE__),
      max_age: opts[:max_age] || @default_max_age,
      interval: Config.to_ms(opts[:interval] || @default_interval),
      limit: opts[:limit] || @default_limit,
      store: Config.get_store_module(conf),
      peer: conf[:peer],
      conf: conf,
      total_pruned: 0,
      last_run: nil
    }

    # Schedule first run (with initial delay to let system settle)
    Process.send_after(self(), :prune, 30_000)

    Logger.debug(
      "[Scheduler.Plugins.Pruner] Started with max_age=#{inspect(state.max_age)}, interval=#{state.interval}ms"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:prune, state) do
    new_state =
      case Config.leader?(state.peer) do
        true -> prune_executions(state)
        false -> state
      end

    schedule_prune(state.interval)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:prune_now, _from, state) do
    new_state = prune_executions(state)
    {:reply, {:ok, new_state.total_pruned - state.total_pruned}, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      total_pruned: state.total_pruned,
      last_run: state.last_run,
      max_age: state.max_age,
      interval: state.interval,
      limit: state.limit
    }

    {:reply, stats, state}
  end

  # ============================================
  # Public API
  # ============================================

  @doc """
  Triggers immediate pruning.
  """
  @spec prune_now(atom()) :: {:ok, non_neg_integer()}
  def prune_now(name \\ __MODULE__) do
    GenServer.call(name, :prune_now)
  end

  @doc """
  Returns pruning statistics.
  """
  @spec stats(atom()) :: map()
  def stats(name \\ __MODULE__) do
    GenServer.call(name, :stats)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp prune_executions(state) do
    now = DateTime.utc_now()
    before = Config.subtract_duration(now, state.max_age)

    state.store.prune_executions(before: before, limit: state.limit)
    |> handle_prune_result(state, now)
  end

  defp handle_prune_result({:ok, count}, state, now) when count > 0 do
    Logger.info("[Scheduler.Plugins.Pruner] Pruned #{count} execution records")
    Telemetry.plugin_event(:prune, __MODULE__, %{count: count})
    %{state | total_pruned: state.total_pruned + count, last_run: now}
  end

  defp handle_prune_result({:ok, 0}, state, now) do
    %{state | last_run: now}
  end

  defp handle_prune_result({:error, reason}, state, now) do
    Logger.warning("[Scheduler.Plugins.Pruner] Prune failed: #{inspect(reason)}")
    %{state | last_run: now}
  end

  defp schedule_prune(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
