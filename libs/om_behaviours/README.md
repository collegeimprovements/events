# OmBehaviours

Common behaviour patterns for Elixir applications: Adapter, Service, Builder, Worker, Plugin, and HealthCheck.

- **Zero dependencies**
- **129 tests** covering all modules, callbacks, edge cases, and supervision integration
- **Validated adapter resolution** with `resolve!/2` for fail-fast production use
- **Default `child_spec/1`** via `use OmBehaviours.Service` (overridable)
- **Behaviour introspection** that's safe with non-existent modules and non-atom inputs

## Installation

```elixir
def deps do
  [{:om_behaviours, "~> 0.1.0"}]
end
```

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:om_behaviours, "~> 0.1.0"}
```

**That's it.** No configuration, no environment variables, zero dependencies. Just use the behaviour modules directly.

**Optional — Supervision** (only if using `Service` or `Worker` patterns with stateful processes):

```elixir
# application.ex
children = [MyApp.MyService]
```

## Quick Start

| Behaviour | Purpose | Use Case |
|-----------|---------|----------|
| `Adapter` | Swappable implementations | Storage backends, API clients, payment processors |
| `Service` | Supervised services | Connection pools, background workers, stateful services |
| `Builder` | Fluent construction | Query builders, validation pipelines, multi-step configs |
| `Worker` | Background execution | Scheduled jobs, async tasks, retryable operations |
| `Plugin` | Extension points | Middleware, hooks, library extensibility |
| `HealthCheck` | Status reporting | Database probes, API pings, system diagnostics |

## Adapter Pattern

Adapters enable swappable backend implementations. Define a service behaviour, then implement it with different adapters (S3, local file, mock, etc.).

### Defining a Storage Service

```elixir
defmodule MyApp.Storage do
  @callback upload(key :: String.t(), data :: binary()) :: {:ok, url :: String.t()} | {:error, term()}
  @callback download(key :: String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
end
```

### S3 Adapter (Production)

```elixir
defmodule MyApp.Storage.S3 do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :s3

  @impl OmBehaviours.Adapter
  def adapter_config(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      region: Keyword.get(opts, :region, "us-east-1"),
      acl: Keyword.get(opts, :acl, :private)
    }
  end

  @impl MyApp.Storage
  def upload(key, data) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    case ExAws.S3.put_object(config.bucket, key, data) |> ExAws.request() do
      {:ok, _} -> {:ok, "https://#{config.bucket}.s3.amazonaws.com/#{key}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MyApp.Storage
  def download(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    ExAws.S3.get_object(config.bucket, key) |> ExAws.request()
  end

  @impl MyApp.Storage
  def delete(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    case ExAws.S3.delete_object(config.bucket, key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Local Adapter (Development)

```elixir
defmodule MyApp.Storage.Local do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :local

  @impl OmBehaviours.Adapter
  def adapter_config(opts) do
    %{root_path: Keyword.get(opts, :root_path, "priv/uploads")}
  end

  @impl MyApp.Storage
  def upload(key, data) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    path = Path.join(config.root_path, key)
    File.mkdir_p!(Path.dirname(path))

    case File.write(path, data) do
      :ok -> {:ok, "file://#{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl MyApp.Storage
  def download(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    File.read(Path.join(config.root_path, key))
  end

  @impl MyApp.Storage
  def delete(key) do
    config = adapter_config(Application.get_env(:my_app, :storage, []))
    case File.rm(Path.join(config.root_path, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Mock Adapter (Testing)

```elixir
defmodule MyApp.Storage.Mock do
  @behaviour MyApp.Storage
  @behaviour OmBehaviours.Adapter

  @impl OmBehaviours.Adapter
  def adapter_name, do: :mock

  @impl OmBehaviours.Adapter
  def adapter_config(_opts), do: %{}

  @impl MyApp.Storage
  def upload(key, _data), do: {:ok, "mock://#{key}"}

  @impl MyApp.Storage
  def download(_key), do: {:ok, "mock data"}

  @impl MyApp.Storage
  def delete(_key), do: :ok
end
```

### Dynamic Adapter Resolution

```elixir
# Lightweight resolution (no validation, pure string manipulation)
OmBehaviours.Adapter.resolve(:s3, MyApp.Storage)
#=> MyApp.Storage.S3

OmBehaviours.Adapter.resolve(:google_cloud, MyApp.Storage)
#=> MyApp.Storage.GoogleCloud

# Validated resolution (ensures module exists and implements Adapter)
OmBehaviours.Adapter.resolve!(:s3, MyApp.Storage)
#=> MyApp.Storage.S3

OmBehaviours.Adapter.resolve!(:nonexistent, MyApp.Storage)
#=> ** (ArgumentError) adapter module MyApp.Storage.Nonexistent is not available

OmBehaviours.Adapter.resolve!(:string, Elixir)
#=> ** (ArgumentError) Elixir.String does not implement OmBehaviours.Adapter behaviour
```

### `resolve/2` vs `resolve!/2`

| | `resolve/2` | `resolve!/2` |
|--|-------------|--------------|
| Validates module exists | No | Yes |
| Validates behaviour | No | Yes |
| On failure | Returns atom anyway | Raises `ArgumentError` |
| Use when | You'll validate later | You need guaranteed correctness |

### Configuration-Based Selection

```elixir
# config/dev.exs
config :my_app, storage_adapter: :local

# config/prod.exs
config :my_app, storage_adapter: :s3

# Runtime resolution
defmodule MyApp.Storage do
  def adapter do
    :my_app
    |> Application.get_env(:storage_adapter, :local)
    |> OmBehaviours.Adapter.resolve!(__MODULE__)
  end

  def upload(key, data), do: adapter().upload(key, data)
end
```

## Service Pattern

Services represent supervised business capabilities with clear boundaries.

### Using `use` (Recommended)

`use OmBehaviours.Service` provides a default `child_spec/1` so you only need to implement `start_link/1`:

```elixir
defmodule MyApp.Worker do
  use OmBehaviours.Service
  use GenServer

  @impl OmBehaviours.Service
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    {:ok, %{adapter: opts[:adapter] || :email}}
  end
end

# Default child_spec/1 produces:
# %{id: MyApp.Worker, start: {MyApp.Worker, :start_link, [opts]}, restart: :permanent, type: :worker}
```

### Custom child_spec (Override the Default)

```elixir
defmodule MyApp.Pool do
  use OmBehaviours.Service

  @impl true
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 10_000,
      type: :supervisor
    }
  end

  @impl true
  def start_link(opts) do
    children = [{DBConnection, pool_opts(opts)}]
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  defp pool_opts(opts) do
    [
      pool_size: Keyword.get(opts, :pool_size, 10),
      pool_timeout: Keyword.get(opts, :pool_timeout, 5000)
    ]
  end
end
```

### Adding to Supervision Tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.Worker, []},
      {MyApp.Pool, pool_size: 20}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Builder Pattern

Builders provide fluent APIs for constructing complex data structures.

### Query Builder Example

```elixir
defmodule MyApp.QueryBuilder do
  use OmBehaviours.Builder

  defstruct [:schema, :filters, :sorts, :limit, :offset]

  @impl true
  def new(schema, opts \\ []) do
    %__MODULE__{schema: schema, filters: [], sorts: [], limit: opts[:limit]}
  end

  @impl true
  def compose(builder, {:filter, field, value}) do
    %{builder | filters: [{field, value} | builder.filters]}
  end

  def compose(builder, {:sort, field, dir}) do
    %{builder | sorts: [{field, dir} | builder.sorts]}
  end

  @impl true
  def build(builder) do
    {builder.schema, builder.filters, builder.sorts, builder.limit}
  end

  defcompose where(builder, field, value) do
    compose(builder, {:filter, field, value})
  end

  defcompose order_by(builder, field, dir \\ :asc) do
    compose(builder, {:sort, field, dir})
  end
end

# Usage
MyApp.QueryBuilder.new(User)
|> MyApp.QueryBuilder.where(:status, :active)
|> MyApp.QueryBuilder.order_by(:name, :asc)
|> MyApp.QueryBuilder.build()
```

## Worker Pattern

Workers define units of background work with optional scheduling, retry backoff, and timeouts.

### Simple Worker

```elixir
defmodule MyApp.Workers.SendEmail do
  use OmBehaviours.Worker

  @impl true
  def perform(%{to: to, subject: subject, body: body}) do
    case Mailer.deliver(to, subject, body) do
      {:ok, _} -> {:ok, :sent}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Scheduled Worker with Custom Backoff

```elixir
defmodule MyApp.Workers.DailyCleanup do
  use OmBehaviours.Worker

  @impl true
  def perform(_args) do
    deleted = Repo.delete_all(expired_query())
    {:ok, %{deleted: deleted}}
  end

  @impl true
  def schedule, do: "0 3 * * *"

  @impl true
  def backoff(attempt), do: min(1000 * :math.pow(2, attempt) |> trunc(), 60_000)

  @impl true
  def timeout, do: :timer.minutes(10)
end
```

### Default Behaviour

| Callback | Default | Override? |
|----------|---------|-----------|
| `perform/1` | — (required) | — |
| `schedule/0` | `nil` (manual only) | Yes |
| `backoff/1` | Exponential, capped at 30s | Yes |
| `timeout/0` | 60 seconds | Yes |

## Plugin Pattern

Plugins provide a lifecycle for extending libraries and applications: validate → prepare → start.

### Stateless Plugin

```elixir
defmodule MyApp.Plugins.RateLimiter do
  use OmBehaviours.Plugin

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
    {:ok, %{
      max_requests: Keyword.fetch!(opts, :max_requests),
      window_ms: Keyword.get(opts, :window_ms, 60_000)
    }}
  end
end
```

### Stateful Plugin (with Supervised Process)

```elixir
defmodule MyApp.Plugins.MetricsCollector do
  use OmBehaviours.Plugin

  @impl true
  def plugin_name, do: :metrics_collector

  @impl true
  def validate(_opts), do: :ok

  @impl true
  def prepare(opts) do
    {:ok, %{interval: Keyword.get(opts, :interval, 5_000)}}
  end

  @impl true
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end
end
```

### Plugin Lifecycle

```elixir
# Boot-time plugin initialization
def init_plugin(module, opts) do
  with :ok <- module.validate(opts),
       {:ok, state} <- module.prepare(opts) do
    module.start_link(state)
  end
end
```

### Default Behaviour

| Callback | Default | Override? |
|----------|---------|-----------|
| `plugin_name/0` | — (required) | — |
| `validate/1` | — (required) | — |
| `prepare/1` | — (required) | — |
| `start_link/1` | `:ignore` | Yes |

## HealthCheck Pattern

Health checks report operational status of system components with severity levels and timeout enforcement.

### Database Health Check

```elixir
defmodule MyApp.HealthChecks.Database do
  use OmBehaviours.HealthCheck

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

### Cache Health Check (with Custom Timeout)

```elixir
defmodule MyApp.HealthChecks.Cache do
  use OmBehaviours.HealthCheck

  @impl true
  def name, do: :cache

  @impl true
  def severity, do: :warning

  @impl true
  def check do
    key = "__health_check__"
    Cache.put(key, "ok", ttl: 1_000)

    case Cache.get(key) do
      "ok" -> {:ok, %{status: :connected}}
      _ -> {:error, :cache_unreachable}
    end
  end

  @impl true
  def timeout, do: 3_000
end
```

### Running Health Checks

```elixir
# Single check
{:ok, result} = OmBehaviours.HealthCheck.run(MyApp.HealthChecks.Database)
result.status     #=> :healthy | :unhealthy | :timeout
result.severity   #=> :critical | :warning | :info
result.duration_ms #=> 2

# Multiple checks concurrently
checks = [MyApp.HealthChecks.Database, MyApp.HealthChecks.Cache]
results = OmBehaviours.HealthCheck.run_all(checks)
Enum.all?(results, & &1.status == :healthy)
```

### Severity Levels

| Level | Meaning | Example |
|-------|---------|---------|
| `:critical` | System cannot function | Database, core service |
| `:warning` | Degraded but functional | Cache, non-essential API |
| `:info` | Informational | Disk usage, queue depth |

### Default Behaviour

| Callback | Default | Override? |
|----------|---------|-----------|
| `name/0` | — (required) | — |
| `severity/0` | — (required) | — |
| `check/0` | — (required) | — |
| `timeout/0` | 5 seconds | Yes |

## Behaviour Introspection

```elixir
# Check if a module implements a specific behaviour
OmBehaviours.implements?(MyApp.Storage.S3, OmBehaviours.Adapter)
#=> true

# Behaviour-specific helpers
OmBehaviours.Adapter.implements?(MyApp.Storage.S3)          #=> true
OmBehaviours.Service.implements?(MyApp.NotificationService)  #=> true
OmBehaviours.Builder.implements?(MyApp.QueryBuilder)         #=> true
OmBehaviours.Worker.implements?(MyApp.Workers.SendEmail)     #=> true
OmBehaviours.Plugin.implements?(MyApp.Plugins.RateLimiter)   #=> true
OmBehaviours.HealthCheck.implements?(MyApp.HealthChecks.DB)  #=> true

# Safe with non-existent modules (returns false, never raises)
OmBehaviours.implements?(DoesNotExist.Module, OmBehaviours.Adapter)
#=> false
```

## API Reference

### OmBehaviours

| Function | Spec | Description |
|----------|------|-------------|
| `implements?/2` | `(module(), module()) :: boolean()` | Check if module implements behaviour |

### OmBehaviours.Adapter

| Callback | Spec | Description |
|----------|------|-------------|
| `adapter_name/0` | `() :: atom()` | Unique adapter identifier |
| `adapter_config/1` | `(keyword()) :: map()` | Validate opts, return config map |

| Function | Spec | Description |
|----------|------|-------------|
| `resolve/2` | `(atom(), module()) :: module()` | Name to module (no validation) |
| `resolve!/2` | `(atom(), module()) :: module()` | Name to module (validated, raises) |
| `implements?/1` | `(module()) :: boolean()` | Check Adapter behaviour |

### OmBehaviours.Service

| Callback | Spec | Required with `use`? |
|----------|------|---------------------|
| `child_spec/1` | `(keyword()) :: Supervisor.child_spec()` | No (default provided) |
| `start_link/1` | `(keyword()) :: {:ok, pid()} \| {:error, term()}` | Yes |

### OmBehaviours.Builder

| Callback | Spec | Description |
|----------|------|-------------|
| `new/2` | `(term(), keyword()) :: struct()` | Create builder with initial data |
| `compose/2` | `(struct(), term()) :: struct()` | Apply operation, return new builder |
| `build/1` | `(struct()) :: term()` | Convert state to final result |

| Macro | Description |
|-------|-------------|
| `defcompose/2` | Sugar for defining chainable builder methods |

### OmBehaviours.Worker

| Callback | Spec | Required with `use`? |
|----------|------|---------------------|
| `perform/1` | `(term()) :: {:ok, term()} \| {:error, term()}` | Yes |
| `schedule/0` | `() :: String.t() \| nil` | No (default: `nil`) |
| `backoff/1` | `(non_neg_integer()) :: non_neg_integer()` | No (default: exponential) |
| `timeout/0` | `() :: non_neg_integer()` | No (default: 60s) |

### OmBehaviours.Plugin

| Callback | Spec | Required with `use`? |
|----------|------|---------------------|
| `plugin_name/0` | `() :: atom()` | Yes |
| `validate/1` | `(keyword()) :: :ok \| {:error, term()}` | Yes |
| `prepare/1` | `(keyword()) :: {:ok, term()} \| {:error, term()}` | Yes |
| `start_link/1` | `(term()) :: {:ok, pid()} \| {:error, term()} \| :ignore` | No (default: `:ignore`) |

### OmBehaviours.HealthCheck

| Callback | Spec | Required with `use`? |
|----------|------|---------------------|
| `name/0` | `() :: atom()` | Yes |
| `severity/0` | `() :: :critical \| :warning \| :info` | Yes |
| `check/0` | `() :: {:ok, map()} \| {:error, term()}` | Yes |
| `timeout/0` | `() :: non_neg_integer()` | No (default: 5s) |

| Function | Spec | Description |
|----------|------|-------------|
| `run/1` | `(module()) :: {:ok, map()}` | Run check with timeout enforcement |
| `run_all/1` | `([module()]) :: [map()]` | Run multiple checks concurrently |

## Design Principles

| Pattern | Principle |
|---------|-----------|
| **Adapter** | Stateless. Pass config per call. Return `{:ok, _} \| {:error, _}`. |
| **Service** | Single responsibility. Explicit config via opts. Supervision-ready. |
| **Builder** | Immutable. Each operation returns new struct. Separate build from use. |
| **Worker** | Idempotent. Return result tuples. Configurable retry/timeout. |
| **Plugin** | Validate early. Stateless preferred. Composable. |
| **HealthCheck** | Fast. Non-destructive. Independent. Severity-aware. |

## License

MIT
