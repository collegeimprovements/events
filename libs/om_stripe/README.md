# OmStripe

Stripe API client with dual API support for Elixir.

## Installation

```elixir
def deps do
  [
    {:om_stripe, "~> 0.1.0"},
    {:om_api_client, "~> 0.1.0"},
    {:fn_types, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Configure
config = OmStripe.config(api_key: "sk_test_...")

# Create a customer
{:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, config)

# Create a payment intent
{:ok, intent} = OmStripe.create_payment_intent(%{
  amount: 1000,
  currency: "usd"
}, config)
```

## Features

- **Dual API** - Direct functions and chainable pipeline API
- **Result Tuples** - Consistent `{:ok, result} | {:error, StripeError}` returns
- **Idempotency** - Built-in idempotency key support
- **Connect** - Stripe Connect support for platforms
- **Error Handling** - Rich error types with recovery information

---

## Configuration

### From Options

```elixir
# Basic configuration
config = OmStripe.config(api_key: "sk_test_...")

# With specific API version
config = OmStripe.config(
  api_key: "sk_test_...",
  api_version: "2024-10-28.acacia"
)

# For Stripe Connect
config = OmStripe.config(
  api_key: "sk_test_...",
  connect_account: "acct_123456"
)

# With custom timeout and retries
config = OmStripe.config(
  api_key: "sk_test_...",
  timeout: 60_000,
  max_retries: 5
)
```

### From Environment

```elixir
# Reads STRIPE_API_KEY or STRIPE_SECRET_KEY
config = OmStripe.config_from_env()
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `STRIPE_API_KEY` | Stripe API key |
| `STRIPE_SECRET_KEY` | Alternative API key env var |
| `STRIPE_API_VERSION` | API version (optional) |
| `STRIPE_CONNECT_ACCOUNT` | Default connected account (optional) |

### Test vs Live Mode

```elixir
OmStripe.Config.test_mode?(config)
#=> true  # if api_key starts with "sk_test_"

OmStripe.Config.live_mode?(config)
#=> true  # if api_key starts with "sk_live_"
```

---

## Direct API

Simple function calls with config as the last argument.

### Customers

```elixir
# Create
{:ok, customer} = OmStripe.create_customer(%{
  email: "user@example.com",
  name: "John Doe",
  metadata: %{"user_id" => "123"}
}, config)

# Retrieve
{:ok, customer} = OmStripe.get_customer("cus_123", config)

# Update
{:ok, customer} = OmStripe.update_customer("cus_123", %{
  email: "new@example.com"
}, config)

# Delete
{:ok, deleted} = OmStripe.delete_customer("cus_123", config)

# List
{:ok, %{"data" => customers}} = OmStripe.list_customers(config, limit: 10)

# List with filters
{:ok, %{"data" => customers}} = OmStripe.list_customers(config,
  email: "user@example.com",
  created: %{"gte" => 1609459200}
)
```

### Charges

```elixir
# Create a charge
{:ok, charge} = OmStripe.create_charge(%{
  amount: 2000,
  currency: "usd",
  source: "tok_visa",
  description: "Order #123"
}, config)

# Retrieve
{:ok, charge} = OmStripe.get_charge("ch_123", config)
```

### Payment Intents

```elixir
# Create
{:ok, intent} = OmStripe.create_payment_intent(%{
  amount: 1000,
  currency: "usd",
  payment_method_types: ["card"],
  metadata: %{"order_id" => "456"}
}, config)

# Retrieve
{:ok, intent} = OmStripe.get_payment_intent("pi_123", config)

# Confirm
{:ok, intent} = OmStripe.confirm_payment_intent("pi_123", config,
  payment_method: "pm_card_visa"
)

# Cancel
{:ok, intent} = OmStripe.cancel_payment_intent("pi_123", config)
```

---

## Pipeline API

Chainable operations with config first. Useful for complex operations.

### Basic Usage

```elixir
# Create
OmStripe.new(config)
|> OmStripe.customers()
|> OmStripe.create(%{email: "user@example.com"})

# Retrieve
OmStripe.new(config)
|> OmStripe.customers("cus_123")
|> OmStripe.retrieve()

# Update
OmStripe.new(config)
|> OmStripe.customers("cus_123")
|> OmStripe.update(%{email: "new@example.com"})

# Delete
OmStripe.new(config)
|> OmStripe.customers("cus_123")
|> OmStripe.remove()

# List
OmStripe.new(config)
|> OmStripe.customers()
|> OmStripe.list(limit: 10)
```

### Available Resources

```elixir
# Customers
OmStripe.customers(req)
OmStripe.customers(req, "cus_123")

# Charges
OmStripe.charges(req)
OmStripe.charges(req, "ch_123")

# Payment Intents
OmStripe.payment_intents(req)
OmStripe.payment_intents(req, "pi_123")

# Subscriptions
OmStripe.subscriptions(req)
OmStripe.subscriptions(req, "sub_123")

# Invoices
OmStripe.invoices(req)
OmStripe.invoices(req, "in_123")
```

---

## Idempotency

Prevent duplicate operations with idempotency keys:

```elixir
# Direct API
{:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, config,
  idempotency_key: "create_user_123"
)

# Pipeline API
OmStripe.new(config)
|> OmStripe.customers()
|> OmStripe.create(%{email: "user@example.com"},
  idempotency_key: "create_user_123"
)
```

Stripe guarantees idempotent operations within 24 hours.

---

## Stripe Connect

Work with connected accounts:

```elixir
# Option 1: Configure at init
config = OmStripe.config(
  api_key: "sk_test_...",
  connect_account: "acct_123"
)

{:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, config)

# Option 2: Change account dynamically
config = OmStripe.config(api_key: "sk_test_...")
account_config = OmStripe.Config.for_account(config, "acct_456")

{:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, account_config)
```

---

## Error Handling

All operations return `{:ok, result}` or `{:error, %StripeError{}}`:

```elixir
alias FnTypes.Errors.StripeError
alias FnTypes.Protocols.{Normalizable, Recoverable}

case OmStripe.create_customer(%{email: "invalid"}, config) do
  {:ok, customer} ->
    IO.puts("Created: #{customer["id"]}")

  {:error, %StripeError{type: "card_error"} = error} ->
    # Card was declined - show user-friendly message
    IO.puts("Card error: #{error.message}")

  {:error, %StripeError{type: "invalid_request_error", param: param} = error} ->
    # Invalid parameter
    IO.puts("Invalid #{param}: #{error.message}")

  {:error, %StripeError{type: "rate_limit_error"} = error} ->
    # Rate limited - use Recoverable protocol
    if Recoverable.recoverable?(error) do
      delay = Recoverable.retry_delay(error, 1)
      Process.sleep(delay)
      # Retry...
    end

  {:error, %StripeError{type: "api_error"} = error} ->
    # Stripe API error - retry with backoff
    Logger.error("Stripe API error: #{error.message}")

  {:error, %StripeError{} = error} ->
    # Normalize to standard error format
    normalized = Normalizable.normalize(error)
    Logger.error("Stripe error: #{inspect(normalized)}")
end
```

### StripeError Fields

| Field | Description |
|-------|-------------|
| `type` | Error type (card_error, invalid_request_error, etc.) |
| `code` | Error code (card_declined, expired_card, etc.) |
| `message` | Human-readable message |
| `param` | Parameter that caused the error |
| `decline_code` | Decline reason for card errors |
| `request_id` | Stripe request ID for support |
| `doc_url` | Link to Stripe documentation |

### Error Types

| Type | Description | Retryable |
|------|-------------|-----------|
| `card_error` | Card was declined | No |
| `invalid_request_error` | Invalid parameters | No |
| `authentication_error` | Invalid API key | No |
| `rate_limit_error` | Too many requests | Yes |
| `api_error` | Stripe API problem | Yes |
| `idempotency_error` | Idempotency key conflict | No |

---

## Real-World Examples

### E-commerce Checkout

```elixir
defmodule MyApp.Checkout do
  def process_payment(user, cart, payment_method_id) do
    config = OmStripe.config_from_env()

    with {:ok, customer} <- get_or_create_customer(user, config),
         {:ok, intent} <- create_payment_intent(customer, cart, config),
         {:ok, confirmed} <- confirm_payment(intent, payment_method_id, config) do
      {:ok, confirmed}
    end
  end

  defp get_or_create_customer(user, config) do
    case user.stripe_customer_id do
      nil ->
        {:ok, customer} = OmStripe.create_customer(%{
          email: user.email,
          metadata: %{"user_id" => user.id}
        }, config)
        # Save customer.id to user...
        {:ok, customer}

      id ->
        OmStripe.get_customer(id, config)
    end
  end

  defp create_payment_intent(customer, cart, config) do
    OmStripe.create_payment_intent(%{
      amount: cart.total_cents,
      currency: "usd",
      customer: customer["id"],
      metadata: %{"cart_id" => cart.id}
    }, config, idempotency_key: "cart_#{cart.id}")
  end

  defp confirm_payment(intent, payment_method_id, config) do
    OmStripe.confirm_payment_intent(intent["id"], config,
      payment_method: payment_method_id
    )
  end
end
```

### Subscription Management

```elixir
defmodule MyApp.Subscriptions do
  def subscribe(customer_id, price_id, config) do
    OmStripe.new(config)
    |> OmStripe.subscriptions()
    |> OmStripe.create(%{
      customer: customer_id,
      items: [%{price: price_id}],
      payment_behavior: "default_incomplete",
      expand: ["latest_invoice.payment_intent"]
    })
  end

  def cancel(subscription_id, config) do
    OmStripe.new(config)
    |> OmStripe.subscriptions(subscription_id)
    |> OmStripe.remove()
  end

  def list_for_customer(customer_id, config) do
    OmStripe.new(config)
    |> OmStripe.subscriptions()
    |> OmStripe.list(customer: customer_id, status: "active")
  end
end
```

---

## Configuration Reference

```elixir
# config/config.exs
config :om_stripe,
  api_key: System.get_env("STRIPE_API_KEY"),
  api_version: "2024-10-28.acacia"

# config/runtime.exs
config :my_app, :stripe,
  api_key: System.fetch_env!("STRIPE_API_KEY")
```

## License

MIT
