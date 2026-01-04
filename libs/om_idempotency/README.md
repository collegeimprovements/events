# OmIdempotency

Database-backed idempotency key management for safe API retries in Elixir.

## Installation

```elixir
def deps do
  [{:om_idempotency, "~> 0.1.0"}]
end
```

## Why Idempotency?

When building APIs that interact with external services (payments, emails, webhooks), network failures can leave you uncertain whether an operation completed. Without idempotency:

```
Client → Server → Stripe: "Charge $100"
         ← Network timeout (did it work?)
Client → Server → Stripe: "Charge $100" (retry)
         → Customer charged $200!
```

With idempotency:

```
Client → Server: "Charge $100" (key: order_123)
         ← Network timeout
Client → Server: "Charge $100" (key: order_123, retry)
         ← Returns cached result, no duplicate charge
```

## Quick Start

```elixir
# 1. Run migration
mix ecto.gen.migration add_idempotency_records

# 2. Use the migration helper
defmodule MyApp.Repo.Migrations.AddIdempotencyRecords do
  use Ecto.Migration

  def change do
    OmIdempotency.Migration.create_table()
  end
end

# 3. Configure
config :om_idempotency, repo: MyApp.Repo

# 4. Use it
key = OmIdempotency.generate_key(:charge_order, order_id: 123)

OmIdempotency.execute(key, fn ->
  Stripe.create_charge(%{amount: 1000, customer: "cus_123"})
end)
```

---

## Key Generation

### Random Keys (UUIDv7)

```elixir
# Generate a random unique key
key = OmIdempotency.generate_key()
#=> "01913a77-7e30-7f4a-8c1e-b5f3c8d9e0f1"
```

### Deterministic Keys (Recommended)

Create keys from operation + parameters. Same inputs = same key = same result.

```elixir
# From operation name
key = OmIdempotency.generate_key(:send_welcome_email)
#=> "send_welcome_email"

# From operation + parameters
key = OmIdempotency.generate_key(:charge_order, order_id: 456, amount: 1000)
#=> "charge_order:amount=1000:order_id=456"

# With scope (for multi-tenant or service isolation)
key = OmIdempotency.generate_key(:create_customer, user_id: 123, scope: "stripe")
#=> "stripe:create_customer:user_id=123"
```

### Hashed Keys (For Complex Data)

When parameters are complex or contain sensitive data:

```elixir
key = OmIdempotency.hash_key(:process_webhook, %{
  event_id: "evt_123",
  payload: large_payload,
  signature: "sig_abc"
})
#=> "process_webhook:a1b2c3d4e5f6g7h8..."

# With scope
key = OmIdempotency.hash_key(:sync_user, user_data, scope: "external_api")
#=> "external_api:sync_user:9f8e7d6c5b4a..."
```

---

## Executing with Idempotency

### Basic Execution

```elixir
key = OmIdempotency.generate_key(:create_charge, order_id: order.id)

result = OmIdempotency.execute(key, fn ->
  case Stripe.create_charge(%{amount: order.total, customer: customer_id}) do
    {:ok, charge} -> {:ok, charge}
    {:error, reason} -> {:error, reason}
  end
end)

case result do
  {:ok, charge} -> process_successful_charge(charge)
  {:error, reason} -> handle_error(reason)
end
```

### With Options

```elixir
OmIdempotency.execute(key, fn ->
  external_api_call()
end,
  # Scope for isolation
  scope: "stripe",

  # Time-to-live (default: 24 hours)
  ttl: :timer.hours(48),

  # Metadata stored with the record
  metadata: %{user_id: user.id, ip: conn.remote_ip},

  # Handle in-progress duplicates
  on_duplicate: :wait,  # :return | :wait | :error

  # Wait timeout when on_duplicate: :wait
  wait_timeout: 5_000
)
```

### Duplicate Handling Strategies

| Strategy | Behavior | Use When |
|----------|----------|----------|
| `:return` | Return `{:error, {:in_progress, record}}` | Default, handle manually |
| `:wait` | Wait up to `wait_timeout` for completion | Concurrent requests expected |
| `:error` | Return `{:error, :in_progress}` immediately | Fail fast |

```elixir
# Strategy: :return (default)
case OmIdempotency.execute(key, fn -> api_call() end) do
  {:ok, result} -> handle_success(result)
  {:error, {:in_progress, _record}} -> {:accepted, "Processing"}
  {:error, reason} -> handle_error(reason)
end

# Strategy: :wait
result = OmIdempotency.execute(key, fn -> api_call() end,
  on_duplicate: :wait,
  wait_timeout: 10_000
)
# Blocks until original completes or timeout

# Strategy: :error
result = OmIdempotency.execute(key, fn -> api_call() end,
  on_duplicate: :error
)
# Immediately returns {:error, :in_progress}
```

---

## Manual Control

For more control over the idempotency lifecycle:

### Check Existing Records

```elixir
case OmIdempotency.get(key) do
  {:ok, %{state: :completed, response: response}} ->
    # Already done, use cached response
    {:ok, response}

  {:ok, %{state: :processing}} ->
    # Someone else is working on it
    {:error, :in_progress}

  {:ok, %{state: :failed, error: error}} ->
    # Previous attempt failed
    {:error, error}

  {:error, :not_found} ->
    # Safe to execute
    execute_operation()
end
```

### Manual State Management

```elixir
# Create a pending record
{:ok, record} = OmIdempotency.create(key,
  scope: "payments",
  metadata: %{order_id: 123}
)

# Start processing (with optimistic locking)
case OmIdempotency.start_processing(record) do
  {:ok, processing_record} ->
    # Execute the operation
    case do_api_call() do
      {:ok, response} ->
        OmIdempotency.complete(processing_record, response)
        {:ok, response}

      {:error, error} ->
        if permanent_error?(error) do
          OmIdempotency.fail(processing_record, error)
        else
          OmIdempotency.release(processing_record)  # Allow retry
        end
        {:error, error}
    end

  {:error, :already_processing} ->
    {:error, :in_progress}

  {:error, :stale} ->
    # Record was modified, refetch and retry
    handle_stale_record(key)
end
```

---

## Record States

```
┌─────────┐
│ pending │ ← Initial state after create()
└────┬────┘
     │ start_processing()
     ▼
┌────────────┐
│ processing │ ← Locked, operation in progress
└─────┬──────┘
      │
      ├─── complete() ──→ ┌───────────┐
      │                   │ completed │ ← Success, response cached
      │                   └───────────┘
      │
      ├─── fail() ──────→ ┌────────┐
      │                   │ failed │ ← Permanent failure recorded
      │                   └────────┘
      │
      └─── release() ───→ ┌─────────┐
                          │ pending │ ← Retryable, lock released
                          └─────────┘

                    After TTL expires:
                          ┌─────────┐
                          │ expired │ ← Cleaned up by maintenance
                          └─────────┘
```

---

## API Integration

### Phoenix Controller

```elixir
defmodule MyAppWeb.PaymentController do
  use MyAppWeb, :controller

  def create(conn, %{"order_id" => order_id} = params) do
    # Get idempotency key from header
    idempotency_key = get_idempotency_key(conn, order_id)

    case OmIdempotency.execute(idempotency_key, fn ->
      Payments.process(order_id, params)
    end, scope: "payments", on_duplicate: :wait) do
      {:ok, payment} ->
        conn
        |> put_status(:created)
        |> json(%{payment: payment})

      {:error, :in_progress} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "processing"})

      {:error, :wait_timeout} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Request still processing"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  defp get_idempotency_key(conn, order_id) do
    case get_req_header(conn, "idempotency-key") do
      [key] -> "payments:#{key}"
      [] -> OmIdempotency.generate_key(:create_payment, order_id: order_id)
    end
  end
end
```

### Plug for Automatic Handling

```elixir
defmodule MyAppWeb.Plugs.Idempotency do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    scope = Keyword.get(opts, :scope, "api")

    case get_req_header(conn, "idempotency-key") do
      [key] ->
        full_key = "#{scope}:#{key}"

        case OmIdempotency.get(full_key, scope) do
          {:ok, %{state: :completed, response: response}} ->
            conn
            |> put_resp_header("x-idempotent-replayed", "true")
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))
            |> halt()

          {:ok, %{state: :processing}} ->
            conn
            |> put_status(:conflict)
            |> put_resp_content_type("application/json")
            |> send_resp(409, Jason.encode!(%{error: "Request in progress"}))
            |> halt()

          _ ->
            assign(conn, :idempotency_key, full_key)
        end

      [] ->
        conn
    end
  end
end
```

### Webhook Processing

```elixir
defmodule MyApp.Webhooks.StripeHandler do
  def handle_event(%{"id" => event_id, "type" => type} = event) do
    key = OmIdempotency.hash_key(:stripe_webhook, %{event_id: event_id})

    OmIdempotency.execute(key, fn ->
      case type do
        "payment_intent.succeeded" -> handle_payment_success(event)
        "payment_intent.failed" -> handle_payment_failure(event)
        "customer.subscription.created" -> handle_subscription_created(event)
        _ -> {:ok, :ignored}
      end
    end, scope: "webhooks", ttl: :timer.hours(72))
  end
end
```

---

## Background Job Integration

### With Oban

```elixir
defmodule MyApp.Workers.SendEmailWorker do
  use Oban.Worker, queue: :emails

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "template" => template}}) do
    key = OmIdempotency.generate_key(:send_email,
      user_id: user_id,
      template: template
    )

    OmIdempotency.execute(key, fn ->
      case Mailer.send(user_id, template) do
        {:ok, _} -> {:ok, :sent}
        {:error, reason} -> {:error, reason}
      end
    end, scope: "emails")
  end
end
```

### Retry-Safe Operations

```elixir
defmodule MyApp.Services.OrderFulfillment do
  def fulfill(order) do
    key = OmIdempotency.generate_key(:fulfill_order, order_id: order.id)

    OmIdempotency.execute(key, fn ->
      with {:ok, _} <- reserve_inventory(order),
           {:ok, _} <- charge_payment(order),
           {:ok, shipment} <- create_shipment(order),
           {:ok, _} <- send_confirmation(order) do
        {:ok, shipment}
      end
    end, scope: "fulfillment", metadata: %{
      customer_id: order.customer_id,
      total: order.total
    })
  end
end
```

---

## Maintenance

### Cleanup Expired Records

```elixir
# Manual cleanup
{:ok, count} = OmIdempotency.cleanup_expired()
#=> {:ok, 150}

# Schedule with Oban
defmodule MyApp.Workers.IdempotencyCleanup do
  use Oban.Worker, queue: :maintenance

  @impl Oban.Worker
  def perform(_job) do
    {:ok, deleted} = OmIdempotency.cleanup_expired()
    {:ok, recovered} = OmIdempotency.recover_stale()

    Logger.info("Idempotency cleanup: #{deleted} expired, #{recovered} stale")
    :ok
  end
end

# Oban cron config
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 * * * *", MyApp.Workers.IdempotencyCleanup}  # Hourly
    ]}
  ]
```

### Recover Stale Processing Records

```elixir
# Records stuck in :processing longer than lock_timeout
{:ok, count} = OmIdempotency.recover_stale()
#=> {:ok, 3}
```

---

## Configuration Reference

```elixir
config :om_idempotency,
  # Required: Ecto repo
  repo: MyApp.Repo,

  # Time-to-live for records (default: 24 hours)
  ttl: {24, :hours},

  # Lock timeout for processing state (default: 30 seconds)
  lock_timeout: {30, :seconds},

  # Telemetry event prefix
  telemetry_prefix: [:my_app, :idempotency]
```

---

## Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:om_idempotency, :start]` | `%{count: 1}` | `%{key, scope}` |
| `[:om_idempotency, :stop]` | `%{duration: native_time}` | `%{key, scope}` |
| `[:om_idempotency, :cache_hit]` | `%{count: 1}` | `%{key, scope}` |
| `[:om_idempotency, :completed]` | `%{count: 1}` | `%{key, scope}` |
| `[:om_idempotency, :failed]` | `%{count: 1}` | `%{key, scope}` |
| `[:om_idempotency, :released]` | `%{count: 1}` | `%{key, scope}` |
| `[:om_idempotency, :error]` | `%{count: 1}` | `%{key, scope}` |

```elixir
# Attach handlers
:telemetry.attach_many(
  "idempotency-logger",
  [
    [:om_idempotency, :cache_hit],
    [:om_idempotency, :completed]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)
```

---

## Best Practices

### 1. Use Deterministic Keys

```elixir
# Good: Same operation always gets same key
key = OmIdempotency.generate_key(:charge, order_id: order.id)

# Bad: Random key defeats the purpose
key = OmIdempotency.generate_key()  # Different each time!
```

### 2. Include All Relevant Parameters

```elixir
# Good: Key captures the operation's identity
key = OmIdempotency.generate_key(:transfer,
  from_account: from.id,
  to_account: to.id,
  amount: amount,
  currency: currency
)

# Bad: Missing parameters could cause conflicts
key = OmIdempotency.generate_key(:transfer, amount: amount)
```

### 3. Use Scopes for Isolation

```elixir
# Different services, different scopes
OmIdempotency.execute(key, fn -> stripe_call() end, scope: "stripe")
OmIdempotency.execute(key, fn -> sendgrid_call() end, scope: "sendgrid")
```

### 4. Handle All States

```elixir
case OmIdempotency.execute(key, operation) do
  {:ok, result} -> handle_success(result)
  {:error, {:in_progress, _}} -> {:accepted, "Processing"}
  {:error, :wait_timeout} -> {:error, "Still processing"}
  {:error, reason} -> handle_error(reason)
end
```

### 5. Set Appropriate TTLs

```elixir
# Short-lived operations
OmIdempotency.execute(key, fn -> api_call() end, ttl: :timer.hours(1))

# Long-running or critical operations
OmIdempotency.execute(key, fn -> payment() end, ttl: :timer.hours(72))
```

## License

MIT
