defmodule OmScheduler.Lifeline do
  @moduledoc """
  Detects and rescues stuck jobs.

  Jobs can become "stuck" when:
  - A node crashes while executing a job
  - A job hangs without timeout
  - Network partition causes heartbeat loss

  The lifeline periodically:
  1. Checks for jobs with stale heartbeats
  2. Marks them for rescue (retry or discard)
  3. Cleans up orphaned locks

  ## Configuration

      config :om_scheduler,
        plugins: [
          {OmScheduler.Lifeline,
            interval: {30, :seconds},
            rescue_after: {5, :minutes}}
        ]

  ## How It Works

  When a job starts, the executor records a heartbeat. While running,
  the heartbeat is updated periodically. If the heartbeat becomes stale
  (older than `rescue_after`), the lifeline:

  1. Marks the execution as `:rescued`
  2. Schedules the job for retry (if retries remain)
  3. Releases any held locks
  """

  use GenServer
  require Logger

  alias OmScheduler.{Config, Telemetry}

  @type state :: %{
          interval: pos_integer(),
          rescue_after: pos_integer(),
          conf: keyword(),
          store: module()
        }

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts the lifeline process.

  ## Options

  - `:interval` - Check interval (default: 30 seconds)
  - `:rescue_after` - Rescue jobs stuck longer than this (default: 5 minutes)
  - `:conf` - Scheduler configuration
  """
  def start_link(opts) do
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
  Records a heartbeat for a running job.
  """
  @spec heartbeat(module(), String.t()) :: :ok | {:error, term()}
  def heartbeat(store, job_name) do
    store.record_heartbeat(job_name, node())
  end

  @doc """
  Manually triggers a rescue check.
  """
  @spec check_now(atom()) :: {:ok, non_neg_integer()}
  def check_now(name \\ __MODULE__) do
    GenServer.call(name, :check_now)
  end

  # ============================================
  # Plugin Behaviour
  # ============================================

  @doc false
  def prepare(opts) do
    {:ok, opts}
  end

  @doc false
  def validate(_opts) do
    :ok
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())

    interval = opts |> Keyword.get(:interval, {30, :seconds}) |> Config.to_ms()
    rescue_after = opts |> Keyword.get(:rescue_after, {5, :minutes}) |> Config.to_ms()

    state = %{
      interval: interval,
      rescue_after: rescue_after,
      conf: conf,
      store: Config.get_store_module(conf)
    }

    schedule_check(interval)

    Logger.debug(
      "[Scheduler.Lifeline] Started with interval=#{interval}ms rescue_after=#{rescue_after}ms"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check, state) do
    rescued_count = do_rescue_check(state)

    log_rescue_result(rescued_count)

    schedule_check(state.interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:check_now, _from, state) do
    rescued_count = do_rescue_check(state)
    {:reply, {:ok, rescued_count}, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp schedule_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp do_rescue_check(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.rescue_after, :millisecond)

    case state.store.get_stuck_executions(cutoff) do
      {:ok, stuck_executions} ->
        Enum.reduce(stuck_executions, 0, fn execution, count ->
          case rescue_execution(execution, state) do
            :ok -> count + 1
            {:error, _} -> count
          end
        end)

      {:error, reason} ->
        Logger.warning("[Scheduler.Lifeline] Failed to get stuck executions: #{inspect(reason)}")
        0
    end
  end

  defp rescue_execution(execution, state) do
    Logger.info(
      "[Scheduler.Lifeline] Rescuing stuck job: #{execution.job_name} " <>
        "(started: #{execution.started_at}, node: #{execution.node})"
    )

    Telemetry.execute([:job, :rescue], %{system_time: System.system_time()}, %{
      job_name: execution.job_name,
      execution_id: execution.id,
      node: execution.node,
      stuck_duration_ms: DateTime.diff(DateTime.utc_now(), execution.started_at, :millisecond)
    })

    with :ok <- state.store.mark_execution_rescued(execution.id),
         :ok <- state.store.release_lock(execution.job_name),
         :ok <- maybe_schedule_retry(execution, state) do
      :ok
    end
  end

  defp maybe_schedule_retry(execution, state) do
    case state.store.get_job(execution.job_name) do
      {:ok, job} ->
        case execution.attempt < job.max_retries do
          true ->
            next_run = DateTime.utc_now()

            state.store.update_job(job.name, %{
              next_run_at: next_run,
              last_error: "Rescued by lifeline (stuck)"
            })

            :ok

          false ->
            Logger.info("[Scheduler.Lifeline] Job #{job.name} exceeded max retries, discarding")
            :ok
        end

      {:error, :not_found} ->
        # Job was deleted, nothing to retry
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp log_rescue_result(0), do: :ok

  defp log_rescue_result(count) do
    Logger.info("[Scheduler.Lifeline] Rescued #{count} stuck job(s)")
  end
end
