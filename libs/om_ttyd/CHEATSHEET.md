# OmTtyd Cheatsheet

> Web-based terminal sharing via ttyd. Requires `ttyd` binary. For full docs, see `README.md`.

## Basic Usage

```elixir
# Start terminal
{:ok, pid} = OmTtyd.start("bash")
{:ok, pid} = OmTtyd.start("bash", port: 8080)
{:ok, pid} = OmTtyd.start(["zsh", "-l"])
{:ok, pid} = OmTtyd.start("htop")

# Get info
OmTtyd.url(pid)                                   #=> "http://localhost:7681"
OmTtyd.port(pid)                                   #=> 7681
OmTtyd.info(pid)                                   #=> %{port: 7681, url: ..., uptime_seconds: ...}
OmTtyd.alive?(pid)                                 #=> true

# Stop
OmTtyd.stop(pid)
```

---

## Options

```elixir
{:ok, pid} = OmTtyd.start("bash",
  port: 7681,                                      # default: 7681
  interface: "0.0.0.0",                            # bind address
  credential: "user:pass",                          # basic auth
  readonly: true,                                   # read-only mode
  max_clients: 5,                                   # concurrent limit
  ssl: true,                                        # enable SSL
  ssl_cert: "/path/to/cert.pem",
  ssl_key: "/path/to/key.pem"
)
```

---

## Session Manager

```elixir
# Start manager
{:ok, pid} = OmTtyd.SessionManager.start_link(name: MyApp.Terminals)

# Create named sessions
{:ok, session} = OmTtyd.SessionManager.create(MyApp.Terminals, "debug",
  command: "bash", port: 7682)

# List / get / stop sessions
sessions = OmTtyd.SessionManager.list(MyApp.Terminals)
{:ok, session} = OmTtyd.SessionManager.get(MyApp.Terminals, "debug")
:ok = OmTtyd.SessionManager.stop(MyApp.Terminals, "debug")
```

---

## Supervision

```elixir
children = [
  {OmTtyd.SessionManager, name: MyApp.Terminals}
]
```
