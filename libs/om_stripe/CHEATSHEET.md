# OmStripe Cheatsheet

> Stripe API client with dual API support. For full docs, see `README.md`.

## Setup

```elixir
config = OmStripe.config(api_key: "sk_test_...")
config = OmStripe.config_from_env()               # reads STRIPE_API_KEY

# With options
config = OmStripe.config(
  api_key: "sk_test_...",
  api_version: "2024-10-28.acacia",
  connect_account: "acct_123456",                  # Stripe Connect
  timeout: 60_000,
  max_retries: 5
)

OmStripe.Config.test_mode?(config)                 #=> true
```

---

## Direct API

```elixir
# Customers
{:ok, customer} = OmStripe.create_customer(%{email: "user@example.com"}, config)
{:ok, customer} = OmStripe.get_customer("cus_123", config)
{:ok, customer} = OmStripe.update_customer("cus_123", %{name: "New"}, config)
{:ok, _} = OmStripe.delete_customer("cus_123", config)
{:ok, customers} = OmStripe.list_customers(%{limit: 10}, config)

# Payment Intents
{:ok, intent} = OmStripe.create_payment_intent(%{amount: 1000, currency: "usd"}, config)
{:ok, intent} = OmStripe.confirm_payment_intent("pi_123", config)
{:ok, intent} = OmStripe.cancel_payment_intent("pi_123", config)

# Charges
{:ok, charge} = OmStripe.create_charge(%{amount: 1000, currency: "usd", source: "tok_123"}, config)
```

---

## Idempotency

```elixir
{:ok, intent} = OmStripe.create_payment_intent(
  %{amount: 1000, currency: "usd"},
  config,
  idempotency_key: "order_123"
)
```

---

## Error Handling

```elixir
case OmStripe.create_charge(params, config) do
  {:ok, charge} -> {:ok, charge}
  {:error, %FnTypes.Errors.StripeError{type: "card_error", code: "card_declined"}} -> {:error, :declined}
  {:error, %FnTypes.Errors.StripeError{type: "rate_limit_error"}} -> retry_later()
  {:error, %FnTypes.Errors.StripeError{type: "api_error"}} -> {:error, :stripe_down}
  {:error, error} -> {:error, error}
end
```

| Error Type | Meaning |
|------------|---------|
| `"card_error"` | Card declined/invalid |
| `"invalid_request_error"` | Bad parameters |
| `"authentication_error"` | Bad API key |
| `"rate_limit_error"` | Too many requests |
| `"api_error"` | Stripe internal error |
| `"api_connection_error"` | Network failure |

---

## Webhook Verification

```elixir
{:ok, event} = OmStripe.Webhook.construct_event(
  payload,
  signature_header,
  webhook_secret
)
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `STRIPE_API_KEY` | API key |
| `STRIPE_SECRET_KEY` | Alternative key env var |
| `STRIPE_API_VERSION` | API version |
| `STRIPE_CONNECT_ACCOUNT` | Default connected account |
