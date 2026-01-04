# OmKillSwitch

Runtime service kill switches for graceful degradation in Elixir.

## Installation

```elixir
def deps do
  [{:om_kill_switch, "~> 0.1.0"}]
end
```

## Why Kill Switches?

When external services fail, your application has two choices:

```
Without Kill Switches:
┌─────────┐     ┌─────────┐     ┌─────────┐
│ Request │────▶│   App   │────▶│   S3    │ ← Timeout (30s)
└─────────┘     └─────────┘     └─────────┘
                     │                ↓
                     │           503 Error
                     │                ↓
                     └────── User waits 30s+ ──────▶ Error page

With Kill Switches:
┌─────────┐     ┌─────────┐     ┌─────────┐
│ Request │────▶│   App   │──X──│   S3    │ ← Known to be down
└─────────┘     └─────────┘     └─────────┘
                     │
                     │ (S3 disabled, use fallback)
                     ↓
               ┌───────────┐
               │ DB/Local  │ ← Immediate fallback
               └───────────┘
                     │
                     └────── User served instantly ──▶ Success
```

Kill switches let your application continue with reduced capabilities rather than failing entirely.

## Quick Start

```elixir
# 1. Add to supervision tree
children = [
  {OmKillSwitch, services: [:s3, :cache, :email, :payments]}
]

# 2. Check before calling external services
if OmKillSwitch.enabled?(:payments) do
  Stripe.charge(customer, amount)
else
  {:error, :payments_disabled}
end

# 3. Disable at runtime when issues detected
OmKillSwitch.disable(:payments, reason: "Stripe API returning 500s")

# 4. Re-enable when resolved
OmKillSwitch.enable(:payments)
```

---

## Core API

### Checking Service Status

```elixir
# Simple boolean check
OmKillSwitch.enabled?(:s3)
#=> true

# Pattern-matchable check with reason
case OmKillSwitch.check(:s3) do
  :enabled ->
    S3.upload(bucket, key, content)

  {:disabled, reason} ->
    Logger.warning("S3 disabled: #{reason}")
    {:error, :service_disabled}
end

# Detailed status
OmKillSwitch.status(:s3)
#=> %{enabled: true, reason: nil, disabled_at: nil}

OmKillSwitch.status(:s3)
#=> %{enabled: false, reason: "S3 outage detected", disabled_at: ~U[2025-01-15 10:30:00Z]}
```

### Executing with Protection

```elixir
# Execute or return error
result = OmKillSwitch.execute(:s3, fn ->
  S3.upload(bucket, key, content)
end)

case result do
  {:ok, _} -> :success
  {:error, {:service_disabled, reason}} -> handle_disabled(reason)
  {:error, other} -> handle_error(other)
end

# Execute with fallback
result = OmKillSwitch.with_service(:cache,
  fn -> Cache.get(key) end,
  fallback: fn -> Repo.get(User, id) end
)
```

### Runtime Control

```elixir
# Disable with reason
OmKillSwitch.disable(:s3, reason: "AWS us-east-1 outage")

# Enable
OmKillSwitch.enable(:s3)

# Get all statuses
OmKillSwitch.status_all()
#=> %{
#     s3: %{enabled: false, reason: "AWS outage", disabled_at: ~U[...]},
#     cache: %{enabled: true, reason: nil, disabled_at: nil},
#     email: %{enabled: true, reason: nil, disabled_at: nil}
#   }

# List registered services
OmKillSwitch.services()
#=> [:s3, :cache, :email, :payments]
```

---

## Configuration

### Application Config

```elixir
# config/config.exs
config :om_kill_switch,
  # List of services to manage
  services: [:s3, :cache, :email, :payments, :database],

  # Default enabled state per service
  s3: true,
  cache: true,
  email: true,
  payments: true,
  database: true,

  # Custom GenServer name (optional)
  name: MyApp.KillSwitch,

  # Cache module for Cache service wrapper
  cache_module: MyApp.Cache
```

### Environment Variables

Each service can be controlled via environment variables:

| Service | Environment Variable | Values |
|---------|---------------------|--------|
| `:s3` | `S3_ENABLED` | `true`, `false`, `0`, `1` |
| `:cache` | `CACHE_ENABLED` | `true`, `false`, `0`, `1` |
| `:email` | `EMAIL_ENABLED` | `true`, `false`, `0`, `1` |
| `:payments` | `PAYMENTS_ENABLED` | `true`, `false`, `0`, `1` |

```bash
# Disable S3 before deployment during AWS incident
S3_ENABLED=false mix phx.server

# Disable non-critical services for maintenance
CACHE_ENABLED=false EMAIL_ENABLED=false mix phx.server
```

### Priority Order

Configuration is read in priority order:

1. **Environment variable** (`S3_ENABLED=false`)
2. **Application config** (`config :om_kill_switch, s3: false`)
3. **Default** (`true` - enabled)

---

## Service Wrappers

### S3 Service Wrapper

Pre-built wrapper for S3 operations with automatic kill switch protection:

```elixir
alias OmKillSwitch.Services.S3

# Check status
S3.enabled?()
#=> true

S3.check()
#=> :enabled | {:disabled, "reason"}

S3.status()
#=> %{enabled: true, reason: nil, disabled_at: nil}

# Control
S3.disable(reason: "AWS outage")
S3.enable()
```

#### S3 Operations

```elixir
# List files
{:ok, result} = S3.list("my-bucket", prefix: "uploads/")
#=> {:ok, %{files: [...], next: nil}}

# With fallback when S3 is disabled
S3.list("my-bucket",
  prefix: "uploads/",
  fallback: fn -> {:ok, %{files: [], next: nil}} end
)

# Upload file
:ok = S3.upload("my-bucket", "photos/cat.jpg", jpeg_binary,
  content_type: "image/jpeg"
)

# Upload with fallback to database storage
S3.upload("my-bucket", "photos/cat.jpg", jpeg_binary,
  fallback: fn -> DbStorage.save("photos/cat.jpg", jpeg_binary) end
)

# Download file
{:ok, binary} = S3.download("my-bucket", "photos/cat.jpg")

# Download with fallback
S3.download("my-bucket", "photos/cat.jpg",
  fallback: fn -> DbStorage.fetch("photos/cat.jpg") end
)

# Delete file
:ok = S3.delete("my-bucket", "photos/old.jpg")

# Check existence
S3.exists?("my-bucket", "photos/cat.jpg")
#=> true

# Presigned URLs for direct browser upload/download
{:ok, upload_url} = S3.url_for_upload("my-bucket", "photos/new.jpg",
  expires_in: {5, :minutes}
)

{:ok, download_url} = S3.url_for_download("my-bucket", "photos/cat.jpg",
  expires_in: {1, :hour}
)
```

### Cache Service Wrapper

Pre-built wrapper for cache operations with graceful degradation:

```elixir
alias OmKillSwitch.Services.Cache

# Check status
Cache.enabled?()
Cache.check()
Cache.status()

# Control
Cache.disable(reason: "Redis memory exhausted")
Cache.enable()
```

#### Cache Operations

```elixir
# Get - returns nil if cache disabled (cache miss behavior)
user = Cache.get({User, 123})

# Put - returns :ok even if disabled (graceful no-op)
:ok = Cache.put({User, 123}, user, ttl: :timer.hours(1))

# Delete - returns :ok even if disabled
:ok = Cache.delete({User, 123})

# Get multiple
users = Cache.get_all([{User, 1}, {User, 2}, {User, 3}])

# Check key exists
Cache.has_key?({User, 123})
#=> false (when cache disabled)

# Fetch with compute - always computes when cache disabled
user = Cache.fetch({User, id}, fn ->
  Repo.get(User, id)
end, ttl: :timer.hours(1))

# Custom operation with fallback
Cache.with_cache(
  fn -> MyApp.Cache.transaction(fn -> complex_operation() end) end,
  fallback: fn -> {:ok, :skipped} end
)
```

#### Cache Behavior When Disabled

| Operation | Behavior When Disabled |
|-----------|----------------------|
| `get/2` | Returns `nil` (cache miss) |
| `put/3` | Returns `:ok` (no-op) |
| `delete/2` | Returns `:ok` (no-op) |
| `get_all/2` | Returns `[]` |
| `has_key?/2` | Returns `false` |
| `fetch/3` | Always calls compute function |

---

## Creating Custom Service Wrappers

### Basic Pattern

```elixir
defmodule MyApp.KillSwitch.Payments do
  @service :payments

  def enabled?, do: OmKillSwitch.enabled?(@service)
  def check, do: OmKillSwitch.check(@service)
  def status, do: OmKillSwitch.status(@service)
  def disable(opts \\ []), do: OmKillSwitch.disable(@service, opts)
  def enable, do: OmKillSwitch.enable(@service)

  def charge(customer, amount, opts \\ []) do
    fallback = Keyword.get(opts, :fallback)

    case {check(), fallback} do
      {:enabled, _} ->
        Stripe.Charge.create(%{
          customer: customer,
          amount: amount,
          currency: "usd"
        })

      {{:disabled, reason}, nil} ->
        {:error, {:service_disabled, reason}}

      {{:disabled, _}, fallback} when is_function(fallback, 0) ->
        fallback.()
    end
  end

  def create_customer(email, opts \\ []) do
    OmKillSwitch.execute(@service, fn ->
      Stripe.Customer.create(%{email: email})
    end)
  end
end
```

### With Circuit Breaker Integration

```elixir
defmodule MyApp.KillSwitch.API do
  @service :external_api
  @error_threshold 5
  @reset_timeout :timer.minutes(5)

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{error_count: 0, last_error_at: nil}}
  end

  def call(request) do
    case OmKillSwitch.check(@service) do
      :enabled ->
        case ExternalAPI.request(request) do
          {:ok, response} ->
            reset_errors()
            {:ok, response}

          {:error, reason} = error ->
            record_error(reason)
            error
        end

      {:disabled, reason} ->
        {:error, {:service_disabled, reason}}
    end
  end

  defp record_error(reason) do
    GenServer.cast(__MODULE__, {:error, reason})
  end

  defp reset_errors do
    GenServer.cast(__MODULE__, :reset)
  end

  def handle_cast({:error, reason}, state) do
    new_count = state.error_count + 1
    now = System.monotonic_time(:millisecond)

    if new_count >= @error_threshold do
      OmKillSwitch.disable(@service, reason: "Circuit breaker: #{reason}")
      schedule_reset()
    end

    {:noreply, %{state | error_count: new_count, last_error_at: now}}
  end

  def handle_cast(:reset, state) do
    {:noreply, %{state | error_count: 0}}
  end

  def handle_info(:reset_circuit, state) do
    OmKillSwitch.enable(@service)
    {:noreply, %{state | error_count: 0}}
  end

  defp schedule_reset do
    Process.send_after(self(), :reset_circuit, @reset_timeout)
  end
end
```

---

## Supervision Tree Setup

### Basic Setup

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {OmKillSwitch, services: [:s3, :cache, :email, :payments]},
      MyApp.Repo,
      MyApp.Cache,
      MyAppWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### With Named Instance

```elixir
children = [
  {OmKillSwitch,
    name: MyApp.KillSwitch,
    services: [:s3, :cache, :email, :payments]
  }
]

# Use with name
OmKillSwitch.enabled?(:s3)  # Uses default
GenServer.call(MyApp.KillSwitch, {:get_state, :s3})  # Uses named
```

### Multiple Environments

```elixir
# config/dev.exs
config :om_kill_switch,
  services: [:s3, :cache, :email, :payments],
  # Disable S3 in development
  s3: false

# config/prod.exs
config :om_kill_switch,
  services: [:s3, :cache, :email, :payments, :analytics],
  # All enabled in production
  s3: true,
  cache: true,
  email: true,
  payments: true,
  analytics: true
```

---

## Phoenix Integration

### Controller Pattern

```elixir
defmodule MyAppWeb.UploadController do
  use MyAppWeb, :controller

  alias OmKillSwitch.Services.S3

  def create(conn, %{"file" => upload}) do
    case S3.check() do
      :enabled ->
        handle_s3_upload(conn, upload)

      {:disabled, reason} ->
        handle_fallback_upload(conn, upload, reason)
    end
  end

  defp handle_s3_upload(conn, upload) do
    case S3.upload("my-bucket", upload.filename, File.read!(upload.path)) do
      :ok ->
        json(conn, %{url: "https://bucket.s3.amazonaws.com/#{upload.filename}"})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Upload failed"})
    end
  end

  defp handle_fallback_upload(conn, upload, reason) do
    Logger.warning("S3 disabled, using local storage: #{reason}")

    # Fall back to local storage
    local_path = Path.join("priv/static/uploads", upload.filename)
    File.cp!(upload.path, local_path)

    json(conn, %{url: "/uploads/#{upload.filename}"})
  end
end
```

### Plug for Service Status

```elixir
defmodule MyAppWeb.Plugs.ServiceStatus do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    status = OmKillSwitch.status_all()

    disabled_services =
      status
      |> Enum.filter(fn {_, %{enabled: enabled}} -> not enabled end)
      |> Enum.map(fn {service, _} -> service end)

    conn
    |> put_resp_header("x-services-disabled", Enum.join(disabled_services, ","))
    |> assign(:service_status, status)
    |> assign(:disabled_services, disabled_services)
  end
end
```

### LiveView Admin Dashboard

```elixir
defmodule MyAppWeb.Admin.KillSwitchLive do
  use MyAppWeb, :live_view

  @refresh_interval 5_000

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    {:ok, assign(socket, services: load_services())}
  end

  def render(assigns) do
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold mb-4">Service Kill Switches</h1>

      <div class="grid grid-cols-2 gap-4">
        <%= for {service, status} <- @services do %>
          <div class={"p-4 rounded-lg border #{status_class(status)}"}>
            <div class="flex justify-between items-center">
              <div>
                <h3 class="font-semibold"><%= service %></h3>
                <%= if status.reason do %>
                  <p class="text-sm text-gray-500"><%= status.reason %></p>
                <% end %>
                <%= if status.disabled_at do %>
                  <p class="text-xs text-gray-400">
                    Disabled: <%= format_time(status.disabled_at) %>
                  </p>
                <% end %>
              </div>
              <button
                phx-click="toggle"
                phx-value-service={service}
                class={"px-4 py-2 rounded #{button_class(status)}"}
              >
                <%= if status.enabled, do: "Disable", else: "Enable" %>
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("toggle", %{"service" => service}, socket) do
    service = String.to_existing_atom(service)

    if OmKillSwitch.enabled?(service) do
      OmKillSwitch.disable(service, reason: "Disabled via admin dashboard")
    else
      OmKillSwitch.enable(service)
    end

    {:noreply, assign(socket, services: load_services())}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, services: load_services())}
  end

  defp load_services do
    OmKillSwitch.status_all()
    |> Enum.sort_by(fn {service, _} -> service end)
  end

  defp status_class(%{enabled: true}), do: "border-green-300 bg-green-50"
  defp status_class(%{enabled: false}), do: "border-red-300 bg-red-50"

  defp button_class(%{enabled: true}), do: "bg-red-500 text-white hover:bg-red-600"
  defp button_class(%{enabled: false}), do: "bg-green-500 text-white hover:bg-green-600"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end
end
```

---

## Health Check Integration

### With OmHealth

```elixir
defmodule MyApp.HealthChecks.ServiceStatus do
  @behaviour OmHealth.Check

  @impl true
  def check do
    status = OmKillSwitch.status_all()

    disabled =
      status
      |> Enum.filter(fn {_, %{enabled: enabled}} -> not enabled end)
      |> Enum.into(%{})

    case map_size(disabled) do
      0 ->
        {:ok, %{all_services_enabled: true}}

      count ->
        {:degraded, %{
          disabled_count: count,
          disabled_services: disabled
        }}
    end
  end
end

# In health check config
config :om_health,
  checks: [
    {MyApp.HealthChecks.ServiceStatus, interval: 10_000}
  ]
```

### Custom Health Endpoint

```elixir
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def check(conn, _params) do
    status = OmKillSwitch.status_all()

    all_enabled = Enum.all?(status, fn {_, %{enabled: e}} -> e end)

    http_status = if all_enabled, do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(%{
      status: if(all_enabled, do: "healthy", else: "degraded"),
      services: format_services(status)
    })
  end

  defp format_services(status) do
    Enum.into(status, %{}, fn {service, s} ->
      {service, %{
        enabled: s.enabled,
        reason: s.reason,
        disabled_since: s.disabled_at && DateTime.to_iso8601(s.disabled_at)
      }}
    end)
  end
end
```

---

## Telemetry Events

### Events Emitted

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:om_kill_switch, :enabled]` | `%{count: 1}` | `%{service: atom, reason: nil}` |
| `[:om_kill_switch, :disabled]` | `%{count: 1}` | `%{service: atom, reason: string}` |

### Attaching Handlers

```elixir
defmodule MyApp.Telemetry do
  require Logger

  def attach do
    :telemetry.attach_many(
      "kill-switch-handler",
      [
        [:om_kill_switch, :enabled],
        [:om_kill_switch, :disabled]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:om_kill_switch, :disabled], _measurements, metadata, _config) do
    Logger.warning("""
    [ALERT] Service disabled!
    Service: #{metadata.service}
    Reason: #{metadata.reason}
    """)

    # Send alert
    Slack.post_message("#alerts", """
    :rotating_light: Service `#{metadata.service}` has been disabled
    Reason: #{metadata.reason}
    """)
  end

  def handle_event([:om_kill_switch, :enabled], _measurements, metadata, _config) do
    Logger.info("Service #{metadata.service} re-enabled")

    Slack.post_message("#alerts", """
    :white_check_mark: Service `#{metadata.service}` has been re-enabled
    """)
  end
end
```

### Metrics with Prometheus

```elixir
defmodule MyApp.Metrics do
  def setup do
    :telemetry.attach_many(
      "prometheus-kill-switch",
      [
        [:om_kill_switch, :enabled],
        [:om_kill_switch, :disabled]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:om_kill_switch, event], _measurements, metadata, _config) do
    :prometheus_counter.inc(
      :kill_switch_events_total,
      [metadata.service, event]
    )
  end
end
```

---

## Real-World Patterns

### AWS Outage Response

```elixir
defmodule MyApp.IncidentResponse do
  @moduledoc """
  Automated incident response for AWS outages.
  """

  def handle_aws_incident(region) when region in ["us-east-1", "us-west-2"] do
    # Immediately disable S3 in affected region
    OmKillSwitch.disable(:s3, reason: "AWS #{region} incident - #{DateTime.utc_now()}")

    # Notify ops team
    notify_ops_team(region)

    # Enable degraded mode
    Application.put_env(:my_app, :storage_mode, :local_fallback)

    {:ok, :degraded_mode_enabled}
  end

  def resolve_aws_incident(region) do
    # Verify S3 is actually working
    case verify_s3_connectivity() do
      :ok ->
        OmKillSwitch.enable(:s3)
        Application.put_env(:my_app, :storage_mode, :s3)
        {:ok, :normal_mode_restored}

      {:error, reason} ->
        {:error, {:s3_still_unavailable, reason}}
    end
  end

  defp verify_s3_connectivity do
    # Try a simple operation
    case OmS3.list("s3://my-bucket/health-check/", OmS3.from_env()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_ops_team(region) do
    PagerDuty.trigger_incident(%{
      title: "AWS #{region} incident detected",
      severity: "high",
      details: %{
        services_disabled: [:s3],
        fallback_mode: :local_storage
      }
    })
  end
end
```

### Database Connection Pool Exhaustion

```elixir
defmodule MyApp.DatabaseMonitor do
  use GenServer
  require Logger

  @check_interval :timer.seconds(30)
  @pool_threshold 0.9  # 90% utilization

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  def handle_info(:check_pool, state) do
    pool_stats = get_pool_stats()

    cond do
      pool_stats.utilization > @pool_threshold and OmKillSwitch.enabled?(:database) ->
        Logger.warning("Database pool at #{pool_stats.utilization * 100}%, disabling non-critical queries")
        OmKillSwitch.disable(:database, reason: "Pool exhaustion protection")

      pool_stats.utilization < @pool_threshold * 0.7 and not OmKillSwitch.enabled?(:database) ->
        Logger.info("Database pool recovered, re-enabling")
        OmKillSwitch.enable(:database)

      true ->
        :ok
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_pool, @check_interval)
  end

  defp get_pool_stats do
    # Get DBConnection pool stats
    # This is a simplified example
    %{utilization: 0.5, busy: 5, idle: 5}
  end
end
```

### Payment Processing Degradation

```elixir
defmodule MyApp.PaymentProcessor do
  alias OmKillSwitch

  @primary_provider :stripe
  @fallback_provider :braintree

  def charge(customer, amount, opts \\ []) do
    case {provider_status(@primary_provider), provider_status(@fallback_provider)} do
      {:enabled, _} ->
        charge_with_provider(@primary_provider, customer, amount, opts)

      {:disabled, :enabled} ->
        Logger.warning("Primary payment provider disabled, using fallback")
        charge_with_provider(@fallback_provider, customer, amount, opts)

      {:disabled, :disabled} ->
        {:error, :all_payment_providers_disabled}
    end
  end

  defp provider_status(provider) do
    service = :"payments_#{provider}"

    case OmKillSwitch.check(service) do
      :enabled -> :enabled
      {:disabled, _} -> :disabled
    end
  end

  defp charge_with_provider(:stripe, customer, amount, opts) do
    Stripe.Charge.create(%{
      customer: customer,
      amount: amount,
      currency: Keyword.get(opts, :currency, "usd")
    })
  end

  defp charge_with_provider(:braintree, customer, amount, opts) do
    Braintree.Transaction.sale(%{
      customer_id: customer,
      amount: Money.to_decimal(amount),
      options: %{submit_for_settlement: true}
    })
  end
end
```

### Gradual Rollout with Kill Switch

```elixir
defmodule MyApp.FeatureFlags do
  @moduledoc """
  Combine kill switches with percentage rollouts.
  """

  def enabled?(feature, user) do
    # First check kill switch
    case OmKillSwitch.check(feature) do
      {:disabled, _reason} ->
        false

      :enabled ->
        # Then check rollout percentage
        in_rollout?(feature, user)
    end
  end

  defp in_rollout?(feature, user) do
    # Get rollout percentage from config
    percentage = get_rollout_percentage(feature)

    # Deterministic bucketing based on user ID
    bucket = :erlang.phash2({feature, user.id}, 100)
    bucket < percentage
  end

  defp get_rollout_percentage(feature) do
    Application.get_env(:my_app, :feature_rollouts, %{})
    |> Map.get(feature, 0)
  end

  # Instant kill for a feature
  def kill_feature(feature, reason) do
    OmKillSwitch.disable(feature, reason: reason)
  end

  # Gradual rollout
  def set_rollout(feature, percentage) when percentage >= 0 and percentage <= 100 do
    rollouts = Application.get_env(:my_app, :feature_rollouts, %{})
    Application.put_env(:my_app, :feature_rollouts, Map.put(rollouts, feature, percentage))
  end
end
```

---

## Best Practices

### 1. Always Provide Fallbacks for Critical Paths

```elixir
# Good: Graceful degradation
def get_user_avatar(user_id) do
  OmKillSwitch.with_service(:s3,
    fn -> S3.download("avatars", "#{user_id}.jpg") end,
    fallback: fn -> {:ok, default_avatar_binary()} end
  )
end

# Bad: Hard failure
def get_user_avatar(user_id) do
  OmKillSwitch.execute(:s3, fn ->
    S3.download("avatars", "#{user_id}.jpg")
  end)
  # Returns {:error, {:service_disabled, _}} with no fallback
end
```

### 2. Log State Changes

```elixir
# Attach telemetry handlers at application start
def start(_type, _args) do
  MyApp.Telemetry.attach()
  # ...
end

# Log all state changes
def handle_event([:om_kill_switch, event], _, %{service: service, reason: reason}, _) do
  Logger.warning("[KillSwitch] #{service} #{event}: #{reason || "no reason"}")
end
```

### 3. Use Specific Reasons

```elixir
# Good: Specific, actionable reason
OmKillSwitch.disable(:s3, reason: "AWS us-east-1 outage - ticket #12345")
OmKillSwitch.disable(:email, reason: "SendGrid rate limit exceeded")
OmKillSwitch.disable(:payments, reason: "Stripe webhook verification failing")

# Bad: Vague reason
OmKillSwitch.disable(:s3, reason: "Not working")
OmKillSwitch.disable(:email)  # No reason at all
```

### 4. Monitor Disabled Duration

```elixir
defmodule MyApp.KillSwitchMonitor do
  use GenServer

  @alert_threshold :timer.minutes(30)
  @check_interval :timer.minutes(5)

  def handle_info(:check_duration, state) do
    OmKillSwitch.status_all()
    |> Enum.filter(fn {_, %{enabled: e}} -> not e end)
    |> Enum.each(fn {service, %{disabled_at: disabled_at}} ->
      duration = DateTime.diff(DateTime.utc_now(), disabled_at, :millisecond)

      if duration > @alert_threshold do
        alert_long_disable(service, duration)
      end
    end)

    schedule_check()
    {:noreply, state}
  end

  defp alert_long_disable(service, duration_ms) do
    minutes = div(duration_ms, 60_000)

    Slack.post_message("#ops", """
    :warning: Service `#{service}` has been disabled for #{minutes} minutes.
    Please verify if this is intentional.
    """)
  end
end
```

### 5. Test Fallback Paths

```elixir
defmodule MyApp.UploadTest do
  use ExUnit.Case

  describe "upload with S3 disabled" do
    setup do
      OmKillSwitch.disable(:s3, reason: "Test")
      on_exit(fn -> OmKillSwitch.enable(:s3) end)
    end

    test "falls back to local storage" do
      result = MyApp.Uploads.store(content, filename)

      assert {:ok, path} = result
      assert String.starts_with?(path, "/uploads/")
      assert File.exists?(Path.join("priv/static", path))
    end
  end
end
```

---

## Configuration Reference

```elixir
config :om_kill_switch,
  # Required: List of services to manage
  services: [:s3, :cache, :email, :payments, :database, :analytics],

  # Per-service default state (optional, default: true)
  s3: true,
  cache: true,
  email: true,
  payments: true,
  database: true,
  analytics: false,  # Disabled by default

  # GenServer name (optional, default: OmKillSwitch)
  name: MyApp.KillSwitch,

  # Cache module for Cache service wrapper (optional)
  cache_module: MyApp.Cache
```

## Environment Variables

| Variable | Service | Values |
|----------|---------|--------|
| `S3_ENABLED` | `:s3` | `true`, `false`, `0`, `1` |
| `CACHE_ENABLED` | `:cache` | `true`, `false`, `0`, `1` |
| `EMAIL_ENABLED` | `:email` | `true`, `false`, `0`, `1` |
| `PAYMENTS_ENABLED` | `:payments` | `true`, `false`, `0`, `1` |
| `DATABASE_ENABLED` | `:database` | `true`, `false`, `0`, `1` |
| `{SERVICE}_ENABLED` | `:service` | `true`, `false`, `0`, `1` |

## License

MIT
