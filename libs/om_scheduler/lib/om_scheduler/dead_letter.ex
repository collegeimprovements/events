defmodule OmScheduler.DeadLetter do
  @moduledoc """
  Dead Letter Queue for failed jobs.

  Stores jobs that have exhausted retries or encountered terminal errors,
  allowing for later inspection, replay, or manual intervention.

  ## Configuration

      config :om_scheduler,
        dead_letter: [
          enabled: true,
          max_age: {30, :days},      # Auto-prune after 30 days
          max_entries: 10_000,       # Max entries per queue
          on_dead_letter: &MyApp.notify_failure/1  # Optional callback
        ]

  ## Usage

      alias OmScheduler.DeadLetter

      # List dead letter entries
      DeadLetter.list(limit: 50)
      DeadLetter.list(queue: :billing, since: ~U[2024-01-01 00:00:00Z])

      # Get a specific entry
      DeadLetter.get("entry_id")

      # Retry a dead letter entry
      DeadLetter.retry("entry_id")
      DeadLetter.retry_all(queue: :billing)

      # Delete entries
      DeadLetter.delete("entry_id")
      DeadLetter.prune(before: ~U[2024-01-01 00:00:00Z])

  ## Entry Structure

      %DeadLetter.Entry{
        id: "uuid",
        job_name: "sync_data",
        queue: :default,
        module: "MyApp.Jobs",
        function: "sync",
        args: %{},
        error: %{type: :timeout, message: "..."},
        error_class: :retryable,
        attempts: 5,
        first_failed_at: ~U[2024-01-15 10:00:00Z],
        last_failed_at: ~U[2024-01-15 10:15:00Z],
        stacktrace: "...",
        meta: %{}
      }

  ## Telemetry Events

  - `[:scheduler, :dead_letter, :insert]` - Entry added to DLQ
  - `[:scheduler, :dead_letter, :retry]` - Entry retried
  - `[:scheduler, :dead_letter, :delete]` - Entry deleted
  - `[:scheduler, :dead_letter, :prune]` - Entries pruned
  """

  use GenServer
  require Logger

  alias OmScheduler.{Config, Job, ErrorClassifier}

  defmodule Entry do
    @moduledoc """
    A dead letter queue entry.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            job_name: String.t(),
            queue: atom(),
            module: String.t(),
            function: String.t(),
            args: map() | list(),
            error: map(),
            error_class: atom(),
            attempts: pos_integer(),
            first_failed_at: DateTime.t(),
            last_failed_at: DateTime.t(),
            stacktrace: String.t() | nil,
            meta: map(),
            inserted_at: DateTime.t()
          }

    defstruct [
      :id,
      :job_name,
      :queue,
      :module,
      :function,
      :args,
      :error,
      :error_class,
      :attempts,
      :first_failed_at,
      :last_failed_at,
      :stacktrace,
      :meta,
      :inserted_at
    ]

    @doc """
    Creates a new entry from a job and error.
    """
    @spec new(Job.t(), term(), pos_integer(), keyword()) :: t()
    def new(%Job{} = job, error, attempts, opts \\ []) do
      now = DateTime.utc_now()

      %__MODULE__{
        id: generate_id(),
        job_name: job.name,
        queue: job.queue,
        module: job.module,
        function: job.function,
        args: job.args,
        error: normalize_error(error),
        error_class: ErrorClassifier.get_class(error),
        attempts: attempts,
        first_failed_at: Keyword.get(opts, :first_failed_at, now),
        last_failed_at: now,
        stacktrace: Keyword.get(opts, :stacktrace),
        meta: job.meta || %{},
        inserted_at: now
      }
    end

    defp generate_id do
      Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    end

    defp normalize_error(error) when is_map(error), do: error

    defp normalize_error({:exception, exception, _stacktrace}) do
      %{
        type: :exception,
        exception: exception.__struct__,
        message: Exception.message(exception)
      }
    end

    defp normalize_error({kind, reason, stacktrace}) when is_list(stacktrace) do
      %{
        type: kind,
        reason: inspect(reason)
      }
    end

    defp normalize_error({kind, reason}) do
      %{
        type: kind,
        reason: inspect(reason)
      }
    end

    defp normalize_error(error) when is_atom(error) do
      %{type: error}
    end

    defp normalize_error(error) do
      %{type: :unknown, reason: inspect(error)}
    end
  end

  @type opts :: [
          name: atom(),
          max_entries: pos_integer(),
          max_age: pos_integer() | {pos_integer(), atom()},
          on_dead_letter: (Entry.t() -> any()) | nil
        ]

  defstruct [
    :name,
    :max_entries,
    :max_age,
    :on_dead_letter,
    entries: %{},
    by_queue: %{},
    by_job: %{}
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Starts the dead letter queue.
  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Inserts a failed job into the dead letter queue.
  """
  @spec insert(Job.t(), term(), pos_integer(), keyword()) :: {:ok, Entry.t()}
  def insert(%Job{} = job, error, attempts, opts \\ []) do
    GenServer.call(__MODULE__, {:insert, job, error, attempts, opts})
  end

  @doc """
  Lists dead letter entries with optional filtering.

  ## Options

  - `:queue` - Filter by queue
  - `:job_name` - Filter by job name
  - `:error_class` - Filter by error class
  - `:since` - Filter entries after this time
  - `:limit` - Max entries to return (default: 100)
  - `:offset` - Offset for pagination (default: 0)
  """
  @spec list(keyword()) :: {:ok, [Entry.t()]}
  def list(opts \\ []) do
    GenServer.call(__MODULE__, {:list, opts})
  end

  @doc """
  Gets a specific dead letter entry by ID.
  """
  @spec get(String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @doc """
  Retries a dead letter entry.

  Returns the entry that was retried, or an error if not found.
  """
  @spec retry(String.t()) :: {:ok, Entry.t()} | {:error, :not_found}
  def retry(id) do
    GenServer.call(__MODULE__, {:retry, id})
  end

  @doc """
  Retries all entries matching the filter.

  ## Options

  - `:queue` - Filter by queue
  - `:job_name` - Filter by job name
  - `:error_class` - Filter by error class
  - `:limit` - Max entries to retry (default: 100)

  Returns the count of entries queued for retry.
  """
  @spec retry_all(keyword()) :: {:ok, non_neg_integer()}
  def retry_all(opts \\ []) do
    GenServer.call(__MODULE__, {:retry_all, opts})
  end

  @doc """
  Deletes a dead letter entry.
  """
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id) do
    GenServer.call(__MODULE__, {:delete, id})
  end

  @doc """
  Prunes old dead letter entries.

  ## Options

  - `:before` - Delete entries older than this time
  - `:limit` - Max entries to delete (default: 1000)

  Returns the count of deleted entries.
  """
  @spec prune(keyword()) :: {:ok, non_neg_integer()}
  def prune(opts \\ []) do
    GenServer.call(__MODULE__, {:prune, opts})
  end

  @doc """
  Returns statistics about the dead letter queue.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Returns child spec for supervision.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
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
    # Load config
    app_config = Config.get()
    dlq_config = Keyword.get(app_config, :dead_letter, [])

    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      max_entries: Keyword.get(dlq_config, :max_entries, 10_000),
      max_age: normalize_max_age(Keyword.get(dlq_config, :max_age, {30, :days})),
      on_dead_letter: Keyword.get(dlq_config, :on_dead_letter)
    }

    # Schedule periodic pruning
    schedule_prune()

    {:ok, state}
  end

  @impl true
  def handle_call({:insert, job, error, attempts, opts}, _from, state) do
    entry = Entry.new(job, error, attempts, opts)

    # Check max entries
    state =
      if map_size(state.entries) >= state.max_entries do
        prune_oldest(state)
      else
        state
      end

    # Insert entry
    new_state = do_insert(state, entry)

    # Emit telemetry
    emit_insert(entry)

    # Call callback if configured
    if state.on_dead_letter do
      spawn(fn -> state.on_dead_letter.(entry) end)
    end

    Logger.warning(
      "[Scheduler.DeadLetter] Job #{entry.job_name} added to DLQ " <>
        "(attempts: #{entry.attempts}, error: #{entry.error_class})"
    )

    {:reply, {:ok, entry}, new_state}
  end

  def handle_call({:list, opts}, _from, state) do
    entries =
      state.entries
      |> Map.values()
      |> filter_entries(opts)
      |> sort_entries()
      |> paginate_entries(opts)

    {:reply, {:ok, entries}, state}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.get(state.entries, id) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry}, state}
    end
  end

  def handle_call({:retry, id}, _from, state) do
    case Map.get(state.entries, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        # Queue the job for retry
        queue_for_retry(entry)

        # Remove from dead letter queue
        new_state = do_delete(state, id)

        emit_retry(entry)
        {:reply, {:ok, entry}, new_state}
    end
  end

  def handle_call({:retry_all, opts}, _from, state) do
    entries =
      state.entries
      |> Map.values()
      |> filter_entries(opts)
      |> Enum.take(Keyword.get(opts, :limit, 100))

    # Queue all for retry
    Enum.each(entries, &queue_for_retry/1)

    # Remove from dead letter queue
    new_state =
      Enum.reduce(entries, state, fn entry, acc ->
        do_delete(acc, entry.id)
      end)

    count = length(entries)
    Logger.info("[Scheduler.DeadLetter] Queued #{count} entries for retry")

    {:reply, {:ok, count}, new_state}
  end

  def handle_call({:delete, id}, _from, state) do
    case Map.get(state.entries, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        new_state = do_delete(state, id)
        emit_delete(entry)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:prune, opts}, _from, state) do
    before_time =
      Keyword.get_lazy(opts, :before, fn ->
        DateTime.add(DateTime.utc_now(), -state.max_age, :millisecond)
      end)

    limit = Keyword.get(opts, :limit, 1000)

    {to_delete, _} =
      state.entries
      |> Map.values()
      |> Enum.filter(fn entry ->
        DateTime.compare(entry.inserted_at, before_time) == :lt
      end)
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> Enum.split(limit)

    new_state =
      Enum.reduce(to_delete, state, fn entry, acc ->
        do_delete(acc, entry.id)
      end)

    count = length(to_delete)

    if count > 0 do
      Logger.info("[Scheduler.DeadLetter] Pruned #{count} old entries")
      emit_prune(count)
    end

    {:reply, {:ok, count}, new_state}
  end

  def handle_call(:stats, _from, state) do
    by_queue =
      state.entries
      |> Map.values()
      |> Enum.group_by(& &1.queue)
      |> Map.new(fn {queue, entries} -> {queue, length(entries)} end)

    by_class =
      state.entries
      |> Map.values()
      |> Enum.group_by(& &1.error_class)
      |> Map.new(fn {class, entries} -> {class, length(entries)} end)

    stats = %{
      total: map_size(state.entries),
      by_queue: by_queue,
      by_error_class: by_class,
      max_entries: state.max_entries,
      max_age_ms: state.max_age
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:prune, state) do
    before_time = DateTime.add(DateTime.utc_now(), -state.max_age, :millisecond)

    to_delete =
      state.entries
      |> Map.values()
      |> Enum.filter(fn entry ->
        DateTime.compare(entry.inserted_at, before_time) == :lt
      end)

    new_state =
      Enum.reduce(to_delete, state, fn entry, acc ->
        do_delete(acc, entry.id)
      end)

    if length(to_delete) > 0 do
      Logger.info("[Scheduler.DeadLetter] Auto-pruned #{length(to_delete)} old entries")
    end

    schedule_prune()
    {:noreply, new_state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp do_insert(state, entry) do
    entries = Map.put(state.entries, entry.id, entry)

    by_queue =
      Map.update(state.by_queue, entry.queue, [entry.id], fn ids ->
        [entry.id | ids]
      end)

    by_job =
      Map.update(state.by_job, entry.job_name, [entry.id], fn ids ->
        [entry.id | ids]
      end)

    %{state | entries: entries, by_queue: by_queue, by_job: by_job}
  end

  defp do_delete(state, id) do
    case Map.get(state.entries, id) do
      nil ->
        state

      entry ->
        entries = Map.delete(state.entries, id)

        by_queue =
          Map.update(state.by_queue, entry.queue, [], fn ids ->
            List.delete(ids, id)
          end)

        by_job =
          Map.update(state.by_job, entry.job_name, [], fn ids ->
            List.delete(ids, id)
          end)

        %{state | entries: entries, by_queue: by_queue, by_job: by_job}
    end
  end

  defp prune_oldest(state) do
    oldest =
      state.entries
      |> Map.values()
      |> Enum.min_by(& &1.inserted_at, DateTime, fn -> nil end)

    case oldest do
      nil -> state
      entry -> do_delete(state, entry.id)
    end
  end

  defp filter_entries(entries, opts) do
    entries
    |> maybe_filter_queue(opts[:queue])
    |> maybe_filter_job(opts[:job_name])
    |> maybe_filter_class(opts[:error_class])
    |> maybe_filter_since(opts[:since])
  end

  defp maybe_filter_queue(entries, nil), do: entries

  defp maybe_filter_queue(entries, queue) do
    Enum.filter(entries, &(&1.queue == queue))
  end

  defp maybe_filter_job(entries, nil), do: entries

  defp maybe_filter_job(entries, job_name) do
    Enum.filter(entries, &(&1.job_name == job_name))
  end

  defp maybe_filter_class(entries, nil), do: entries

  defp maybe_filter_class(entries, error_class) do
    Enum.filter(entries, &(&1.error_class == error_class))
  end

  defp maybe_filter_since(entries, nil), do: entries

  defp maybe_filter_since(entries, since) do
    Enum.filter(entries, fn entry ->
      DateTime.compare(entry.inserted_at, since) in [:gt, :eq]
    end)
  end

  defp sort_entries(entries) do
    Enum.sort_by(entries, & &1.inserted_at, {:desc, DateTime})
  end

  defp paginate_entries(entries, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    entries
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  defp queue_for_retry(entry) do
    # Re-insert the job for execution
    # This would integrate with the scheduler's insert function
    alias OmScheduler

    job_attrs = %{
      name: entry.job_name,
      queue: entry.queue,
      module: entry.module,
      function: entry.function,
      args: entry.args,
      meta: Map.put(entry.meta, "retried_from_dlq", true)
    }

    case OmScheduler.insert(job_attrs) do
      {:ok, _} ->
        Logger.info("[Scheduler.DeadLetter] Retried job #{entry.job_name}")

      {:error, reason} ->
        Logger.error(
          "[Scheduler.DeadLetter] Failed to retry job #{entry.job_name}: #{inspect(reason)}"
        )
    end
  end

  defp normalize_max_age(ms) when is_integer(ms), do: ms
  defp normalize_max_age({n, unit}), do: Config.to_ms({n, unit})

  defp schedule_prune do
    # Prune every hour
    Process.send_after(self(), :prune, :timer.hours(1))
  end

  # ============================================
  # Telemetry
  # ============================================

  defp emit_insert(entry) do
    :telemetry.execute(
      [:scheduler, :dead_letter, :insert],
      %{system_time: System.system_time()},
      %{
        job_name: entry.job_name,
        queue: entry.queue,
        error_class: entry.error_class,
        attempts: entry.attempts
      }
    )
  end

  defp emit_retry(entry) do
    :telemetry.execute(
      [:scheduler, :dead_letter, :retry],
      %{system_time: System.system_time()},
      %{job_name: entry.job_name, queue: entry.queue}
    )
  end

  defp emit_delete(entry) do
    :telemetry.execute(
      [:scheduler, :dead_letter, :delete],
      %{system_time: System.system_time()},
      %{job_name: entry.job_name, queue: entry.queue}
    )
  end

  defp emit_prune(count) do
    :telemetry.execute(
      [:scheduler, :dead_letter, :prune],
      %{count: count},
      %{}
    )
  end
end
