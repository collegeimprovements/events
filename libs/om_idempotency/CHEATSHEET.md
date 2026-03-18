# OmIdempotency Cheatsheet

> Database-backed idempotency key management for safe API retries. For full docs, see `README.md`.

## Setup

```elixir
config :om_idempotency, repo: MyApp.Repo

# Run migration
defmodule MyApp.Repo.Migrations.AddIdempotencyRecords do
  use Ecto.Migration
  def change, do: OmIdempotency.Migration.create_table()
end
```

---

## Core API

```elixir
# Generate key
key = OmIdempotency.generate_key(:charge_order, order_id: 123, amount: 1000)
#=> "charge_order:amount=1000:order_id=123"

# Execute idempotently (returns cached result on retry)
{:ok, result} = OmIdempotency.execute(key, fn ->
  Stripe.create_charge(%{amount: 1000, customer: "cus_123"})
end)
```

---

## Key Generation

```elixir
# Random (UUIDv7)
key = OmIdempotency.generate_key()

# Deterministic (same inputs = same key)
key = OmIdempotency.generate_key(:send_email)
key = OmIdempotency.generate_key(:charge_order, order_id: 456, amount: 1000)

# With scope (multi-tenant)
key = OmIdempotency.generate_key(:create_customer, user_id: 123, scope: "stripe")

# Hashed (complex/sensitive data)
key = OmIdempotency.hash_key(:process_webhook, %{event_id: "evt_123", payload: large})
```

---

## Options

```elixir
OmIdempotency.execute(key, fn -> work() end,
  ttl: :timer.hours(24),             # key expiration
  on_duplicate: :return,              # :return | :wait | :error
  repo: MyApp.Repo                   # override repo
)
```
