defmodule OmScheduler.RateLimiter do
  @moduledoc """
  Rate limiting facade for scheduled jobs.

  This module provides backward-compatible API that delegates to
  `OmScheduler.Strategies.StrategyRunner`.

  ## Configuration

      config :om_scheduler,
        rate_limits: [
          # Queue-level: max 100 jobs per minute for :api queue
          {:queue, :api, limit: 100, period: {1, :minute}},

          # Worker-level: max 10 per hour for specific worker
          {:worker, MyApp.ExpensiveWorker, limit: 10, period: {1, :hour}},

          # Global: max 1000 jobs per minute across all queues
          {:global, limit: 1000, period: {1, :minute}}
        ]

  ## Algorithm

  Uses a token bucket by default:
  - Each bucket has a maximum number of tokens
  - Tokens replenish at a fixed rate
  - Each job execution consumes one token
  - When no tokens available, job is rescheduled

  ## Usage

      # Check before executing
      case RateLimiter.acquire(:queue, :api) do
        :ok -> execute_job()
        {:error, :rate_limited, retry_after_ms} -> reschedule(retry_after_ms)
      end

  ## Strategy-Based Architecture

  The actual rate limiting logic is now implemented via pluggable strategies.
  See `OmScheduler.Strategies.RateLimiterStrategy` for details.

  To use a custom rate limiter strategy:

      config :om_scheduler,
        strategies: [
          rate_limiter: MyApp.CustomRateLimiter
        ]
  """

  alias OmScheduler.Strategies.StrategyRunner

  @type bucket_key :: {:queue, atom()} | {:worker, module()} | :global

  # ============================================
  # Client API (delegates to StrategyRunner)
  # ============================================

  @doc """
  Attempts to acquire a token for the given scope.

  ## Examples

      RateLimiter.acquire(:queue, :default)
      RateLimiter.acquire(:worker, MyApp.ExpensiveWorker)
      RateLimiter.acquire(:global)

  ## Returns

  - `:ok` - Token acquired, proceed with execution
  - `{:error, :rate_limited, retry_after_ms}` - Rate limited, retry after delay
  """
  @spec acquire(atom(), atom() | module()) ::
          :ok | {:error, :rate_limited, pos_integer()}
  def acquire(scope, key \\ nil) do
    StrategyRunner.rate_acquire(scope, key)
  end

  @doc """
  Checks if a token is available without consuming it.
  """
  @spec check(atom(), atom() | module()) :: :ok | {:error, :rate_limited, pos_integer()}
  def check(scope, key \\ nil) do
    StrategyRunner.rate_check(scope, key)
  end

  @doc """
  Returns current bucket status for monitoring.
  """
  @spec status() :: map()
  def status do
    StrategyRunner.rate_status()
  end

  @doc """
  Checks rate limits for a job before execution.

  Checks in order: worker -> queue -> global
  Returns the first limit that blocks, or :ok if all pass.

  The second argument is ignored (kept for backward compatibility).
  """
  @spec check_job(map(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def check_job(job, _name \\ nil) do
    # Delegate to acquire_job since check_job is typically followed by acquire
    # and StrategyRunner combines them
    worker_module = get_worker_module(job)
    queue = get_queue(job)

    with :ok <- check_if_configured(:worker, worker_module),
         :ok <- check_if_configured(:queue, queue),
         :ok <- check_if_configured(:global, nil) do
      :ok
    end
  end

  @doc """
  Acquires tokens for a job before execution.

  Acquires in order: worker -> queue -> global
  If any fails, previously acquired tokens are not released (conservative).

  The second argument is ignored (kept for backward compatibility).
  """
  @spec acquire_job(map(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def acquire_job(job, _name \\ nil) do
    StrategyRunner.rate_acquire_for_job(job)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp check_if_configured(scope, key) do
    case StrategyRunner.rate_check(scope, key) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp get_worker_module(job) do
    case Map.get(job, :module) do
      nil -> nil
      module when is_atom(module) -> module
      module when is_binary(module) -> String.to_existing_atom("Elixir.#{module}")
    end
  rescue
    ArgumentError -> nil
  end

  defp get_queue(job) do
    case Map.get(job, :queue) do
      nil -> :default
      queue when is_atom(queue) -> queue
      queue when is_binary(queue) -> String.to_existing_atom(queue)
    end
  rescue
    ArgumentError -> :default
  end
end
