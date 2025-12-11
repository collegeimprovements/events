defmodule Events.Infra.Scheduler.Peer.Postgres do
  @moduledoc """
  Leader election using PostgreSQL advisory locks.

  Only one node can hold an advisory lock at a time, making this
  suitable for clustered production deployments.

  ## How It Works

  1. Each node attempts to acquire a PostgreSQL advisory lock
  2. Only one node can hold the lock at a time
  3. When the leader dies, the lock is automatically released
  4. Another node will acquire the lock and become the new leader

  ## Usage

      config :my_app, Events.Infra.Scheduler,
        peer: Events.Infra.Scheduler.Peer.Postgres,
        repo: MyApp.Repo

  ## Configuration

  The telemetry prefix is configurable via:

      config :events, Events.Infra.Scheduler.Peer.Postgres, telemetry_prefix: [:my_app, :scheduler, :peer]

  Default prefix: `[:events, :scheduler, :peer]`
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.Config

  @behaviour Events.Infra.Scheduler.Peer.Behaviour

  @telemetry_prefix Application.compile_env(:events, [__MODULE__, :telemetry_prefix], [:events, :scheduler, :peer])
  @default_repo Application.compile_env(:events, [__MODULE__, :repo], Events.Core.Repo)

  # Advisory lock key - using consistent hash of scheduler name
  @lock_key 123_456_789
  @check_interval 10_000
  @heartbeat_interval 30_000

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
    conf = Keyword.get(opts, :conf, Config.get())

    state = %{
      name: Keyword.get(opts, :name, __MODULE__),
      leader: false,
      started_at: DateTime.utc_now(),
      repo: conf[:repo] || @default_repo,
      prefix: conf[:prefix] || "public",
      lock_key: @lock_key
    }

    # Register ourselves as a peer
    register_peer(state)

    # Try to become leader
    send(self(), :try_leader)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:leader?, _from, state) do
    {:reply, state.leader, state}
  end

  def handle_call(:get_leader, _from, state) do
    leader = get_current_leader(state)
    {:reply, leader, state}
  end

  def handle_call(:peers, _from, state) do
    peers = list_peers(state)
    {:reply, peers, state}
  end

  @impl GenServer
  def handle_info(:try_leader, state) do
    new_state = try_acquire_lock(state)
    schedule_check()
    {:noreply, new_state}
  end

  def handle_info(:check_leader, state) do
    new_state =
      if state.leader do
        # Verify we still have the lock
        if verify_lock(state) do
          update_heartbeat(state)
          state
        else
          Logger.info("[Scheduler.Peer.Postgres] Lost leadership")
          emit_telemetry(:resignation, state)
          %{state | leader: false}
        end
      else
        try_acquire_lock(state)
      end

    schedule_check()
    {:noreply, new_state}
  end

  def handle_info(:heartbeat, state) do
    if state.leader do
      update_heartbeat(state)
    end

    schedule_heartbeat()
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.leader do
      release_lock(state)
    end

    unregister_peer(state)
    :ok
  end

  # ============================================
  # Lock Management
  # ============================================

  defp try_acquire_lock(state) do
    # Use pg_try_advisory_lock for non-blocking attempt
    sql = "SELECT pg_try_advisory_lock($1)"

    case state.repo.query(sql, [state.lock_key]) do
      {:ok, %{rows: [[true]]}} ->
        if not state.leader do
          Logger.info("[Scheduler.Peer.Postgres] Became leader")
          emit_telemetry(:election, state)
          update_heartbeat(state)
          schedule_heartbeat()
        end

        %{state | leader: true}

      {:ok, %{rows: [[false]]}} ->
        state

      {:error, reason} ->
        Logger.warning("[Scheduler.Peer.Postgres] Failed to acquire lock: #{inspect(reason)}")
        state
    end
  end

  defp verify_lock(state) do
    # Check if we still hold the lock
    sql = """
    SELECT EXISTS (
      SELECT 1 FROM pg_locks
      WHERE locktype = 'advisory'
        AND objid = $1
        AND pid = pg_backend_pid()
    )
    """

    case state.repo.query(sql, [state.lock_key]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  defp release_lock(state) do
    sql = "SELECT pg_advisory_unlock($1)"
    state.repo.query(sql, [state.lock_key])
  end

  # ============================================
  # Peer Registry
  # ============================================

  defp register_peer(state) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 60, :second)

    sql = """
    INSERT INTO scheduler_peers (id, name, node, started_at, expires_at, inserted_at, updated_at)
    VALUES (gen_random_uuid(), $1, $2, $3, $4, $3, $3)
    ON CONFLICT (name) DO UPDATE
    SET node = EXCLUDED.node,
        started_at = EXCLUDED.started_at,
        expires_at = EXCLUDED.expires_at,
        updated_at = EXCLUDED.updated_at
    """

    state.repo.query(sql, [to_string(state.name), to_string(node()), now, expires_at],
      prefix: state.prefix
    )
  end

  defp unregister_peer(state) do
    sql = "DELETE FROM scheduler_peers WHERE name = $1"
    state.repo.query(sql, [to_string(state.name)], prefix: state.prefix)
  end

  defp update_heartbeat(state) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 60, :second)

    sql = """
    UPDATE scheduler_peers
    SET expires_at = $2, updated_at = $3
    WHERE name = $1
    """

    state.repo.query(sql, [to_string(state.name), expires_at, now], prefix: state.prefix)
  end

  defp get_current_leader(state) do
    # The leader is the peer that holds the advisory lock
    sql = """
    SELECT p.node
    FROM scheduler_peers p
    JOIN pg_locks l ON l.locktype = 'advisory' AND l.objid = $1
    JOIN pg_stat_activity a ON a.pid = l.pid
    WHERE p.expires_at > NOW()
    ORDER BY p.updated_at DESC
    LIMIT 1
    """

    case state.repo.query(sql, [state.lock_key], prefix: state.prefix) do
      {:ok, %{rows: [[node_str]]}} ->
        String.to_atom(node_str)

      _ ->
        nil
    end
  end

  defp list_peers(state) do
    sql = """
    SELECT name, node, started_at,
           EXISTS (
             SELECT 1 FROM pg_locks l
             JOIN pg_stat_activity a ON a.pid = l.pid
             WHERE l.locktype = 'advisory' AND l.objid = $1
           ) as is_leader
    FROM scheduler_peers
    WHERE expires_at > NOW()
    ORDER BY started_at
    """

    case state.repo.query(sql, [state.lock_key], prefix: state.prefix) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [_name, node_str, started_at, is_leader] ->
          %{
            node: String.to_atom(node_str),
            leader: is_leader,
            started_at: started_at
          }
        end)

      _ ->
        []
    end
  end

  # ============================================
  # Scheduling
  # ============================================

  defp schedule_check do
    Process.send_after(self(), :check_leader, @check_interval)
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  # ============================================
  # Telemetry
  # ============================================

  defp emit_telemetry(event, state) do
    :telemetry.execute(
      @telemetry_prefix ++ [event],
      %{system_time: System.system_time()},
      %{node: node(), name: state.name}
    )
  end
end
