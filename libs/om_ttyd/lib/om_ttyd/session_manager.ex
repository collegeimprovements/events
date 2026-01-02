defmodule OmTtyd.SessionManager do
  @moduledoc """
  Manages per-session ttyd terminal instances.

  Each browser tab gets its own ttyd process running on a dynamic port.
  Sessions are tracked via Registry and cleaned up when the owning
  process (e.g., LiveView) terminates.

  ## Architecture

      Browser Tab 1 ──> LiveView 1 ──> TtydSession 1 ──> ttyd :7700
      Browser Tab 2 ──> LiveView 2 ──> TtydSession 2 ──> ttyd :7701
      Browser Tab 3 ──> LiveView 3 ──> TtydSession 3 ──> ttyd :7702

  ## Usage

      # Add to your supervision tree
      children = [
        OmTtyd.SessionManager
      ]

      # Start a session (usually from LiveView mount)
      {:ok, session_id, port} = OmTtyd.SessionManager.start_session(self())

      # Get session info
      {:ok, port} = OmTtyd.SessionManager.get_session(session_id)

      # Stop a session (automatic on process exit)
      :ok = OmTtyd.SessionManager.stop_session(session_id)

  ## Configuration

  Configure the port range via application config:

      config :om_ttyd, :session_manager,
        port_range: 7700..7799

  """

  use Supervisor

  require Logger

  @default_port_range 7700..7799

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the session manager supervisor.

  ## Options

    * `:name` - Supervisor name (default: #{__MODULE__})
    * `:port_range` - Port range for sessions (default: 7700..7799)
    * `:session_module` - Session module to use (default: OmTtyd.Session)

  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts a new ttyd session for the given owner process.

  The session will be automatically cleaned up when the owner process dies.

  Returns `{:ok, session_id, port}` or `{:error, reason}`.
  """
  @spec start_session(pid(), keyword()) :: {:ok, String.t(), pos_integer()} | {:error, term()}
  def start_session(owner_pid, opts \\ []) do
    name = Keyword.get(opts, :manager, __MODULE__)
    session_id = generate_session_id()

    case find_available_port(name) do
      {:ok, port} ->
        session_opts =
          opts
          |> Keyword.put(:session_id, session_id)
          |> Keyword.put(:port, port)
          |> Keyword.put(:owner, owner_pid)

        supervisor = supervisor_name(name)
        session_module = Keyword.get(opts, :session_module, OmTtyd.Session)

        case DynamicSupervisor.start_child(supervisor, {session_module, session_opts}) do
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
  @spec get_session(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, :not_found}
  def get_session(session_id, opts \\ []) do
    name = Keyword.get(opts, :manager, __MODULE__)
    registry = registry_name(name)

    case Registry.lookup(registry, session_id) do
      [{_pid, port}] -> {:ok, port}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Stops a session by ID.
  """
  @spec stop_session(String.t(), keyword()) :: :ok | {:error, :not_found}
  def stop_session(session_id, opts \\ []) do
    name = Keyword.get(opts, :manager, __MODULE__)
    registry = registry_name(name)
    supervisor = supervisor_name(name)

    case Registry.lookup(registry, session_id) do
      [{pid, _port}] ->
        DynamicSupervisor.terminate_child(supervisor, pid)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active sessions.
  """
  @spec list_sessions(keyword()) :: [{String.t(), pos_integer(), pid()}]
  def list_sessions(opts \\ []) do
    name = Keyword.get(opts, :manager, __MODULE__)
    registry = registry_name(name)
    Registry.select(registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3", :"$2"}}]}])
  end

  @doc """
  Returns the count of active sessions.
  """
  @spec session_count(keyword()) :: non_neg_integer()
  def session_count(opts \\ []) do
    name = Keyword.get(opts, :manager, __MODULE__)
    supervisor = supervisor_name(name)
    DynamicSupervisor.count_children(supervisor).active
  end

  @doc """
  Returns ports currently in use.
  """
  @spec used_ports(keyword()) :: [pos_integer()]
  def used_ports(opts \\ []) do
    list_sessions(opts)
    |> Enum.map(fn {_id, port, _pid} -> port end)
    |> Enum.sort()
  end

  @doc """
  Returns the Registry name for this manager.
  """
  def registry_name(manager \\ __MODULE__) do
    Module.concat(manager, Registry)
  end

  @doc """
  Returns the DynamicSupervisor name for this manager.
  """
  def supervisor_name(manager \\ __MODULE__) do
    Module.concat(manager, DynamicSupervisor)
  end

  # ============================================================================
  # Supervisor Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    children = [
      {Registry, keys: :unique, name: registry_name(name)},
      {DynamicSupervisor, strategy: :one_for_one, name: supervisor_name(name)}
    ]

    # Store configuration in persistent term for quick access
    port_range = Keyword.get(opts, :port_range, @default_port_range)
    :persistent_term.put({__MODULE__, name, :port_range}, port_range)

    Supervisor.init(children, strategy: :one_for_all)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp find_available_port(manager) do
    used = MapSet.new(used_ports(manager: manager))
    port_range = get_port_range(manager)

    port_range
    |> Enum.shuffle()
    |> Enum.find(fn port -> not MapSet.member?(used, port) end)
    |> case do
      nil -> {:error, :no_ports_available}
      port -> {:ok, port}
    end
  end

  defp get_port_range(manager) do
    case :persistent_term.get({__MODULE__, manager, :port_range}, nil) do
      nil -> @default_port_range
      range -> range
    end
  end
end
