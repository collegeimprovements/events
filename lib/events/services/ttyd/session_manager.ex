defmodule Events.Services.Ttyd.SessionManager do
  @moduledoc """
  Manages per-session ttyd terminal instances.

  Each browser tab gets its own ttyd process running on a dynamic port.
  Sessions are tracked via Registry and cleaned up when the owning
  process (LiveView) terminates.

  ## Architecture

      Browser Tab 1 ──> LiveView 1 ──> TtydSession 1 ──> ttyd :7700
      Browser Tab 2 ──> LiveView 2 ──> TtydSession 2 ──> ttyd :7701
      Browser Tab 3 ──> LiveView 3 ──> TtydSession 3 ──> ttyd :7702

  ## Usage

      # Start a session (usually from LiveView mount)
      {:ok, session_id, port} = SessionManager.start_session(self())

      # Get session info
      {:ok, port} = SessionManager.get_session(session_id)

      # Stop a session (automatic on process exit)
      :ok = SessionManager.stop_session(session_id)

  """

  use Supervisor

  require Logger

  @registry __MODULE__.Registry
  @supervisor __MODULE__.DynamicSupervisor
  @port_range 7700..7799

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the session manager supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new ttyd session for the given owner process.

  The session will be automatically cleaned up when the owner process dies.

  Returns `{:ok, session_id, port}` or `{:error, reason}`.
  """
  @spec start_session(pid(), keyword()) :: {:ok, String.t(), pos_integer()} | {:error, term()}
  def start_session(owner_pid, opts \\ []) do
    session_id = generate_session_id()

    case find_available_port() do
      {:ok, port} ->
        session_opts =
          opts
          |> Keyword.put(:session_id, session_id)
          |> Keyword.put(:port, port)
          |> Keyword.put(:owner, owner_pid)

        case DynamicSupervisor.start_child(@supervisor, {
               Events.Services.Ttyd.Session,
               session_opts
             }) do
          {:ok, _pid} ->
            Logger.info("[TtydSessionManager] Started session #{session_id} on port #{port}")
            {:ok, session_id, port}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :no_ports_available} = error ->
        error
    end
  end

  @doc """
  Gets the port for an existing session.
  """
  @spec get_session(String.t()) :: {:ok, pos_integer()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{_pid, port}] -> {:ok, port}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Stops a session by ID.
  """
  @spec stop_session(String.t()) :: :ok | {:error, :not_found}
  def stop_session(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _port}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active sessions.
  """
  @spec list_sessions() :: [{String.t(), pos_integer(), pid()}]
  def list_sessions do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3", :"$2"}}]}])
  end

  @doc """
  Returns the count of active sessions.
  """
  @spec session_count() :: non_neg_integer()
  def session_count do
    DynamicSupervisor.count_children(@supervisor).active
  end

  @doc """
  Returns ports currently in use.
  """
  @spec used_ports() :: [pos_integer()]
  def used_ports do
    list_sessions()
    |> Enum.map(fn {_id, port, _pid} -> port end)
    |> Enum.sort()
  end

  # ============================================================================
  # Supervisor Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @supervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp find_available_port do
    used = MapSet.new(used_ports())

    @port_range
    |> Enum.shuffle()
    |> Enum.find(fn port -> not MapSet.member?(used, port) end)
    |> case do
      nil -> {:error, :no_ports_available}
      port -> {:ok, port}
    end
  end
end
