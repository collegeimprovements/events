defmodule OmScheduler.Drainer do
  @moduledoc """
  Graceful shutdown for the scheduler.

  The drainer allows for a clean shutdown by:
  1. Pausing all queues (stop accepting new jobs)
  2. Waiting for running jobs to complete
  3. Timing out after a configurable grace period

  ## Usage

  Add to your application's stop callback:

      def stop(_state) do
        OmScheduler.Drainer.drain()
      end

  Or with options:

      OmScheduler.Drainer.drain(timeout: 30_000)

  ## Configuration

  The default timeout is configured via:

      config :om_scheduler,
        shutdown_grace_period: {15, :seconds}
  """

  require Logger

  alias OmScheduler.{Config, Queue}

  @default_timeout 15_000
  @poll_interval 100

  @doc """
  Drains all queues, waiting for running jobs to complete.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: from config or 15s)
  - `:queues` - Specific queues to drain (default: all)

  ## Returns

  - `:ok` - All jobs completed within timeout
  - `{:timeout, running_count}` - Some jobs still running after timeout
  """
  @spec drain(keyword()) :: :ok | {:timeout, non_neg_integer()}
  def drain(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, get_default_timeout())
    queues = Keyword.get(opts, :queues, :all)

    Logger.info("[Scheduler.Drainer] Starting graceful shutdown, timeout=#{timeout}ms")

    # Step 1: Pause all queues to stop accepting new jobs
    pause_queues(queues)

    # Step 2: Wait for running jobs to complete
    deadline = System.monotonic_time(:millisecond) + timeout
    result = wait_for_completion(deadline, queues)

    case result do
      :ok ->
        Logger.info("[Scheduler.Drainer] All jobs completed, shutdown complete")
        :ok

      {:timeout, count} ->
        Logger.warning("[Scheduler.Drainer] Timeout reached with #{count} jobs still running")
        {:timeout, count}
    end
  end

  @doc """
  Pauses all queues, preventing new jobs from being picked up.
  """
  @spec pause(keyword()) :: :ok
  def pause(opts \\ []) do
    queues = Keyword.get(opts, :queues, :all)
    pause_queues(queues)
    :ok
  end

  @doc """
  Resumes all paused queues.
  """
  @spec resume(keyword()) :: :ok
  def resume(opts \\ []) do
    queues = Keyword.get(opts, :queues, :all)
    resume_queues(queues)
    :ok
  end

  @doc """
  Returns the number of currently running jobs across all queues.
  """
  @spec running_count(keyword()) :: non_neg_integer()
  def running_count(opts \\ []) do
    queues = Keyword.get(opts, :queues, :all)
    get_running_count(queues)
  end

  @doc """
  Checks if all queues are drained (no running jobs).
  """
  @spec drained?(keyword()) :: boolean()
  def drained?(opts \\ []) do
    running_count(opts) == 0
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp get_default_timeout do
    case Config.get()[:shutdown_grace_period] do
      nil -> @default_timeout
      ms when is_integer(ms) -> ms
      {n, unit} -> Config.to_ms({n, unit})
    end
  end

  defp pause_queues(:all) do
    get_all_queues()
    |> Enum.each(&pause_queue/1)
  end

  defp pause_queues(queues) when is_list(queues) do
    Enum.each(queues, &pause_queue/1)
  end

  defp pause_queue(queue) do
    case Queue.Supervisor.get_producer(queue) do
      nil -> :ok
      pid -> GenServer.call(pid, :pause, 5000)
    end
  rescue
    _ -> :ok
  end

  defp resume_queues(:all) do
    get_all_queues()
    |> Enum.each(&resume_queue/1)
  end

  defp resume_queues(queues) when is_list(queues) do
    Enum.each(queues, &resume_queue/1)
  end

  defp resume_queue(queue) do
    case Queue.Supervisor.get_producer(queue) do
      nil -> :ok
      pid -> GenServer.call(pid, :resume, 5000)
    end
  rescue
    _ -> :ok
  end

  defp get_all_queues do
    case Config.get()[:queues] do
      nil -> [:default]
      false -> []
      queues when is_list(queues) -> Keyword.keys(queues)
    end
  end

  defp wait_for_completion(deadline, queues) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      count = get_running_count(queues)
      if count == 0, do: :ok, else: {:timeout, count}
    else
      count = get_running_count(queues)

      if count == 0 do
        :ok
      else
        Logger.debug("[Scheduler.Drainer] Waiting for #{count} jobs to complete...")
        Process.sleep(@poll_interval)
        wait_for_completion(deadline, queues)
      end
    end
  end

  defp get_running_count(:all) do
    Queue.Supervisor.all_stats()
    |> Map.values()
    |> Enum.map(&Map.get(&1, :running, 0))
    |> Enum.sum()
  end

  defp get_running_count(queues) when is_list(queues) do
    stats = Queue.Supervisor.all_stats()

    queues
    |> Enum.map(fn queue ->
      case Map.get(stats, queue) do
        nil -> 0
        queue_stats -> Map.get(queue_stats, :running, 0)
      end
    end)
    |> Enum.sum()
  end
end
