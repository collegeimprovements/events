defmodule OmIdempotency.HealthCheck do
  @moduledoc """
  Health check module for idempotency system.

  Monitors the health of the idempotency system by checking:
  - Database connectivity
  - Number of stale processing records
  - Number of expired records
  - Overall system statistics

  Can be integrated with Events.Observability.SystemHealth or used standalone.

  ## Examples

      HealthCheck.check()
      #=> {:ok, %{
        status: :healthy,
        stale_count: 2,
        expired_count: 150,
        stats: %{pending: 10, processing: 5, completed: 1000}
      }}
  """

  alias OmIdempotency
  alias OmIdempotency.Query
  alias FnTypes.Result

  @stale_threshold 10
  @expired_threshold 1000

  @doc """
  Performs a health check on the idempotency system.

  ## Options

  - `:repo` - Ecto repo module
  - `:stale_threshold` - Max stale records before unhealthy (default: 10)
  - `:expired_threshold` - Max expired records before warning (default: 1000)

  ## Returns

  - `{:ok, %{status: :healthy, ...}}` - System is healthy
  - `{:ok, %{status: :degraded, ...}}` - System has warnings
  - `{:error, %{status: :unhealthy, ...}}` - System is unhealthy
  """
  @spec check(keyword()) :: {:ok, map()} | {:error, map()}
  def check(opts \\ []) do
    stale_threshold = Keyword.get(opts, :stale_threshold, @stale_threshold)
    expired_threshold = Keyword.get(opts, :expired_threshold, @expired_threshold)

    {:ok, nil}
    |> Result.and_then(fn _ -> check_db_connection(opts) end)
    |> Result.and_then(fn _ -> check_stale_records(opts) end)
    |> Result.and_then(fn stale -> check_expired_records(stale, opts) end)
    |> Result.and_then(fn {stale, expired} -> check_stats({stale, expired}, opts) end)
    |> Result.map(fn {stale, expired, stats} ->
      determine_health_status(stale, expired, stats, stale_threshold, expired_threshold)
    end)
  rescue
    error ->
      {:error, %{
        status: :unhealthy,
        error: Exception.message(error),
        timestamp: DateTime.utc_now()
      }}
  end

  @doc """
  Quick health check that only tests database connectivity.
  """
  @spec quick_check(keyword()) :: :ok | {:error, term()}
  def quick_check(opts \\ []) do
    case check_db_connection(opts) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp check_db_connection(opts) do
    repo = OmIdempotency.repo(opts)

    case repo.query("SELECT 1") do
      {:ok, _} -> {:ok, :connected}
      {:error, reason} -> {:error, {:db_error, reason}}
    end
  rescue
    error -> {:error, {:db_exception, Exception.message(error)}}
  end

  defp check_stale_records(opts) do
    case Query.list_stale_processing(opts) do
      {:ok, stale_records} -> {:ok, length(stale_records)}
      {:error, reason} -> {:error, {:stale_check_failed, reason}}
    end
  end

  defp check_expired_records(stale_count, opts) do
    case Query.list_expired(opts) do
      {:ok, expired_records} -> {:ok, {stale_count, length(expired_records)}}
      {:error, reason} -> {:error, {:expired_check_failed, reason}}
    end
  end

  defp check_stats({stale_count, expired_count}, opts) do
    case Query.stats(opts) do
      {:ok, stats} -> {:ok, {stale_count, expired_count, stats}}
      {:error, reason} -> {:error, {:stats_check_failed, reason}}
    end
  end

  defp determine_health_status(stale_count, expired_count, stats, stale_threshold, expired_threshold) do
    cond do
      stale_count > stale_threshold ->
        {:error, %{
          status: :unhealthy,
          reason: "Too many stale processing records",
          stale_count: stale_count,
          expired_count: expired_count,
          stats: stats,
          timestamp: DateTime.utc_now()
        }}

      expired_count > expired_threshold ->
        {:ok, %{
          status: :degraded,
          reason: "High number of expired records (cleanup recommended)",
          stale_count: stale_count,
          expired_count: expired_count,
          stats: stats,
          timestamp: DateTime.utc_now()
        }}

      true ->
        {:ok, %{
          status: :healthy,
          stale_count: stale_count,
          expired_count: expired_count,
          stats: stats,
          timestamp: DateTime.utc_now()
        }}
    end
  end
end
