defmodule Events.Types.Throttler do
  @moduledoc """
  Throttle mechanism - limits execution to once per interval.

  Throttling allows immediate execution but blocks subsequent calls until
  the interval has passed. Useful for scroll events, progress updates,
  API rate limiting, or any situation where you want regular execution
  at a maximum rate.

  ## Usage

      # Start a throttler (add to supervision tree for long-lived use)
      {:ok, throttler} = Throttler.start_link(interval: 1000)

      # First call executes immediately
      Throttler.call(throttler, fn -> update_progress() end)
      #=> {:ok, result}

      # Subsequent calls within interval are blocked
      Throttler.call(throttler, fn -> update_progress() end)
      #=> {:error, :throttled}

      # After interval passes, next call executes
      Process.sleep(1000)
      Throttler.call(throttler, fn -> update_progress() end)
      #=> {:ok, result}

  ## Supervision

      children = [
        {Events.Types.Throttler, name: :progress_throttler, interval: 100}
      ]

  ## Difference from Debounce

  - **Throttle**: Executes immediately, blocks subsequent calls for interval
  - **Debounce**: Waits for quiet period, then executes once

  Use throttle when you want regular execution at a maximum rate.
  Use debounce when you want to wait for activity to stop.
  """

  use GenServer

  @type t :: pid() | atom()

  @default_interval 100

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts a throttler process.

  ## Options

    * `:interval` - Minimum milliseconds between executions (default: 100)
    * `:name` - Optional name for the process (atom)

  ## Examples

      {:ok, throttler} = Throttler.start_link(interval: 1000)
      {:ok, throttler} = Throttler.start_link(interval: 500, name: :my_throttler)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    interval = Keyword.get(opts, :interval, @default_interval)

    GenServer.start_link(
      __MODULE__,
      %{interval: interval, last_run: 0},
      name: Keyword.get(opts, :name)
    )
  end

  @doc """
  Executes a function if the throttle interval has passed.

  Returns `{:ok, result}` if the function was executed, or
  `{:error, :throttled}` if called too soon after the last execution.

  ## Parameters

    * `throttler` - The throttler pid or name
    * `fun` - Zero-arity function to execute

  ## Examples

      case Throttler.call(throttler, fn -> expensive_operation() end) do
        {:ok, result} -> handle_result(result)
        {:error, :throttled} -> :skipped
      end
  """
  @spec call(t(), (-> result)) :: {:ok, result} | {:error, :throttled} when result: term()
  def call(throttler, fun) when is_function(fun, 0) do
    GenServer.call(throttler, {:throttle, fun})
  end

  @doc """
  Resets the throttler, allowing immediate execution of the next call.

  ## Examples

      Throttler.call(throttler, fn -> work() end)
      Throttler.reset(throttler)
      Throttler.call(throttler, fn -> work() end)  # Executes immediately
  """
  @spec reset(t()) :: :ok
  def reset(throttler) do
    GenServer.call(throttler, :reset)
  end

  @doc """
  Returns the time remaining until the next execution is allowed.

  Returns `0` if execution is allowed immediately.

  ## Examples

      Throttler.remaining(throttler)
      #=> 450  # 450ms until next allowed execution
  """
  @spec remaining(t()) :: non_neg_integer()
  def remaining(throttler) do
    GenServer.call(throttler, :remaining)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:throttle, fun}, _from, state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_run

    if elapsed >= state.interval do
      result = fun.()
      {:reply, {:ok, result}, %{state | last_run: now}}
    else
      {:reply, {:error, :throttled}, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | last_run: 0}}
  end

  @impl true
  def handle_call(:remaining, _from, state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_run
    remaining = max(0, state.interval - elapsed)
    {:reply, remaining, state}
  end
end
