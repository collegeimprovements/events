defmodule OmScheduler.Store.Behaviour do
  @moduledoc """
  Behaviour for scheduler storage backends.

  Implement this behaviour to add new storage backends (Redis, etc.)

  ## Implementations

  - `OmScheduler.Store.Memory` - ETS-based, for development
  - `OmScheduler.Store.Database` - PostgreSQL-based, for production
  """

  alias OmScheduler.{Job, Execution}
  alias OmScheduler.Workflow

  @type job :: Job.t()
  @type workflow :: Workflow.t()
  @type execution :: Execution.t()
  @type job_name :: String.t()
  @type workflow_name :: atom()
  @type opts :: keyword()

  # ============================================
  # Workflow Operations
  # ============================================

  @doc """
  Registers a workflow definition in the store.

  Returns `{:ok, workflow}` on success, `{:error, reason}` if the workflow name already exists.
  """
  @callback register_workflow(workflow()) :: {:ok, workflow()} | {:error, term()}

  @doc """
  Fetches a workflow by name.

  Returns `{:ok, workflow}` if found, `{:error, :not_found}` otherwise.
  """
  @callback get_workflow(workflow_name()) :: {:ok, workflow()} | {:error, :not_found}

  @doc """
  Lists all registered workflows.

  ## Options

  - `:tags` - Filter by tags (any match)
  - `:trigger_type` - Filter by trigger type (:manual, :scheduled, :event)
  """
  @callback list_workflows(opts()) :: [map()]

  @doc """
  Updates a workflow by name.

  Returns `{:ok, updated_workflow}` on success.
  """
  @callback update_workflow(workflow_name(), map()) :: {:ok, workflow()} | {:error, term()}

  @doc """
  Deletes a workflow by name.

  Returns `:ok` on success, `{:error, :not_found}` if the workflow doesn't exist.
  """
  @callback delete_workflow(workflow_name()) :: :ok | {:error, term()}

  # ============================================
  # Job Operations
  # ============================================

  @doc """
  Registers a new job in the store.

  Returns `{:ok, job}` on success, `{:error, reason}` if the job name already exists.
  """
  @callback register_job(job()) :: {:ok, job()} | {:error, term()}

  @doc """
  Fetches a job by name.

  Returns `{:ok, job}` if found, `{:error, :not_found}` otherwise.
  """
  @callback get_job(job_name()) :: {:ok, job()} | {:error, :not_found}

  @doc """
  Lists all jobs, optionally filtered.

  ## Options

  - `:queue` - Filter by queue name
  - `:state` - Filter by state (:active, :paused, :disabled)
  - `:tags` - Filter by tags (any match)
  - `:limit` - Maximum number of results
  - `:offset` - Offset for pagination
  """
  @callback list_jobs(opts()) :: {:ok, [job()]}

  @doc """
  Updates a job by name.

  Returns `{:ok, updated_job}` on success.
  """
  @callback update_job(job_name(), map()) :: {:ok, job()} | {:error, term()}

  @doc """
  Deletes a job by name.

  Returns `:ok` on success, `{:error, :not_found}` if the job doesn't exist.
  """
  @callback delete_job(job_name()) :: :ok | {:error, term()}

  # ============================================
  # Scheduling Operations
  # ============================================

  @doc """
  Gets all jobs that are due for execution.

  A job is due if:
  - enabled is true
  - paused is false
  - state is :active
  - next_run_at <= now

  ## Options

  - `:queue` - Filter by queue
  - `:limit` - Maximum number of jobs to return
  """
  @callback get_due_jobs(DateTime.t(), opts()) :: {:ok, [job()]}

  @doc """
  Marks a job as running (acquires the execution lock).

  Returns `{:ok, job}` if the lock was acquired, `{:error, :locked}` if already running.
  """
  @callback mark_running(job_name(), node :: atom()) :: {:ok, job()} | {:error, term()}

  @doc """
  Marks a job execution as completed.

  Updates last_run_at, next_run_at, run_count, and optionally last_result.
  """
  @callback mark_completed(job_name(), result :: term(), DateTime.t() | nil) ::
              {:ok, job()} | {:error, term()}

  @doc """
  Marks a job execution as failed.

  Updates error_count, last_error, and optionally schedules a retry.
  """
  @callback mark_failed(job_name(), reason :: term(), DateTime.t() | nil) ::
              {:ok, job()} | {:error, term()}

  @doc """
  Releases a job's execution lock without marking complete/failed.

  Used when a job is cancelled or times out.
  """
  @callback release_lock(job_name()) :: :ok | {:error, term()}

  @doc """
  Marks a job execution as cancelled.

  Updates the job state and records cancellation in history.
  """
  @callback mark_cancelled(job_name(), reason :: term()) ::
              {:ok, job()} | {:error, term()}

  # ============================================
  # Execution History
  # ============================================

  @doc """
  Records a job execution start.
  """
  @callback record_execution_start(execution()) :: {:ok, execution()} | {:error, term()}

  @doc """
  Records a job execution completion.
  """
  @callback record_execution_complete(execution()) :: {:ok, execution()} | {:error, term()}

  @doc """
  Gets execution history for a job.

  ## Options

  - `:limit` - Maximum number of results
  - `:since` - Only executions after this time
  - `:result` - Filter by result (:ok, :error, :timeout, etc.)
  """
  @callback get_executions(job_name(), opts()) :: {:ok, [execution()]}

  @doc """
  Deletes old execution records.

  ## Options

  - `:before` - Delete executions before this time
  - `:limit` - Maximum number to delete
  """
  @callback prune_executions(opts()) :: {:ok, non_neg_integer()}

  # ============================================
  # Unique Job Enforcement
  # ============================================

  @doc """
  Acquires a unique lock for a job.

  Used to prevent concurrent executions when `unique: true`.
  """
  @callback acquire_unique_lock(key :: String.t(), owner :: String.t(), ttl_ms :: pos_integer()) ::
              {:ok, String.t()} | {:error, :locked}

  @doc """
  Releases a unique lock.
  """
  @callback release_unique_lock(key :: String.t(), owner :: String.t()) :: :ok | {:error, term()}

  @doc """
  Cleans up expired unique locks.
  """
  @callback cleanup_expired_locks() :: {:ok, non_neg_integer()}

  @doc """
  Checks if there's a conflicting execution for a unique key.

  Used by enhanced unique job enforcement to check against specific states.

  ## Arguments

  - `key` - The unique key to check
  - `states` - States that count as conflicts (e.g., [:running, :scheduled])
  - `cutoff` - Optional DateTime; only consider executions after this time

  ## Returns

  - `{:ok, true}` - Conflict exists
  - `{:ok, false}` - No conflict
  - `{:error, :not_implemented}` - Store doesn't support this check
  """
  @callback check_unique_conflict(
              key :: String.t(),
              states :: [atom()],
              cutoff :: DateTime.t() | nil
            ) ::
              {:ok, boolean()} | {:error, :not_implemented}

  # ============================================
  # Lifeline / Heartbeat Operations
  # ============================================

  @doc """
  Records a heartbeat for a running job.

  Called periodically while a job is executing to indicate it's still alive.
  """
  @callback record_heartbeat(job_name(), node :: atom()) :: :ok | {:error, term()}

  @doc """
  Gets executions that appear stuck (no recent heartbeat).

  Returns executions in `:running` state with heartbeat older than cutoff.
  """
  @callback get_stuck_executions(cutoff :: DateTime.t()) :: {:ok, [execution()]} | {:error, term()}

  @doc """
  Marks an execution as rescued by the lifeline.

  Updates execution state to `:rescued` and records rescue metadata.
  """
  @callback mark_execution_rescued(execution_id :: String.t()) :: :ok | {:error, term()}
end
