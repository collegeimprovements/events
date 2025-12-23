defmodule Events.Services.Ttyd.Server do
  @moduledoc """
  Supervised ttyd terminal server.

  This module wraps `Events.Services.Ttyd` as a proper child spec
  for supervision trees.

  ## Usage

  Add to your application supervision tree:

      # lib/events/application.ex
      children = [
        {Events.Services.Ttyd.Server, [
          command: "bash",
          port: 7681,
          writable: true
        ]}
      ]

  Or start manually:

      {:ok, pid} = Events.Services.Ttyd.Server.start_link(
        command: "bash",
        port: 7681
      )

  Access the running server:

      Events.Services.Ttyd.Server.url()
      # => "http://localhost:7681"

  """

  use GenServer

  require Logger

  alias Events.Services.Ttyd

  @default_name __MODULE__

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the ttyd server.

  ## Options

    * `:command` - Command to run (default: "bash")
    * `:name` - GenServer name (default: #{inspect(@default_name)})
    * All other options are passed to `Ttyd.start_link/2`

  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the URL of the running ttyd server.
  """
  @spec url(GenServer.server()) :: String.t()
  def url(server \\ @default_name) do
    GenServer.call(server, :url)
  end

  @doc """
  Returns the port of the running ttyd server.
  """
  @spec port(GenServer.server()) :: pos_integer()
  def port(server \\ @default_name) do
    GenServer.call(server, :port)
  end

  @doc """
  Returns info about the running ttyd server.
  """
  @spec info(GenServer.server()) :: map()
  def info(server \\ @default_name) do
    GenServer.call(server, :info)
  end

  @doc """
  Checks if the ttyd server is running and healthy.
  """
  @spec alive?(GenServer.server()) :: boolean()
  def alive?(server \\ @default_name) do
    GenServer.call(server, :alive?)
  catch
    :exit, _ -> false
  end

  @doc """
  Returns the child spec for supervision.
  """
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, @default_name),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    command = Keyword.get(opts, :command, "bash")
    ttyd_opts = Keyword.drop(opts, [:command])

    Logger.info("[TtydServer] Starting ttyd with command: #{inspect(command)}")

    case Ttyd.start_link(command, ttyd_opts) do
      {:ok, ttyd_pid} ->
        Process.link(ttyd_pid)
        {:ok, %{ttyd_pid: ttyd_pid, command: command, opts: ttyd_opts}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:url, _from, state) do
    url = Ttyd.url(state.ttyd_pid)
    {:reply, url, state}
  end

  def handle_call(:port, _from, state) do
    port = Ttyd.port(state.ttyd_pid)
    {:reply, port, state}
  end

  def handle_call(:info, _from, state) do
    info = Ttyd.info(state.ttyd_pid)
    {:reply, info, state}
  end

  def handle_call(:alive?, _from, state) do
    alive = Ttyd.alive?(state.ttyd_pid)
    {:reply, alive, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{ttyd_pid: pid} = state) do
    Logger.warning("[TtydServer] ttyd process exited: #{inspect(reason)}")
    # Let supervisor handle restart
    {:stop, reason, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[TtydServer] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[TtydServer] Terminating: #{inspect(reason)}")

    if state.ttyd_pid && Process.alive?(state.ttyd_pid) do
      Ttyd.stop(state.ttyd_pid)
    end

    :ok
  end
end
