defmodule Events.Infra.Scheduler.Execution do
  @moduledoc """
  Schema for job execution history.

  Records the outcome of each job execution for monitoring and debugging.

  ## Fields

  - `job_id` - Reference to the scheduled job
  - `job_name` - Denormalized for queries after job deletion
  - `node` - Node that executed the job
  - `attempt` - Attempt number (1-based)
  - `state` - Execution state: running, completed, failed, cancelled, timeout
  - `started_at` - When execution started
  - `completed_at` - When execution finished
  - `scheduled_at` - When the job was originally scheduled
  - `queue_time_ms` - Time spent waiting in queue
  - `duration_ms` - Execution duration
  - `result` - Execution result: ok, error, timeout, cancelled, discard
  - `error` - Error message if failed
  - `stacktrace` - Stack trace if failed
  - `meta` - Additional metadata
  """

  use Events.Core.Schema

  @type state :: :running | :completed | :failed | :cancelled | :timeout | :rescued
  @type result :: :ok | :error | :timeout | :cancelled | :discard | :rescued

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          job_id: Ecto.UUID.t() | nil,
          job_name: String.t(),
          node: String.t(),
          attempt: non_neg_integer(),
          state: state(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          scheduled_at: DateTime.t() | nil,
          heartbeat_at: DateTime.t() | nil,
          queue_time_ms: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          result: result() | nil,
          error: String.t() | nil,
          stacktrace: String.t() | nil,
          meta: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "scheduler_executions" do
    field :job_id, Ecto.UUID
    field :job_name, :string, required: true
    field :node, :string, required: true
    field :attempt, :integer, default: 1

    field :state, Ecto.Enum,
      values: [:running, :completed, :failed, :cancelled, :timeout, :rescued],
      default: :running

    field :started_at, :utc_datetime_usec, required: true
    field :completed_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :heartbeat_at, :utc_datetime_usec
    field :queue_time_ms, :integer
    field :duration_ms, :integer

    field :result, Ecto.Enum, values: [:ok, :error, :timeout, :cancelled, :discard, :rescued]

    field :error, :string
    field :stacktrace, :string

    field :meta, :map, default: %{}

    timestamps()
  end

  @required_fields [:job_name, :node, :started_at]
  @optional_fields [
    :job_id,
    :attempt,
    :state,
    :completed_at,
    :scheduled_at,
    :heartbeat_at,
    :queue_time_ms,
    :duration_ms,
    :result,
    :error,
    :stacktrace,
    :meta
  ]

  # ============================================
  # Changesets
  # ============================================

  @doc """
  Creates a changeset for starting an execution.
  """
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Creates a changeset for completing an execution.
  """
  def complete_changeset(execution, attrs) do
    execution
    |> cast(attrs, [:state, :completed_at, :duration_ms, :result, :error, :stacktrace])
    |> validate_required([:state, :completed_at])
  end

  # ============================================
  # Builders
  # ============================================

  @doc """
  Creates a new execution record for a starting job.

  ## Examples

      iex> Execution.start(job, 1)
      %Execution{state: :running, ...}
  """
  @spec start(map() | struct(), pos_integer()) :: t()
  def start(job, attempt \\ 1) do
    now = DateTime.utc_now()

    queue_time_ms =
      case Map.get(job, :scheduled_at) || Map.get(job, :next_run_at) do
        nil -> nil
        scheduled -> DateTime.diff(now, scheduled, :millisecond)
      end

    %__MODULE__{
      job_id: Map.get(job, :id),
      job_name: Map.get(job, :name),
      node: to_string(node()),
      attempt: attempt,
      state: :running,
      started_at: now,
      scheduled_at: Map.get(job, :next_run_at),
      heartbeat_at: now,
      queue_time_ms: queue_time_ms,
      meta: build_meta(job)
    }
  end

  @doc """
  Marks an execution as completed successfully.
  """
  @spec complete(t(), term()) :: t()
  def complete(%__MODULE__{} = execution, _result \\ nil) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    %{execution | state: :completed, result: :ok, completed_at: now, duration_ms: duration}
  end

  @doc """
  Marks an execution as failed.
  """
  @spec fail(t(), term(), String.t() | nil) :: t()
  def fail(%__MODULE__{} = execution, reason, stacktrace \\ nil) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    error_msg =
      case reason do
        %{message: msg} -> msg
        msg when is_binary(msg) -> msg
        other -> inspect(other)
      end

    %{
      execution
      | state: :failed,
        result: :error,
        completed_at: now,
        duration_ms: duration,
        error: error_msg,
        stacktrace: stacktrace
    }
  end

  @doc """
  Marks an execution as timed out.
  """
  @spec timeout(t()) :: t()
  def timeout(%__MODULE__{} = execution) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    %{
      execution
      | state: :timeout,
        result: :timeout,
        completed_at: now,
        duration_ms: duration,
        error: "Execution timed out"
    }
  end

  @doc """
  Marks an execution as cancelled.
  """
  @spec cancel(t(), String.t() | nil) :: t()
  def cancel(%__MODULE__{} = execution, reason \\ nil) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    %{
      execution
      | state: :cancelled,
        result: :cancelled,
        completed_at: now,
        duration_ms: duration,
        error: reason || "Execution cancelled"
    }
  end

  @doc """
  Marks an execution as discarded (max retries exceeded).
  """
  @spec discard(t(), String.t() | nil) :: t()
  def discard(%__MODULE__{} = execution, reason \\ nil) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    %{
      execution
      | state: :failed,
        result: :discard,
        completed_at: now,
        duration_ms: duration,
        error: reason || "Maximum retries exceeded"
    }
  end

  @doc """
  Marks an execution as rescued by the lifeline.
  """
  @spec mark_rescued(t(), String.t() | nil) :: t()
  def mark_rescued(%__MODULE__{} = execution, reason \\ nil) do
    now = DateTime.utc_now()
    duration = DateTime.diff(now, execution.started_at, :millisecond)

    %{
      execution
      | state: :rescued,
        result: :rescued,
        completed_at: now,
        duration_ms: duration,
        error: reason || "Rescued by lifeline (stuck)"
    }
  end

  @doc """
  Updates the heartbeat timestamp.
  """
  @spec heartbeat(t()) :: t()
  def heartbeat(%__MODULE__{} = execution) do
    %{execution | heartbeat_at: DateTime.utc_now()}
  end

  # ============================================
  # Query Helpers
  # ============================================

  @doc """
  Returns true if the execution is still running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{state: :running}), do: true
  def running?(%__MODULE__{}), do: false

  @doc """
  Returns true if the execution finished successfully.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{result: :ok}), do: true
  def success?(%__MODULE__{}), do: false

  @doc """
  Returns true if the execution failed.
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{state: state}) when state in [:failed, :timeout], do: true
  def failed?(%__MODULE__{}), do: false

  # ============================================
  # Private Helpers
  # ============================================

  defp build_meta(job) do
    %{
      "scheduled" => true,
      "schedule_type" => to_string(Map.get(job, :schedule_type, "unknown")),
      "queue" => Map.get(job, :queue, "default")
    }
  end
end
