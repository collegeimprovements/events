# OmHealth Cheatsheet

> Health check system with DSL-based configuration. For full docs, see `README.md`.

## Define Health Module

```elixir
defmodule MyApp.Health do
  use OmHealth

  config do
    app_name :my_app
    repo MyApp.Repo
    endpoint MyAppWeb.Endpoint
  end

  services do
    service :database, module: MyApp.Repo, type: :repo, critical: true
    service :cache, module: MyApp.Cache, type: :cache, critical: false
    service :pubsub, module: MyApp.PubSub, type: :pubsub
    service :payments, type: :custom, check: {MyApp.Health, :check_stripe}, critical: true
  end

  def check_stripe do
    case Stripe.ping() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

---

## Usage

```elixir
# Full health report
health = MyApp.Health.check_all()
#=> %{status: :healthy, services: %{database: :ok, cache: :ok, ...}}

# Display (colored console output)
MyApp.Health.display()

# Overall status
MyApp.Health.overall_status()                      #=> :healthy | :degraded | :unhealthy

# Status aggregation
# :healthy   - all services OK
# :degraded  - non-critical service down
# :unhealthy - critical service down
```

---

## Service Types

| Type | Checks |
|------|--------|
| `:repo` | `Ecto.Adapters.SQL.query(repo, "SELECT 1")` |
| `:cache` | Cache connectivity |
| `:pubsub` | PubSub process alive |
| `:endpoint` | Endpoint process alive |
| `:telemetry` | Telemetry handler alive |
| `:custom` | Your function |

---

## Custom Check

```elixir
service :external_api, type: :custom,
  check: fn ->
    case MyApp.ExternalAPI.ping() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end,
  critical: true
```
