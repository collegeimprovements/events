# OmGoogle

Google API clients with service account authentication for Elixir.

## Installation

```elixir
def deps do
  [
    {:om_google, "~> 0.1.0"},
    {:jose, "~> 1.11"},  # For JWT signing
    {:req, "~> 0.4"}     # HTTP client
  ]
end
```

## Features

- **Service Account Authentication** - JWT-based OAuth2 token generation
- **Token Caching** - GenServer for automatic token refresh
- **Firebase Cloud Messaging** - FCM HTTP v1 API client
- **Result Tuples** - Consistent `{:ok, value} | {:error, reason}` returns

## Quick Start

```elixir
# Load service account credentials
{:ok, creds} = OmGoogle.credentials_from_env()

# Send a push notification
{:ok, config} = OmGoogle.FCM.config_from_env()
{:ok, _response} = OmGoogle.FCM.push(config,
  token: "device_fcm_token",
  title: "Hello",
  body: "World"
)
```

---

## Service Account Authentication

### Loading Credentials

```elixir
alias OmGoogle.ServiceAccount

# From environment variable (recommended)
# Can be a file path OR JSON content
{:ok, creds} = ServiceAccount.from_env("GOOGLE_APPLICATION_CREDENTIALS")

# From JSON file
{:ok, creds} = ServiceAccount.from_json_file("/path/to/service-account.json")

# From JSON string
json = ~s({"project_id": "my-project", "private_key": "...", ...})
{:ok, creds} = ServiceAccount.from_json(json)

# From a map (decoded JSON)
{:ok, creds} = ServiceAccount.from_map(%{
  "project_id" => "my-project",
  "private_key" => "-----BEGIN PRIVATE KEY-----\n...",
  "client_email" => "service@project.iam.gserviceaccount.com"
})
```

### Getting Access Tokens

```elixir
# Request a token for specific scopes
{:ok, token} = ServiceAccount.get_access_token(creds, [
  "https://www.googleapis.com/auth/firebase.messaging"
])

# Token structure
%{
  access_token: "ya29.c.b0Aaek...",
  expires_at: ~U[2024-01-15 12:00:00Z],
  token_type: "Bearer"
}

# Check if token is still valid (with safety buffer)
ServiceAccount.token_valid?(token)
#=> true

# Use the token in requests
headers = [{"authorization", "#{token.token_type} #{token.access_token}"}]
```

### Token Server (Production)

For production use, use the TokenServer for automatic token caching and refresh:

```elixir
# Add to your supervision tree
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    {:ok, creds} = OmGoogle.ServiceAccount.from_env()

    children = [
      {OmGoogle.ServiceAccount.TokenServer,
        credentials: creds,
        scopes: OmGoogle.FCM.scopes(),
        name: :google_token_server}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# Get tokens from the server (automatically refreshed)
{:ok, token} = OmGoogle.ServiceAccount.TokenServer.get_token(:google_token_server)

# Force a refresh
{:ok, token} = OmGoogle.ServiceAccount.TokenServer.refresh_token(:google_token_server)
```

### Service Account JSON Format

Your service account JSON file (from Google Cloud Console) should contain:

```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "service-account@your-project.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

---

## Firebase Cloud Messaging (FCM)

### Setup

1. Create a Firebase project at https://console.firebase.google.com
2. Go to Project Settings > Service Accounts
3. Generate a new private key (downloads JSON file)
4. Set `GOOGLE_APPLICATION_CREDENTIALS` environment variable

### Configuration

```elixir
alias OmGoogle.FCM

# From environment variable
{:ok, config} = FCM.config_from_env()

# Or with explicit credentials
{:ok, creds} = OmGoogle.credentials_from_env()
config = FCM.config(credentials: creds)

# With custom project ID
config = FCM.config(
  credentials: creds,
  project_id: "my-firebase-project"
)
```

### Sending Notifications

#### Simple Notification

```elixir
{:ok, response} = FCM.push(config,
  token: "device_registration_token",
  title: "New Message",
  body: "You have a new message from John"
)

# Response includes the message name
%{"name" => "projects/my-project/messages/0:1234567890..."}
```

#### Data-Only Message (Silent Push)

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  data: %{
    "type" => "sync",
    "resource_id" => "123",
    "action" => "update"
  }
)
```

#### Notification with Data

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  title: "Order Update",
  body: "Your order #123 has shipped!",
  data: %{
    "order_id" => "123",
    "screen" => "order_details"
  }
)
```

#### With Image

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  title: "New Photo",
  body: "Someone shared a photo with you",
  image: "https://example.com/photo.jpg"
)
```

### Topic Messaging

#### Send to Topic

```elixir
# Send to all devices subscribed to "news" topic
{:ok, _} = FCM.push_to_topic(config, "news",
  title: "Breaking News",
  body: "Something important happened!"
)
```

#### Topic Conditions

```elixir
# Send to devices subscribed to BOTH news AND local
{:ok, _} = FCM.push_to_condition(config,
  "'news' in topics && 'local' in topics",
  title: "Local News",
  body: "News in your area"
)

# Send to devices subscribed to news OR weather
{:ok, _} = FCM.push_to_condition(config,
  "'news' in topics || 'weather' in topics",
  title: "Update Available",
  body: "Check out what's new"
)
```

### Platform-Specific Options

#### Android Configuration

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  title: "Urgent Alert",
  body: "This is important!",
  android: %{
    priority: :high,                    # :normal or :high
    ttl: "86400s",                     # Time to live (string with unit)
    collapse_key: "alerts",            # Group notifications
    restricted_package_name: "com.myapp",
    notification: %{
      "click_action" => "OPEN_ACTIVITY",
      "color" => "#FF0000",
      "sound" => "alert.wav",
      "channel_id" => "urgent"
    }
  }
)
```

#### iOS/APNs Configuration

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  title: "New Message",
  body: "You have a new message",
  apns: %{
    headers: %{
      "apns-priority" => "10",          # 10 = immediate, 5 = power-saving
      "apns-push-type" => "alert",
      "apns-expiration" => "0"          # Expire immediately if not delivered
    },
    payload: %{
      "aps" => %{
        "sound" => "default",
        "badge" => 1,
        "mutable-content" => 1,
        "category" => "MESSAGE"
      }
    }
  }
)
```

#### Web Push Configuration

```elixir
{:ok, _} = FCM.push(config,
  token: "device_token",
  title: "Web Notification",
  body: "Hello from the web!",
  webpush: %{
    headers: %{
      "TTL" => "86400",
      "Urgency" => "high"
    },
    notification: %{
      "icon" => "https://example.com/icon.png",
      "badge" => "https://example.com/badge.png",
      "actions" => [
        %{"action" => "view", "title" => "View"},
        %{"action" => "dismiss", "title" => "Dismiss"}
      ]
    }
  }
)
```

### Batch Sending

Send multiple messages concurrently:

```elixir
messages = [
  [token: "token1", title: "Hello", body: "User 1"],
  [token: "token2", title: "Hello", body: "User 2"],
  [token: "token3", title: "Hello", body: "User 3"]
]

results = FCM.push_batch(config, messages, concurrency: 10)

# Results are in the same order as messages
Enum.zip(messages, results)
|> Enum.each(fn {msg, result} ->
  case result do
    {:ok, response} -> IO.puts("Sent to #{msg[:token]}: #{response["name"]}")
    {:error, reason} -> IO.puts("Failed #{msg[:token]}: #{inspect(reason)}")
  end
end)
```

### Using with TokenServer (Recommended)

For production, use TokenServer to avoid token refresh latency:

```elixir
# In application.ex
{:ok, creds} = OmGoogle.credentials_from_env()

children = [
  {OmGoogle.ServiceAccount.TokenServer,
    credentials: creds,
    scopes: OmGoogle.FCM.scopes(),
    name: :fcm_token_server}
]

# In your code
def send_notification(user, message) do
  FCM.push_with_server(:fcm_token_server, project_id(),
    token: user.fcm_token,
    title: message.title,
    body: message.body
  )
end

defp project_id do
  Application.get_env(:my_app, :firebase_project_id)
end
```

### Error Handling

```elixir
case FCM.push(config, token: "invalid_token", title: "Test", body: "Test") do
  {:ok, response} ->
    Logger.info("Message sent: #{response["name"]}")

  {:error, {:invalid_token, _}} ->
    # Device token is no longer valid - remove from database
    Logger.warn("Invalid token, removing from database")

  {:error, {:unauthorized, _}} ->
    # Service account credentials are invalid
    Logger.error("Invalid credentials")

  {:error, {:forbidden, _}} ->
    # Service account doesn't have FCM permissions
    Logger.error("Permission denied")

  {:error, %{code: "UNREGISTERED", message: msg}} ->
    # Device unregistered from FCM
    Logger.warn("Device unregistered: #{msg}")

  {:error, %{code: "QUOTA_EXCEEDED", message: msg}} ->
    # Rate limited
    Logger.warn("Rate limited: #{msg}")

  {:error, {:server_error, status, body}} ->
    # FCM server error - retry later
    Logger.error("FCM error #{status}: #{inspect(body)}")

  {:error, reason} ->
    Logger.error("Unknown error: #{inspect(reason)}")
end
```

### FCM Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `UNREGISTERED` | Device no longer registered | Remove token from database |
| `INVALID_ARGUMENT` | Invalid message format | Check message structure |
| `SENDER_ID_MISMATCH` | Wrong project/sender | Verify project ID |
| `QUOTA_EXCEEDED` | Rate limit exceeded | Implement backoff |
| `UNAVAILABLE` | FCM temporarily unavailable | Retry with backoff |
| `INTERNAL` | FCM internal error | Retry with backoff |
| `THIRD_PARTY_AUTH_ERROR` | APNs auth error | Check APNs configuration |

---

## Configuration

```elixir
# config/config.exs
config :om_google,
  default_credentials_env: "GOOGLE_APPLICATION_CREDENTIALS"

# config/runtime.exs (for production)
config :my_app,
  firebase_project_id: System.get_env("FIREBASE_PROJECT_ID")
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON file OR JSON content |
| `FIREBASE_CREDENTIALS` | Alternative env var for credentials |

## Dependencies

- `jose` - JWT signing with RS256
- `req` - HTTP client for API requests
- `fn_types` - Functional utilities (Result, Config)
- `om_api_client` - API client base

## License

MIT
