defmodule Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket do
  @moduledoc """
  Token bucket rate limiting strategy.

  Implements standard token bucket algorithm with automatic refill.

  ## Algorithm

  - Each bucket has a maximum number of tokens
  - Tokens replenish at a fixed rate based on period
  - Each job execution consumes one token
  - When no tokens available, job is rescheduled

  ## Configuration

      config :events, Events.Infra.Scheduler,
        rate_limiter_strategy: Events.Infra.Scheduler.Strategies.RateLimiter.TokenBucket,
        rate_limits: [
          {:queue, :api, limit: 100, period: {1, :minute}},
          {:global, limit: 1000, period: {1, :minute}}
        ]
  """

  @behaviour Events.Infra.Scheduler.Strategies.RateLimiterStrategy

  require Logger

  alias Events.Infra.Scheduler.{Config, Telemetry}

  @type bucket :: %{
          tokens: float(),
          max_tokens: pos_integer(),
          refill_rate: float(),
          last_refill: integer()
        }

  # ============================================
  # Behaviour Implementation
  # ============================================

  @impl true
  def init(opts) do
    rate_limits = Keyword.get(opts, :rate_limits, [])
    buckets = initialize_buckets(rate_limits)

    Logger.debug("[RateLimiter.TokenBucket] Initialized with #{map_size(buckets)} bucket(s)")

    {:ok, %{buckets: buckets, config: rate_limits}}
  end

  @impl true
  def acquire(scope, key, state) do
    bucket_key = to_bucket_key(scope, key)

    case Map.get(state.buckets, bucket_key) do
      nil ->
        {:error, :not_configured, state}

      bucket ->
        {result, updated_bucket} = try_acquire(bucket)
        new_buckets = Map.put(state.buckets, bucket_key, updated_bucket)
        new_state = %{state | buckets: new_buckets}

        case result do
          :ok ->
            {:ok, new_state}

          {:rate_limited, retry_after} ->
            emit_rate_limit_event(bucket_key, retry_after)
            {:error, :rate_limited, retry_after, new_state}
        end
    end
  end

  @impl true
  def check(scope, key, state) do
    bucket_key = to_bucket_key(scope, key)

    case Map.get(state.buckets, bucket_key) do
      nil ->
        {:error, :not_configured, state}

      bucket ->
        bucket = refill_bucket(bucket)
        new_buckets = Map.put(state.buckets, bucket_key, bucket)
        new_state = %{state | buckets: new_buckets}

        case bucket.tokens >= 1.0 do
          true -> {:ok, new_state}
          false -> {:error, :rate_limited, calculate_retry_after(bucket), new_state}
        end
    end
  end

  @impl true
  def status(state) do
    state.buckets
    |> Enum.map(fn {key, bucket} ->
      bucket = refill_bucket(bucket)

      {key,
       %{
         tokens: bucket.tokens,
         max_tokens: bucket.max_tokens,
         available: bucket.tokens >= 1.0,
         refill_rate_per_second: bucket.refill_rate * 1000
       }}
    end)
    |> Map.new()
  end

  @impl true
  def acquire_for_job(job, state) do
    worker_module = get_worker_module(job)
    queue = get_queue(job)

    # Try to acquire in order: worker -> queue -> global
    with {:ok, state} <- acquire_if_configured(:worker, worker_module, state),
         {:ok, state} <- acquire_if_configured(:queue, queue, state),
         {:ok, state} <- acquire_if_configured(:global, nil, state) do
      {:ok, state}
    end
  end

  @impl true
  def tick(state) do
    # Refill all buckets
    updated_buckets =
      state.buckets
      |> Enum.map(fn {key, bucket} -> {key, refill_bucket(bucket)} end)
      |> Map.new()

    {:ok, %{state | buckets: updated_buckets}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp to_bucket_key(:global, _), do: :global
  defp to_bucket_key(:queue, queue), do: {:queue, queue}
  defp to_bucket_key(:worker, worker), do: {:worker, worker}

  defp initialize_buckets(rate_limits) do
    rate_limits
    |> Enum.map(&parse_rate_limit/1)
    |> Enum.filter(&(&1 != nil))
    |> Map.new()
  end

  defp parse_rate_limit({:queue, queue, opts}) do
    bucket = create_bucket(opts)
    {{:queue, queue}, bucket}
  end

  defp parse_rate_limit({:worker, worker, opts}) do
    bucket = create_bucket(opts)
    {{:worker, worker}, bucket}
  end

  defp parse_rate_limit({:global, opts}) do
    bucket = create_bucket(opts)
    {:global, bucket}
  end

  defp parse_rate_limit(_), do: nil

  defp create_bucket(opts) do
    limit = Keyword.fetch!(opts, :limit)
    period_ms = opts |> Keyword.fetch!(:period) |> Config.to_ms()

    # Refill rate: tokens per millisecond
    refill_rate = limit / period_ms

    %{
      tokens: limit * 1.0,
      max_tokens: limit,
      refill_rate: refill_rate,
      last_refill: System.monotonic_time(:millisecond)
    }
  end

  defp try_acquire(bucket) do
    bucket = refill_bucket(bucket)

    case bucket.tokens >= 1.0 do
      true ->
        {:ok, %{bucket | tokens: bucket.tokens - 1.0}}

      false ->
        retry_after = calculate_retry_after(bucket)
        {{:rate_limited, retry_after}, bucket}
    end
  end

  defp refill_bucket(bucket) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - bucket.last_refill
    new_tokens = min(bucket.max_tokens * 1.0, bucket.tokens + elapsed * bucket.refill_rate)

    %{bucket | tokens: new_tokens, last_refill: now}
  end

  defp calculate_retry_after(bucket) do
    # Time until 1 token is available
    tokens_needed = 1.0 - bucket.tokens
    max(1, round(tokens_needed / bucket.refill_rate))
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

  defp acquire_if_configured(scope, key, state) do
    case acquire(scope, key, state) do
      {:error, :not_configured, state} -> {:ok, state}
      result -> result
    end
  end

  defp emit_rate_limit_event(key, retry_after) do
    Telemetry.execute([:rate_limit, :exceeded], %{system_time: System.system_time()}, %{
      bucket: key,
      retry_after_ms: retry_after
    })
  end
end
