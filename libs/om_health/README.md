# OmHealth

Health check system for Elixir applications with customizable checks and aggregation.

## Installation

```elixir
def deps do
  [{:om_health, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
defmodule MyApp.Health do
  use OmHealth

  config do
    app_name "my_app"
    repo MyApp.Repo
    endpoint MyAppWeb.Endpoint
    cache MyApp.Cache
  end

  services do
    service :database, type: :postgres
    service :cache, type: :redis
    service :external_api, type: :custom, check: {MyApp.Health, :check_api}
  end

  def check_api do
    case MyApp.ExternalAPI.ping() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

# Get health status
MyApp.Health.check()
# => %{
#   status: :healthy,
#   services: [
#     %{name: :database, status: :healthy, latency_ms: 2},
#     %{name: :cache, status: :healthy, latency_ms: 1}
#   ]
# }
```

## Built-in Check Types

```elixir
services do
  service :database, type: :postgres     # PostgreSQL via Ecto
  service :cache, type: :redis           # Redis
  service :queue, type: :oban            # Oban job queue
  service :http, type: :http, url: "https://api.example.com/health"
end
```

## Custom Checks

```elixir
service :payment_gateway,
  type: :custom,
  check: {MyApp.Health, :check_payments}

def check_payments do
  case Stripe.ping() do
    :ok -> :ok
    {:ok, _} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

## HTTP Endpoint

```elixir
# In your router
forward "/health", OmHealth.Plug, health_module: MyApp.Health

# GET /health
# => {"status": "healthy", "services": [...]}

# GET /health/ready
# => {"ready": true}

# GET /health/live
# => {"live": true}
```

## Environment Detection

```elixir
OmHealth.Environment.detect()
# => :kubernetes | :docker | :fly | :heroku | :local

OmHealth.Environment.kubernetes?()
# => true | false
```

## Aggregated Status

Status is computed based on all services:

- `:healthy` - All services healthy
- `:degraded` - Some services unhealthy but system operational
- `:unhealthy` - Critical services down

## Configuration

```elixir
config do
  app_name "my_app"
  repo MyApp.Repo           # For database checks
  endpoint MyAppWeb.Endpoint # For Phoenix checks
  cache MyApp.Cache         # For cache checks
end
```

## License

MIT
