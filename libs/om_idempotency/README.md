# OmIdempotency

Idempotency key generation and validation for safe API retries.

## Installation

```elixir
def deps do
  [{:om_idempotency, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias OmIdempotency

# Generate a key
key = OmIdempotency.generate()
# => "idem_01HXYZ..."

# Generate from components
key = OmIdempotency.generate(user_id: 123, action: :create_order)
# => "idem_7a8b9c..."

# Validate format
OmIdempotency.valid?(key)
# => true
```

## Key Generation

```elixir
# Random key
OmIdempotency.generate()

# Deterministic from components (same inputs = same key)
OmIdempotency.generate(
  user_id: user.id,
  action: :transfer,
  amount: 1000
)

# With custom prefix
OmIdempotency.generate(prefix: "pay")
# => "pay_01HXYZ..."
```

## Validation

```elixir
OmIdempotency.valid?("idem_01HXYZ...")  # => true
OmIdempotency.valid?("invalid")          # => false
```

## Usage in APIs

```elixir
def create_payment(conn, params) do
  idempotency_key = get_req_header(conn, "idempotency-key") |> List.first()

  case OmIdempotency.check(idempotency_key) do
    {:ok, :new} ->
      result = Payments.create(params)
      OmIdempotency.store(idempotency_key, result)
      json(conn, result)

    {:ok, {:cached, result}} ->
      json(conn, result)

    {:error, :invalid_key} ->
      conn |> put_status(400) |> json(%{error: "Invalid idempotency key"})
  end
end
```

## License

MIT
