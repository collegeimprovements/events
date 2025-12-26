defmodule OmScheduler.Store.Database do
  @moduledoc """
  PostgreSQL-based store for the scheduler.

  Suitable for production deployments with persistence and clustering.

  ## Usage

      # In config
      config :my_app, OmScheduler,
        store: :database,
        repo: MyApp.Repo

  ## Configuration

  The default repo fallback is configurable via:

      config :om_scheduler.Store.Database, repo: MyApp.Repo

  Default repo fallback: `OmScheduler.Config.repo()`
  """

  import Ecto.Query
  require Logger

  alias OmScheduler.{Job, Execution, Config}
  alias OmScheduler.Workflow

  @behaviour OmScheduler.Store.Behaviour

  @default_repo Application.compile_env(:events, [__MODULE__, :repo], OmScheduler.Config.repo())

  # ETS table for workflow definitions (workflows are stored in memory only for now)
  @workflows_table :scheduler_workflows_database

  # ============================================
  # Configuration
  # ============================================

  defp repo do
    Config.get()[:repo] || @default_repo
  end

  defp prefix do
    Config.get()[:prefix] || "public"
  end

  defp ensure_workflows_table do
    case :ets.whereis(@workflows_table) do
      :undefined ->
        :ets.new(@workflows_table, [
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

  # ============================================
  # Workflow Operations (stored in ETS, not database for now)
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def register_workflow(%Workflow{} = workflow) do
    ensure_workflows_table()

    case :ets.insert_new(@workflows_table, {workflow.name, workflow}) do
      true -> {:ok, workflow}
      false -> {:error, :already_exists}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_workflow(name) when is_atom(name) do
    ensure_workflows_table()

    case :ets.lookup(@workflows_table, name) do
      [{^name, workflow}] -> {:ok, workflow}
      [] -> {:error, :not_found}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def list_workflows(opts \\ []) do
    ensure_workflows_table()

    tags = Keyword.get(opts, :tags, [])
    trigger_type = Keyword.get(opts, :trigger_type)

    :ets.tab2list(@workflows_table)
    |> Enum.map(fn {_name, workflow} ->
      %{
        name: workflow.name,
        steps: map_size(workflow.steps),
        trigger_type: workflow.trigger_type,
        schedule: workflow.schedule,
        tags: workflow.tags,
        state: workflow.state
      }
    end)
    |> Enum.filter(fn workflow_info ->
      (tags == [] or Enum.any?(tags, &(&1 in workflow_info.tags))) and
        (is_nil(trigger_type) or workflow_info.trigger_type == trigger_type)
    end)
  end

  @impl OmScheduler.Store.Behaviour
  def update_workflow(name, attrs) when is_atom(name) and is_map(attrs) do
    case get_workflow(name) do
      {:ok, workflow} ->
        updated = struct(workflow, Map.to_list(attrs))
        :ets.insert(@workflows_table, {name, updated})
        {:ok, updated}

      error ->
        error
    end
  end

  @impl OmScheduler.Store.Behaviour
  def delete_workflow(name) when is_atom(name) do
    ensure_workflows_table()

    case :ets.delete(@workflows_table, name) do
      true -> :ok
      false -> {:error, :not_found}
    end
  end

  # ============================================
  # Job Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def register_job(%Job{} = job) do
    job
    |> Job.changeset(Map.from_struct(job))
    |> repo().insert(prefix: prefix())
  end

  @impl OmScheduler.Store.Behaviour
  def get_job(name) when is_binary(name) do
    query = from(j in Job, where: j.name == ^name)

    case repo().one(query, prefix: prefix()) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def list_jobs(opts \\ []) do
    query = build_jobs_query(opts)
    jobs = repo().all(query, prefix: prefix())
    {:ok, jobs}
  end

  @impl OmScheduler.Store.Behaviour
  def update_job(name, attrs) when is_binary(name) and is_map(attrs) do
    case get_job(name) do
      {:ok, job} ->
        job
        |> Job.changeset(attrs)
        |> repo().update(prefix: prefix())

      error ->
        error
    end
  end

  @impl OmScheduler.Store.Behaviour
  def delete_job(name) when is_binary(name) do
    query = from(j in Job, where: j.name == ^name)

    case repo().delete_all(query, prefix: prefix()) do
      {0, _} -> {:error, :not_found}
      {_, _} -> :ok
    end
  end

  # ============================================
  # Scheduling Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def get_due_jobs(now, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(j in Job,
        where: j.enabled == true,
        where: j.paused == false,
        where: j.state == :active,
        where: j.next_run_at <= ^now,
        order_by: [asc: j.priority, asc: j.next_run_at],
        limit: ^limit
      )
      |> maybe_filter_queue(opts[:queue])

    {:ok, repo().all(query, prefix: prefix())}
  end

  defp maybe_filter_queue(query, nil), do: query
  defp maybe_filter_queue(query, queue), do: from(j in query, where: j.queue == ^to_string(queue))

  @impl OmScheduler.Store.Behaviour
  def mark_running(name, node) do
    with {:ok, job} <- get_job(name),
         :ok <- maybe_acquire_lock(job, node) do
      do_mark_running(job)
    end
  end

  defp maybe_acquire_lock(%Job{unique: false}, _node), do: :ok

  defp maybe_acquire_lock(%Job{unique: true, name: name, timeout: timeout}, node) do
    case acquire_unique_lock(name, to_string(node), timeout) do
      {:ok, _} -> :ok
      {:error, :locked} = error -> error
    end
  end

  defp do_mark_running(job) do
    job
    |> Job.execution_changeset(%{last_run_at: DateTime.utc_now()})
    |> repo().update(prefix: prefix())
  end

  @impl OmScheduler.Store.Behaviour
  def mark_completed(name, result, next_run_at) do
    with {:ok, job} <- get_job(name) do
      attrs = %{
        run_count: job.run_count + 1,
        last_result: truncate_string(inspect(result), 255),
        next_run_at: next_run_at
      }

      update_result =
        job
        |> Job.execution_changeset(attrs)
        |> repo().update(prefix: prefix())

      maybe_release_lock(job)
      update_result
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_failed(name, reason, next_run_at) do
    with {:ok, job} <- get_job(name) do
      attrs = %{
        error_count: job.error_count + 1,
        last_error: truncate_string(inspect(reason), 1000),
        next_run_at: next_run_at
      }

      update_result =
        job
        |> Job.execution_changeset(attrs)
        |> repo().update(prefix: prefix())

      maybe_release_lock(job)
      update_result
    end
  end

  defp maybe_release_lock(%Job{unique: true, name: name}) do
    release_unique_lock(name, to_string(node()))
  end

  defp maybe_release_lock(%Job{unique: false}), do: :ok

  @impl OmScheduler.Store.Behaviour
  def release_lock(name) do
    case get_job(name) do
      {:ok, job} -> maybe_release_lock(job)
      {:error, _} -> :ok
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_cancelled(name, reason) do
    with {:ok, job} <- get_job(name) do
      next_run = calculate_next_run(job)

      attrs = %{
        last_error: truncate_string("Cancelled: #{inspect(reason)}", 1000),
        next_run_at: next_run
      }

      update_result =
        job
        |> Job.execution_changeset(attrs)
        |> repo().update(prefix: prefix())

      maybe_release_lock(job)
      update_result
    end
  end

  defp calculate_next_run(job) do
    case Job.calculate_next_run(job, DateTime.utc_now()) do
      {:ok, next} -> next
      {:error, _} -> nil
    end
  end

  # ============================================
  # Execution History
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def record_execution_start(%Execution{} = execution) do
    execution
    |> Execution.changeset(Map.from_struct(execution))
    |> repo().insert(prefix: prefix())
  end

  @impl OmScheduler.Store.Behaviour
  def record_execution_complete(%Execution{id: id} = execution) when not is_nil(id) do
    query = from(e in Execution, where: e.id == ^id)

    case repo().one(query, prefix: prefix()) do
      nil ->
        # If not found, insert as new
        record_execution_start(execution)

      existing ->
        existing
        |> Execution.complete_changeset(Map.from_struct(execution))
        |> repo().update(prefix: prefix())
    end
  end

  def record_execution_complete(%Execution{} = execution) do
    record_execution_start(execution)
  end

  @impl OmScheduler.Store.Behaviour
  def get_executions(job_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from(e in Execution,
        where: e.job_name == ^job_name,
        order_by: [desc: e.started_at],
        limit: ^limit
      )
      |> maybe_filter_since(opts[:since])
      |> maybe_filter_result(opts[:result])

    {:ok, repo().all(query, prefix: prefix())}
  end

  defp maybe_filter_since(query, nil), do: query
  defp maybe_filter_since(query, since), do: from(e in query, where: e.started_at > ^since)

  defp maybe_filter_result(query, nil), do: query
  defp maybe_filter_result(query, result), do: from(e in query, where: e.result == ^result)

  @impl OmScheduler.Store.Behaviour
  def prune_executions(opts \\ []) do
    before = Keyword.get(opts, :before, DateTime.add(DateTime.utc_now(), -7, :day))
    limit = Keyword.get(opts, :limit, 10_000)

    # Get IDs to delete
    subquery =
      from(e in Execution,
        where: e.inserted_at < ^before,
        select: e.id,
        limit: ^limit
      )

    # Delete by IDs
    query = from(e in Execution, where: e.id in subquery(subquery))

    case repo().delete_all(query, prefix: prefix()) do
      {count, _} -> {:ok, count}
    end
  end

  # ============================================
  # Unique Job Enforcement
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def acquire_unique_lock(key, owner, ttl_ms) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl_ms, :millisecond)

    # Try to insert, or update if expired
    sql = """
    INSERT INTO scheduler_locks (id, key, owner, expires_at, inserted_at)
    VALUES (gen_random_uuid(), $1, $2, $3, $4)
    ON CONFLICT (key) DO UPDATE
    SET owner = EXCLUDED.owner,
        expires_at = EXCLUDED.expires_at
    WHERE scheduler_locks.expires_at < $4
    RETURNING key
    """

    case repo().query(sql, [key, owner, expires_at, now], prefix: prefix()) do
      {:ok, %{num_rows: 1}} ->
        {:ok, key}

      {:ok, %{num_rows: 0}} ->
        {:error, :locked}

      {:error, reason} ->
        Logger.warning("Failed to acquire lock #{key}: #{inspect(reason)}")
        {:error, :locked}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def release_unique_lock(key, owner) do
    sql = """
    DELETE FROM scheduler_locks
    WHERE key = $1 AND owner = $2
    """

    repo().query(sql, [key, owner], prefix: prefix())
    :ok
  end

  @impl OmScheduler.Store.Behaviour
  def cleanup_expired_locks do
    now = DateTime.utc_now()

    sql = """
    DELETE FROM scheduler_locks
    WHERE expires_at < $1
    """

    case repo().query(sql, [now], prefix: prefix()) do
      {:ok, %{num_rows: count}} -> {:ok, count}
      {:error, _} -> {:ok, 0}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def check_unique_conflict(key, states, cutoff) do
    now = DateTime.utc_now()

    # First check locks table
    lock_sql = """
    SELECT 1 FROM scheduler_locks
    WHERE key = $1 AND expires_at > $2
    LIMIT 1
    """

    case repo().query(lock_sql, [key, now], prefix: prefix()) do
      {:ok, %{num_rows: 1}} ->
        # Lock exists and is valid - conflict
        {:ok, true}

      {:ok, %{num_rows: 0}} ->
        # Check executions table
        check_execution_conflict(key, states, cutoff)

      {:error, _} ->
        {:error, :not_implemented}
    end
  end

  defp check_execution_conflict(key, states, cutoff) do
    state_strings = Enum.map(states, &to_string/1)

    base_query =
      from(e in Execution,
        where: e.job_name == ^key,
        where: e.state in ^state_strings,
        limit: 1
      )

    query =
      case cutoff do
        nil -> base_query
        cutoff_dt -> from(e in base_query, where: e.started_at >= ^cutoff_dt)
      end

    case repo().one(query, prefix: prefix()) do
      nil -> {:ok, false}
      _exec -> {:ok, true}
    end
  end

  # ============================================
  # Lifeline / Heartbeat Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def record_heartbeat(job_name, _node) do
    now = DateTime.utc_now()

    query =
      from(e in Execution,
        where: e.job_name == ^job_name,
        where: e.state == :running,
        order_by: [desc: e.started_at],
        limit: 1
      )

    case repo().one(query, prefix: prefix()) do
      nil ->
        {:error, :not_found}

      execution ->
        execution
        |> Ecto.Changeset.change(%{heartbeat_at: now})
        |> repo().update(prefix: prefix())

        :ok
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_stuck_executions(cutoff) do
    query =
      from(e in Execution,
        where: e.state == :running,
        where: not is_nil(e.heartbeat_at),
        where: e.heartbeat_at < ^cutoff,
        order_by: [asc: e.heartbeat_at]
      )

    {:ok, repo().all(query, prefix: prefix())}
  end

  @impl OmScheduler.Store.Behaviour
  def mark_execution_rescued(execution_id) do
    now = DateTime.utc_now()

    query = from(e in Execution, where: e.id == ^execution_id)

    case repo().one(query, prefix: prefix()) do
      nil ->
        {:error, :not_found}

      execution ->
        duration = DateTime.diff(now, execution.started_at, :millisecond)

        execution
        |> Ecto.Changeset.change(%{
          state: :rescued,
          result: :rescued,
          completed_at: now,
          duration_ms: duration,
          error: "Rescued by lifeline (stuck)"
        })
        |> repo().update(prefix: prefix())

        :ok
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_jobs_query(opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    from(j in Job,
      order_by: [asc: j.name],
      limit: ^limit,
      offset: ^offset
    )
    |> maybe_filter_queue(opts[:queue])
    |> maybe_filter_state(opts[:state])
    |> maybe_filter_tags(Keyword.get(opts, :tags, []))
  end

  defp maybe_filter_state(query, nil), do: query
  defp maybe_filter_state(query, state), do: from(j in query, where: j.state == ^state)

  defp maybe_filter_tags(query, []), do: query

  defp maybe_filter_tags(query, tags),
    do: from(j in query, where: fragment("? && ?", j.tags, ^tags))

  defp truncate_string(str, max_length) when is_binary(str) and byte_size(str) <= max_length do
    str
  end

  defp truncate_string(str, max_length) when is_binary(str) do
    String.slice(str, 0, max_length - 3) <> "..."
  end

  defp truncate_string(other, _max_length), do: inspect(other)
end
