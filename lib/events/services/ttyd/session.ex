defmodule Events.Services.Ttyd.Session do
  @moduledoc """
  A single ttyd terminal session.

  Each session wraps one ttyd process and is tied to an owner process
  (typically a LiveView). When the owner dies, the session cleans up
  the ttyd process automatically.

  ## Options

    * `:session_id` - Unique session identifier (required)
    * `:port` - Port to run ttyd on (required)
    * `:owner` - Owner process to monitor (required)
    * `:command` - Shell command (default: "bash")
    * `:writable` - Allow terminal input (default: true)
    * `:cwd` - Working directory (default: user home or "/")

  """

  use GenServer

  require Logger

  alias Events.Services.Ttyd

  @registry Events.Services.Ttyd.SessionManager.Registry

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  @doc """
  Returns the port this session is running on.
  """
  @spec port(String.t()) :: {:ok, pos_integer()} | {:error, :not_found}
  def port(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{_pid, port}] -> {:ok, port}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns info about the session.
  """
  @spec info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def info(session_id) do
    try do
      GenServer.call(via(session_id), :info)
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    session_id = Keyword.fetch!(opts, :session_id)
    port = Keyword.fetch!(opts, :port)
    owner = Keyword.fetch!(opts, :owner)

    command = Keyword.get(opts, :command, default_command())
    writable = Keyword.get(opts, :writable, true)
    cwd = Keyword.get(opts, :cwd, default_cwd())

    # Monitor owner process for cleanup
    owner_ref = Process.monitor(owner)

    # Register with port as value for quick lookups
    Registry.register(@registry, session_id, port)

    # Start ttyd process
    ttyd_opts = [
      port: port,
      writable: writable,
      cwd: cwd,
      # Exit when client disconnects (cleanup)
      exit_no_conn: true,
      # Reasonable timeout for reconnection
      ping_interval: 10,
      client_options: [
        disable_leave_alert: true,
        title_fixed: "Terminal - #{String.slice(session_id, 0, 8)}"
      ]
    ]

    Logger.info("[TtydSession] Starting session #{session_id} on port #{port}")

    case Ttyd.start_link(command, ttyd_opts) do
      {:ok, ttyd_pid} ->
        Process.link(ttyd_pid)

        state = %{
          session_id: session_id,
          port: port,
          owner: owner,
          owner_ref: owner_ref,
          ttyd_pid: ttyd_pid,
          command: command,
          started_at: DateTime.utc_now()
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("[TtydSession] Failed to start ttyd: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      session_id: state.session_id,
      port: state.port,
      command: state.command,
      started_at: state.started_at,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
      url: "http://localhost:#{state.port}"
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{owner_ref: ref} = state) do
    Logger.info(
      "[TtydSession] Owner died (#{inspect(reason)}), stopping session #{state.session_id}"
    )

    {:stop, :normal, state}
  end

  def handle_info({:EXIT, pid, reason}, %{ttyd_pid: pid} = state) do
    Logger.info(
      "[TtydSession] ttyd exited (#{inspect(reason)}), stopping session #{state.session_id}"
    )

    {:stop, :normal, %{state | ttyd_pid: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("[TtydSession] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[TtydSession] Terminating session #{state.session_id}: #{inspect(reason)}")

    if state.ttyd_pid && Process.alive?(state.ttyd_pid) do
      Ttyd.stop(state.ttyd_pid, 2000)
    end

    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp via(session_id) do
    {:via, Registry, {@registry, session_id}}
  end

  defp default_command do
    case :os.type() do
      {:unix, :darwin} -> System.get_env("SHELL", "/bin/zsh")
      {:unix, _} -> System.get_env("SHELL", "/bin/bash")
      {:win32, _} -> "cmd.exe"
    end
  end

  defp default_cwd do
    System.get_env("HOME") || System.get_env("USERPROFILE") || "/"
  end
end
