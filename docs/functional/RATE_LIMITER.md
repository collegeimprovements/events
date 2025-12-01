# Events.Types.RateLimiter

Functional rate limiting with multiple algorithms.

## Overview

`RateLimiter` provides pure, functional rate limiting that can be used with any state storage backend. Each algorithm returns a new state and a decision, making it easy to integrate with GenServers, ETS, Redis, or any other storage mechanism.

```elixir
alias Events.Types.RateLimiter

# Create a token bucket limiter
state = RateLimiter.token_bucket(capacity: 10, refill_rate: 1)

# Check if action is allowed
case RateLimiter.check(state) do
  {:allow, new_state} -> {:ok, proceed(new_state)}
  {:deny, new_state, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
end
```

## Algorithms

| Algorithm | Best For | Behavior |
|-----------|----------|----------|
| **Token Bucket** | API rate limits | Allows bursts up to capacity, refills over time |
| **Sliding Window** | Request counting | Smooth rate enforcement, no boundary issues |
| **Leaky Bucket** | Traffic shaping | Constant output rate, smooths bursts |
| **Fixed Window** | Simple counting | Resets at fixed intervals |

## Token Bucket

Tokens accumulate over time up to a maximum capacity. Each request consumes tokens. Allows bursts while maintaining an average rate.

```
┌─────────────────────────────────────┐
│ Capacity: 10 tokens                 │
│ Refill: 2 tokens/second             │
│                                     │
│ ████████░░  (8 tokens available)    │
│                                     │
│ Request → consumes 1 token          │
│ Wait → tokens refill                │
└─────────────────────────────────────┘
```

```elixir
# 10 requests/second with burst of 50
state = RateLimiter.token_bucket(
  capacity: 50,      # Max tokens (burst size)
  refill_rate: 10.0  # Tokens per second
)

# Start with fewer tokens (no initial burst)
state = RateLimiter.token_bucket(
  capacity: 10,
  refill_rate: 1.0,
  initial_tokens: 0
)
```

**Use when:**
- You want to allow occasional bursts
- Need smooth rate limiting over time
- API rate limiting with burst tolerance

## Sliding Window

Counts requests within a sliding time window. Provides smoother rate limiting than fixed windows without boundary issues.

```
┌─────────────────────────────────────┐
│ Window: 1 minute                    │
│ Max: 100 requests                   │
│                                     │
│ ──────[    60 second window    ]────│
│       ↑                        ↑    │
│    oldest                    newest │
│                                     │
│ Requests in window: 45/100          │
└─────────────────────────────────────┘
```

```elixir
# Max 100 requests per minute
state = RateLimiter.sliding_window(
  max_requests: 100,
  window_ms: 60_000
)

# Max 10 requests per second
state = RateLimiter.sliding_window(
  max_requests: 10,
  window_ms: 1_000
)
```

**Use when:**
- Need precise request counting
- Want to avoid fixed window boundary issues
- Rate limiting should be smooth and predictable

## Leaky Bucket

Requests fill a bucket that "leaks" at a constant rate. Smooths out bursts into a steady flow.

```
┌─────────────────────────────────────┐
│ Capacity: 50 requests               │
│ Leak rate: 10/second                │
│                                     │
│    ▼ Requests come in (any rate)    │
│ ┌─────┐                             │
│ │█████│ ← Bucket fills              │
│ │█████│                             │
│ │░░░░░│                             │
│ └──┬──┘                             │
│    ▼ Leaks out at steady 10/sec     │
└─────────────────────────────────────┘
```

```elixir
# Buffer up to 50 requests, process 10/second
state = RateLimiter.leaky_bucket(
  capacity: 50,    # Max queue size
  leak_rate: 10.0  # Requests processed per second
)
```

**Use when:**
- Need to smooth traffic to downstream services
- Want constant output rate regardless of input
- Protecting slow backends from bursts

## Fixed Window

Simple counting within fixed time intervals. Resets completely at window boundaries.

```
┌─────────────────────────────────────┐
│ Window: 1 hour                      │
│ Max: 1000 requests                  │
│                                     │
│ |-------- Hour 1 --------|          │
│ Requests: 750/1000                  │
│                                     │
│ At hour boundary → resets to 0      │
└─────────────────────────────────────┘
```

```elixir
# Max 1000 requests per hour
state = RateLimiter.fixed_window(
  max_requests: 1000,
  window_ms: 3_600_000
)
```

**Use when:**
- Simplicity is more important than smoothness
- Rate limiting aligns with billing periods
- Memory efficiency is critical

## Core Operations

### check/2

Check if a request should be allowed:

```elixir
state = RateLimiter.token_bucket(capacity: 10)

case RateLimiter.check(state) do
  {:allow, new_state} ->
    # Proceed with request, use new_state for next check
    {:ok, new_state}

  {:deny, new_state, retry_after_ms} ->
    # Rate limited, retry after specified milliseconds
    {:error, {:rate_limited, retry_after_ms}}
end
```

With custom cost:

```elixir
# Expensive operation costs 5 tokens
RateLimiter.check(state, cost: 5)
```

### would_allow?/2

Check without consuming resources:

```elixir
if RateLimiter.would_allow?(state) do
  expensive_operation()
else
  :rate_limited
end
```

### status/2

Get current rate limiter status:

```elixir
status = RateLimiter.status(state)
#=> %{remaining: 8, limit: 10, reset_ms: 1000}
```

### reset/1

Reset to initial state:

```elixir
fresh_state = RateLimiter.reset(state)
```

## Result Integration

### check_result/2

Returns standard Result tuple:

```elixir
case RateLimiter.check_result(state) do
  {:ok, new_state} -> proceed(new_state)
  {:error, {:rate_limited, ms}} -> retry_later(ms)
end
```

### with_limit/3

Execute action only if rate limit allows:

```elixir
case RateLimiter.with_limit(state, fn -> make_api_call() end) do
  {:ok, result, new_state} ->
    {:ok, result, new_state}

  {:error, {:rate_limited, retry_after}, new_state} ->
    {:retry, retry_after, new_state}
end
```

## Composite Rate Limiters

Combine multiple limits (all must pass):

```elixir
# 10/second AND 100/minute
per_second = RateLimiter.token_bucket(capacity: 10, refill_rate: 10.0)
per_minute = RateLimiter.sliding_window(max_requests: 100, window_ms: 60_000)

composite = RateLimiter.compose([per_second, per_minute])

case RateLimiter.check(composite) do
  {:allow, new_composite} ->
    # Both limits passed
    {:ok, new_composite}

  {:deny, new_composite, retry_after} ->
    # At least one limit exceeded, retry_after is max of all
    {:error, retry_after}
end
```

## Real-World Examples

### GenServer-Based Rate Limiter

```elixir
defmodule MyApp.RateLimiter do
  use GenServer
  alias Events.Types.RateLimiter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check(key) do
    GenServer.call(__MODULE__, {:check, key})
  end

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, default_config())
    {:ok, %{limiters: %{}, config: config}}
  end

  @impl true
  def handle_call({:check, key}, _from, state) do
    limiter = Map.get(state.limiters, key, new_limiter(state.config))

    case RateLimiter.check(limiter) do
      {:allow, new_limiter} ->
        new_state = put_in(state.limiters[key], new_limiter)
        {:reply, :ok, new_state}

      {:deny, new_limiter, retry_after} ->
        new_state = put_in(state.limiters[key], new_limiter)
        {:reply, {:error, {:rate_limited, retry_after}}, new_state}
    end
  end

  defp default_config do
    %{capacity: 10, refill_rate: 1.0}
  end

  defp new_limiter(config) do
    RateLimiter.token_bucket(
      capacity: config.capacity,
      refill_rate: config.refill_rate
    )
  end
end
```

### ETS-Based Per-User Limiting

```elixir
defmodule MyApp.UserRateLimiter do
  alias Events.Types.RateLimiter

  @table :user_rate_limiters

  def init do
    :ets.new(@table, [:named_table, :public, :set])
  end

  def check(user_id) do
    now = System.monotonic_time(:millisecond)

    state = case :ets.lookup(@table, user_id) do
      [{^user_id, stored_state}] -> stored_state
      [] -> initial_state()
    end

    case RateLimiter.check(state, now: now) do
      {:allow, new_state} ->
        :ets.insert(@table, {user_id, new_state})
        :ok

      {:deny, new_state, retry_after} ->
        :ets.insert(@table, {user_id, new_state})
        {:error, {:rate_limited, retry_after}}
    end
  end

  defp initial_state do
    RateLimiter.token_bucket(capacity: 100, refill_rate: 10.0)
  end
end
```

### Plug for Phoenix

```elixir
defmodule MyAppWeb.RateLimitPlug do
  import Plug.Conn
  alias Events.Types.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    key = rate_limit_key(conn, opts)

    case MyApp.RateLimiter.check(key) do
      :ok ->
        conn

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", to_string(div(retry_after, 1000)))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> send_resp(429, "Too Many Requests")
        |> halt()
    end
  end

  defp rate_limit_key(conn, opts) do
    case Keyword.get(opts, :by, :ip) do
      :ip -> conn.remote_ip |> :inet.ntoa() |> to_string()
      :user -> conn.assigns[:current_user].id
      fun when is_function(fun) -> fun.(conn)
    end
  end
end

# In router
plug MyAppWeb.RateLimitPlug, by: :ip
```

### Tiered API Rate Limiting

```elixir
defmodule MyApp.APIRateLimiter do
  alias Events.Types.RateLimiter

  def limiter_for_tier(tier) do
    case tier do
      :free ->
        RateLimiter.compose([
          RateLimiter.token_bucket(capacity: 10, refill_rate: 1.0),
          RateLimiter.sliding_window(max_requests: 100, window_ms: 3_600_000)
        ])

      :basic ->
        RateLimiter.compose([
          RateLimiter.token_bucket(capacity: 50, refill_rate: 10.0),
          RateLimiter.sliding_window(max_requests: 1000, window_ms: 3_600_000)
        ])

      :premium ->
        RateLimiter.compose([
          RateLimiter.token_bucket(capacity: 200, refill_rate: 50.0),
          RateLimiter.sliding_window(max_requests: 10_000, window_ms: 3_600_000)
        ])

      :enterprise ->
        # No rate limit, but still track for metrics
        RateLimiter.token_bucket(capacity: 1_000_000, refill_rate: 1_000_000.0)
    end
  end
end
```

### Retry with Backoff

```elixir
defmodule MyApp.RateLimitedClient do
  alias Events.Types.RateLimiter

  def call_with_retry(state, fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    do_call(state, fun, 0, max_retries)
  end

  defp do_call(state, _fun, attempt, max) when attempt >= max do
    {:error, :max_retries_exceeded}
  end

  defp do_call(state, fun, attempt, max_retries) do
    case RateLimiter.check(state) do
      {:allow, new_state} ->
        case fun.() do
          {:ok, result} -> {:ok, result, new_state}
          {:error, _} = error -> error
        end

      {:deny, new_state, retry_after} ->
        Process.sleep(retry_after)
        do_call(new_state, fun, attempt + 1, max_retries)
    end
  end
end
```

## Function Reference

| Function | Description |
|----------|-------------|
| `token_bucket/1` | Create token bucket limiter |
| `sliding_window/1` | Create sliding window limiter |
| `leaky_bucket/1` | Create leaky bucket limiter |
| `fixed_window/1` | Create fixed window limiter |
| `check/2` | Check if request allowed |
| `would_allow?/2` | Check without consuming |
| `status/2` | Get current status |
| `reset/1` | Reset to initial state |
| `check_result/2` | Check with Result return |
| `with_limit/3` | Execute if allowed |
| `compose/1` | Combine multiple limiters |

## Algorithm Comparison

| Aspect | Token Bucket | Sliding Window | Leaky Bucket | Fixed Window |
|--------|-------------|----------------|--------------|--------------|
| Burst handling | Allows up to capacity | No bursts | Smooths bursts | Allows at boundary |
| Memory usage | O(1) | O(n) requests | O(1) | O(1) |
| Precision | High | High | High | Low at boundaries |
| Complexity | Low | Medium | Low | Low |
| Best for | API limits | Request counting | Traffic shaping | Simple quotas |
