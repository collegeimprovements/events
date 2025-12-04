defmodule Events.Infra.Scheduler.Peer.Global do
  @moduledoc """
  Leader election using Erlang's :global registry.

  Suitable for single-node deployments and development.
  In a cluster, only one node can register a global name.

  ## Usage

      config :events, Events.Infra.Scheduler,
        peer: Events.Infra.Scheduler.Peer.Global
  """

  use GenServer
  require Logger

  @behaviour Events.Infra.Scheduler.Peer.Behaviour

  @leader_key :events_scheduler_leader
  @check_interval 5_000

  # ============================================
  # Client API
  # ============================================

  @impl Events.Infra.Scheduler.Peer.Behaviour
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Events.Infra.Scheduler.Peer.Behaviour
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl Events.Infra.Scheduler.Peer.Behaviour
  def leader?(name \\ __MODULE__) do
    GenServer.call(name, :leader?)
  end

  @impl Events.Infra.Scheduler.Peer.Behaviour
  def get_leader(name \\ __MODULE__) do
    GenServer.call(name, :get_leader)
  end

  @impl Events.Infra.Scheduler.Peer.Behaviour
  def peers(name \\ __MODULE__) do
    GenServer.call(name, :peers)
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    state = %{
      name: Keyword.get(opts, :name, __MODULE__),
      leader: false,
      started_at: DateTime.utc_now(),
      conf: Keyword.get(opts, :conf, [])
    }

    # Try to become leader immediately
    send(self(), :try_leader)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:leader?, _from, state) do
    {:reply, state.leader, state}
  end

  def handle_call(:get_leader, _from, state) do
    leader =
      case :global.whereis_name(@leader_key) do
        :undefined -> nil
        pid -> node(pid)
      end

    {:reply, leader, state}
  end

  def handle_call(:peers, _from, state) do
    peers = [
      %{
        node: node(),
        leader: state.leader,
        started_at: state.started_at
      }
    ]

    {:reply, peers, state}
  end

  @impl GenServer
  def handle_info(:try_leader, state) do
    new_state = try_become_leader(state)
    schedule_check()
    {:noreply, new_state}
  end

  def handle_info(:check_leader, state) do
    new_state =
      if state.leader do
        # Verify we're still the leader
        case :global.whereis_name(@leader_key) do
          pid when pid == self() ->
            state

          _ ->
            Logger.info("[Scheduler.Peer.Global] Lost leadership")
            emit_telemetry(:resignation, state)
            %{state | leader: false}
        end
      else
        try_become_leader(state)
      end

    schedule_check()
    {:noreply, new_state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.leader do
      :global.unregister_name(@leader_key)
    end

    :ok
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp try_become_leader(state) do
    case :global.register_name(@leader_key, self()) do
      :yes ->
        if not state.leader do
          Logger.info("[Scheduler.Peer.Global] Became leader")
          emit_telemetry(:election, state)
        end

        %{state | leader: true}

      :no ->
        state
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check_leader, @check_interval)
  end

  defp emit_telemetry(event, state) do
    :telemetry.execute(
      [:events, :scheduler, :peer, event],
      %{system_time: System.system_time()},
      %{node: node(), name: state.name}
    )
  end
end
