# OmBehaviours Cheatsheet

> Six behaviour contracts for structuring Elixir applications.

## Setup

```elixir
alias OmBehaviours.{Adapter, Service, Builder, Worker, Plugin, HealthCheck}
```

No configuration required. Zero dependencies.

---

## Adapter Pattern

Swappable backend implementations (S3, local, mock, etc.)

### Define a Service Interface

```elixir
defmodule MyApp.Storage do
  @callback upload(key :: String.t(), data :: binary()) :: {:ok, String.t()} | {:error, term()}
  @callback download(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
end
```

### Implement Adapters

```elixir
defmodule MyApp.Storage.S3 do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :s3

  @impl OmBehaviours.Adapter
  def adapter_config(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),        # required — raises KeyError if missing
      region: Keyword.get(opts, :region, "us-east-1")
    }
  end

  @impl MyApp.Storage
  def upload(key, data), do: {:ok, "s3://#{key}"}
  def download(key), do: {:ok, "data"}
  def delete(key), do: :ok
end
```

### Resolve Adapters at Runtime

```elixir
# Lightweight resolution (no validation)
Adapter.resolve(:s3, MyApp.Storage)            #=> MyApp.Storage.S3
Adapter.resolve(:google_cloud, MyApp.Storage)  #=> MyApp.Storage.GoogleCloud

# Validated resolution (raises on bad module or missing behaviour)
Adapter.resolve!(:s3, MyApp.Storage)           #=> MyApp.Storage.S3
Adapter.resolve!(:nonexistent, MyApp.Storage)  #=> ** (ArgumentError) not available
```

### Adapter Callbacks

| Callback | Returns | Purpose |
|----------|---------|---------|
| `adapter_name/0` | `atom()` | Unique identifier (`:s3`, `:local`, `:mock`) |
| `adapter_config/1` | `map()` | Validate opts, apply defaults, return config map |

---

## Service Pattern

Contract for supervised processes.

### Using `use` (recommended)

```elixir
defmodule MyApp.Worker do
  use OmBehaviours.Service    # provides default child_spec/1

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
end
```

### Service Callbacks

| Callback | Returns | Required with `use`? |
|----------|---------|---------------------|
| `child_spec/1` | `Supervisor.child_spec()` | No (default provided) |
| `start_link/1` | `{:ok, pid()} \| {:error, term()}` | Yes |

---

## Builder Pattern

Fluent chainable construction: `new → compose → compose → build`.

### Define a Builder

```elixir
defmodule MyApp.QueryBuilder do
  use OmBehaviours.Builder    # injects @behaviour + imports defcompose

  defstruct [:schema, filters: [], sorts: []]

  @impl true
  def new(schema, _opts \\ []), do: %__MODULE__{schema: schema}

  @impl true
  def compose(builder, {:filter, field, value}) do
    %{builder | filters: [{field, value} | builder.filters]}
  end

  @impl true
  def build(builder), do: {builder.schema, builder.filters}

  defcompose where(builder, field, value) do
    compose(builder, {:filter, field, value})
  end
end
```

### Builder Callbacks

| Callback | Returns | Purpose |
|----------|---------|---------|
| `new/2` | `struct()` | Create builder with initial data + options |
| `compose/2` | `struct()` | Apply an operation, return new builder |
| `build/1` | `term()` | Convert builder state to final result |

---

## Worker Pattern

Background job execution with scheduling, retry, and timeout.

### Simple Worker

```elixir
defmodule MyApp.Workers.SendEmail do
  use OmBehaviours.Worker    # defaults: no schedule, exponential backoff, 60s timeout

  @impl true
  def perform(%{to: to, body: body}) do
    case Mailer.deliver(to, body) do
      {:ok, _} -> {:ok, :sent}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Scheduled Worker

```elixir
defmodule MyApp.Workers.Cleanup do
  use OmBehaviours.Worker

  @impl true
  def perform(_args), do: {:ok, Repo.delete_all(expired_query())}

  @impl true
  def schedule, do: "0 3 * * *"          # Daily at 3 AM

  @impl true
  def backoff(attempt), do: 500 * (attempt + 1)  # Linear backoff

  @impl true
  def timeout, do: :timer.minutes(10)
end
```

### Worker Callbacks

| Callback | Default | Required with `use`? |
|----------|---------|---------------------|
| `perform/1` | — | Yes |
| `schedule/0` | `nil` | No |
| `backoff/1` | `min(1000 * 2^attempt, 30_000)` | No |
| `timeout/0` | `60_000` | No |

---

## Plugin Pattern

Extension points with validate → prepare → start lifecycle.

### Stateless Plugin

```elixir
defmodule MyApp.Plugins.RateLimiter do
  use OmBehaviours.Plugin    # default start_link returns :ignore

  @impl true
  def plugin_name, do: :rate_limiter

  @impl true
  def validate(opts) do
    case Keyword.fetch(opts, :max_requests) do
      {:ok, n} when is_integer(n) and n > 0 -> :ok
      _ -> {:error, ":max_requests must be a positive integer"}
    end
  end

  @impl true
  def prepare(opts) do
    {:ok, %{max_requests: Keyword.fetch!(opts, :max_requests)}}
  end
end
```

### Stateful Plugin

```elixir
defmodule MyApp.Plugins.Metrics do
  use OmBehaviours.Plugin

  @impl true
  def plugin_name, do: :metrics

  @impl true
  def validate(_opts), do: :ok

  @impl true
  def prepare(opts), do: {:ok, %{interval: Keyword.get(opts, :interval, 5_000)}}

  @impl true
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end
end
```

### Plugin Lifecycle

```elixir
with :ok <- plugin.validate(opts),
     {:ok, state} <- plugin.prepare(opts) do
  plugin.start_link(state)
end
```

### Plugin Callbacks

| Callback | Default | Required with `use`? |
|----------|---------|---------------------|
| `plugin_name/0` | — | Yes |
| `validate/1` | — | Yes |
| `prepare/1` | — | Yes |
| `start_link/1` | `:ignore` | No |

---

## HealthCheck Pattern

System health reporting with severity and timeout.

### Define a Health Check

```elixir
defmodule MyApp.HealthChecks.Database do
  use OmBehaviours.HealthCheck    # default timeout: 5s

  @impl true
  def name, do: :database

  @impl true
  def severity, do: :critical

  @impl true
  def check do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1") do
      {:ok, _} -> {:ok, %{latency_ms: 1}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Run Health Checks

```elixir
# Single check (enforces timeout, returns timing)
{:ok, result} = HealthCheck.run(MyApp.HealthChecks.Database)
result.status      #=> :healthy | :unhealthy | :timeout
result.severity    #=> :critical | :warning | :info
result.duration_ms #=> 2

# Multiple checks concurrently
results = HealthCheck.run_all([Database, Cache, ExternalApi])
Enum.all?(results, & &1.status == :healthy)
```

### Severity Levels

| Level | Meaning | Example |
|-------|---------|---------|
| `:critical` | System cannot function | Database, core service |
| `:warning` | Degraded but functional | Cache, non-essential API |
| `:info` | Informational | Disk usage, queue depth |

### HealthCheck Callbacks

| Callback | Default | Required with `use`? |
|----------|---------|---------------------|
| `name/0` | — | Yes |
| `severity/0` | — | Yes |
| `check/0` | — | Yes |
| `timeout/0` | `5_000` | No |

---

## Behaviour Introspection

```elixir
# Check any behaviour
OmBehaviours.implements?(MyApp.Storage.S3, OmBehaviours.Adapter)   #=> true

# Behaviour-specific shortcuts
Adapter.implements?(MyApp.Storage.S3)              #=> true
Service.implements?(MyApp.Worker)                  #=> true
Builder.implements?(MyApp.QueryBuilder)            #=> true
Worker.implements?(MyApp.Workers.SendEmail)        #=> true
Plugin.implements?(MyApp.Plugins.RateLimiter)      #=> true
HealthCheck.implements?(MyApp.HealthChecks.DB)     #=> true

# Safe with non-existent modules
OmBehaviours.implements?(DoesNotExist, OmBehaviours.Adapter)  #=> false
```

---

## When to Use What

| Scenario | Use |
|----------|-----|
| Swappable backends (storage, payment, email) | `Adapter` |
| Environment-specific implementations (dev/test/prod) | `Adapter` + config |
| Supervised GenServer / process | `Service` |
| Constructing complex data step-by-step | `Builder` |
| Background job / scheduled task | `Worker` |
| Library extension points / hooks | `Plugin` |
| System health monitoring | `HealthCheck` |

---

## Design Principles

| Pattern | Principle |
|---------|-----------|
| **Adapter** | Stateless. Pass config per call. Return `{:ok, _} \| {:error, _}`. |
| **Service** | Single responsibility. Explicit config via opts. Supervision-ready. |
| **Builder** | Immutable. Each operation returns new struct. Separate build from use. |
| **Worker** | Idempotent. Return result tuples. Configurable retry/timeout. |
| **Plugin** | Validate early. Stateless preferred. Composable. |
| **HealthCheck** | Fast. Non-destructive. Independent. Severity-aware. |

---

## Architecture

```
OmBehaviours ────── Behaviour introspection (implements?/2)
├── Adapter ─────── Swappable implementations
│   ├── adapter_name/0, adapter_config/1
│   ├── resolve/2, resolve!/2
│   └── implements?/1
├── Service ─────── Supervised services
│   ├── child_spec/1, start_link/1
│   └── implements?/1
├── Builder ─────── Fluent construction
│   ├── new/2, compose/2, build/1
│   ├── defcompose/2
│   └── implements?/1
├── Worker ──────── Background execution
│   ├── perform/1
│   ├── schedule/0, backoff/1, timeout/0
│   └── implements?/1
├── Plugin ──────── Extension points
│   ├── plugin_name/0, validate/1, prepare/1
│   ├── start_link/1
│   └── implements?/1
└── HealthCheck ─── Status reporting
    ├── name/0, severity/0, check/0, timeout/0
    ├── run/1, run_all/1
    └── implements?/1
```
