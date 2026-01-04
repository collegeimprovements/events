# OmHealth

Comprehensive health check system for Elixir applications with customizable checks, environment detection, and beautiful console output.

## Installation

```elixir
def deps do
  [{:om_health, "~> 0.1.0"}]
end
```

## Why OmHealth?

Production applications need visibility into their dependencies:

```
Manual Health Checks                   OmHealth
─────────────────────────────────────────────────────────────────────
def health do                          defmodule MyApp.Health do
  db_ok = check_db()                     use OmHealth
  cache_ok = check_cache()
  queue_ok = check_queue()               config do
  # ... more manual checks                 app_name :my_app
                                           repo MyApp.Repo
  cond do                                  endpoint MyAppWeb.Endpoint
    not db_ok -> :unhealthy              end
    not cache_ok -> :degraded
    true -> :healthy                     services do
  end                                      service :database, type: :repo, critical: true
end                                        service :cache, type: :cache
                                           service :queue, type: :oban
                                         end
                                       end

                                       # Automatic status aggregation
                                       MyApp.Health.check_all()
                                       MyApp.Health.display()
```

**Benefits:**
- **DSL-Based Configuration** - Clean, declarative service definitions
- **Automatic Aggregation** - healthy/degraded/unhealthy based on criticality
- **Environment Detection** - Mix env, Docker, node info
- **Beautiful Display** - Colored tabular console output
- **Extensible** - Custom check functions for any service

---

## Quick Start

### Define Health Module

```elixir
defmodule MyApp.Health do
  use OmHealth

  config do
    app_name :my_app
    repo MyApp.Repo
    endpoint MyAppWeb.Endpoint
    cache MyApp.Cache
  end

  services do
    service :database,
      module: MyApp.Repo,
      type: :repo,
      critical: true

    service :cache,
      module: MyApp.Cache,
      type: :cache,
      critical: false

    service :pubsub,
      module: MyApp.PubSub,
      type: :pubsub,
      critical: false

    service :payments,
      type: :custom,
      check: {MyApp.Health, :check_stripe},
      critical: true
  end

  def check_stripe do
    case Stripe.ping() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Use the Health Module

```elixir
# Get full health report
health = MyApp.Health.check_all()
#=> %{
#     services: [...],
#     environment: %{...},
#     proxy: %{...},
#     timestamp: ~U[2025-01-15 10:00:00Z],
#     duration_ms: 15
#   }

# Get overall status
MyApp.Health.overall_status()
#=> :healthy | :degraded | :unhealthy

# Display formatted output
MyApp.Health.display()
```

---

## Service Types

### Repository (`:repo`)

Checks Ecto repository connection:

```elixir
service :database,
  module: MyApp.Repo,
  type: :repo,
  critical: true
```

Performs `SELECT 1` query to verify connection.

### Cache (`:cache`)

Checks cache read/write operations:

```elixir
service :cache,
  module: MyApp.Cache,
  type: :cache,
  critical: false
```

Performs put/get/delete cycle with test key.

### PubSub (`:pubsub`)

Checks Phoenix PubSub process:

```elixir
service :pubsub,
  module: MyApp.PubSub,
  type: :pubsub,
  critical: false
```

Verifies process is running.

### Endpoint (`:endpoint`)

Checks Phoenix Endpoint process:

```elixir
service :web,
  module: MyAppWeb.Endpoint,
  type: :endpoint,
  critical: true
```

Reports adapter and port information.

### Telemetry (`:telemetry`)

Checks telemetry process:

```elixir
service :metrics,
  module: MyApp.Telemetry,
  type: :telemetry,
  critical: false
```

### Custom (`:custom`)

For any custom health check:

```elixir
service :stripe,
  type: :custom,
  check: {MyApp.Health, :check_stripe},
  critical: true

service :elasticsearch,
  type: :custom,
  check: &MyApp.Search.healthy?/0,
  critical: false
```

---

## Custom Check Functions

### MFA Tuple

```elixir
service :payments,
  type: :custom,
  check: {MyApp.Health, :check_payments},
  critical: true

# In the same module or another module:
def check_payments do
  case Stripe.charges_list(limit: 1) do
    {:ok, _} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

### Function Capture

```elixir
service :search,
  type: :custom,
  check: &MyApp.Search.healthy?/0,
  critical: false
```

### Return Values

Custom checks should return:

| Return | Meaning |
|--------|---------|
| `:ok` | Service healthy |
| `{:ok, info}` | Healthy with info string |
| `{:error, reason}` | Service unhealthy |

```elixir
def check_elasticsearch do
  case Elasticsearch.cluster_health() do
    {:ok, %{"status" => "green"}} ->
      {:ok, "Cluster green"}

    {:ok, %{"status" => "yellow"}} ->
      {:ok, "Cluster yellow - replicas missing"}

    {:ok, %{"status" => "red"}} ->
      {:error, "Cluster red - data unavailable"}

    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## Criticality

Services are marked as critical or optional:

```elixir
service :database, type: :repo, critical: true   # Required for app to work
service :cache, type: :cache, critical: false    # App works without it
```

### Status Aggregation

| Scenario | Overall Status |
|----------|----------------|
| All services healthy | `:healthy` |
| Optional services down | `:degraded` |
| Critical services down | `:unhealthy` |

```elixir
case MyApp.Health.overall_status() do
  :healthy -> # All systems go
  :degraded -> # App running with reduced functionality
  :unhealthy -> # App cannot function properly
end
```

---

## Health Check Result

```elixir
MyApp.Health.check_all()
#=> %{
#     services: [
#       %{
#         name: "Database",
#         status: :ok,
#         adapter: "Ecto.Postgres",
#         critical: true,
#         info: "Connected & ready",
#         impact: nil
#       },
#       %{
#         name: "Cache",
#         status: :error,
#         adapter: "Nebulex.Redis",
#         critical: false,
#         info: "Connection refused",
#         impact: "Cache unavailable"
#       }
#     ],
#     environment: %{
#       mix_env: :prod,
#       elixir_version: "1.15.0",
#       otp_release: "26",
#       node_name: :myapp@prod-1,
#       hostname: "prod-1.myapp.com",
#       in_docker: true,
#       live_reload: :not_applicable,
#       watchers: []
#     },
#     proxy: %{
#       configured: true,
#       http_proxy: "http://proxy.internal:8080",
#       https_proxy: "http://proxy.internal:8080",
#       no_proxy: "localhost,127.0.0.1,.internal",
#       services_using_proxy: ["Req", "AWS S3"]
#     },
#     timestamp: ~U[2025-01-15 10:30:00Z],
#     duration_ms: 23
#   }
```

---

## Console Display

```elixir
MyApp.Health.display()
```

Output:

```
=============================================================================================
                                    SYSTEM HEALTH STATUS
=============================================================================================

ENVIRONMENT

  Mix Environment : prod
  Elixir / OTP    : 1.15.0 / 26
  Node            : myapp@prod-1
  Hostname        : prod-1.myapp.com
  Container       : Docker

---------------------------------------------------------------------------------------------

SERVICES

SERVICE      | STATUS     | ADAPTER            | LEVEL    | INFO
-------------+------------+--------------------+----------+--------------------------------
Database     | Running    | Ecto.Postgres      | Critical | Connected & ready
Cache        | Failed     | Nebulex.Redis      | Degraded | Cache unavailable
Queue        | Running    | Oban               | Optional | Operational
Payments     | Running    | Custom             | Critical | Healthy
=============================================================================================

DEGRADED: 1 optional service(s) unavailable
  Application running with reduced functionality
  * Cache: Cache unavailable

Checked at 2025-01-15 10:30:00 UTC (23ms)
```

### Display Options

```elixir
# Disable colors
MyApp.Health.display(color: false)

# Custom title
MyApp.Health.display(title: "MY APP HEALTH")
```

---

## Environment Detection

### Get Environment Info

```elixir
OmHealth.Environment.get_info()
#=> %{
#     mix_env: :dev,
#     elixir_version: "1.15.0",
#     otp_release: "26",
#     node_name: :nonode@nohost,
#     hostname: "developer-macbook",
#     in_docker: false,
#     live_reload: :enabled,
#     watchers: [:esbuild, :tailwind]
#   }
```

### Docker Detection

```elixir
OmHealth.Environment.in_docker?()
#=> true | false
```

Detects Docker via:
- `/.dockerenv` file presence
- `/run/.containerenv` file presence
- `DOCKER_CONTAINER` environment variable

### Safe Helpers

```elixir
# Safe Mix.env() that doesn't crash in release
OmHealth.Environment.safe_mix_env()
#=> :prod | :dev | :test | :unknown

# Safe hostname lookup
OmHealth.Environment.safe_hostname()
#=> "myhost.local"
```

---

## Proxy Detection

### Get Proxy Config

```elixir
OmHealth.Proxy.get_config()
#=> %{
#     configured: true,
#     http_proxy: "http://proxy.example.com:8080",
#     https_proxy: "http://proxy.example.com:8080",
#     no_proxy: "localhost,127.0.0.1",
#     services_using_proxy: ["Req", "AWS S3"]
#   }
```

### Check if Proxy Configured

```elixir
OmHealth.Proxy.configured?()
#=> true | false
```

### Environment Variables

Reads from (case-insensitive):
- `HTTP_PROXY` / `http_proxy`
- `HTTPS_PROXY` / `https_proxy`
- `NO_PROXY` / `no_proxy`

---

## HTTP Endpoint

### Phoenix Router Integration

```elixir
# In your router.ex
forward "/health", OmHealth.Plug, health_module: MyApp.Health
```

### Endpoints

```
GET /health       # Full health status
GET /health/ready # Readiness probe
GET /health/live  # Liveness probe
```

### Response Format

```json
// GET /health
{
  "status": "healthy",
  "services": [
    {
      "name": "Database",
      "status": "ok",
      "critical": true
    },
    {
      "name": "Cache",
      "status": "ok",
      "critical": false
    }
  ],
  "environment": {
    "mix_env": "prod",
    "hostname": "prod-1"
  }
}

// GET /health/ready
{"ready": true}

// GET /health/live
{"live": true}
```

### Custom Plug Implementation

```elixir
defmodule MyAppWeb.HealthPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["health"]} = conn, opts) do
    health_module = Keyword.fetch!(opts, :health_module)
    health = health_module.check_all()
    status = health_module.overall_status()

    http_status =
      case status do
        :healthy -> 200
        :degraded -> 200
        :unhealthy -> 503
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(http_status, Jason.encode!(format_health(health, status)))
    |> halt()
  end

  def call(%Plug.Conn{path_info: ["health", "ready"]} = conn, opts) do
    health_module = Keyword.fetch!(opts, :health_module)
    status = health_module.overall_status()
    ready = status != :unhealthy

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(if(ready, do: 200, else: 503), Jason.encode!(%{ready: ready}))
    |> halt()
  end

  def call(%Plug.Conn{path_info: ["health", "live"]} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{live: true}))
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp format_health(health, status) do
    %{
      status: status,
      services: Enum.map(health.services, &format_service/1),
      environment: %{
        mix_env: health.environment.mix_env,
        hostname: health.environment.hostname
      },
      timestamp: DateTime.to_iso8601(health.timestamp)
    }
  end

  defp format_service(service) do
    %{
      name: service.name,
      status: service.status,
      critical: service.critical
    }
  end
end
```

---

## Kubernetes Integration

### Deployment Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          livenessProbe:
            httpGet:
              path: /health/live
              port: 4000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 5
```

### Critical vs Optional Mapping

| Probe | OmHealth Behavior |
|-------|-------------------|
| Liveness | Always returns 200 (app is running) |
| Readiness | Returns 503 if critical services down |

---

## Real-World Examples

### Full-Stack Application

```elixir
defmodule MyApp.Health do
  use OmHealth

  config do
    app_name :my_app
    repo MyApp.Repo
    endpoint MyAppWeb.Endpoint
    cache MyApp.Cache
  end

  services do
    # Core infrastructure (critical)
    service :database,
      module: MyApp.Repo,
      type: :repo,
      critical: true

    service :web,
      module: MyAppWeb.Endpoint,
      type: :endpoint,
      critical: true

    # Optional infrastructure
    service :cache,
      module: MyApp.Cache,
      type: :cache,
      critical: false

    service :pubsub,
      module: MyApp.PubSub,
      type: :pubsub,
      critical: false

    service :background_jobs,
      type: :custom,
      check: {__MODULE__, :check_oban},
      critical: false

    # External services
    service :stripe,
      type: :custom,
      check: {__MODULE__, :check_stripe},
      critical: true

    service :sendgrid,
      type: :custom,
      check: {__MODULE__, :check_sendgrid},
      critical: false

    service :s3,
      type: :custom,
      check: {__MODULE__, :check_s3},
      critical: false
  end

  def check_oban do
    case Oban.check_queue(:default) do
      %{paused: false} -> :ok
      _ -> {:error, "Queue paused"}
    end
  rescue
    _ -> {:error, "Oban not running"}
  end

  def check_stripe do
    case Stripe.Balance.retrieve() do
      {:ok, _} -> :ok
      {:error, %{message: msg}} -> {:error, msg}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def check_sendgrid do
    # Simple API key validation
    case SendGrid.api_key_valid?() do
      true -> :ok
      false -> {:error, "Invalid API key"}
    end
  end

  def check_s3 do
    case ExAws.S3.list_buckets() |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
```

### Microservice with External Dependencies

```elixir
defmodule OrderService.Health do
  use OmHealth

  config do
    app_name :order_service
    repo OrderService.Repo
  end

  services do
    service :database,
      module: OrderService.Repo,
      type: :repo,
      critical: true

    service :user_service,
      type: :custom,
      check: {__MODULE__, :check_user_service},
      critical: true

    service :inventory_service,
      type: :custom,
      check: {__MODULE__, :check_inventory_service},
      critical: true

    service :notification_service,
      type: :custom,
      check: {__MODULE__, :check_notification_service},
      critical: false
  end

  def check_user_service do
    url = Application.get_env(:order_service, :user_service_url)
    check_http_service("#{url}/health")
  end

  def check_inventory_service do
    url = Application.get_env(:order_service, :inventory_service_url)
    check_http_service("#{url}/health")
  end

  def check_notification_service do
    url = Application.get_env(:order_service, :notification_service_url)
    check_http_service("#{url}/health")
  end

  defp check_http_service(url) do
    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
```

### IEx Helper

```elixir
# In lib/my_app/iex_helpers.ex
defmodule MyApp.IExHelpers do
  def health do
    MyApp.Health.display()
  end

  def health_json do
    MyApp.Health.check_all()
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end
end

# In .iex.exs
import MyApp.IExHelpers

# Now in IEx:
iex> health
# Displays formatted health status
```

---

## Best Practices

### 1. Mark Database as Critical

```elixir
service :database, type: :repo, critical: true
```

Without the database, most apps can't function.

### 2. Mark External APIs Based on Impact

```elixir
# Payment processing - critical for checkout
service :stripe, type: :custom, check: ..., critical: true

# Email sending - can queue for later
service :sendgrid, type: :custom, check: ..., critical: false
```

### 3. Use Timeouts in Custom Checks

```elixir
def check_external_api do
  case Req.get(url, receive_timeout: 5_000) do
    {:ok, %{status: 200}} -> :ok
    _ -> {:error, "Unavailable"}
  end
rescue
  _ -> {:error, "Timeout"}
end
```

### 4. Handle Check Errors Gracefully

```elixir
def check_service do
  # Always rescue to prevent health check from crashing
  case Service.ping() do
    :ok -> :ok
    {:error, reason} -> {:error, reason}
  end
rescue
  e -> {:error, Exception.message(e)}
end
```

### 5. Provide Useful Impact Messages

The display shows impact for failed services:

```elixir
# In custom checks, include context in error
def check_search do
  case Elasticsearch.ping() do
    :ok -> :ok
    {:error, _} -> {:error, "Search functionality unavailable"}
  end
end
```

---

## Configuration

```elixir
# config/config.exs
config :om_health,
  # Default timeout for health checks
  timeout: 5_000,

  # Services that use proxy (for display)
  proxy_services: ["Req", "AWS S3", "ExAws"]
```

---

## Module Reference

| Module | Purpose |
|--------|---------|
| `OmHealth` | Main module with DSL and check functions |
| `OmHealth.Environment` | Environment detection (Mix env, Docker, versions) |
| `OmHealth.Proxy` | Proxy configuration detection |
| `OmHealth.Display` | Formatted console output |

## License

MIT
