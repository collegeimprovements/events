defmodule OmScheduler.Strategies.RateLimiter.Noop do
  @moduledoc """
  No-op rate limiter implementation.

  Always allows execution without any rate limiting.
  Useful for development, testing, or when rate limiting is
  handled at a different layer.

  ## Configuration

      config :om_scheduler,
        rate_limiter_strategy: OmScheduler.Strategies.RateLimiter.Noop
  """

  @behaviour OmScheduler.Strategies.RateLimiterStrategy

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def acquire(_scope, _key, state), do: {:ok, state}

  @impl true
  def check(_scope, _key, state), do: {:ok, state}

  @impl true
  def status(_state), do: %{}

  @impl true
  def acquire_for_job(_job, state), do: {:ok, state}
end
