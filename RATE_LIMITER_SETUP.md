# Rate Limiter Setup

This project now includes a clean, isolated rate limiter implementation using Hammer with Redis backend.

## Components

### 1. Dependencies (mix.exs)

```elixir
{:hammer, "~> 6.2"},
{:hammer_backend_redis, "~> 6.2"}
```

### 2. Configuration (config/config.exs)

The rate limiter is configured to use Redis as the backend:

```elixir
config :hammer,
  backend: {Hammer.Backend.Redis, [
    expiry_ms: 60_000 * 60 * 2,  # 2 hours
    redix_config: [
      host: System.get_env("REDIS_HOST", "localhost"),
      port: String.to_integer(System.get_env("REDIS_PORT", "6379"))
    ]
  ]}
```

### 3. Rate Limiter Plug (lib/events_web/plugs/rate_limiter.ex)

A reusable plug that can be added to any pipeline with customizable options.

### 4. Router Integration (lib/events_web/router.ex)

The rate limiter is currently added to the `:api` pipeline:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug EventsWeb.Plugs.RateLimiter
end
```

## Usage Examples

### Default Configuration (60 requests per minute by IP)

```elixir
pipeline :api do
  plug EventsWeb.Plugs.RateLimiter
end
```

### Custom Rate Limits

```elixir
pipeline :strict_api do
  plug EventsWeb.Plugs.RateLimiter,
    max_requests: 10,
    interval_ms: 60_000,  # 10 requests per minute
    id_prefix: "strict"
end
```

### Rate Limit by User ID

```elixir
pipeline :authenticated_api do
  plug :load_current_user
  plug EventsWeb.Plugs.RateLimiter,
    identifier: fn conn ->
      # Use user ID if available, fallback to IP
      conn.assigns[:current_user_id] ||
        EventsWeb.Plugs.RateLimiter.get_ip(conn)
    end
end
```

### Different Limits for Different Endpoints

```elixir
scope "/api/v1", EventsWeb do
  pipe_through :api

  # These routes use the default rate limit (60/min)
  get "/users", UserController, :index
  get "/posts", PostController, :index
end

scope "/api/v1/admin", EventsWeb.Admin do
  pipeline :admin_rate_limit do
    plug EventsWeb.Plugs.RateLimiter,
      max_requests: 100,
      interval_ms: 60_000
  end

  pipe_through [:api, :admin_rate_limit]

  # These routes use higher limits (100/min)
  post "/bulk_import", AdminController, :bulk_import
end
```

## Rate Limit Response

When a client exceeds the rate limit, they receive:

**Status:** 429 Too Many Requests

**Headers:**
- `x-ratelimit-limit`: Maximum requests allowed
- `x-ratelimit-remaining`: 0
- `x-ratelimit-reset`: Seconds until limit resets
- `retry-after`: Seconds to wait before retrying

**Body:**
```json
{
  "error": "Too many requests",
  "message": "Rate limit exceeded. Please try again in 60 seconds.",
  "retry_after": 60
}
```

## Running Redis

### Development

```bash
# Using Docker
docker run -d -p 6379:6379 redis:alpine

# Or using Homebrew (macOS)
brew install redis
brew services start redis
```

### Production

Set environment variables:
```bash
export REDIS_HOST=your-redis-host.com
export REDIS_PORT=6379
```

## Testing

To test the rate limiter:

1. Start Redis
2. Start your Phoenix server: `mix phx.server`
3. Make requests to an API endpoint:

```bash
# Should succeed 60 times
for i in {1..70}; do
  curl http://localhost:4000/api/your-endpoint
done
```

After 60 requests, you'll receive 429 responses.

## Customization Options

The `EventsWeb.Plugs.RateLimiter` accepts these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_requests` | integer | 60 | Maximum requests allowed in the time window |
| `interval_ms` | integer | 60000 | Time window in milliseconds (default: 1 minute) |
| `id_prefix` | string | "rl" | Prefix for rate limit bucket ID in Redis |
| `identifier` | function | IP-based | Function to extract identifier from conn |

## Error Handling

If Redis is unavailable, the plug logs the error but allows requests through to prevent service disruption. This fail-open behavior ensures your API remains available even if the rate limiter backend has issues.
