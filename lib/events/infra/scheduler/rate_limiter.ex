defmodule Events.Infra.Scheduler.RateLimiter do
  @moduledoc """
  Token bucket rate limiting for scheduled jobs.

  Prevents job storms by limiting execution rate per queue or per worker.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        rate_limits: [
          # Queue-level: max 100 jobs per minute for :api queue
          {:queue, :api, limit: 100, period: {1, :minute}},

          # Worker-level: max 10 per hour for specific worker
          {:worker, MyApp.ExpensiveWorker, limit: 10, period: {1, :hour}},

          # Global: max 1000 jobs per minute across all queues
          {:global, limit: 1000, period: {1, :minute}}
        ]

  ## Algorithm

  Uses a sliding window token bucket:
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
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.{Config, Telemetry}

  @type bucket_key :: {:queue, atom()} | {:worker, module()} | :global
  @type bucket :: %{
          tokens: float(),
          max_tokens: pos_integer(),
          refill_rate: float(),
          last_refill: integer()
        }

  @type state :: %{
          buckets: %{bucket_key() => bucket()},
          config: keyword()
        }

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts the rate limiter process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Attempts to acquire a token for the given scope.

  ## Examples

      RateLimiter.acquire(:queue, :default)
      RateLimiter.acquire(:worker, MyApp.ExpensiveWorker)
      RateLimiter.acquire(:global)

  ## Returns

  - `:ok` - Token acquired, proceed with execution
  - `{:error, :rate_limited, retry_after_ms}` - Rate limited, retry after delay
  - `{:error, :not_configured}` - No rate limit configured for this scope
  """
  @spec acquire(atom(), atom() | module(), atom()) ::
          :ok | {:error, :rate_limited, pos_integer()} | {:error, :not_configured}
  def acquire(scope, key \\ nil, name \\ __MODULE__)

  def acquire(:global, _key, name) do
    GenServer.call(name, {:acquire, :global})
  end

  def acquire(:queue, queue, name) do
    GenServer.call(name, {:acquire, {:queue, queue}})
  end

  def acquire(:worker, worker, name) do
    GenServer.call(name, {:acquire, {:worker, worker}})
  end

  @doc """
  Checks if a token is available without consuming it.
  """
  @spec check(atom(), atom() | module(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def check(scope, key \\ nil, name \\ __MODULE__)

  def check(:global, _key, name) do
    GenServer.call(name, {:check, :global})
  end

  def check(:queue, queue, name) do
    GenServer.call(name, {:check, {:queue, queue}})
  end

  def check(:worker, worker, name) do
    GenServer.call(name, {:check, {:worker, worker}})
  end

  @doc """
  Returns current bucket status for monitoring.
  """
  @spec status(atom()) :: map()
  def status(name \\ __MODULE__) do
    GenServer.call(name, :status)
  end

  @doc """
  Checks rate limits for a job before execution.

  Checks in order: worker -> queue -> global
  Returns the first limit that blocks, or :ok if all pass.
  """
  @spec check_job(map(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def check_job(job, name \\ __MODULE__) do
    worker_module = get_worker_module(job)
    queue = get_queue(job)

    with :ok <- check_worker_limit(worker_module, name),
         :ok <- check_queue_limit(queue, name),
         :ok <- check_global_limit(name) do
      :ok
    end
  end

  @doc """
  Acquires tokens for a job before execution.

  Acquires in order: worker -> queue -> global
  If any fails, previously acquired tokens are not released (conservative).
  """
  @spec acquire_job(map(), atom()) :: :ok | {:error, :rate_limited, pos_integer()}
  def acquire_job(job, name \\ __MODULE__) do
    worker_module = get_worker_module(job)
    queue = get_queue(job)

    with :ok <- acquire_worker_limit(worker_module, name),
         :ok <- acquire_queue_limit(queue, name),
         :ok <- acquire_global_limit(name) do
      :ok
    end
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())
    rate_limits = Keyword.get(conf, :rate_limits, [])

    buckets = initialize_buckets(rate_limits)

    Logger.debug("[Scheduler.RateLimiter] Started with #{map_size(buckets)} bucket(s)")

    {:ok, %{buckets: buckets, config: rate_limits}}
  end

  @impl GenServer
  def handle_call({:acquire, key}, _from, state) do
    case Map.get(state.buckets, key) do
      nil ->
        {:reply, {:error, :not_configured}, state}

      bucket ->
        {result, updated_bucket} = try_acquire(bucket)
        new_buckets = Map.put(state.buckets, key, updated_bucket)

        case result do
          :ok ->
            {:reply, :ok, %{state | buckets: new_buckets}}

          {:rate_limited, retry_after} ->
            emit_rate_limit_event(key, retry_after)
            {:reply, {:error, :rate_limited, retry_after}, %{state | buckets: new_buckets}}
        end
    end
  end

  @impl GenServer
  def handle_call({:check, key}, _from, state) do
    case Map.get(state.buckets, key) do
      nil ->
        {:reply, :ok, state}

      bucket ->
        bucket = refill_bucket(bucket)
        new_buckets = Map.put(state.buckets, key, bucket)

        result =
          case bucket.tokens >= 1.0 do
            true -> :ok
            false -> {:error, :rate_limited, calculate_retry_after(bucket)}
          end

        {:reply, result, %{state | buckets: new_buckets}}
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status =
      state.buckets
      |> Enum.map(fn {key, bucket} ->
        bucket = refill_bucket(bucket)

        {key,
         %{
           tokens: bucket.tokens,
           max_tokens: bucket.max_tokens,
           available: bucket.tokens >= 1.0
         }}
      end)
      |> Map.new()

    {:reply, status, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

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
    round(tokens_needed / bucket.refill_rate)
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

  defp check_worker_limit(nil, _name), do: :ok

  defp check_worker_limit(worker, name) do
    case check(:worker, worker, name) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp check_queue_limit(queue, name) do
    case check(:queue, queue, name) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp check_global_limit(name) do
    case check(:global, nil, name) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp acquire_worker_limit(nil, _name), do: :ok

  defp acquire_worker_limit(worker, name) do
    case acquire(:worker, worker, name) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp acquire_queue_limit(queue, name) do
    case acquire(:queue, queue, name) do
      {:error, :not_configured} -> :ok
      result -> result
    end
  end

  defp acquire_global_limit(name) do
    case acquire(:global, nil, name) do
      {:error, :not_configured} -> :ok
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
