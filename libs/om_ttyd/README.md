# OmTtyd

Web-based terminal sharing for Elixir via ttyd.

## Installation

```elixir
def deps do
  [
    {:om_ttyd, "~> 0.1.0"},
    {:ex_cmd, "~> 0.10"}
  ]
end
```

**System Requirement**: ttyd must be installed:

```bash
# macOS
brew install ttyd

# Debian/Ubuntu
apt install ttyd

# Arch Linux
pacman -S ttyd
```

## Quick Start

```elixir
# Start a bash terminal on port 7681
{:ok, pid} = OmTtyd.start("bash")

# Get the URL
OmTtyd.url(pid)
#=> "http://localhost:7681"

# Stop the server
OmTtyd.stop(pid)
```

## Features

- **Web Terminal** - Share terminal sessions via browser
- **Authentication** - Basic auth support
- **SSL/TLS** - Encrypted connections
- **Read-Only Mode** - For monitoring/demos
- **Client Limits** - Control concurrent connections
- **xterm.js Options** - ZMODEM, Sixel, themes, fonts
- **Process Management** - GenServer lifecycle control
- **Supervision** - Built-in child spec for supervision trees

---

## Basic Usage

### Start a Terminal

```elixir
# Simple bash shell
{:ok, pid} = OmTtyd.start("bash")

# Specific shell with arguments
{:ok, pid} = OmTtyd.start(["zsh", "-l"])

# Run a specific command
{:ok, pid} = OmTtyd.start("htop")

# Custom port
{:ok, pid} = OmTtyd.start("bash", port: 8080)
```

### Server Information

```elixir
# Get URL
OmTtyd.url(pid)
#=> "http://localhost:7681"

# Get port
OmTtyd.port(pid)
#=> 7681

# Get full info
OmTtyd.info(pid)
#=> %{
#     port: 7681,
#     url: "http://localhost:7681",
#     command: "bash",
#     uptime_seconds: 3600,
#     started_at: ~U[2025-01-15 10:00:00Z],
#     ssl: false,
#     os_pid: 12345
#   }

# Check if alive
OmTtyd.alive?(pid)
#=> true
```

### Stop Server

```elixir
# Graceful stop (default 5s timeout)
OmTtyd.stop(pid)

# With custom timeout
OmTtyd.stop(pid, 10_000)
```

---

## Authentication

### Basic Auth

```elixir
{:ok, pid} = OmTtyd.start("bash",
  credential: {"admin", "secretpassword"}
)
# Access at http://localhost:7681 with username/password prompt
```

### Reverse Proxy Auth

```elixir
# Trust auth header from reverse proxy
{:ok, pid} = OmTtyd.start("bash",
  auth_header: "X-Authenticated-User"
)
```

---

## SSL/TLS

### Basic SSL

```elixir
{:ok, pid} = OmTtyd.start("bash",
  ssl: true,
  ssl_cert: "/etc/ssl/certs/server.pem",
  ssl_key: "/etc/ssl/private/server.key"
)

OmTtyd.url(pid)
#=> "https://localhost:7681"
```

### With Client Certificate Verification

```elixir
{:ok, pid} = OmTtyd.start("bash",
  ssl: true,
  ssl_cert: "/path/to/cert.pem",
  ssl_key: "/path/to/key.pem",
  ssl_ca: "/path/to/ca.pem"  # For client cert verification
)
```

---

## Access Control

### Read-Only Mode

```elixir
# Default is read-only (safe for sharing)
{:ok, pid} = OmTtyd.start("htop")

# Explicitly read-only
{:ok, pid} = OmTtyd.start("bash", readonly: true)

# Enable writing (interactive terminal)
{:ok, pid} = OmTtyd.start("bash", writable: true)
```

### Connection Limits

```elixir
# Limit concurrent clients
{:ok, pid} = OmTtyd.start("bash", max_clients: 10)

# Exit after single client disconnects
{:ok, pid} = OmTtyd.start("bash", once: true)

# Exit when all clients disconnect
{:ok, pid} = OmTtyd.start("bash", exit_no_conn: true)

# Reject cross-origin WebSocket connections
{:ok, pid} = OmTtyd.start("bash", check_origin: true)
```

---

## xterm.js Client Options

Customize the terminal appearance and behavior:

```elixir
{:ok, pid} = OmTtyd.start("bash",
  client_options: [
    # Appearance
    font_size: 14,
    line_height: 1.2,
    cursor_style: :bar,           # :block, :underline, :bar
    theme: %{
      "background" => "#1e1e1e",
      "foreground" => "#d4d4d4",
      "cursor" => "#aeafad"
    },

    # Behavior
    disable_leave_alert: true,    # No "leave page?" prompt
    disable_resize_overlay: true, # No resize indicator
    disable_reconnect: true,      # No auto-reconnect
    close_on_disconnect: true,    # Close tab on disconnect

    # File Transfer
    enable_zmodem: true,          # ZMODEM file transfer (rz/sz)
    enable_trzsz: true,           # trzsz file transfer

    # Graphics
    enable_sixel: true,           # Sixel image support

    # Window
    title_fixed: "My Terminal",   # Fixed browser title
    renderer_type: :canvas        # :webgl (default) or :canvas
  ]
)
```

---

## Network Options

### Port Configuration

```elixir
# Specific port
{:ok, pid} = OmTtyd.start("bash", port: 9000)

# Random available port
{:ok, pid} = OmTtyd.start("bash", port: 0)
OmTtyd.port(pid)  # Returns assigned port
```

### Network Interface

```elixir
# Bind to specific interface
{:ok, pid} = OmTtyd.start("bash", interface: "eth0")

# IPv6 support
{:ok, pid} = OmTtyd.start("bash", ipv6: true)
```

### UNIX Socket

```elixir
{:ok, pid} = OmTtyd.start("bash",
  interface: "/var/run/ttyd.sock",
  socket_owner: {"www-data", "www-data"}
)
```

---

## Process Options

```elixir
{:ok, pid} = OmTtyd.start("bash",
  # Run as specific user/group
  uid: 1000,
  gid: 1000,

  # Working directory
  cwd: "/home/user/project",

  # Signal to send on exit
  signal: :sigterm  # :sighup, :sigint, :sigterm, :sigkill
)
```

---

## Reverse Proxy Setup

```elixir
# Behind nginx/Apache with base path
{:ok, pid} = OmTtyd.start("bash",
  base_path: "/terminal",
  auth_header: "X-Auth-User"
)

# Nginx config example:
# location /terminal {
#   proxy_pass http://localhost:7681;
#   proxy_http_version 1.1;
#   proxy_set_header Upgrade $http_upgrade;
#   proxy_set_header Connection "upgrade";
#   proxy_set_header X-Auth-User $remote_user;
# }
```

---

## Supervision

### Using OmTtyd.Server

```elixir
# In your application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {OmTtyd.Server, [
        command: "bash",
        port: 7681,
        writable: true,
        credential: {"admin", "secret"}
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# Access the running server
OmTtyd.Server.url()
#=> "http://localhost:7681"

OmTtyd.Server.info()
#=> %{port: 7681, uptime_seconds: 3600, ...}
```

### Multiple Terminals

```elixir
children = [
  {OmTtyd.Server, [
    name: :admin_terminal,
    command: "bash",
    port: 7681,
    writable: true
  ]},
  {OmTtyd.Server, [
    name: :monitoring,
    command: "htop",
    port: 7682,
    readonly: true
  ]}
]

# Access by name
OmTtyd.Server.url(:admin_terminal)
OmTtyd.Server.url(:monitoring)
```

---

## Callbacks

```elixir
{:ok, pid} = OmTtyd.start("bash",
  on_start: fn url ->
    IO.puts("Terminal available at: #{url}")
    # Send notification, log, etc.
  end
)
```

---

## Utility Functions

```elixir
# Check if ttyd is available
OmTtyd.available?()
#=> true

# Get ttyd version
{:ok, version} = OmTtyd.version()
#=> {:ok, "ttyd version 1.7.4"}

# Raising version
OmTtyd.version!()
#=> "ttyd version 1.7.4"
```

---

## Real-World Examples

### Admin Dashboard Terminal

```elixir
defmodule MyApp.AdminTerminal do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def url, do: GenServer.call(__MODULE__, :url)

  def init(_opts) do
    {:ok, pid} = OmTtyd.start("bash", [
      port: 9000,
      writable: true,
      credential: admin_credentials(),
      ssl: true,
      ssl_cert: ssl_cert_path(),
      ssl_key: ssl_key_path(),
      client_options: [
        title_fixed: "Admin Console",
        theme: %{"background" => "#0d1117"}
      ]
    ])

    {:ok, %{ttyd: pid}}
  end

  def handle_call(:url, _from, state) do
    {:reply, OmTtyd.url(state.ttyd), state}
  end

  defp admin_credentials do
    {
      Application.get_env(:my_app, :admin_user),
      Application.get_env(:my_app, :admin_pass)
    }
  end

  defp ssl_cert_path, do: Application.get_env(:my_app, :ssl_cert)
  defp ssl_key_path, do: Application.get_env(:my_app, :ssl_key)
end
```

### Read-Only System Monitor

```elixir
# Share htop with the team
{:ok, pid} = OmTtyd.start("htop", [
  port: 8080,
  max_clients: 50,
  client_options: [
    title_fixed: "System Monitor",
    disable_reconnect: false  # Allow reconnection
  ]
])
```

### Pair Programming Session

```elixir
# Create a shared terminal session
{:ok, pid} = OmTtyd.start(["tmux", "new-session", "-A", "-s", "pairing"], [
  port: 7681,
  writable: true,
  credential: {"team", "sharedpass"},
  client_options: [
    enable_zmodem: true,  # File transfer
    font_size: 16
  ]
])
```

---

## Options Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `port` | integer | 7681 | Port to listen on (0 = random) |
| `interface` | string | - | Network interface or socket path |
| `credential` | tuple | - | `{username, password}` for basic auth |
| `writable` | boolean | false | Allow client input |
| `readonly` | boolean | false | Alias for `writable: false` |
| `max_clients` | integer | 0 | Max concurrent clients (0 = unlimited) |
| `once` | boolean | false | Exit after first client disconnects |
| `ssl` | boolean | false | Enable SSL/TLS |
| `ssl_cert` | path | - | SSL certificate file |
| `ssl_key` | path | - | SSL private key file |
| `client_options` | keyword | - | xterm.js options |
| `cwd` | path | - | Working directory |

## License

MIT
