defmodule Events.Infra.Scheduler.Strategies.RateLimiterStrategy do
  @moduledoc """
  Behaviour for rate limiting strategies.

  Enables pluggable rate limiter implementations. Implement this behaviour
  to provide custom rate limiting algorithms.

  ## Built-in Implementations

  - `Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket` - Standard token bucket
  - `Events.Infra.Scheduler.Strategies.RateLimiter.SlidingWindow` - Sliding window counter
  - `Events.Infra.Scheduler.Strategies.RateLimiter.Noop` - Pass-through (no limiting)

  ## Configuration

      config :events, Events.Infra.Scheduler,
        rate_limiter_strategy: Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket,
        rate_limits: [
          {:queue, :api, limit: 100, period: {1, :minute}},
          {:worker, MyApp.ExpensiveWorker, limit: 10, period: {1, :hour}},
          {:global, limit: 1000, period: {1, :minute}}
        ]

  ## Implementing a Custom Strategy

      defmodule MyApp.LeakyBucketRateLimiter do
        @behaviour Events.Infra.Scheduler.Strategies.RateLimiterStrategy

        @impl true
        def init(opts) do
          # Initialize leaky bucket state
        end

        @impl true
        def acquire(scope, key, state) do
          # Custom rate limiting logic
        end
      end
  """

  @type scope :: :global | :queue | :worker
  @type key :: atom() | module() | nil
  @type bucket_key :: {:queue, atom()} | {:worker, module()} | :global
  @type state :: map()
  @type opts :: keyword()

  @doc """
  Initializes the rate limiter strategy.

  Called once when the scheduler starts. Returns initial state.
  """
  @callback init(opts()) :: {:ok, state()} | {:error, term()}

  @doc """
  Attempts to acquire a token for the given scope.

  ## Returns

  - `{:ok, state}` - Token acquired, proceed with execution
  - `{:error, :rate_limited, retry_after_ms, state}` - Rate limited, retry after delay
  - `{:error, :not_configured, state}` - No rate limit configured for this scope
  """
  @callback acquire(scope(), key(), state()) ::
              {:ok, state()}
              | {:error, :rate_limited, pos_integer(), state()}
              | {:error, :not_configured, state()}

  @doc """
  Checks if a token is available without consuming it.

  Same return values as `acquire/3` but doesn't decrement tokens.
  """
  @callback check(scope(), key(), state()) ::
              {:ok, state()}
              | {:error, :rate_limited, pos_integer(), state()}
              | {:error, :not_configured, state()}

  @doc """
  Returns current bucket status for monitoring.

  Returns a map of bucket keys to their current state.
  """
  @callback status(state()) :: map()

  @doc """
  Acquires tokens for a job before execution.

  Checks in order: worker -> queue -> global.
  Returns first limit that blocks, or :ok if all pass.
  """
  @callback acquire_for_job(map(), state()) ::
              {:ok, state()} | {:error, :rate_limited, pos_integer(), state()}

  @doc """
  Called periodically to refill tokens or perform maintenance.
  """
  @callback tick(state()) :: {:ok, state()}

  @optional_callbacks [tick: 1]
end
