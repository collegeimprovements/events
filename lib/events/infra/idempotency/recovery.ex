defmodule Events.Infra.Idempotency.Recovery do
  @moduledoc """
  Recovery scheduler for idempotency records.

  Periodically:
  - Finds and releases stale processing records
  - Cleans up expired records

  ## Usage

  Add to your application supervision tree:

      children = [
        # Other children...
        {Events.Infra.Idempotency.Recovery, interval: {5, :minutes}}
      ]

  ## Options

  - `:interval` - How often to run recovery (default: 5 minutes)
  - `:cleanup_interval` - How often to run cleanup (default: 1 hour)
  - `:name` - Process name (default: __MODULE__)

  ## Manual Trigger

      Events.Infra.Idempotency.Recovery.recover_now()
      Events.Infra.Idempotency.Recovery.cleanup_now()
  """

  use GenServer
  require Logger

  alias Events.Infra.Idempotency

  @default_interval_ms 5 * 60 * 1000
  @default_cleanup_interval_ms 60 * 60 * 1000

  @type opts :: [
          interval: pos_integer() | {pos_integer(), atom()},
          cleanup_interval: pos_integer() | {pos_integer(), atom()},
          name: atom()
        ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts the recovery scheduler.

  ## Options

  - `:interval` - Recovery check interval (default: 5 minutes)
  - `:cleanup_interval` - Cleanup interval (default: 1 hour)
  - `:name` - Process name
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Triggers immediate recovery of stale records.

  ## Examples

      Recovery.recover_now()
      #=> {:ok, 3}
  """
  @spec recover_now(atom()) :: {:ok, non_neg_integer()}
  def recover_now(name \\ __MODULE__) do
    GenServer.call(name, :recover_now)
  end

  @doc """
  Triggers immediate cleanup of expired records.

  ## Examples

      Recovery.cleanup_now()
      #=> {:ok, 42}
  """
  @spec cleanup_now(atom()) :: {:ok, non_neg_integer()}
  def cleanup_now(name \\ __MODULE__) do
    GenServer.call(name, :cleanup_now)
  end

  @doc """
  Returns the current stats.

  ## Examples

      Recovery.stats()
      #=> %{last_recovery: ~U[...], last_cleanup: ~U[...], recovered: 10, cleaned: 50}
  """
  @spec stats(atom()) :: map()
  def stats(name \\ __MODULE__) do
    GenServer.call(name, :stats)
  end

  @doc """
  Returns a child spec for supervision.
  """
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
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
    interval = normalize_duration(Keyword.get(opts, :interval, @default_interval_ms))

    cleanup_interval =
      normalize_duration(Keyword.get(opts, :cleanup_interval, @default_cleanup_interval_ms))

    state = %{
      interval: interval,
      cleanup_interval: cleanup_interval,
      last_recovery: nil,
      last_cleanup: nil,
      total_recovered: 0,
      total_cleaned: 0
    }

    # Schedule first runs
    schedule_recovery(interval)
    schedule_cleanup(cleanup_interval)

    Logger.info(
      "[Idempotency.Recovery] Started with interval=#{interval}ms, cleanup_interval=#{cleanup_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:recover_now, _from, state) do
    {count, new_state} = do_recovery(state)
    {:reply, {:ok, count}, new_state}
  end

  def handle_call(:cleanup_now, _from, state) do
    {count, new_state} = do_cleanup(state)
    {:reply, {:ok, count}, new_state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      last_recovery: state.last_recovery,
      last_cleanup: state.last_cleanup,
      total_recovered: state.total_recovered,
      total_cleaned: state.total_cleaned,
      interval_ms: state.interval,
      cleanup_interval_ms: state.cleanup_interval
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:recover, state) do
    {_count, new_state} = do_recovery(state)
    schedule_recovery(state.interval)
    {:noreply, new_state}
  end

  def handle_info(:cleanup, state) do
    {_count, new_state} = do_cleanup(state)
    schedule_cleanup(state.cleanup_interval)
    {:noreply, new_state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp do_recovery(state) do
    {:ok, count} = Idempotency.recover_stale()

    new_state = %{
      state
      | last_recovery: DateTime.utc_now(),
        total_recovered: state.total_recovered + count
    }

    if count > 0 do
      emit_telemetry(:recovery, count)
    end

    {count, new_state}
  rescue
    error ->
      Logger.error("[Idempotency.Recovery] Recovery failed: #{Exception.message(error)}")
      {0, state}
  end

  defp do_cleanup(state) do
    {:ok, count} = Idempotency.cleanup_expired()

    new_state = %{
      state
      | last_cleanup: DateTime.utc_now(),
        total_cleaned: state.total_cleaned + count
    }

    if count > 0 do
      emit_telemetry(:cleanup, count)
    end

    {count, new_state}
  rescue
    error ->
      Logger.error("[Idempotency.Recovery] Cleanup failed: #{Exception.message(error)}")
      {0, state}
  end

  defp schedule_recovery(interval) do
    Process.send_after(self(), :recover, interval)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp normalize_duration({n, :second}), do: n * 1000
  defp normalize_duration({n, :seconds}), do: n * 1000
  defp normalize_duration({n, :minute}), do: n * 60 * 1000
  defp normalize_duration({n, :minutes}), do: n * 60 * 1000
  defp normalize_duration({n, :hour}), do: n * 60 * 60 * 1000
  defp normalize_duration({n, :hours}), do: n * 60 * 60 * 1000
  defp normalize_duration(ms) when is_integer(ms), do: ms

  defp emit_telemetry(event, count) do
    :telemetry.execute(
      [:events, :idempotency, :recovery, event],
      %{count: count},
      %{}
    )
  end
end
