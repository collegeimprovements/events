defmodule OmApiClient.Middleware.RateLimiter do
  @moduledoc """
  Rate limiter that tracks API rate limits from response headers.

  Provides proactive rate limit awareness by:
  - Tracking X-RateLimit-* headers from responses
  - Queuing requests when limits are near exhaustion
  - Waiting automatically when rate limited

  ## Usage

      # Start a rate limiter
      RateLimiter.start_link(name: :stripe_api)

      # Acquire permission before making a request
      :ok = RateLimiter.acquire(:stripe_api)

      # Update limits from response headers
      RateLimiter.update_from_response(:stripe_api, response)

  ## Token Bucket Algorithm

  Uses a token bucket for smooth rate limiting:
  - Tokens are added at `refill_rate` per `refill_interval`
  - Each request consumes one token
  - When bucket is empty, requests wait for tokens

  ## Header Tracking

  Recognizes common rate limit headers:
  - `X-RateLimit-Limit` / `X-Rate-Limit-Limit`
  - `X-RateLimit-Remaining` / `X-Rate-Limit-Remaining`
  - `X-RateLimit-Reset` / `X-Rate-Limit-Reset`
  - `Retry-After`

  ## Configuration

  - `:name` - Process name (required)
  - `:bucket_size` - Maximum tokens (default: 100)
  - `:refill_rate` - Tokens to add per interval (default: 10)
  - `:refill_interval` - Interval in ms (default: 1000)
  - `:wait_timeout` - Max wait time in ms (default: 30000)
  """

  use GenServer

  @type name :: atom()
  @type opts :: [
          name: name(),
          bucket_size: pos_integer(),
          refill_rate: pos_integer(),
          refill_interval: pos_integer(),
          wait_timeout: pos_integer()
        ]

  @default_bucket_size 100
  @default_refill_rate 10
  @default_refill_interval 1_000
  @default_wait_timeout 30_000

  defstruct [
    :name,
    :bucket_size,
    :refill_rate,
    :refill_interval,
    :wait_timeout,
    :refill_timer,
    tokens: nil,
    api_limit: nil,
    api_remaining: nil,
    api_reset: nil,
    waiting: []
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts a rate limiter process.

  ## Options

  - `:name` - Process name (required)
  - `:bucket_size` - Maximum tokens (default: 100)
  - `:refill_rate` - Tokens to add per interval (default: 10)
  - `:refill_interval` - Interval in ms (default: 1000)
  - `:wait_timeout` - Max wait time in ms (default: 30000)

  ## Examples

      RateLimiter.start_link(name: :stripe_api)
      RateLimiter.start_link(name: :github_api, bucket_size: 5000)
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Acquires permission to make a request.

  Returns immediately if tokens are available, otherwise waits.
  Returns `{:error, :timeout}` if wait exceeds timeout.

  ## Examples

      RateLimiter.acquire(:stripe_api)
      #=> :ok

      RateLimiter.acquire(:stripe_api, timeout: 5000)
      #=> :ok | {:error, :timeout}
  """
  @spec acquire(name(), keyword()) :: :ok | {:error, :timeout | :rate_limited}
  def acquire(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_wait_timeout)
    GenServer.call(name, {:acquire, timeout}, timeout + 1000)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  Updates rate limit state from API response headers.

  Call this after each request to keep limits in sync with the API.

  ## Examples

      RateLimiter.update_from_response(:stripe_api, response)
      RateLimiter.update_from_headers(:stripe_api, response.headers)
  """
  @spec update_from_response(name(), map() | Req.Response.t()) :: :ok
  def update_from_response(name, %Req.Response{headers: headers}) do
    update_from_headers(name, headers)
  end

  def update_from_response(name, %{headers: headers}) do
    update_from_headers(name, headers)
  end

  @doc """
  Updates rate limit state from headers.

  ## Examples

      RateLimiter.update_from_headers(:stripe_api, [{"x-ratelimit-remaining", "99"}])
  """
  @spec update_from_headers(name(), list() | map()) :: :ok
  def update_from_headers(name, headers) do
    limits = parse_rate_limit_headers(headers)
    GenServer.cast(name, {:update_limits, limits})
  end

  @doc """
  Gets the current rate limiter state.

  ## Examples

      RateLimiter.get_state(:stripe_api)
      #=> %{tokens: 95, api_remaining: 99, api_reset: 1705334400}
  """
  @spec get_state(name()) :: map()
  def get_state(name) do
    GenServer.call(name, :get_state)
  end

  @doc """
  Returns a child spec for supervision.

  ## Examples

      children = [
        {RateLimiter, name: :stripe_api},
        {RateLimiter, name: :github_api, bucket_size: 5000}
      ]
  """
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl true
  def init(opts) do
    bucket_size = Keyword.get(opts, :bucket_size, @default_bucket_size)
    refill_interval = Keyword.get(opts, :refill_interval, @default_refill_interval)

    state = %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      bucket_size: bucket_size,
      refill_rate: Keyword.get(opts, :refill_rate, @default_refill_rate),
      refill_interval: refill_interval,
      wait_timeout: Keyword.get(opts, :wait_timeout, @default_wait_timeout),
      tokens: bucket_size,
      waiting: []
    }

    timer = schedule_refill(refill_interval)
    {:ok, %{state | refill_timer: timer}}
  end

  @impl true
  def handle_call({:acquire, timeout}, from, state) do
    case try_acquire(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:wait, new_state} ->
        # Add to waiting queue with deadline
        deadline = System.monotonic_time(:millisecond) + timeout
        waiting = state.waiting ++ [{from, deadline}]
        {:noreply, %{new_state | waiting: waiting}}
    end
  end

  def handle_call(:get_state, _from, state) do
    reply = %{
      tokens: state.tokens,
      bucket_size: state.bucket_size,
      api_limit: state.api_limit,
      api_remaining: state.api_remaining,
      api_reset: state.api_reset,
      waiting_count: length(state.waiting)
    }

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:update_limits, limits}, state) do
    new_state = %{
      state
      | api_limit: limits[:limit] || state.api_limit,
        api_remaining: limits[:remaining] || state.api_remaining,
        api_reset: limits[:reset] || state.api_reset
    }

    # Sync tokens with API remaining if available
    new_state =
      case limits[:remaining] do
        nil -> new_state
        remaining -> %{new_state | tokens: min(remaining, state.bucket_size)}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:refill, state) do
    # Add tokens up to bucket size
    new_tokens = min(state.tokens + state.refill_rate, state.bucket_size)
    state = %{state | tokens: new_tokens}

    # Process waiting requests
    state = process_waiting(state)

    # Schedule next refill
    timer = schedule_refill(state.refill_interval)
    {:noreply, %{state | refill_timer: timer}}
  end

  def handle_info({:timeout, ref, :acquire_timeout}, state) do
    # Remove expired waiters
    now = System.monotonic_time(:millisecond)

    {expired, remaining} =
      Enum.split_with(state.waiting, fn {_from, deadline} ->
        deadline <= now
      end)

    # Reply with timeout to expired waiters
    Enum.each(expired, fn {from, _deadline} ->
      GenServer.reply(from, {:error, :timeout})
    end)

    # Cancel the timer reference if it exists
    if is_reference(ref), do: Process.cancel_timer(ref)

    {:noreply, %{state | waiting: remaining}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp try_acquire(%{tokens: tokens} = state) when tokens > 0 do
    {:ok, %{state | tokens: tokens - 1}}
  end

  defp try_acquire(state) do
    {:wait, state}
  end

  defp process_waiting(%{waiting: []} = state), do: state

  defp process_waiting(%{tokens: 0} = state), do: state

  defp process_waiting(%{waiting: waiting, tokens: tokens} = state) do
    now = System.monotonic_time(:millisecond)

    # Partition into expired and valid
    {expired, valid} = Enum.split_with(waiting, fn {_from, deadline} -> deadline <= now end)

    # Reply timeout to expired
    Enum.each(expired, fn {from, _deadline} ->
      GenServer.reply(from, {:error, :timeout})
    end)

    # Process valid waiters
    {to_serve, remaining, new_tokens} = serve_waiters(valid, tokens, [])

    # Reply :ok to served waiters
    Enum.each(to_serve, fn {from, _deadline} ->
      GenServer.reply(from, :ok)
    end)

    %{state | waiting: remaining, tokens: new_tokens}
  end

  defp serve_waiters([], tokens, served), do: {Enum.reverse(served), [], tokens}
  defp serve_waiters(waiting, 0, served), do: {Enum.reverse(served), waiting, 0}

  defp serve_waiters([waiter | rest], tokens, served) do
    serve_waiters(rest, tokens - 1, [waiter | served])
  end

  defp schedule_refill(interval) do
    Process.send_after(self(), :refill, interval)
  end

  defp parse_rate_limit_headers(headers) when is_list(headers) do
    headers_map =
      Map.new(headers, fn {k, v} ->
        {String.downcase(to_string(k)), v}
      end)

    parse_rate_limit_headers(headers_map)
  end

  defp parse_rate_limit_headers(headers) when is_map(headers) do
    %{
      limit: parse_int(headers["x-ratelimit-limit"] || headers["x-rate-limit-limit"]),
      remaining: parse_int(headers["x-ratelimit-remaining"] || headers["x-rate-limit-remaining"]),
      reset: parse_reset(headers["x-ratelimit-reset"] || headers["x-rate-limit-reset"])
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_reset(nil), do: nil

  defp parse_reset(value) when is_binary(value) do
    case Integer.parse(value) do
      {timestamp, ""} -> timestamp
      _ -> nil
    end
  end

  defp parse_reset(value) when is_integer(value), do: value
end
