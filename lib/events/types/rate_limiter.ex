defmodule Events.Types.RateLimiter do
  @moduledoc """
  Functional rate limiting with multiple algorithms.

  RateLimiter provides pure, functional rate limiting that can be used
  with any state storage backend. Each algorithm returns a new state
  and a decision, making it easy to integrate with GenServers, ETS, Redis, etc.

  ## Quick Start

      alias Events.Types.RateLimiter

      # Create a token bucket limiter (10 tokens, refills 1/second)
      state = RateLimiter.token_bucket(capacity: 10, refill_rate: 1)

      # Check if action is allowed
      case RateLimiter.check(state) do
        {:allow, new_state} -> proceed_with(new_state)
        {:deny, new_state, retry_after_ms} -> wait_or_reject(retry_after_ms)
      end

  ## Algorithms

  | Algorithm | Best For | Behavior |
  |-----------|----------|----------|
  | Token Bucket | API rate limits | Allows bursts up to capacity |
  | Sliding Window | Request counting | Smooth rate enforcement |
  | Leaky Bucket | Traffic shaping | Constant output rate |
  | Fixed Window | Simple counting | Resets at intervals |

  ## Token Bucket

  Tokens accumulate over time up to capacity. Each request consumes tokens.
  Allows bursts while maintaining average rate.

      # 100 requests/minute with burst of 20
      state = RateLimiter.token_bucket(capacity: 20, refill_rate: 100/60)

  ## Sliding Window

  Counts requests in a sliding time window. Provides smooth rate limiting
  without the boundary issues of fixed windows.

      # Max 100 requests per minute
      state = RateLimiter.sliding_window(max_requests: 100, window_ms: 60_000)

  ## Leaky Bucket

  Requests enter a bucket that "leaks" at a constant rate.
  Smooths out bursts into a steady flow.

      # Process 10 requests/second max
      state = RateLimiter.leaky_bucket(capacity: 50, leak_rate: 10)

  ## Fixed Window

  Simple counting within fixed time intervals.
  Resets completely at window boundaries.

      # Max 1000 requests per hour
      state = RateLimiter.fixed_window(max_requests: 1000, window_ms: 3_600_000)

  ## Multi-Key Rate Limiting

  For per-user or per-IP limits, maintain state per key:

      defmodule MyRateLimiter do
        use Agent

        def start_link(_) do
          Agent.start_link(fn -> %{} end, name: __MODULE__)
        end

        def check(user_id) do
          Agent.get_and_update(__MODULE__, fn states ->
            state = Map.get(states, user_id, initial_state())
            {result, new_state} = RateLimiter.check(state)
            {result, Map.put(states, user_id, new_state)}
          end)
        end

        defp initial_state do
          RateLimiter.token_bucket(capacity: 10, refill_rate: 1)
        end
      end

  ## With Result Type

      alias Events.Types.{RateLimiter, Result}

      def rate_limited_action(state, action) do
        case RateLimiter.check(state) do
          {:allow, new_state} ->
            result = action.()
            {Result.ok(result), new_state}

          {:deny, new_state, retry_after} ->
            {Result.error({:rate_limited, retry_after}), new_state}
        end
      end
  """

  alias Events.Types.Result

  # ============================================================================
  # Types
  # ============================================================================

  @type algorithm :: :token_bucket | :sliding_window | :leaky_bucket | :fixed_window

  @type state :: %{
          algorithm: algorithm(),
          config: map(),
          data: map(),
          last_update: integer()
        }

  @type check_result :: {:allow, state()} | {:deny, state(), retry_after_ms :: non_neg_integer()}

  @type cost :: pos_integer()

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Creates a token bucket rate limiter.

  Tokens accumulate at `refill_rate` per second, up to `capacity`.
  Each request consumes 1 token (or specified cost).
  Allows bursts up to capacity.

  ## Options

  - `:capacity` - Maximum tokens (default: 10)
  - `:refill_rate` - Tokens added per second (default: 1.0)
  - `:initial_tokens` - Starting tokens (default: capacity)

  ## Examples

      # 10 requests/second with burst of 50
      RateLimiter.token_bucket(capacity: 50, refill_rate: 10)

      # Start empty (no initial burst allowed)
      RateLimiter.token_bucket(capacity: 10, initial_tokens: 0)
  """
  @spec token_bucket(keyword()) :: state()
  def token_bucket(opts \\ []) do
    capacity = Keyword.get(opts, :capacity, 10)
    refill_rate = Keyword.get(opts, :refill_rate, 1.0)
    initial_tokens = Keyword.get(opts, :initial_tokens, capacity)

    %{
      algorithm: :token_bucket,
      config: %{capacity: capacity, refill_rate: refill_rate},
      data: %{tokens: initial_tokens * 1.0},
      last_update: now_ms()
    }
  end

  @doc """
  Creates a sliding window rate limiter.

  Counts requests within a sliding time window.
  Provides smoother limiting than fixed windows.

  ## Options

  - `:max_requests` - Maximum requests per window (default: 100)
  - `:window_ms` - Window size in milliseconds (default: 60_000)

  ## Examples

      # Max 100 requests per minute
      RateLimiter.sliding_window(max_requests: 100, window_ms: 60_000)

      # Max 10 requests per second
      RateLimiter.sliding_window(max_requests: 10, window_ms: 1_000)
  """
  @spec sliding_window(keyword()) :: state()
  def sliding_window(opts \\ []) do
    max_requests = Keyword.get(opts, :max_requests, 100)
    window_ms = Keyword.get(opts, :window_ms, 60_000)

    %{
      algorithm: :sliding_window,
      config: %{max_requests: max_requests, window_ms: window_ms},
      data: %{timestamps: []},
      last_update: now_ms()
    }
  end

  @doc """
  Creates a leaky bucket rate limiter.

  Requests fill the bucket, which "leaks" at a constant rate.
  Smooths bursts into steady output.

  ## Options

  - `:capacity` - Maximum bucket size (default: 10)
  - `:leak_rate` - Requests leaked per second (default: 1.0)

  ## Examples

      # Buffer up to 50, process 10/second
      RateLimiter.leaky_bucket(capacity: 50, leak_rate: 10)
  """
  @spec leaky_bucket(keyword()) :: state()
  def leaky_bucket(opts \\ []) do
    capacity = Keyword.get(opts, :capacity, 10)
    leak_rate = Keyword.get(opts, :leak_rate, 1.0)

    %{
      algorithm: :leaky_bucket,
      config: %{capacity: capacity, leak_rate: leak_rate},
      data: %{level: 0.0},
      last_update: now_ms()
    }
  end

  @doc """
  Creates a fixed window rate limiter.

  Simple counting within fixed time intervals.
  Resets completely at window boundaries.

  ## Options

  - `:max_requests` - Maximum requests per window (default: 100)
  - `:window_ms` - Window size in milliseconds (default: 60_000)

  ## Examples

      # Max 1000 requests per hour
      RateLimiter.fixed_window(max_requests: 1000, window_ms: 3_600_000)
  """
  @spec fixed_window(keyword()) :: state()
  def fixed_window(opts \\ []) do
    max_requests = Keyword.get(opts, :max_requests, 100)
    window_ms = Keyword.get(opts, :window_ms, 60_000)
    now = now_ms()

    %{
      algorithm: :fixed_window,
      config: %{max_requests: max_requests, window_ms: window_ms},
      data: %{count: 0, window_start: window_start(now, window_ms)},
      last_update: now
    }
  end

  # ============================================================================
  # Core Operations
  # ============================================================================

  @doc """
  Checks if a request should be allowed.

  Returns `{:allow, new_state}` if allowed, or
  `{:deny, new_state, retry_after_ms}` if denied.

  ## Options

  - `:cost` - Cost of this request in tokens/slots (default: 1)
  - `:now` - Current time in ms (default: System.monotonic_time(:millisecond))

  ## Examples

      case RateLimiter.check(state) do
        {:allow, new_state} ->
          # Proceed with request
          {:ok, new_state}

        {:deny, new_state, retry_after} ->
          # Rate limited
          {:error, {:rate_limited, retry_after}, new_state}
      end

      # Custom cost
      RateLimiter.check(state, cost: 5)
  """
  @spec check(state(), keyword()) :: check_result()
  def check(state, opts \\ []) do
    cost = Keyword.get(opts, :cost, 1)
    now = Keyword.get(opts, :now, now_ms())

    state
    |> update_state(now)
    |> do_check(cost, now)
  end

  @doc """
  Checks if a request would be allowed without consuming resources.

  Useful for checking rate limit status before performing expensive operations.

  ## Examples

      if RateLimiter.would_allow?(state) do
        expensive_operation()
      else
        :rate_limited
      end
  """
  @spec would_allow?(state(), keyword()) :: boolean()
  def would_allow?(state, opts \\ []) do
    cost = Keyword.get(opts, :cost, 1)
    now = Keyword.get(opts, :now, now_ms())

    state
    |> update_state(now)
    |> can_allow?(cost)
  end

  @doc """
  Gets current rate limiter status.

  Returns information about the current state:
  - `:remaining` - Remaining capacity
  - `:limit` - Maximum capacity
  - `:reset_ms` - Milliseconds until reset/refill

  ## Examples

      status = RateLimiter.status(state)
      # %{remaining: 8, limit: 10, reset_ms: 1000}
  """
  @spec status(state(), keyword()) :: map()
  def status(state, opts \\ []) do
    now = Keyword.get(opts, :now, now_ms())
    updated = update_state(state, now)
    get_status(updated, now)
  end

  @doc """
  Resets the rate limiter to initial state.

  ## Examples

      new_state = RateLimiter.reset(state)
  """
  @spec reset(state()) :: state()
  def reset(%{algorithm: :token_bucket, config: config}) do
    token_bucket(capacity: config.capacity, refill_rate: config.refill_rate)
  end

  def reset(%{algorithm: :sliding_window, config: config}) do
    sliding_window(max_requests: config.max_requests, window_ms: config.window_ms)
  end

  def reset(%{algorithm: :leaky_bucket, config: config}) do
    leaky_bucket(capacity: config.capacity, leak_rate: config.leak_rate)
  end

  def reset(%{algorithm: :fixed_window, config: config}) do
    fixed_window(max_requests: config.max_requests, window_ms: config.window_ms)
  end

  # ============================================================================
  # Result Integration
  # ============================================================================

  @doc """
  Wraps check result in Result type.

  Returns `{:ok, new_state}` or `{:error, {:rate_limited, retry_after}}`.

  ## Examples

      case RateLimiter.check_result(state) do
        {:ok, new_state} -> proceed(new_state)
        {:error, {:rate_limited, ms}} -> retry_later(ms)
      end
  """
  @spec check_result(state(), keyword()) :: Result.t(state(), {:rate_limited, non_neg_integer()})
  def check_result(state, opts \\ []) do
    case check(state, opts) do
      {:allow, new_state} ->
        {:ok, new_state}

      {:deny, _new_state, retry_after} ->
        {:error, {:rate_limited, retry_after}}
    end
  end

  @doc """
  Executes action if rate limit allows.

  ## Examples

      RateLimiter.with_limit(state, fn ->
        make_api_call()
      end)
      |> case do
        {:ok, result, new_state} -> {:ok, result, new_state}
        {:error, {:rate_limited, ms}, state} -> {:retry, ms, state}
      end
  """
  @spec with_limit(state(), (-> result), keyword()) ::
          {:ok, result, state()} | {:error, {:rate_limited, non_neg_integer()}, state()}
        when result: any()
  def with_limit(state, fun, opts \\ []) when is_function(fun, 0) do
    case check(state, opts) do
      {:allow, new_state} ->
        result = fun.()
        {:ok, result, new_state}

      {:deny, new_state, retry_after} ->
        {:error, {:rate_limited, retry_after}, new_state}
    end
  end

  # ============================================================================
  # Composition
  # ============================================================================

  @doc """
  Creates a composite rate limiter that checks multiple limits.

  All limits must pass for the request to be allowed.
  Useful for tiered limits (e.g., per-second AND per-minute).

  ## Examples

      # 10/second AND 100/minute
      per_second = RateLimiter.token_bucket(capacity: 10, refill_rate: 10)
      per_minute = RateLimiter.sliding_window(max_requests: 100, window_ms: 60_000)

      composite = RateLimiter.compose([per_second, per_minute])

      case RateLimiter.check(composite) do
        {:allow, new_composite} -> proceed()
        {:deny, new_composite, retry_after} -> wait(retry_after)
      end
  """
  @spec compose([state()]) :: state()
  def compose(limiters) when is_list(limiters) do
    %{
      algorithm: :composite,
      config: %{},
      data: %{limiters: limiters},
      last_update: now_ms()
    }
  end

  # ============================================================================
  # Private - State Updates
  # ============================================================================

  defp update_state(%{algorithm: :token_bucket} = state, now) do
    elapsed_ms = now - state.last_update
    elapsed_seconds = elapsed_ms / 1000.0

    tokens_to_add = elapsed_seconds * state.config.refill_rate
    new_tokens = min(state.data.tokens + tokens_to_add, state.config.capacity * 1.0)

    %{state | data: %{tokens: new_tokens}, last_update: now}
  end

  defp update_state(%{algorithm: :sliding_window} = state, now) do
    window_start = now - state.config.window_ms
    new_timestamps = Enum.filter(state.data.timestamps, &(&1 >= window_start))

    %{state | data: %{timestamps: new_timestamps}, last_update: now}
  end

  defp update_state(%{algorithm: :leaky_bucket} = state, now) do
    elapsed_ms = now - state.last_update
    elapsed_seconds = elapsed_ms / 1000.0

    leaked = elapsed_seconds * state.config.leak_rate
    new_level = max(0.0, state.data.level - leaked)

    %{state | data: %{level: new_level}, last_update: now}
  end

  defp update_state(%{algorithm: :fixed_window} = state, now) do
    window_ms = state.config.window_ms
    current_window_start = window_start(now, window_ms)

    if current_window_start > state.data.window_start do
      # New window, reset count
      %{state | data: %{count: 0, window_start: current_window_start}, last_update: now}
    else
      %{state | last_update: now}
    end
  end

  defp update_state(%{algorithm: :composite} = state, now) do
    new_limiters = Enum.map(state.data.limiters, &update_state(&1, now))
    %{state | data: %{limiters: new_limiters}, last_update: now}
  end

  # ============================================================================
  # Private - Check Logic
  # ============================================================================

  defp do_check(%{algorithm: :token_bucket} = state, cost, _now) do
    if state.data.tokens >= cost do
      new_state = %{state | data: %{tokens: state.data.tokens - cost}}
      {:allow, new_state}
    else
      tokens_needed = cost - state.data.tokens
      retry_after = ceil(tokens_needed / state.config.refill_rate * 1000)
      {:deny, state, retry_after}
    end
  end

  defp do_check(%{algorithm: :sliding_window} = state, cost, now) do
    current_count = length(state.data.timestamps)

    if current_count + cost <= state.config.max_requests do
      new_timestamps = add_timestamps(state.data.timestamps, now, cost)
      new_state = %{state | data: %{timestamps: new_timestamps}}
      {:allow, new_state}
    else
      # Find when oldest request will expire
      oldest = List.first(state.data.timestamps)
      retry_after = if oldest, do: max(0, oldest + state.config.window_ms - now), else: 0
      {:deny, state, retry_after}
    end
  end

  defp do_check(%{algorithm: :leaky_bucket} = state, cost, _now) do
    new_level = state.data.level + cost

    if new_level <= state.config.capacity do
      new_state = %{state | data: %{level: new_level}}
      {:allow, new_state}
    else
      overflow = new_level - state.config.capacity
      retry_after = ceil(overflow / state.config.leak_rate * 1000)
      {:deny, state, retry_after}
    end
  end

  defp do_check(%{algorithm: :fixed_window} = state, cost, now) do
    if state.data.count + cost <= state.config.max_requests do
      new_state = %{state | data: %{state.data | count: state.data.count + cost}}
      {:allow, new_state}
    else
      window_end = state.data.window_start + state.config.window_ms
      retry_after = max(0, window_end - now)
      {:deny, state, retry_after}
    end
  end

  defp do_check(%{algorithm: :composite} = state, cost, now) do
    {results, new_limiters} =
      state.data.limiters
      |> Enum.map(fn limiter -> do_check(limiter, cost, now) end)
      |> Enum.map_reduce([], fn
        {:allow, new_limiter}, acc -> {:allow, [new_limiter | acc]}
        {:deny, new_limiter, _retry} = deny, acc -> {deny, [new_limiter | acc]}
      end)

    new_limiters = Enum.reverse(new_limiters)
    new_state = %{state | data: %{limiters: new_limiters}}

    # Find any denials
    denials = Enum.filter(results, &match?({:deny, _, _}, &1))

    case denials do
      [] ->
        {:allow, new_state}

      _ ->
        # Return max retry_after from all denials
        max_retry = denials |> Enum.map(fn {:deny, _, r} -> r end) |> Enum.max()
        {:deny, new_state, max_retry}
    end
  end

  # ============================================================================
  # Private - Helpers
  # ============================================================================

  defp can_allow?(%{algorithm: :token_bucket} = state, cost) do
    state.data.tokens >= cost
  end

  defp can_allow?(%{algorithm: :sliding_window} = state, cost) do
    length(state.data.timestamps) + cost <= state.config.max_requests
  end

  defp can_allow?(%{algorithm: :leaky_bucket} = state, cost) do
    state.data.level + cost <= state.config.capacity
  end

  defp can_allow?(%{algorithm: :fixed_window} = state, cost) do
    state.data.count + cost <= state.config.max_requests
  end

  defp can_allow?(%{algorithm: :composite} = state, cost) do
    Enum.all?(state.data.limiters, &can_allow?(&1, cost))
  end

  defp get_status(%{algorithm: :token_bucket} = state, _now) do
    tokens_for_full = state.config.capacity - state.data.tokens

    reset_ms =
      if tokens_for_full > 0, do: ceil(tokens_for_full / state.config.refill_rate * 1000), else: 0

    %{
      remaining: trunc(state.data.tokens),
      limit: state.config.capacity,
      reset_ms: reset_ms
    }
  end

  defp get_status(%{algorithm: :sliding_window} = state, now) do
    count = length(state.data.timestamps)
    oldest = List.first(state.data.timestamps)
    reset_ms = if oldest, do: max(0, oldest + state.config.window_ms - now), else: 0

    %{
      remaining: state.config.max_requests - count,
      limit: state.config.max_requests,
      reset_ms: reset_ms
    }
  end

  defp get_status(%{algorithm: :leaky_bucket} = state, _now) do
    drain_time =
      if state.data.level > 0, do: ceil(state.data.level / state.config.leak_rate * 1000), else: 0

    %{
      remaining: trunc(state.config.capacity - state.data.level),
      limit: state.config.capacity,
      reset_ms: drain_time
    }
  end

  defp get_status(%{algorithm: :fixed_window} = state, now) do
    window_end = state.data.window_start + state.config.window_ms

    %{
      remaining: state.config.max_requests - state.data.count,
      limit: state.config.max_requests,
      reset_ms: max(0, window_end - now)
    }
  end

  defp get_status(%{algorithm: :composite} = state, now) do
    # Return minimum remaining across all limiters
    statuses = Enum.map(state.data.limiters, &get_status(&1, now))
    min_remaining = statuses |> Enum.map(& &1.remaining) |> Enum.min()
    max_reset = statuses |> Enum.map(& &1.reset_ms) |> Enum.max()

    %{
      remaining: min_remaining,
      limit: nil,
      reset_ms: max_reset,
      details: statuses
    }
  end

  defp add_timestamps(timestamps, now, 1), do: timestamps ++ [now]
  defp add_timestamps(timestamps, now, cost), do: timestamps ++ List.duplicate(now, cost)

  defp window_start(now, window_ms) do
    div(now, window_ms) * window_ms
  end

  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end
