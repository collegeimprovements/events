defmodule OmScheduler.Strategies.CircuitBreaker.Noop do
  @moduledoc """
  No-op circuit breaker implementation.

  Always allows execution without any circuit breaking logic.
  Useful for development, testing, or when circuit breaking is
  handled at a different layer.

  ## Configuration

      config :om_scheduler,
        circuit_breaker_strategy: OmScheduler.Strategies.CircuitBreaker.Noop
  """

  @behaviour OmScheduler.Strategies.CircuitBreakerStrategy

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def allow?(_circuit_name, state), do: {:ok, state}

  @impl true
  def record_success(_circuit_name, state), do: {:ok, state}

  @impl true
  def record_failure(_circuit_name, _error, state), do: {:ok, state}

  @impl true
  def get_state(_circuit_name, _state), do: nil

  @impl true
  def get_all_states(_state), do: %{}

  @impl true
  def reset(_circuit_name, state), do: {:ok, state}

  @impl true
  def register(_circuit_name, _opts, state), do: {:ok, state}
end
