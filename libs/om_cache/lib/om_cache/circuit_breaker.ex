defmodule OmCache.CircuitBreaker do
  @moduledoc """
  Circuit breaker for cache operations with graceful degradation.

  Automatically disables cache and falls back to source when:
  - Cache connection fails repeatedly
  - Error rate exceeds threshold
  - Latency exceeds acceptable limits

  Implements the circuit breaker pattern with three states:
  - `:closed` - Normal operation, cache active
  - `:open` - Cache disabled, all requests go to fallback
  - `:half_open` - Testing if cache has recovered

  ## Usage

      # Start circuit breaker for a cache
      OmCache.CircuitBreaker.start_link(MyApp.Cache)

      # Use with automatic fallback
      OmCache.CircuitBreaker.call(MyApp.Cache, fn cache ->
        cache.get({User, 123})
      end, fallback: fn ->
        Repo.get(User, 123)
      end)

  ## Configuration

      config :om_cache, OmCache.CircuitBreaker,
        error_threshold: 5,           # Open after 5 consecutive errors
        error_timeout: 60_000,         # Reset error count after 1 minute
        open_timeout: 30_000,          # Try half-open after 30 seconds
        latency_threshold: 1000,       # Open if latency > 1s
        latency_sample_size: 10        # Sample last 10 operations
  """

  use GenServer
  require Logger

  @type state :: :closed | :open | :half_open
  @type circuit_state :: %{
          state: state(),
          cache: module(),
          error_count: non_neg_integer(),
          last_error_time: integer() | nil,
          last_state_change: integer(),
          latencies: [non_neg_integer()],
          config: map()
        }

  # Client API

  @doc """
  Starts a circuit breaker for the given cache.

  ## Options

  - `:error_threshold` - Number of consecutive errors before opening (default: 5)
  - `:error_timeout` - Time in ms to reset error count (default: 60_000)
  - `:open_timeout` - Time in ms before trying half-open (default: 30_000)
  - `:latency_threshold` - Max acceptable latency in ms (default: 1000)
  - `:latency_sample_size` - Number of latency samples to track (default: 10)
  """
  @spec start_link(module(), keyword()) :: GenServer.on_start()
  def start_link(cache, opts \\ []) do
    GenServer.start_link(__MODULE__, {cache, opts}, name: process_name(cache))
  end

  @doc """
  Calls a cache operation with automatic fallback if circuit is open.

  ## Options

  - `:fallback` - Function to call when circuit is open (required)
  - `:timeout` - Operation timeout in ms (default: 5000)

  ## Examples

      OmCache.CircuitBreaker.call(MyApp.Cache, fn cache ->
        cache.get({User, 123})
      end, fallback: fn ->
        Repo.get(User, 123)
      end)
  """
  @spec call(module(), (module() -> term()), keyword()) :: term()
  def call(cache, cache_fn, opts \\ []) when is_function(cache_fn, 1) do
    fallback_fn = Keyword.fetch!(opts, :fallback)
    timeout = Keyword.get(opts, :timeout, 5_000)

    case get_state(cache) do
      :closed ->
        execute_with_tracking(cache, cache_fn, fallback_fn, timeout)

      :half_open ->
        execute_with_tracking(cache, cache_fn, fallback_fn, timeout)

      :open ->
        Logger.debug("Circuit open for #{inspect(cache)}, using fallback")
        fallback_fn.()
    end
  end

  @doc """
  Gets the current circuit breaker state.

  ## Examples

      OmCache.CircuitBreaker.get_state(MyApp.Cache)
      #=> :closed
  """
  @spec get_state(module()) :: state()
  def get_state(cache) do
    GenServer.call(process_name(cache), :get_state)
  end

  @doc """
  Checks if the circuit is open.

  ## Examples

      OmCache.CircuitBreaker.open?(MyApp.Cache)
      #=> false
  """
  @spec open?(module()) :: boolean()
  def open?(cache) do
    get_state(cache) == :open
  end

  @doc """
  Manually resets the circuit breaker to closed state.

  ## Examples

      OmCache.CircuitBreaker.reset(MyApp.Cache)
      #=> :ok
  """
  @spec reset(module()) :: :ok
  def reset(cache) do
    GenServer.call(process_name(cache), :reset)
  end

  @doc """
  Gets circuit breaker statistics.

  ## Examples

      OmCache.CircuitBreaker.stats(MyApp.Cache)
      #=> %{
      #     state: :closed,
      #     error_count: 0,
      #     avg_latency_ms: 2.5,
      #     uptime_seconds: 3600
      #   }
  """
  @spec stats(module()) :: map()
  def stats(cache) do
    GenServer.call(process_name(cache), :stats)
  end

  # Server Callbacks

  @impl true
  def init({cache, opts}) do
    config = %{
      error_threshold: Keyword.get(opts, :error_threshold, 5),
      error_timeout: Keyword.get(opts, :error_timeout, 60_000),
      open_timeout: Keyword.get(opts, :open_timeout, 30_000),
      latency_threshold: Keyword.get(opts, :latency_threshold, 1_000),
      latency_sample_size: Keyword.get(opts, :latency_sample_size, 10)
    }

    state = %{
      state: :closed,
      cache: cache,
      error_count: 0,
      last_error_time: nil,
      last_state_change: System.monotonic_time(:millisecond),
      latencies: [],
      config: config
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Check if we should transition from open to half-open
    new_state =
      if state.state == :open do
        check_open_timeout(state)
      else
        state
      end

    {:reply, new_state.state, new_state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | state: :closed,
        error_count: 0,
        last_error_time: nil,
        last_state_change: System.monotonic_time(:millisecond),
        latencies: []
    }

    Logger.info("Circuit breaker reset for #{inspect(state.cache)}")
    {:reply, :ok, new_state}
  end

  def handle_call(:stats, _from, state) do
    uptime_ms = System.monotonic_time(:millisecond) - state.last_state_change
    avg_latency = calculate_avg_latency(state.latencies)

    stats = %{
      state: state.state,
      error_count: state.error_count,
      avg_latency_ms: avg_latency,
      uptime_seconds: div(uptime_ms, 1000)
    }

    {:reply, stats, state}
  end

  def handle_call({:record_success, latency_ms}, _from, state) do
    new_state =
      state
      |> record_latency(latency_ms)
      |> reset_errors_if_timeout()
      |> check_latency_threshold()
      |> maybe_close_circuit()

    {:reply, :ok, new_state}
  end

  def handle_call(:record_error, _from, state) do
    new_state =
      state
      |> increment_error_count()
      |> check_error_threshold()

    {:reply, :ok, new_state}
  end

  # Private Helpers

  defp process_name(cache), do: Module.concat(__MODULE__, cache)

  defp execute_with_tracking(cache, cache_fn, fallback_fn, timeout) do
    start_time = System.monotonic_time(:millisecond)
    task = Task.async(fn -> cache_fn.(cache) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        latency = System.monotonic_time(:millisecond) - start_time
        GenServer.call(process_name(cache), {:record_success, latency})
        result

      {:exit, reason} ->
        Logger.warning("Cache operation failed for #{inspect(cache)}: #{inspect(reason)}")
        GenServer.call(process_name(cache), :record_error)
        fallback_fn.()

      nil ->
        Logger.warning("Cache operation timeout for #{inspect(cache)}")
        GenServer.call(process_name(cache), :record_error)
        fallback_fn.()
    end
  end

  defp record_latency(state, latency_ms) do
    latencies = [latency_ms | state.latencies] |> Enum.take(state.config.latency_sample_size)
    %{state | latencies: latencies}
  end

  defp increment_error_count(state) do
    %{state | error_count: state.error_count + 1, last_error_time: System.monotonic_time(:millisecond)}
  end

  defp reset_errors_if_timeout(state) do
    if state.last_error_time do
      now = System.monotonic_time(:millisecond)
      elapsed = now - state.last_error_time

      if elapsed > state.config.error_timeout do
        %{state | error_count: 0, last_error_time: nil}
      else
        state
      end
    else
      state
    end
  end

  defp check_error_threshold(state) do
    if state.error_count >= state.config.error_threshold and state.state != :open do
      Logger.warning("Opening circuit breaker for #{inspect(state.cache)} (errors: #{state.error_count})")

      %{
        state
        | state: :open,
          last_state_change: System.monotonic_time(:millisecond)
      }
    else
      state
    end
  end

  defp check_latency_threshold(state) do
    avg_latency = calculate_avg_latency(state.latencies)

    if avg_latency > state.config.latency_threshold and state.state != :open do
      Logger.warning(
        "Opening circuit breaker for #{inspect(state.cache)} (latency: #{avg_latency}ms)"
      )

      %{
        state
        | state: :open,
          last_state_change: System.monotonic_time(:millisecond)
      }
    else
      state
    end
  end

  defp check_open_timeout(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_state_change

    if elapsed > state.config.open_timeout do
      Logger.info("Transitioning circuit breaker for #{inspect(state.cache)} to half-open")

      %{
        state
        | state: :half_open,
          error_count: 0,
          last_error_time: nil,
          last_state_change: now
      }
    else
      state
    end
  end

  defp maybe_close_circuit(state) do
    if state.state == :half_open and state.error_count == 0 do
      Logger.info("Closing circuit breaker for #{inspect(state.cache)}")

      %{
        state
        | state: :closed,
          last_state_change: System.monotonic_time(:millisecond)
      }
    else
      state
    end
  end

  defp calculate_avg_latency([]), do: 0.0

  defp calculate_avg_latency(latencies) do
    Enum.sum(latencies) / length(latencies)
  end
end
