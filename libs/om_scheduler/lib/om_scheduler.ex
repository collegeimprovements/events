defmodule OmScheduler do
  @moduledoc """
  Cron-based job scheduler with support for intervals, cron expressions,
  and multiple schedules.

  ## Quick Start

  ### 1. Configure

      # config/config.exs
      config :om_scheduler,
        enabled: true,
        store: :memory,  # or :database for production
        queues: [default: 10]

  ### 2. Define Jobs

      defmodule MyApp.Jobs do
        use OmScheduler

        @decorate scheduled(cron: "0 6 * * *")
        def daily_report do
          Reports.generate()
        end

        @decorate scheduled(every: {5, :minutes})
        def sync_inventory do
          Inventory.sync()
        end
      end

  ### 3. Start Scheduler

  Add to your application supervision tree:

      children = [
        # ... other children
        OmScheduler.Supervisor
      ]

  ## Decorator API

  Use `@decorate scheduled(...)` for simple jobs:

      @decorate scheduled(cron: @hourly)
      def aggregate_metrics, do: ...

      @decorate scheduled(every: {30, :seconds}, unique: true)
      def process_queue, do: ...

  ## Worker API

  Use `OmScheduler.Worker` for complex jobs:

      defmodule MyApp.ExportWorker do
        use OmScheduler.Worker

        @impl true
        def schedule, do: [cron: "0 3 * * *", max_retries: 5]

        @impl true
        def perform(%{attempt: attempt}) do
          # Complex logic here
        end
      end

  ## Runtime API

      Scheduler.insert(%{name: "cleanup", cron: "0 2 * * *", ...})
      Scheduler.pause_job("export")
      Scheduler.run_now("report")
      Scheduler.queue_stats()
  """

  alias OmScheduler.{Config, Job, Execution}
  alias OmScheduler.Queue.Producer

  # ============================================
  # Using Macro
  # ============================================

  @doc """
  Sets up a module for scheduled jobs.

  Imports cron macros (@hourly, @daily, etc.) and enables the
  `@decorate scheduled(...)` decorator.

  ## Example

      defmodule MyApp.Jobs do
        use OmScheduler

        @decorate scheduled(cron: @daily)
        def cleanup, do: ...
      end
  """
  defmacro __using__(_opts) do
    quote do
      use OmScheduler.Decorator
      use OmScheduler.Cron.Macros

      Module.register_attribute(__MODULE__, :__scheduled_jobs__, accumulate: true)

      @before_compile OmScheduler.Decorator.Scheduled
    end
  end

  # ============================================
  # Job CRUD
  # ============================================

  @doc """
  Inserts or updates a job.

  ## Examples

      Scheduler.insert(%{
        name: "cleanup",
        module: MyApp.Jobs,
        function: :cleanup,
        cron: "0 2 * * *"
      })
  """
  @spec insert(map()) :: {:ok, Job.t()} | {:error, term()}
  def insert(attrs) do
    with {:ok, job} <- Job.new(attrs) do
      store().register_job(job)
    end
  end

  @doc """
  Gets a job by name.
  """
  @spec get_job(String.t()) :: {:ok, Job.t()} | {:error, :not_found}
  def get_job(name) do
    store().get_job(name)
  end

  @doc """
  Lists all jobs.

  ## Options

  - `:queue` - Filter by queue
  - `:state` - Filter by state
  - `:tags` - Filter by tags
  - `:limit` - Max results
  """
  @spec all(keyword()) :: {:ok, [Job.t()]}
  def all(opts \\ []) do
    store().list_jobs(opts)
  end

  @doc """
  Updates a job by name.
  """
  @spec update(String.t(), map()) :: {:ok, Job.t()} | {:error, term()}
  def update(name, attrs) do
    store().update_job(name, attrs)
  end

  @doc """
  Deletes a job by name.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(name) do
    store().delete_job(name)
  end

  # ============================================
  # Job Control
  # ============================================

  @doc """
  Pauses a job (stops scheduling).
  """
  @spec pause_job(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def pause_job(name) do
    store().update_job(name, %{paused: true, state: :paused})
  end

  @doc """
  Resumes a paused job.
  """
  @spec resume_job(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def resume_job(name) do
    store().update_job(name, %{paused: false, state: :active})
  end

  @doc """
  Triggers immediate execution of a job.

  Bypasses the schedule and runs the job now.
  """
  @spec run_now(String.t()) :: {:ok, term()} | {:error, term()}
  def run_now(name) do
    with {:ok, job} <- get_job(name),
         producer_name <- Config.producer_name(job.queue),
         pid when is_pid(pid) <- Process.whereis(producer_name) do
      Producer.push(producer_name, job)
    else
      nil -> {:error, :no_producer}
      {:error, _} = error -> error
    end
  end

  @doc """
  Cancels a running job.

  If the job is currently executing, it will be terminated immediately.
  The job's next scheduled run will proceed as normal.

  ## Options

  - `:reason` - Cancellation reason (default: `:cancelled`)

  ## Examples

      Scheduler.cancel_job("long_running_export")
      Scheduler.cancel_job("report", reason: :timeout)
  """
  @spec cancel_job(String.t(), keyword()) :: :ok | {:error, :not_found | :not_running}
  def cancel_job(name, opts \\ []) do
    reason = Keyword.get(opts, :reason, :cancelled)

    with {:ok, job} <- get_job(name) do
      producer_name = Config.producer_name(job.queue)

      case Process.whereis(producer_name) do
        nil -> {:error, :not_found}
        _pid -> Producer.cancel(producer_name, name, reason)
      end
    end
  end

  @doc """
  Returns list of currently running jobs across all queues.
  """
  @spec running_jobs() :: [String.t()]
  def running_jobs do
    queue_stats()
    |> Enum.flat_map(fn {_queue, stats} -> Map.get(stats, :running_jobs, []) end)
  end

  # ============================================
  # Queue Management
  # ============================================

  @doc """
  Pauses a queue (stops processing).
  """
  @spec pause_queue(atom()) :: :ok | {:error, term()}
  def pause_queue(queue) do
    with_producer(queue, &Producer.pause/1)
  end

  @doc """
  Resumes a paused queue.
  """
  @spec resume_queue(atom()) :: :ok | {:error, term()}
  def resume_queue(queue) do
    with_producer(queue, &Producer.resume/1)
  end

  @doc """
  Scales queue concurrency.
  """
  @spec scale_queue(atom(), pos_integer()) :: :ok | {:error, term()}
  def scale_queue(queue, concurrency) when is_integer(concurrency) and concurrency > 0 do
    with_producer(queue, &Producer.scale(&1, concurrency))
  end

  @doc """
  Returns statistics for all queues.
  """
  @spec queue_stats() :: map()
  def queue_stats do
    OmScheduler.Queue.Supervisor.all_stats()
  end

  # ============================================
  # History & Monitoring
  # ============================================

  @doc """
  Gets execution history for a job.

  ## Options

  - `:limit` - Max results (default: 100)
  - `:since` - Only executions after this time
  - `:result` - Filter by result
  """
  @spec history(String.t(), keyword()) :: {:ok, [Execution.t()]}
  def history(name, opts \\ []) do
    store().get_executions(name, opts)
  end

  @doc """
  Gets status for a job.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(name) do
    case get_job(name) do
      {:ok, job} ->
        {:ok,
         %{
           name: job.name,
           state: job.state,
           enabled: job.enabled,
           paused: job.paused,
           last_run: job.last_run_at,
           next_run: job.next_run_at,
           run_count: job.run_count,
           error_count: job.error_count,
           last_result: job.last_result,
           last_error: job.last_error
         }}

      error ->
        error
    end
  end

  # ============================================
  # Cluster Info
  # ============================================

  @doc """
  Returns true if this node is the leader.
  """
  @spec is_leader?() :: boolean()
  def is_leader? do
    Config.get()[:peer] |> Config.leader?()
  end

  @doc """
  Returns the current leader node.
  """
  @spec leader_node() :: node() | nil
  def leader_node do
    case Config.get()[:peer] do
      false -> nil
      nil -> node()
      peer_module -> peer_module.get_leader()
    end
  end

  @doc """
  Returns all known peer nodes.
  """
  @spec peers() :: [map()]
  def peers do
    case Config.get()[:peer] do
      false -> []
      nil -> [%{node: node(), leader: true, started_at: nil}]
      peer_module -> peer_module.peers()
    end
  end

  # ============================================
  # Configuration
  # ============================================

  @doc """
  Returns the current scheduler configuration.
  """
  @spec config() :: keyword()
  def config, do: Config.get()

  # ============================================
  # Private Helpers
  # ============================================

  defp store do
    Config.get_store_module(Config.get())
  end

  defp with_producer(queue, fun) do
    producer_name = Config.producer_name(queue)

    case Process.whereis(producer_name) do
      nil -> {:error, :not_found}
      _pid -> fun.(producer_name)
    end
  end
end
