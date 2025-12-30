defmodule Events.Services.Ttyd do
  @moduledoc """
  Full-featured web-based terminal sharing via ttyd and ExCmd.

  ttyd shares a terminal session over the web, accessible via any modern browser.
  Useful for remote collaboration, demos, system administration, and debugging.

  ## Features

  - Start terminal servers with any command
  - Basic authentication support
  - SSL/TLS encryption
  - Read-only mode for monitoring
  - Client connection limits
  - UNIX socket support
  - xterm.js client options (ZMODEM, Sixel, themes)
  - Process lifecycle management via GenServer

  ## Examples

      # Start a bash terminal on port 7681
      {:ok, pid} = Ttyd.start("bash")
      Ttyd.url(pid)  # => "http://localhost:7681"

      # Start with authentication
      {:ok, pid} = Ttyd.start("bash",
        port: 8080,
        credential: {"admin", "secret"}
      )

      # Read-only htop monitoring
      {:ok, pid} = Ttyd.start("htop",
        readonly: true,
        max_clients: 10
      )

      # With SSL
      {:ok, pid} = Ttyd.start("bash",
        ssl: true,
        ssl_cert: "/path/to/cert.pem",
        ssl_key: "/path/to/key.pem"
      )

      # Stop the server
      Ttyd.stop(pid)

  ## Requirements

  ttyd must be installed:

      brew install ttyd      # macOS
      apt install ttyd       # Debian/Ubuntu

  See: https://github.com/tsl0922/ttyd

  """

  use GenServer

  require Logger

  @default_port 7681
  @startup_delay 200

  # Type definitions

  @type credential :: {username :: String.t(), password :: String.t()}
  @type socket_owner :: {user :: String.t(), group :: String.t()}
  @type signal :: :sighup | :sigint | :sigterm | :sigkill | pos_integer()

  @type client_option ::
          {:renderer_type, :webgl | :canvas}
          | {:disable_leave_alert, boolean()}
          | {:disable_resize_overlay, boolean()}
          | {:disable_reconnect, boolean()}
          | {:close_on_disconnect, boolean()}
          | {:enable_zmodem, boolean()}
          | {:enable_trzsz, boolean()}
          | {:enable_sixel, boolean()}
          | {:title_fixed, String.t()}
          | {:font_size, pos_integer()}
          | {:unicode_version, pos_integer()}
          | {:cursor_style, :block | :underline | :bar}
          | {:line_height, float()}
          | {:theme, map()}
          | {String.t(), term()}

  @type ttyd_opts :: [
          # Network options
          port: pos_integer() | 0,
          interface: String.t(),
          socket_owner: socket_owner(),
          ipv6: boolean(),

          # Authentication
          credential: credential(),
          auth_header: String.t(),

          # Process options
          uid: pos_integer(),
          gid: pos_integer(),
          signal: signal(),
          cwd: Path.t(),

          # Client options
          writable: boolean(),
          readonly: boolean(),
          terminal_type: String.t(),
          client_options: [client_option()],
          url_arg: boolean(),

          # Connection limits
          max_clients: non_neg_integer(),
          once: boolean(),
          exit_no_conn: boolean(),
          check_origin: boolean(),
          ping_interval: pos_integer(),

          # SSL options
          ssl: boolean(),
          ssl_cert: Path.t(),
          ssl_key: Path.t(),
          ssl_ca: Path.t(),

          # UI options
          browser: boolean(),
          index: Path.t(),
          base_path: String.t(),

          # Debug options
          debug: 0..7,

          # GenServer options
          name: GenServer.name(),
          on_start: (url :: String.t() -> any()),
          on_client_connect: (-> any()),
          on_client_disconnect: (-> any())
        ]

  @type state :: %{
          port: pos_integer(),
          ssl: boolean(),
          command: String.t() | [String.t()],
          process: port() | nil,
          os_pid: pos_integer() | nil,
          started_at: DateTime.t(),
          client_count: non_neg_integer()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a ttyd server with the given command.

  ## Network Options

    * `:port` - Port to listen on (default: 7681, use 0 for random)
    * `:interface` - Network interface (e.g., "eth0") or UNIX socket path
    * `:socket_owner` - `{user, group}` for UNIX socket ownership
    * `:ipv6` - Enable IPv6 support

  ## Authentication Options

    * `:credential` - `{username, password}` for basic auth
    * `:auth_header` - HTTP header name for reverse proxy auth

  ## Process Options

    * `:uid` - User ID to run the command as
    * `:gid` - Group ID to run the command as
    * `:signal` - Signal to send on exit (default: `:sighup`)
    * `:cwd` - Working directory for the command

  ## Client Options

    * `:writable` - Allow clients to write to TTY (default: false, readonly)
    * `:readonly` - Alias for `writable: false`
    * `:terminal_type` - Terminal type (default: "xterm-256color")
    * `:client_options` - xterm.js options (see below)
    * `:url_arg` - Allow command args in URL query params

  ## Connection Limits

    * `:max_clients` - Maximum concurrent clients (0 = unlimited)
    * `:once` - Exit after single client disconnects
    * `:exit_no_conn` - Exit when all clients disconnect
    * `:check_origin` - Reject cross-origin WebSocket connections
    * `:ping_interval` - WebSocket ping interval in seconds (default: 5)

  ## SSL Options

    * `:ssl` - Enable SSL/TLS
    * `:ssl_cert` - Path to SSL certificate file
    * `:ssl_key` - Path to SSL private key file
    * `:ssl_ca` - Path to CA file for client certificate verification

  ## UI Options

    * `:browser` - Open terminal in default browser on start
    * `:index` - Custom index.html path
    * `:base_path` - Base path for reverse proxy (max 128 chars)

  ## Client Options (xterm.js)

  Passed via `:client_options` keyword list:

    * `renderer_type: :canvas` - Use canvas renderer (default: webgl)
    * `disable_leave_alert: true` - Disable page leave confirmation
    * `disable_resize_overlay: true` - Disable resize overlay
    * `disable_reconnect: true` - Disable auto-reconnect
    * `close_on_disconnect: true` - Close on disconnect (disables reconnect)
    * `enable_zmodem: true` - Enable ZMODEM file transfer
    * `enable_trzsz: true` - Enable trzsz file transfer
    * `enable_sixel: true` - Enable Sixel image output
    * `title_fixed: "My Terminal"` - Fixed browser title
    * `font_size: 14` - Terminal font size
    * `cursor_style: :bar` - Cursor style (:block, :underline, :bar)
    * `line_height: 1.2` - Line height multiplier
    * `theme: %{"background" => "#1e1e1e"}` - xterm.js theme

  ## Callbacks

    * `:on_start` - Called with URL when server starts
    * `:on_client_connect` - Called when client connects
    * `:on_client_disconnect` - Called when client disconnects

  ## Examples

      # Basic shell
      {:ok, pid} = Ttyd.start("bash")

      # Authenticated, writable terminal
      {:ok, pid} = Ttyd.start("zsh",
        port: 9000,
        credential: {"admin", "secret"},
        writable: true
      )

      # Read-only htop with connection limit
      {:ok, pid} = Ttyd.start("htop",
        max_clients: 10,
        client_options: [
          disable_reconnect: true,
          title_fixed: "System Monitor"
        ]
      )

      # UNIX socket with custom ownership
      {:ok, pid} = Ttyd.start("bash",
        interface: "/var/run/ttyd.sock",
        socket_owner: {"www-data", "www-data"}
      )

      # Full SSL setup
      {:ok, pid} = Ttyd.start("bash",
        ssl: true,
        ssl_cert: "/etc/ssl/certs/server.pem",
        ssl_key: "/etc/ssl/private/server.key",
        ssl_ca: "/etc/ssl/certs/ca.pem"
      )

      # Behind reverse proxy
      {:ok, pid} = Ttyd.start("bash",
        base_path: "/terminal",
        auth_header: "X-Auth-User"
      )

  """
  @spec start(String.t() | [String.t()], ttyd_opts()) :: GenServer.on_start()
  def start(command, opts \\ []) do
    {gen_opts, ttyd_opts} = extract_gen_opts(opts)
    GenServer.start(__MODULE__, {command, ttyd_opts}, gen_opts)
  end

  @doc """
  Starts a ttyd server linked to the calling process.
  """
  @spec start_link(String.t() | [String.t()], ttyd_opts()) :: GenServer.on_start()
  def start_link(command, opts \\ []) do
    {gen_opts, ttyd_opts} = extract_gen_opts(opts)
    GenServer.start_link(__MODULE__, {command, ttyd_opts}, gen_opts)
  end

  @doc """
  Stops the ttyd server gracefully.
  """
  @spec stop(GenServer.server(), timeout()) :: :ok
  def stop(server, timeout \\ 5000) do
    GenServer.stop(server, :normal, timeout)
  end

  @doc """
  Returns the URL for the running ttyd instance.

  ## Examples

      {:ok, pid} = Ttyd.start("bash", port: 8080)
      Ttyd.url(pid)
      # => "http://localhost:8080"

      {:ok, pid} = Ttyd.start("bash", ssl: true, port: 443)
      Ttyd.url(pid)
      # => "https://localhost:443"

  """
  @spec url(GenServer.server()) :: String.t()
  def url(server) do
    GenServer.call(server, :url)
  end

  @doc """
  Returns the port the ttyd server is listening on.
  """
  @spec port(GenServer.server()) :: pos_integer()
  def port(server) do
    GenServer.call(server, :port)
  end

  @doc """
  Returns server info including uptime and client count.

  ## Examples

      Ttyd.info(pid)
      # => %{
      #   port: 7681,
      #   url: "http://localhost:7681",
      #   command: "bash",
      #   uptime_seconds: 3600,
      #   started_at: ~U[2025-01-15 10:00:00Z],
      #   ssl: false
      # }

  """
  @spec info(GenServer.server()) :: map()
  def info(server) do
    GenServer.call(server, :info)
  end

  @doc """
  Checks if the ttyd server process is still alive.
  """
  @spec alive?(GenServer.server()) :: boolean()
  def alive?(server) do
    GenServer.call(server, :alive?)
  catch
    :exit, _ -> false
  end

  @doc """
  Checks if ttyd is available in PATH.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("ttyd") != nil
  end

  @doc """
  Returns the ttyd version.
  """
  @spec version() :: {:ok, String.t()} | {:error, :not_found}
  def version do
    if available?() do
      result =
        ExCmd.stream!(["ttyd", "--version"])
        |> Enum.into(<<>>)
        |> String.trim()

      {:ok, result}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns ttyd version, raising if not available.
  """
  @spec version!() :: String.t()
  def version! do
    case version() do
      {:ok, v} -> v
      {:error, :not_found} -> raise "ttyd not found in PATH"
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init({command, opts}) do
    Process.flag(:trap_exit, true)

    port_num = Keyword.get(opts, :port, @default_port)
    ssl? = Keyword.get(opts, :ssl, false)
    on_start = Keyword.get(opts, :on_start)

    args = build_args(command, opts)
    cmd = ["ttyd" | args]

    Logger.info("[ttyd] Starting: #{Enum.join(cmd, " ")}")

    # Start ttyd process using Port for better control
    port =
      Port.open({:spawn_executable, System.find_executable("ttyd")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    # Get OS PID for the process
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    # Give ttyd time to bind to port
    Process.sleep(@startup_delay)

    state = %{
      port: port_num,
      ssl: ssl?,
      command: command,
      process: port,
      os_pid: os_pid,
      started_at: DateTime.utc_now(),
      client_count: 0
    }

    # Call on_start callback
    if is_function(on_start, 1) do
      url = build_url(state)
      on_start.(url)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:reply, build_url(state), state}
  end

  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  def handle_call(:info, _from, state) do
    now = DateTime.utc_now()
    uptime = DateTime.diff(now, state.started_at, :second)

    info = %{
      port: state.port,
      url: build_url(state),
      command: state.command,
      uptime_seconds: uptime,
      started_at: state.started_at,
      ssl: state.ssl,
      os_pid: state.os_pid
    }

    {:reply, info, state}
  end

  def handle_call(:alive?, _from, state) do
    alive = state.process != nil and Port.info(state.process) != nil
    {:reply, alive, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{process: port} = state) do
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      Logger.debug("[ttyd] #{line}")
    end)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{process: port} = state) do
    Logger.info("[ttyd] Process exited with status #{status}")
    {:stop, {:shutdown, {:exit_status, status}}, %{state | process: nil}}
  end

  def handle_info({:EXIT, port, reason}, %{process: port} = state) do
    Logger.info("[ttyd] Port exited: #{inspect(reason)}")
    {:stop, reason, %{state | process: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("[ttyd] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[ttyd] Terminating: #{inspect(reason)}")

    if state.process do
      # Send SIGTERM first
      if state.os_pid do
        System.cmd("kill", ["-TERM", to_string(state.os_pid)], stderr_to_stdout: true)
      end

      # Give it a moment to clean up
      Process.sleep(100)

      # Force close if still open
      try do
        Port.close(state.process)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp extract_gen_opts(opts) do
    {gen_keys, ttyd_keys} = Keyword.split(opts, [:name])
    {gen_keys, ttyd_keys}
  end

  defp build_url(state) do
    scheme = if state.ssl, do: "https", else: "http"
    "#{scheme}://localhost:#{state.port}"
  end

  defp build_args(command, opts) do
    []
    |> add_network_args(opts)
    |> add_auth_args(opts)
    |> add_process_args(opts)
    |> add_client_args(opts)
    |> add_connection_args(opts)
    |> add_ssl_args(opts)
    |> add_ui_args(opts)
    |> add_debug_args(opts)
    |> add_command(command)
  end

  defp add_network_args(args, opts) do
    args
    |> maybe_add_arg("-p", Keyword.get(opts, :port, @default_port))
    |> maybe_add_arg("-i", Keyword.get(opts, :interface))
    |> maybe_add_socket_owner(Keyword.get(opts, :socket_owner))
    |> maybe_add_flag("-6", Keyword.get(opts, :ipv6))
  end

  defp add_auth_args(args, opts) do
    args
    |> maybe_add_credential(Keyword.get(opts, :credential))
    |> maybe_add_arg("-H", Keyword.get(opts, :auth_header))
  end

  defp add_process_args(args, opts) do
    args
    |> maybe_add_arg("-u", Keyword.get(opts, :uid))
    |> maybe_add_arg("-g", Keyword.get(opts, :gid))
    |> maybe_add_signal(Keyword.get(opts, :signal))
    |> maybe_add_arg("-w", Keyword.get(opts, :cwd))
  end

  defp add_client_args(args, opts) do
    writable = Keyword.get(opts, :writable, false)
    readonly = Keyword.get(opts, :readonly, false)

    # writable: true means add -W flag, readonly: true means don't add -W
    # Default is readonly (no -W flag)
    args =
      if writable and not readonly do
        args ++ ["-W"]
      else
        args
      end

    args
    |> maybe_add_arg("-T", Keyword.get(opts, :terminal_type))
    |> add_client_options(Keyword.get(opts, :client_options))
    |> maybe_add_flag("-a", Keyword.get(opts, :url_arg))
  end

  defp add_connection_args(args, opts) do
    args
    |> maybe_add_arg("-m", Keyword.get(opts, :max_clients))
    |> maybe_add_flag("-o", Keyword.get(opts, :once))
    |> maybe_add_flag("-q", Keyword.get(opts, :exit_no_conn))
    |> maybe_add_flag("-O", Keyword.get(opts, :check_origin))
    |> maybe_add_arg("-P", Keyword.get(opts, :ping_interval))
  end

  defp add_ssl_args(args, opts) do
    args
    |> maybe_add_flag("-S", Keyword.get(opts, :ssl))
    |> maybe_add_arg("-C", Keyword.get(opts, :ssl_cert))
    |> maybe_add_arg("-K", Keyword.get(opts, :ssl_key))
    |> maybe_add_arg("-A", Keyword.get(opts, :ssl_ca))
  end

  defp add_ui_args(args, opts) do
    args
    |> maybe_add_flag("-B", Keyword.get(opts, :browser))
    |> maybe_add_arg("-I", Keyword.get(opts, :index))
    |> maybe_add_arg("-b", Keyword.get(opts, :base_path))
  end

  defp add_debug_args(args, opts) do
    maybe_add_arg(args, "-d", Keyword.get(opts, :debug))
  end

  defp add_command(args, command) when is_binary(command) do
    args ++ ["--", command]
  end

  defp add_command(args, command) when is_list(command) do
    args ++ ["--"] ++ command
  end

  defp maybe_add_arg(args, _flag, nil), do: args

  defp maybe_add_arg(args, flag, value) do
    args ++ [flag, to_string(value)]
  end

  defp maybe_add_flag(args, _flag, nil), do: args
  defp maybe_add_flag(args, _flag, false), do: args
  defp maybe_add_flag(args, flag, true), do: args ++ [flag]

  defp maybe_add_credential(args, nil), do: args

  defp maybe_add_credential(args, {user, pass}) do
    args ++ ["-c", "#{user}:#{pass}"]
  end

  defp maybe_add_socket_owner(args, nil), do: args

  defp maybe_add_socket_owner(args, {user, group}) do
    args ++ ["-U", "#{user}:#{group}"]
  end

  defp maybe_add_signal(args, nil), do: args

  defp maybe_add_signal(args, signal) when is_atom(signal) do
    sig_num =
      case signal do
        :sighup -> 1
        :sigint -> 2
        :sigterm -> 15
        :sigkill -> 9
        _ -> 1
      end

    args ++ ["-s", to_string(sig_num)]
  end

  defp maybe_add_signal(args, signal) when is_integer(signal) do
    args ++ ["-s", to_string(signal)]
  end

  defp add_client_options(args, nil), do: args

  defp add_client_options(args, options) when is_list(options) do
    Enum.reduce(options, args, fn {key, value}, acc ->
      opt_string = format_client_option(key, value)
      acc ++ ["-t", opt_string]
    end)
  end

  defp format_client_option(key, value) do
    key_str = format_option_key(key)
    value_str = format_option_value(value)
    "#{key_str}=#{value_str}"
  end

  defp format_option_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> Macro.camelize()
    |> uncapitalize()
  end

  defp format_option_key(key) when is_binary(key), do: key

  defp format_option_value(true), do: "true"
  defp format_option_value(false), do: "false"
  defp format_option_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_option_value(value) when is_map(value), do: JSON.encode!(value)
  defp format_option_value(value), do: to_string(value)

  defp uncapitalize(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp uncapitalize(""), do: ""
end
