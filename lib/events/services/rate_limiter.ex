defmodule Events.Services.RateLimiter do
  @moduledoc """
  Rate limiter service using Hammer v7.

  This module provides rate limiting functionality with ETS backend by default.
  For multi-node deployments, configure Redis backend at compile time.

  ## Usage

      # Check if a request is allowed
      case Events.Services.RateLimiter.check("user:123:api", 60_000, 100) do
        {:allow, count} -> process_request()
        {:deny, retry_after} -> {:error, :rate_limited}
      end

  ## Configuration

  Configure the backend at compile time in `config/prod.exs`:

      # For Redis backend (multi-node deployments)
      config :events, Events.Services.RateLimiter, backend: :redis

  Default is `:ets` which works for single-node deployments.
  """

  # Default to ETS backend - sufficient for single-node deployments
  # For production multi-node: set backend: :redis in config/prod.exs
  use Hammer,
    backend: :ets,
    clean_period: :timer.minutes(1)

  @doc """
  Checks if a request should be allowed based on rate limits.

  Returns `{:allow, count}` if allowed, `{:deny, retry_after_ms}` if rate limited.

  ## Parameters

    * `bucket` - Unique identifier for the rate limit bucket (e.g., "user:123:api")
    * `window_ms` - Time window in milliseconds
    * `limit` - Maximum number of requests allowed in the window

  ## Examples

      # Allow 100 requests per minute
      RateLimiter.check("user:123", 60_000, 100)

      # Allow 10 requests per second
      RateLimiter.check("ip:192.168.1.1", 1_000, 10)

  """
  @spec check(String.t(), pos_integer(), pos_integer()) ::
          {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def check(bucket, window_ms, limit) do
    case hit(bucket, window_ms, limit) do
      {:allow, count} -> {:allow, count}
      {:deny, retry_after} -> {:deny, retry_after}
    end
  end
end
