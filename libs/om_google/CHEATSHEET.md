# OmGoogle Cheatsheet

> Google API clients with service account auth and FCM. For full docs, see `README.md`.

## Service Account Auth

```elixir
alias OmGoogle.ServiceAccount

# Load credentials
{:ok, creds} = ServiceAccount.from_env("GOOGLE_APPLICATION_CREDENTIALS")
{:ok, creds} = ServiceAccount.from_json_file("/path/to/service-account.json")
{:ok, creds} = ServiceAccount.from_json(json_string)

# Get access token
{:ok, token} = ServiceAccount.get_access_token(creds, [
  "https://www.googleapis.com/auth/firebase.messaging"
])

# Check validity
ServiceAccount.token_valid?(token)                 #=> true

# Use token
headers = [{"authorization", "#{token.token_type} #{token.access_token}"}]
```

---

## Token Server (Production)

```elixir
# Supervision tree
children = [
  {OmGoogle.ServiceAccount.TokenServer,
    name: MyApp.GoogleTokens,
    credentials: creds,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"]}
]

# Get cached/auto-refreshed token
{:ok, token} = OmGoogle.ServiceAccount.TokenServer.get_token(MyApp.GoogleTokens)
```

---

## Firebase Cloud Messaging (FCM)

```elixir
alias OmGoogle.FCM

# Config
{:ok, config} = FCM.config_from_env()

# Send push notification
{:ok, response} = FCM.push(config,
  token: "device_token",
  title: "Hello",
  body: "World"
)

# With data payload
{:ok, response} = FCM.push(config,
  token: "device_token",
  title: "Order Shipped",
  body: "Your order is on the way",
  data: %{order_id: "123", action: "view_order"}
)

# Topic message
{:ok, response} = FCM.push(config,
  topic: "news",
  title: "Breaking News",
  body: "Something happened"
)

# Batch send
results = FCM.push_batch(config, [
  %{token: "token1", title: "Hi", body: "Hello"},
  %{token: "token2", title: "Hi", body: "Hello"}
])
```
