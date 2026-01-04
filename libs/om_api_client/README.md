# OmApiClient

Production-ready HTTP API client framework with built-in resilience, authentication, and observability.

## Installation

```elixir
def deps do
  [
    {:om_api_client, "~> 0.1.0"},
    {:req, "~> 0.4"}  # HTTP client
  ]
end
```

## Why OmApiClient?

Building production API clients requires handling many concerns:

```
Traditional Approach                    OmApiClient
─────────────────────────────────────────────────────────────────────
def create_customer(attrs) do          defmodule Stripe do
  # Manual retry logic                   use OmApiClient,
  # Manual circuit breaker                 base_url: "https://api.stripe.com",
  # Manual rate limiting                   auth: :bearer,
  # Manual telemetry                       retry: [max_attempts: 3],
  # Manual auth refresh                    circuit_breaker: :stripe,
  # ... 50+ lines of boilerplate           rate_limiter: :stripe

  HTTPClient.post(url, body, headers)   def create_customer(params, config) do
end                                       new(config)
                                          |> post("/v1/customers", params)
                                        end
                                      end
```

**Benefits:**
- **Resilience Built-In** - Retry, circuit breaker, rate limiting
- **Auth Handling** - Bearer, Basic, OAuth2 with auto-refresh
- **Observability** - Telemetry events, request logging
- **Pagination** - Stream-based auto-pagination
- **Webhook Verification** - Stripe, GitHub, Slack, etc.
- **Type-Safe Responses** - Rich response handling

---

## Quick Start

### Define a Client

```elixir
defmodule MyApp.Clients.GitHub do
  use OmApiClient,
    base_url: "https://api.github.com",
    auth: :bearer,
    content_type: :json

  def get_user(username, config) do
    new(config)
    |> get("/users/#{username}")
  end

  def create_repo(params, config) do
    new(config)
    |> post("/user/repos", params)
  end

  def list_repos(username, config, opts \\ []) do
    new(config)
    |> get("/users/#{username}/repos", query: opts)
  end
end
```

### Use the Client

```elixir
config = %{api_key: "ghp_xxxx"}

case MyApp.Clients.GitHub.get_user("octocat", config) do
  {:ok, %{status: 200, body: user}} ->
    IO.puts("Found user: #{user["name"]}")

  {:ok, %{status: 404}} ->
    {:error, :not_found}

  {:ok, %{status: status}} when status >= 500 ->
    {:error, :server_error}

  {:error, reason} ->
    {:error, reason}
end
```

---

## Client Options

```elixir
use OmApiClient,
  # Required
  base_url: "https://api.example.com",

  # Authentication
  auth: :bearer,           # :bearer | :basic | :api_key | :custom | :none

  # Content type
  content_type: :json,     # :json | :form

  # Resilience
  retry: true,             # Enable retry (or keyword opts)
  retry: [max_attempts: 3, base_delay: 1000],
  circuit_breaker: :api_name,    # Circuit breaker name (atom)
  rate_limiter: :api_name,       # Rate limiter name (atom)

  # Telemetry
  telemetry: true,               # Enable telemetry events
  telemetry_prefix: [:my_app, :api],  # Custom prefix

  # Advanced
  request_module: MyApp.Request,   # Custom Request struct
  response_module: MyApp.Response  # Custom Response struct
```

---

## Request Building

### Chainable API

```elixir
alias OmApiClient.Request

Request.new(config)
|> Request.method(:post)
|> Request.path("/v1/customers")
|> Request.json(%{email: "user@example.com"})
|> Request.header("idempotency-key", key)
|> Request.timeout(30_000)
|> Request.metadata(:operation, :create_customer)
```

### HTTP Methods

```elixir
# GET request
get(request, "/users", query: [page: 1, per_page: 20])

# POST with JSON body
post(request, "/users", %{name: "John", email: "john@example.com"})

# PUT with form data
Request.form(request, email: "new@example.com")
|> put("/users/123", [])

# PATCH
patch(request, "/users/123", %{name: "New Name"})

# DELETE
delete(request, "/users/123")
```

### Body Formats

```elixir
# JSON (default for :json content_type)
Request.json(request, %{email: "user@example.com"})

# Form-encoded
Request.form(request, email: "user@example.com", name: "John")

# Multipart (file uploads)
Request.multipart(request, [
  {:file, "/path/to/file.pdf", filename: "document.pdf"},
  {"field_name", "value"}
])

# Raw binary
Request.body(request, <<binary_data::binary>>)
```

### Query Parameters

```elixir
# Multiple params
Request.query(request, limit: 100, offset: 0, filter: "active")

# Single param
Request.query(request, :page, 2)

# Merged across calls
request
|> Request.query(limit: 50)
|> Request.query(offset: 100)  # Both applied
```

### Headers

```elixir
Request.header(request, "x-custom-header", "value")
|> Request.header("x-another", "value2")

# Multiple at once
Request.headers(request, [
  {"x-request-id", request_id},
  {"x-correlation-id", correlation_id}
])
```

### Timeouts

```elixir
Request.timeout(request, 5_000)           # Connection timeout
|> Request.receive_timeout(30_000)        # Response timeout
```

### Metadata (for Telemetry)

```elixir
request
|> Request.metadata(:operation, :create_customer)
|> Request.metadata(:customer_id, customer_id)
|> Request.metadata(:user_id, current_user.id)
```

---

## Response Handling

### Response Structure

```elixir
%OmApiClient.Response{
  status: 200,
  body: %{"id" => "cus_123", "email" => "user@example.com"},
  headers: %{"x-request-id" => "req_abc"},
  request_id: "local_xyz",
  api_request_id: "stripe_abc",
  rate_limit: %{limit: 100, remaining: 99, reset: 1705334400},
  timing_ms: 150
}
```

### Status Helpers

```elixir
alias OmApiClient.Response

Response.success?(resp)       # 2xx
Response.client_error?(resp)  # 4xx
Response.server_error?(resp)  # 5xx
Response.error?(resp)         # 4xx or 5xx
Response.retryable?(resp)     # 429, 5xx

# Specific checks
Response.rate_limited?(resp)  # 429
Response.unauthorized?(resp)  # 401
Response.forbidden?(resp)     # 403
Response.not_found?(resp)     # 404
```

### Pattern Matching with Categorize

```elixir
case Response.categorize(response) do
  {:ok, body} ->
    {:ok, body}

  {:created, body} ->
    {:ok, body}

  {:no_content, nil} ->
    :ok

  {:not_found, _resp} ->
    {:error, :not_found}

  {:unauthorized, _resp} ->
    {:error, :unauthorized}

  {:rate_limited, resp} ->
    wait_and_retry(Response.retry_after_ms(resp))

  {:unprocessable, resp} ->
    {:error, {:validation, Response.error_message(resp)}}

  {:client_error, resp} ->
    {:error, {:client_error, resp.status}}

  {:server_error, resp} ->
    {:error, :server_error}
end
```

### Data Access

```elixir
# Get from body
Response.get(resp, "id")
Response.get(resp, ["customer", "email"])
Response.get(resp, "missing", "default")

# Nested access
Response.get_in(resp, ["data", "user", "email"])

# Headers
Response.get_header(resp, "x-request-id")
Response.content_type(resp)
```

### Error Extraction

```elixir
# Auto-extracts from common locations
Response.error_message(resp)
#=> "Invalid API key"

Response.error_code(resp)
#=> "invalid_api_key"
```

### Result Conversion

```elixir
# Body on success, response on error
Response.to_result(resp)
#=> {:ok, %{"id" => "..."}} or {:error, %Response{}}

# Extract from path
Response.to_result(resp, ["data", "customer"])

# Full response on success
Response.to_full_result(resp)
#=> {:ok, %Response{}} or {:error, %Response{}}

# Transform
Response.map(resp, fn body -> body["data"] end)
#=> {:ok, data} or {:error, response}
```

---

## Authentication

### Bearer Token (API Key)

```elixir
use OmApiClient, auth: :bearer

# Config provides api_key or access_token
config = %{api_key: "sk_test_xxx"}
# or
config = %{access_token: "ya29.xxx"}
```

### Basic Auth

```elixir
use OmApiClient, auth: :basic

# Config provides username/password or account_sid/auth_token
config = %{username: "user", password: "pass"}
# or (for Twilio-style)
config = %{account_sid: "AC...", auth_token: "xxx"}
```

### API Key (Header/Query)

```elixir
alias OmApiClient.Auth.APIKey

# Bearer token
auth = APIKey.bearer("sk_test_xxx")

# Custom header
auth = APIKey.header("x-api-key", "xxx")

# Query parameter
auth = APIKey.query("api_key", "xxx")
```

### OAuth2

```elixir
alias OmApiClient.Auth.OAuth2

# Create from existing tokens
auth = OAuth2.new(
  access_token: "ya29.xxx",
  refresh_token: "1//xxx",
  expires_in: 3600,
  client_id: "xxx.apps.googleusercontent.com",
  client_secret: "xxx",
  token_url: "https://oauth2.googleapis.com/token"
)

# Provider presets
auth = OAuth2.google(
  access_token: "ya29.xxx",
  refresh_token: "1//xxx",
  expires_at: expires_at,
  client_id: "xxx",
  client_secret: "xxx"
)

auth = OAuth2.github(access_token: "gho_xxx")
auth = OAuth2.slack(access_token: "xoxb-xxx", ...)
auth = OAuth2.microsoft(access_token: "...", tenant: "common")
auth = OAuth2.spotify(access_token: "BQxxx", ...)

# Client credentials flow (server-to-server)
{:ok, auth} = OAuth2.client_credentials(
  client_id: "xxx",
  client_secret: "xxx",
  token_url: "https://accounts.spotify.com/api/token",
  scope: "playlist-read-private"
)

# Check expiration
OAuth2.expired?(auth)      #=> true/false
OAuth2.expires_in(auth)    #=> 3542 (seconds)
OAuth2.can_refresh?(auth)  #=> true/false
```

### Custom Auth Protocol

```elixir
defmodule MyApp.Auth.HMAC do
  defstruct [:key, :secret]

  defimpl OmApiClient.Auth do
    def authenticate(auth, request) do
      timestamp = System.system_time(:second)
      signature = compute_signature(auth, request, timestamp)

      request
      |> Request.header("x-signature", signature)
      |> Request.header("x-timestamp", to_string(timestamp))
    end

    def valid?(_auth), do: true
    def refresh(auth), do: {:ok, auth}

    defp compute_signature(auth, request, timestamp) do
      data = "#{request.method}:#{request.path}:#{timestamp}"
      :crypto.mac(:hmac, :sha256, auth.secret, data)
      |> Base.encode16(case: :lower)
    end
  end
end

# Use with custom auth
use OmApiClient, auth: :custom

config = %{auth: %MyApp.Auth.HMAC{key: "key", secret: "secret"}}
```

---

## Resilience

### Retry Middleware

```elixir
# Enable with defaults
use OmApiClient, retry: true

# Custom configuration
use OmApiClient, retry: [
  max_attempts: 3,
  initial_delay: 1000,
  max_delay: 30_000,
  jitter: 0.25,
  retry_statuses: [408, 429, 500, 502, 503, 504]
]

# Custom retry condition
use OmApiClient, retry: [
  max_attempts: 5,
  retry_on: fn
    {:ok, %{status: 429}} -> true
    {:ok, %{status: s}} when s >= 500 -> true
    {:error, %Mint.TransportError{}} -> true
    _ -> false
  end
]
```

**Retry Behavior:**
- Exponential backoff: `delay = base * 2^(attempt-1)`
- Jitter: Random factor between `1-jitter` and `1+jitter`
- Respects `Retry-After` header from 429 responses

### Circuit Breaker

```elixir
# In client definition
use OmApiClient, circuit_breaker: :stripe_api

# Start circuit breaker in supervision tree
children = [
  {OmApiClient.Middleware.CircuitBreaker,
    name: :stripe_api,
    failure_threshold: 5,      # Failures before opening
    success_threshold: 2,      # Successes to close from half-open
    reset_timeout: 30_000,     # Time before half-open (ms)
    call_timeout: 10_000       # Timeout for wrapped calls
  }
]
```

**Circuit Breaker States:**

```
     Closed  ───[failures >= threshold]──▶  Open
        ▲                                     │
        │                                     │
        └──[successes >= threshold]──  Half-Open  ◀──[reset_timeout]──┘
```

**Manual Control:**

```elixir
alias OmApiClient.Middleware.CircuitBreaker

# Check state
CircuitBreaker.get_state(:stripe_api)
#=> %{state: :closed, failure_count: 2, ...}

# Manual reset
CircuitBreaker.reset(:stripe_api)

# Check if requests allowed
CircuitBreaker.allow_request?(:stripe_api)
#=> :ok | {:error, :circuit_open}
```

### Rate Limiter

```elixir
# In client definition
use OmApiClient, rate_limiter: :stripe_api

# Start rate limiter
children = [
  {OmApiClient.Middleware.RateLimiter,
    name: :stripe_api,
    bucket_size: 100,        # Maximum tokens
    refill_rate: 10,         # Tokens per interval
    refill_interval: 1000,   # Interval in ms
    wait_timeout: 30_000     # Max wait time
  }
]
```

**Token Bucket Algorithm:**
- Tokens added at `refill_rate` per `refill_interval`
- Each request consumes one token
- When empty, requests wait for tokens
- Syncs with API rate limit headers

**Manual Control:**

```elixir
alias OmApiClient.Middleware.RateLimiter

# Acquire permission (blocks if needed)
:ok = RateLimiter.acquire(:stripe_api)
:ok = RateLimiter.acquire(:stripe_api, timeout: 5000)

# Update from response headers
RateLimiter.update_from_response(:stripe_api, response)

# Check state
RateLimiter.get_state(:stripe_api)
#=> %{tokens: 95, api_remaining: 99, ...}
```

---

## Pagination

### Stream-Based Auto-Pagination

```elixir
alias OmApiClient.Pagination

# Lazily fetch all pages
Stripe.new(config)
|> Stripe.customers()
|> Pagination.stream(&Stripe.list/2)
|> Enum.take(100)

# Process in batches
Stripe.new(config)
|> Stripe.customers()
|> Pagination.stream(&Stripe.list/2, batch_size: 50)
|> Stream.each(&process_batch/1)
|> Stream.run()

# Stream pages instead of items
Pagination.stream_pages(request, &Client.list/2)
|> Stream.each(fn page ->
  Enum.each(page, &process_item/1)
end)
|> Stream.run()
```

### Pagination Strategies

**Cursor-Based (Stripe, Slack):**

```elixir
Pagination.stream(request, fetcher,
  strategy: :cursor,
  cursor_path: ["data", Access.at(-1), "id"],
  cursor_param: :starting_after,
  has_more_path: ["has_more"]
)
```

**Offset-Based (Traditional APIs):**

```elixir
Pagination.stream(request, fetcher,
  strategy: :offset,
  offset_param: :offset,
  limit_param: :limit,
  total_path: ["meta", "total"]
)
```

**Link Header (GitHub, REST APIs):**

```elixir
Pagination.stream(request, fetcher,
  strategy: :link_header
)
```

**Page Number:**

```elixir
Pagination.stream(request, fetcher,
  strategy: :page,
  page_param: :page,
  per_page_param: :per_page
)
```

### Collecting Results

```elixir
# Collect all
{:ok, all_items} = Pagination.collect_all(request, fetcher)

# With limit
{:ok, items} = Pagination.collect_all(request, fetcher, max_items: 500)

# Single page
{:ok, %{items: items, next_cursor: cursor, has_more: true}} =
  Pagination.fetch_page(request, fetcher, limit: 50)
```

---

## Webhook Verification

### Unified API

```elixir
alias OmApiClient.Webhook

case Webhook.verify(:stripe, payload, signature, webhook_secret) do
  {:ok, event} ->
    handle_event(event)
  {:error, :signature_mismatch} ->
    {:error, :invalid_signature}
  {:error, :timestamp_expired} ->
    {:error, :replay_attack}
end
```

### Supported Providers

| Provider | Header | Signature Format |
|----------|--------|------------------|
| `:stripe` | `Stripe-Signature` | `t=timestamp,v1=signature` |
| `:github` | `X-Hub-Signature-256` | `sha256=<hex>` |
| `:slack` | `X-Slack-Signature` | `v0=<hex>` |
| `:twilio` | `X-Twilio-Signature` | Base64 HMAC-SHA1 |
| `:shopify` | `X-Shopify-Hmac-SHA256` | Base64 HMAC-SHA256 |
| `:sendgrid` | `X-Twilio-Email-Event-Webhook-Signature` | ECDSA |

### Stripe Webhooks

```elixir
Webhook.verify_stripe(payload, signature, "whsec_xxx",
  tolerance: 300  # Max age in seconds
)
```

### GitHub Webhooks

```elixir
# SHA-256 (recommended)
Webhook.verify_github(payload, "sha256=abc123...", secret)

# Legacy SHA-1
Webhook.verify_github(payload, "sha1=abc123...", secret)
```

### Slack Webhooks

```elixir
Webhook.verify_slack(payload, signature, secret,
  timestamp: request_timestamp,  # From X-Slack-Request-Timestamp
  tolerance: 300
)
```

### Twilio Webhooks

```elixir
Webhook.verify_twilio(params, signature, auth_token,
  url: "https://example.com/webhook"
)
```

### Generic HMAC Verification

```elixir
# For unsupported providers
Webhook.verify_hmac(payload, signature, secret,
  algorithm: :sha256,   # :sha, :sha256, :sha384, :sha512
  encoding: :hex,       # :hex | :base64
  prefix: "sha256="     # Optional prefix to strip
)
```

### Phoenix Controller Example

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  # Plug to capture raw body
  plug :fetch_raw_body when action in [:stripe, :github]

  def stripe(conn, _params) do
    payload = conn.assigns.raw_body
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Webhook.verify(:stripe, payload, signature, webhook_secret()) do
      {:ok, event} ->
        handle_stripe_event(event)
        send_resp(conn, 200, "OK")

      {:error, reason} ->
        send_resp(conn, 400, "Invalid signature: #{reason}")
    end
  end

  defp fetch_raw_body(conn, _opts) do
    {:ok, body, conn} = read_body(conn)
    assign(conn, :raw_body, body)
  end

  defp webhook_secret, do: Application.get_env(:my_app, :stripe_webhook_secret)
end
```

---

## Telemetry

### Events

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:om_api_client, :request, :start]` | `system_time` | `client`, `method`, `path`, `request_id` |
| `[:om_api_client, :request, :stop]` | `duration`, `status` | `client`, `method`, `path`, `request_id` |
| `[:om_api_client, :request, :exception]` | `duration` | `client`, `kind`, `reason`, `stacktrace` |
| `[:om_api_client, :retry]` | `attempt`, `delay_ms` | `client`, `method`, `path` |
| `[:om_api_client, :circuit_breaker, :state_change]` | `from`, `to`, `failure_count` | `circuit_breaker` |

### Attach Handlers

```elixir
# In application.ex
def start(_type, _args) do
  OmApiClient.Telemetry.attach_default_handlers()
  # ...
end

# With options
OmApiClient.Telemetry.attach_logger(
  level: :info,
  slow_threshold_ms: 5000
)
```

### Custom Handlers

```elixir
:telemetry.attach(
  "my-api-metrics",
  [:om_api_client, :request, :stop],
  fn event, measurements, metadata, config ->
    :telemetry.execute(
      [:my_app, :api, :request],
      %{
        duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond),
        status: measurements.status
      },
      %{
        client: metadata.client,
        method: metadata.method,
        path: metadata.path
      }
    )
  end,
  nil
)
```

### Custom Prefix

```elixir
use OmApiClient,
  base_url: "https://api.stripe.com",
  telemetry_prefix: [:my_app, :stripe]

# Events will be:
# [:my_app, :stripe, :request, :start]
# [:my_app, :stripe, :request, :stop]
# etc.
```

### Telemetry Span Helper

```elixir
alias OmApiClient.Telemetry

Telemetry.span(:stripe, fn ->
  Stripe.create_customer(params, config)
end, %{operation: :create_customer})
```

---

## Real-World Examples

### Stripe Client

```elixir
defmodule MyApp.Clients.Stripe do
  use OmApiClient,
    base_url: "https://api.stripe.com",
    auth: :bearer,
    content_type: :form,
    retry: [max_attempts: 3, base_delay: 1000],
    circuit_breaker: :stripe_api,
    rate_limiter: :stripe_api,
    telemetry_prefix: [:my_app, :stripe]

  @impl true
  def default_headers(_config) do
    [{"stripe-version", "2024-01-01"}]
  end

  # Customers
  def create_customer(params, config) do
    new(config)
    |> Request.idempotency_key(generate_idempotency_key())
    |> post("/v1/customers", params)
  end

  def get_customer(customer_id, config) do
    new(config)
    |> get("/v1/customers/#{customer_id}")
  end

  def list_customers(config, opts \\ []) do
    new(config)
    |> get("/v1/customers", query: opts)
  end

  # Paginated listing
  def stream_customers(config, opts \\ []) do
    request = new(config) |> Request.path("/v1/customers")

    Pagination.stream(request, fn req, params ->
      Request.query(req, params) |> execute()
    end, Keyword.merge([
      strategy: :cursor,
      cursor_param: :starting_after,
      data_path: ["data"],
      has_more_path: ["has_more"]
    ], opts))
  end

  # Payment Intents
  def create_payment_intent(params, config) do
    new(config)
    |> Request.idempotency_key(params[:idempotency_key] || generate_idempotency_key())
    |> post("/v1/payment_intents", params)
  end

  def confirm_payment_intent(intent_id, params, config) do
    new(config)
    |> post("/v1/payment_intents/#{intent_id}/confirm", params)
  end

  defp generate_idempotency_key do
    "idem_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
  end
end
```

### GitHub Client with OAuth

```elixir
defmodule MyApp.Clients.GitHub do
  use OmApiClient,
    base_url: "https://api.github.com",
    auth: :custom,
    content_type: :json,
    retry: true

  @impl true
  def default_headers(_config) do
    [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]
  end

  # User operations
  def get_authenticated_user(config) do
    new(config) |> get("/user")
  end

  def list_user_repos(username, config, opts \\ []) do
    new(config)
    |> get("/users/#{username}/repos", query: opts)
  end

  # Repository operations
  def create_repo(params, config) do
    new(config)
    |> post("/user/repos", params)
  end

  def create_issue(owner, repo, params, config) do
    new(config)
    |> post("/repos/#{owner}/#{repo}/issues", params)
  end

  # Stream all repos (handles pagination)
  def stream_repos(owner, config) do
    request = new(config) |> Request.path("/users/#{owner}/repos")

    Pagination.stream(request, fn req, params ->
      Request.query(req, params) |> execute()
    end, strategy: :link_header)
  end
end

# Usage with OAuth
auth = OmApiClient.Auth.OAuth2.github(access_token: "gho_xxxx")
config = %{auth: auth}

{:ok, %{body: user}} = MyApp.Clients.GitHub.get_authenticated_user(config)
```

### Multi-Tenant API Client

```elixir
defmodule MyApp.Clients.SaaS do
  use OmApiClient,
    base_url: "https://api.example.com",
    auth: :bearer,
    telemetry_prefix: [:my_app, :saas]

  # Override base_url per tenant
  @impl true
  def base_url(%{tenant: tenant}) do
    "https://#{tenant}.api.example.com"
  end

  @impl true
  def default_headers(%{tenant: tenant}) do
    [{"x-tenant-id", tenant}]
  end

  def list_resources(config) do
    new(config)
    |> get("/v1/resources")
  end
end

# Usage
config = %{api_key: "key", tenant: "acme"}
{:ok, response} = MyApp.Clients.SaaS.list_resources(config)
```

---

## Best Practices

### 1. Use Idempotency Keys for Mutations

```elixir
def create_charge(params, config) do
  new(config)
  |> Request.idempotency_key(params[:idempotency_key] || generate_key())
  |> post("/v1/charges", params)
end
```

### 2. Configure Resilience for Production

```elixir
# In supervision tree
children = [
  {OmApiClient.Middleware.CircuitBreaker, name: :external_api},
  {OmApiClient.Middleware.RateLimiter, name: :external_api},
  # ...
]
```

### 3. Use Streams for Large Datasets

```elixir
# Good - memory efficient
Client.stream_items(config)
|> Stream.filter(&relevant?/1)
|> Stream.take(1000)
|> Enum.to_list()

# Avoid - loads all into memory
Client.list_all_items(config)
|> Enum.filter(&relevant?/1)
|> Enum.take(1000)
```

### 4. Handle All Response Categories

```elixir
case Response.categorize(response) do
  {:ok, body} -> {:ok, body}
  {:rate_limited, resp} -> retry_with_backoff(resp)
  {:unauthorized, _} -> refresh_auth_and_retry()
  {:not_found, _} -> {:error, :not_found}
  {:server_error, _} -> {:error, :service_unavailable}
  {:client_error, resp} -> {:error, parse_error(resp)}
end
```

### 5. Add Metadata for Debugging

```elixir
new(config)
|> Request.metadata(:operation, :create_order)
|> Request.metadata(:order_id, order_id)
|> Request.metadata(:user_id, current_user.id)
|> post("/orders", params)
```

---

## Configuration

```elixir
# config/config.exs
config :om_api_client,
  # Default telemetry prefix
  telemetry_prefix: [:my_app, :api],

  # Default retry options
  retry: [
    max_attempts: 3,
    initial_delay: 1000,
    max_delay: 30_000
  ]
```

---

## Supervision

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Attach telemetry handlers early
    OmApiClient.Telemetry.attach_default_handlers()

    children = [
      # Circuit breakers
      {OmApiClient.Middleware.CircuitBreaker, name: :stripe_api},
      {OmApiClient.Middleware.CircuitBreaker, name: :github_api},

      # Rate limiters
      {OmApiClient.Middleware.RateLimiter,
        name: :stripe_api, bucket_size: 100, refill_rate: 25},
      {OmApiClient.Middleware.RateLimiter,
        name: :github_api, bucket_size: 5000, refill_rate: 83},

      # Rest of application...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## License

MIT
