defmodule Events.Infra.Scheduler.Store.Memory do
  @moduledoc """
  ETS-based in-memory store for the scheduler.

  Suitable for development and testing. All data is lost on restart.

  ## Usage

      {:ok, _pid} = Store.Memory.start_link(name: :my_scheduler_store)
  """

  use GenServer
  require Logger

  alias Events.Infra.Scheduler.{Job, Execution}

  @behaviour Events.Infra.Scheduler.Store.Behaviour

  @jobs_table :scheduler_jobs_memory
  @executions_table :scheduler_executions_memory
  @locks_table :scheduler_locks_memory

  # ============================================
  # Client API
  # ============================================

  @doc """
  Starts the memory store.

  ## Options

  - `:name` - GenServer name (default: __MODULE__)
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

  # ============================================
  # Behaviour Implementation
  # ============================================

  @impl Events.Infra.Scheduler.Store.Behaviour
  def register_job(%Job{} = job) do
    case :ets.insert_new(@jobs_table, {job.name, job}) do
      true -> {:ok, job}
      false -> {:error, :already_exists}
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def get_job(name) when is_binary(name) do
    case :ets.lookup(@jobs_table, name) do
      [{^name, job}] -> {:ok, job}
      [] -> {:error, :not_found}
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def list_jobs(opts \\ []) do
    jobs =
      :ets.tab2list(@jobs_table)
      |> Enum.map(fn {_name, job} -> job end)
      |> filter_jobs(opts)
      |> paginate(opts)

    {:ok, jobs}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def update_job(name, attrs) when is_binary(name) and is_map(attrs) do
    case get_job(name) do
      {:ok, job} ->
        updated = struct(job, Map.to_list(attrs))
        :ets.insert(@jobs_table, {name, updated})
        {:ok, updated}

      error ->
        error
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def delete_job(name) when is_binary(name) do
    case :ets.delete(@jobs_table, name) do
      true -> :ok
      false -> {:error, :not_found}
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def get_due_jobs(now, opts \\ []) do
    queue = Keyword.get(opts, :queue)
    limit = Keyword.get(opts, :limit, 100)

    jobs =
      :ets.tab2list(@jobs_table)
      |> Enum.map(fn {_name, job} -> job end)
      |> Enum.filter(fn job ->
        Job.runnable?(job) and Job.due?(job, now) and
          (is_nil(queue) or job.queue == to_string(queue))
      end)
      |> Enum.sort_by(fn job -> {job.priority, job.next_run_at} end)
      |> Enum.take(limit)

    {:ok, jobs}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def mark_running(name, node) do
    case get_job(name) do
      {:ok, job} ->
        if job.unique do
          case acquire_unique_lock(job.name, to_string(node), job.timeout) do
            {:ok, _} ->
              updated = %{job | state: :active, last_run_at: DateTime.utc_now()}
              :ets.insert(@jobs_table, {name, updated})
              {:ok, updated}

            {:error, :locked} = error ->
              error
          end
        else
          updated = %{job | state: :active, last_run_at: DateTime.utc_now()}
          :ets.insert(@jobs_table, {name, updated})
          {:ok, updated}
        end

      error ->
        error
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def mark_completed(name, result, next_run_at) do
    case get_job(name) do
      {:ok, job} ->
        updated = %{
          job
          | run_count: job.run_count + 1,
            last_result: inspect(result),
            next_run_at: next_run_at
        }

        :ets.insert(@jobs_table, {name, updated})

        if job.unique do
          release_unique_lock(job.name, to_string(node()))
        end

        {:ok, updated}

      error ->
        error
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def mark_failed(name, reason, next_run_at) do
    case get_job(name) do
      {:ok, job} ->
        updated = %{
          job
          | error_count: job.error_count + 1,
            last_error: inspect(reason),
            next_run_at: next_run_at
        }

        :ets.insert(@jobs_table, {name, updated})

        if job.unique do
          release_unique_lock(job.name, to_string(node()))
        end

        {:ok, updated}

      error ->
        error
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def release_lock(name) do
    case get_job(name) do
      {:ok, job} ->
        if job.unique do
          release_unique_lock(job.name, to_string(node()))
        else
          :ok
        end

      {:error, _} ->
        :ok
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def mark_cancelled(name, reason) do
    with {:ok, job} <- get_job(name) do
      next_run = calculate_next_run(job)

      updated = %{
        job
        | last_error: "Cancelled: #{inspect(reason)}",
          next_run_at: next_run
      }

      :ets.insert(@jobs_table, {name, updated})

      if job.unique do
        release_unique_lock(job.name, to_string(node()))
      end

      {:ok, updated}
    end
  end

  defp calculate_next_run(job) do
    case Job.calculate_next_run(job, DateTime.utc_now()) do
      {:ok, next} -> next
      {:error, _} -> nil
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def record_execution_start(%Execution{} = execution) do
    execution =
      if is_nil(execution.id), do: %{execution | id: Ecto.UUID.generate()}, else: execution

    :ets.insert(@executions_table, {execution.id, execution})
    {:ok, execution}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def record_execution_complete(%Execution{} = execution) do
    :ets.insert(@executions_table, {execution.id, execution})
    {:ok, execution}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def get_executions(job_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)
    result_filter = Keyword.get(opts, :result)

    executions =
      :ets.tab2list(@executions_table)
      |> Enum.map(fn {_id, exec} -> exec end)
      |> Enum.filter(fn exec ->
        exec.job_name == job_name and
          (is_nil(since) or DateTime.compare(exec.started_at, since) == :gt) and
          (is_nil(result_filter) or exec.result == result_filter)
      end)
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
      |> Enum.take(limit)

    {:ok, executions}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def prune_executions(opts \\ []) do
    before = Keyword.get(opts, :before, DateTime.add(DateTime.utc_now(), -7, :day))
    limit = Keyword.get(opts, :limit, 10_000)

    to_delete =
      :ets.tab2list(@executions_table)
      |> Enum.filter(fn {_id, exec} ->
        DateTime.compare(exec.inserted_at || exec.started_at, before) == :lt
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {id, _exec} -> id end)

    Enum.each(to_delete, &:ets.delete(@executions_table, &1))

    {:ok, length(to_delete)}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def acquire_unique_lock(key, owner, ttl_ms) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl_ms, :millisecond)

    # Try to insert new lock
    case :ets.lookup(@locks_table, key) do
      [] ->
        :ets.insert(@locks_table, {key, %{owner: owner, expires_at: expires_at}})
        {:ok, key}

      [{^key, %{expires_at: existing_expires}}] ->
        # Check if existing lock is expired
        if DateTime.compare(existing_expires, now) == :lt do
          :ets.insert(@locks_table, {key, %{owner: owner, expires_at: expires_at}})
          {:ok, key}
        else
          {:error, :locked}
        end
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def release_unique_lock(key, owner) do
    case :ets.lookup(@locks_table, key) do
      [{^key, %{owner: ^owner}}] ->
        :ets.delete(@locks_table, key)
        :ok

      _ ->
        :ok
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def cleanup_expired_locks do
    now = DateTime.utc_now()

    to_delete =
      :ets.tab2list(@locks_table)
      |> Enum.filter(fn {_key, %{expires_at: expires_at}} ->
        DateTime.compare(expires_at, now) == :lt
      end)
      |> Enum.map(fn {key, _} -> key end)

    Enum.each(to_delete, &:ets.delete(@locks_table, &1))

    {:ok, length(to_delete)}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def check_unique_conflict(key, states, cutoff) do
    # Check if there's a lock for this key that's still valid
    now = DateTime.utc_now()

    conflict_exists =
      case :ets.lookup(@locks_table, key) do
        [{^key, %{expires_at: expires_at}}] ->
          # Lock exists and not expired
          valid_lock = DateTime.compare(expires_at, now) != :lt

          # Check cutoff if provided
          within_period =
            case cutoff do
              nil -> true
              cutoff_dt -> DateTime.compare(expires_at, cutoff_dt) != :lt
            end

          valid_lock and within_period

        [] ->
          # Also check executions table for running jobs
          :ets.tab2list(@executions_table)
          |> Enum.any?(fn {_id, exec} ->
            matches_key?(exec, key) and
              exec.state in states and
              within_cutoff?(exec, cutoff)
          end)
      end

    {:ok, conflict_exists}
  end

  defp matches_key?(exec, key) do
    # Simple match: job_name is the key
    exec.job_name == key
  end

  defp within_cutoff?(_exec, nil), do: true

  defp within_cutoff?(exec, cutoff) do
    DateTime.compare(exec.started_at, cutoff) != :lt
  end

  # ============================================
  # Lifeline / Heartbeat Operations
  # ============================================

  @impl Events.Infra.Scheduler.Store.Behaviour
  def record_heartbeat(job_name, _node) do
    now = DateTime.utc_now()

    # Find the running execution for this job and update heartbeat
    :ets.tab2list(@executions_table)
    |> Enum.find(fn {_id, exec} ->
      exec.job_name == job_name and exec.state == :running
    end)
    |> case do
      {id, exec} ->
        updated = %{exec | heartbeat_at: now}
        :ets.insert(@executions_table, {id, updated})
        :ok

      nil ->
        {:error, :not_found}
    end
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def get_stuck_executions(cutoff) do
    stuck =
      :ets.tab2list(@executions_table)
      |> Enum.map(fn {_id, exec} -> exec end)
      |> Enum.filter(fn exec ->
        exec.state == :running and
          not is_nil(exec.heartbeat_at) and
          DateTime.compare(exec.heartbeat_at, cutoff) == :lt
      end)

    {:ok, stuck}
  end

  @impl Events.Infra.Scheduler.Store.Behaviour
  def mark_execution_rescued(execution_id) do
    case :ets.lookup(@executions_table, execution_id) do
      [{^execution_id, exec}] ->
        rescued = Execution.mark_rescued(exec)
        :ets.insert(@executions_table, {execution_id, rescued})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(_opts) do
    # Create ETS tables if they don't exist
    create_table_if_not_exists(@jobs_table)
    create_table_if_not_exists(@executions_table)
    create_table_if_not_exists(@locks_table)

    {:ok, %{}}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp create_table_if_not_exists(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ref ->
        :ok
    end
  end

  defp filter_jobs(jobs, opts) do
    queue = Keyword.get(opts, :queue)
    state = Keyword.get(opts, :state)
    tags = Keyword.get(opts, :tags, [])

    jobs
    |> Enum.filter(fn job ->
      (is_nil(queue) or job.queue == to_string(queue)) and
        (is_nil(state) or job.state == state) and
        (tags == [] or Enum.any?(tags, &(&1 in job.tags)))
    end)
  end

  defp paginate(jobs, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    jobs
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end
end
