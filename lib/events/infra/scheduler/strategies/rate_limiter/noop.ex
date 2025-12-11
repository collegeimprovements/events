defmodule Events.Infra.Scheduler.Strategies.RateLimiter.Noop do
  @moduledoc """
  No-op rate limiter implementation.

  Always allows execution without any rate limiting.
  Useful for development, testing, or when rate limiting is
  handled at a different layer.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        rate_limiter_strategy: Events.Infra.Scheduler.Strategies.RateLimiter.Noop
  """

  @behaviour Events.Infra.Scheduler.Strategies.RateLimiterStrategy

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
