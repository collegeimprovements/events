defmodule OmScheduler.Plugins.Cron do
  @moduledoc """
  Plugin that schedules due jobs for execution.

  Periodically checks for jobs that are due and pushes them to their queues.
  Only runs on the leader node.

  ## Configuration

      config :om_scheduler,
        plugins: [
          {OmScheduler.Plugins.Cron,
            interval: {1, :second},
            limit: 100}
        ]

  ## Options

  - `:interval` - How often to check for due jobs (default: 1 second)
  - `:limit` - Max jobs to schedule per tick (default: 100)
  """

  use GenServer
  require Logger

  alias OmScheduler.{Config, Telemetry}
  alias OmScheduler.Queue.Producer

  @behaviour OmScheduler.Plugin

  @default_interval 1_000
  @default_limit 100

  # ============================================
  # Plugin Callbacks
  # ============================================

  @impl OmScheduler.Plugin
  def validate(opts) do
    with true <- is_nil(opts[:interval]) or Config.valid_duration?(opts[:interval]),
         true <- is_nil(opts[:limit]) or (is_integer(opts[:limit]) and opts[:limit] > 0) do
      :ok
    else
      _ -> {:error, "invalid Cron plugin options"}
    end
  end

  @impl OmScheduler.Plugin
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

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    conf = Keyword.get(opts, :conf, Config.get())

    state = %{
      name: Keyword.get(opts, :name, __MODULE__),
      interval: Config.to_ms(opts[:interval] || @default_interval),
      limit: opts[:limit] || @default_limit,
      store: Config.get_store_module(conf),
      peer: conf[:peer],
      conf: conf,
      scheduled_count: 0,
      last_run: nil
    }

    # Schedule first tick
    schedule_tick(state.interval)

    Logger.debug("[Scheduler.Plugins.Cron] Started with interval=#{state.interval}ms")

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    new_state =
      case Config.leader?(state.peer) do
        true -> schedule_due_jobs(state)
        false -> state
      end

    schedule_tick(state.interval)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      scheduled_count: state.scheduled_count,
      last_run: state.last_run,
      interval: state.interval,
      limit: state.limit
    }

    {:reply, stats, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp schedule_due_jobs(state) do
    now = DateTime.utc_now()

    case state.store.get_due_jobs(now, limit: state.limit) do
      {:ok, []} ->
        %{state | last_run: now}

      {:ok, jobs} ->
        scheduled =
          Enum.reduce(jobs, 0, fn job, count ->
            case push_to_queue(job, state) do
              :ok -> count + 1
              {:error, _} -> count
            end
          end)

        if scheduled > 0 do
          Logger.debug("[Scheduler.Plugins.Cron] Scheduled #{scheduled} jobs")
        end

        %{state | scheduled_count: state.scheduled_count + scheduled, last_run: now}

      {:error, reason} ->
        Logger.warning("[Scheduler.Plugins.Cron] Failed to get due jobs: #{inspect(reason)}")
        %{state | last_run: now}
    end
  end

  defp push_to_queue(job, state) do
    producer_name = Config.producer_name(job.queue)

    case Process.whereis(producer_name) do
      nil ->
        Logger.warning("[Scheduler.Plugins.Cron] No producer for queue #{job.queue}")
        {:error, :no_producer}

      _pid ->
        mark_and_push(job, producer_name, state)
    end
  end

  defp mark_and_push(job, producer_name, state) do
    case state.store.mark_running(job.name, node()) do
      {:ok, _} ->
        Producer.push(producer_name, job)

      {:error, :locked} ->
        Telemetry.job_skip(%{job: job, queue: job.queue}, :unique_conflict)
        {:error, :locked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
