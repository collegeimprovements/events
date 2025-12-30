if Code.ensure_loaded?(Redix) do
  defmodule OmScheduler.Store.Redis do
    @moduledoc """
    Redis-based store for the scheduler.

    Optimized for high-throughput job scheduling with Redis-specific features.

    ## Features

    - **Sorted Sets** for O(log N) due job queries
    - **Atomic locks** with SET NX EX (no cleanup needed)
    - **Lua scripts** for atomic multi-key operations
    - **Pub/Sub** for real-time job notifications
    - **Auto-expiring** execution history

    ## Usage

        config :my_app, OmScheduler,
          store: :redis,
          redis_url: "redis://localhost:6379/0"

    ## Key Structure

    - `scheduler:jobs` - Hash of all jobs (name -> JSON)
    - `scheduler:due:{queue}` - Sorted set (job_name, score=next_run_at)
    - `scheduler:lock:{key}` - Lock keys with TTL
    - `scheduler:exec:{job_name}` - List of executions (newest first)
    - `scheduler:workflows` - Hash of workflow definitions
    - `scheduler:events` - Pub/Sub channel for notifications

    ## Requirements

    Add `{:redix, "~> 1.5"}` to your dependencies to use this store.
    """

    use GenServer
  require Logger

  alias OmScheduler.{Job, Execution, Config}
  alias OmScheduler.Workflow

  @behaviour OmScheduler.Store.Behaviour

  @jobs_key "scheduler:jobs"
  @workflows_key "scheduler:workflows"
  @due_prefix "scheduler:due:"
  @lock_prefix "scheduler:lock:"
  @exec_prefix "scheduler:exec:"
  @events_channel "scheduler:events"

  @max_execution_history 100

  # ============================================
  # Client API
  # ============================================

  @pool_size 5

  @doc """
  Starts the Redis store with connection pool.

  ## Options

  - `:name` - GenServer name (default: __MODULE__)
  - `:redis_url` - Redis URL (default: from config)
  - `:pool_size` - Connection pool size (default: 5)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @doc """
  Returns child specs for starting Redis connections under your supervisor.

  ## Example

      children = [
        {OmScheduler.Store.Redis, redis_url: "redis://localhost:6379"}
      ]
  """
  def pool_child_specs(opts \\ []) do
    redis_url = Keyword.get(opts, :redis_url) || Config.get()[:redis_url] || "redis://localhost:6379/0"
    pool_size = Keyword.get(opts, :pool_size, @pool_size)

    for i <- 1..pool_size do
      Supervisor.child_spec(
        {Redix, {redis_url, [name: pool_name(i)]}},
        id: {Redix, i}
      )
    end
  end

  defp pool_name(index), do: :"scheduler_redis_#{index}"

  defp random_pool_connection do
    pool_name(:rand.uniform(@pool_size))
  end

  # ============================================
  # Workflow Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def register_workflow(%Workflow{} = workflow) do
    case redis_cmd(["HSETNX", @workflows_key, to_string(workflow.name), encode(workflow)]) do
      {:ok, 1} -> {:ok, workflow}
      {:ok, 0} -> {:error, :already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_workflow(name) when is_atom(name) do
    case redis_cmd(["HGET", @workflows_key, to_string(name)]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, data} -> {:ok, decode(data, Workflow)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def list_workflows(opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    trigger_type = Keyword.get(opts, :trigger_type)

    case redis_cmd(["HVALS", @workflows_key]) do
      {:ok, values} ->
        values
        |> Enum.map(&decode(&1, Workflow))
        |> Enum.map(fn workflow ->
          %{
            name: workflow.name,
            steps: map_size(workflow.steps),
            trigger_type: workflow.trigger_type,
            schedule: workflow.schedule,
            tags: workflow.tags,
            state: workflow.state
          }
        end)
        |> Enum.filter(fn info ->
          (tags == [] or Enum.any?(tags, &(&1 in info.tags))) and
            (is_nil(trigger_type) or info.trigger_type == trigger_type)
        end)

      {:error, _} ->
        []
    end
  end

  @impl OmScheduler.Store.Behaviour
  def update_workflow(name, attrs) when is_atom(name) and is_map(attrs) do
    with {:ok, workflow} <- get_workflow(name) do
      updated = struct(workflow, Map.to_list(attrs))

      case redis_cmd(["HSET", @workflows_key, to_string(name), encode(updated)]) do
        {:ok, _} -> {:ok, updated}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl OmScheduler.Store.Behaviour
  def delete_workflow(name) when is_atom(name) do
    case redis_cmd(["HDEL", @workflows_key, to_string(name)]) do
      {:ok, 1} -> :ok
      {:ok, 0} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================
  # Job Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def register_job(%Job{} = job) do
    # Use HSETNX for atomic check-and-set
    case redis_cmd(["HSETNX", @jobs_key, job.name, encode(job)]) do
      {:ok, 1} ->
        # Add to due set if has next_run_at
        if job.next_run_at do
          add_to_due_set(job)
        end

        publish_event(:job_registered, job.name)
        {:ok, job}

      {:ok, 0} ->
        {:error, :already_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_job(name) when is_binary(name) do
    case redis_cmd(["HGET", @jobs_key, name]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, data} -> {:ok, decode(data, Job)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def list_jobs(opts \\ []) do
    queue = Keyword.get(opts, :queue)
    state = Keyword.get(opts, :state)
    tags = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    case redis_cmd(["HVALS", @jobs_key]) do
      {:ok, values} ->
        jobs =
          values
          |> Enum.map(&decode(&1, Job))
          |> Enum.filter(fn job ->
            (is_nil(queue) or job.queue == to_string(queue)) and
              (is_nil(state) or job.state == state) and
              (tags == [] or Enum.any?(tags, &(&1 in job.tags)))
          end)
          |> Enum.drop(offset)
          |> Enum.take(limit)

        {:ok, jobs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def update_job(name, attrs) when is_binary(name) and is_map(attrs) do
    with {:ok, job} <- get_job(name) do
      updated = struct(job, Map.to_list(attrs))

      case redis_cmd(["HSET", @jobs_key, name, encode(updated)]) do
        {:ok, _} ->
          # Update due set if next_run_at changed
          if Map.has_key?(attrs, :next_run_at) do
            update_due_set(updated)
          end

          {:ok, updated}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl OmScheduler.Store.Behaviour
  def delete_job(name) when is_binary(name) do
    # Remove from jobs hash and all due sets
    with {:ok, job} <- get_job(name) do
      redis_cmd(["HDEL", @jobs_key, name])
      redis_cmd(["ZREM", due_key(job.queue), name])
      publish_event(:job_deleted, name)
      :ok
    end
  end

  # ============================================
  # Scheduling Operations - Redis Optimized
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def get_due_jobs(now, opts \\ []) do
    queue = Keyword.get(opts, :queue)
    limit = Keyword.get(opts, :limit, 100)
    score = DateTime.to_unix(now, :millisecond)

    # Get jobs from sorted set where score <= now
    # Using ZRANGEBYSCORE for efficient range query
    key = if queue, do: due_key(queue), else: due_key("default")

    case redis_cmd(["ZRANGEBYSCORE", key, "-inf", to_string(score), "LIMIT", "0", to_string(limit)]) do
      {:ok, names} when is_list(names) ->
        jobs =
          names
          |> Enum.map(&get_job/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, job} -> job end)
          |> Enum.filter(&Job.runnable?/1)
          |> Enum.sort_by(fn job -> {job.priority, job.next_run_at} end)

        {:ok, jobs}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Failed to get due jobs: #{inspect(reason)}")
        {:ok, []}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_running(name, node) do
    with {:ok, job} <- get_job(name),
         :ok <- maybe_acquire_lock(job, node) do
      updated = %{job | state: :active, last_run_at: DateTime.utc_now()}
      save_job(updated)
      publish_event(:job_started, name)
      {:ok, updated}
    end
  end

  defp maybe_acquire_lock(%Job{unique: false}, _node), do: :ok

  defp maybe_acquire_lock(%Job{unique: true, name: name, timeout: timeout}, node) do
    case acquire_unique_lock(name, to_string(node), timeout) do
      {:ok, _} -> :ok
      {:error, :locked} = error -> error
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_completed(name, result, next_run_at) do
    with {:ok, job} <- get_job(name) do
      updated = %{
        job
        | run_count: job.run_count + 1,
          last_result: truncate(inspect(result), 255),
          next_run_at: next_run_at
      }

      save_job(updated)
      update_due_set(updated)
      maybe_release_lock(job)
      publish_event(:job_completed, name)

      {:ok, updated}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_failed(name, reason, next_run_at) do
    with {:ok, job} <- get_job(name) do
      updated = %{
        job
        | error_count: job.error_count + 1,
          last_error: truncate(inspect(reason), 1000),
          next_run_at: next_run_at
      }

      save_job(updated)
      update_due_set(updated)
      maybe_release_lock(job)
      publish_event(:job_failed, name)

      {:ok, updated}
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

      updated = %{
        job
        | last_error: truncate("Cancelled: #{inspect(reason)}", 1000),
          next_run_at: next_run
      }

      save_job(updated)
      update_due_set(updated)
      maybe_release_lock(job)
      publish_event(:job_cancelled, name)

      {:ok, updated}
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
    execution =
      if is_nil(execution.id), do: %{execution | id: Ecto.UUID.generate()}, else: execution

    key = exec_key(execution.job_name)

    # LPUSH and LTRIM for bounded list
    case redis_pipeline([
           ["LPUSH", key, encode(execution)],
           ["LTRIM", key, "0", to_string(@max_execution_history - 1)]
         ]) do
      {:ok, _} -> {:ok, execution}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def record_execution_complete(%Execution{} = execution) do
    key = exec_key(execution.job_name)

    # Find and update the execution in the list
    # For simplicity, just prepend the updated execution
    # (the old one will be trimmed eventually)
    case redis_cmd(["LPUSH", key, encode(execution)]) do
      {:ok, _} -> {:ok, execution}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_executions(job_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)
    result_filter = Keyword.get(opts, :result)

    key = exec_key(job_name)

    case redis_cmd(["LRANGE", key, "0", to_string(limit * 2)]) do
      {:ok, values} when is_list(values) ->
        executions =
          values
          |> Enum.map(&decode(&1, Execution))
          |> Enum.uniq_by(& &1.id)
          |> Enum.filter(fn exec ->
            (is_nil(since) or DateTime.compare(exec.started_at, since) == :gt) and
              (is_nil(result_filter) or exec.result == result_filter)
          end)
          |> Enum.take(limit)

        {:ok, executions}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def prune_executions(opts \\ []) do
    # Redis lists auto-trim via LTRIM, but we can force cleanup
    limit = Keyword.get(opts, :limit, @max_execution_history)

    case redis_cmd(["KEYS", "#{@exec_prefix}*"]) do
      {:ok, keys} when is_list(keys) ->
        count =
          keys
          |> Enum.map(fn key ->
            case redis_cmd(["LTRIM", key, "0", to_string(limit - 1)]) do
              {:ok, _} -> 1
              _ -> 0
            end
          end)
          |> Enum.sum()

        {:ok, count}

      _ ->
        {:ok, 0}
    end
  end

  # ============================================
  # Unique Job Enforcement - Redis Optimized
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def acquire_unique_lock(key, owner, ttl_ms) do
    lock_key = lock_key(key)
    ttl_seconds = max(div(ttl_ms, 1000), 1)

    # SET NX EX - atomic lock with TTL, no cleanup needed!
    case redis_cmd(["SET", lock_key, owner, "NX", "EX", to_string(ttl_seconds)]) do
      {:ok, "OK"} -> {:ok, key}
      {:ok, nil} -> {:error, :locked}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def release_unique_lock(key, owner) do
    lock_key = lock_key(key)

    # Lua script for atomic check-and-delete
    script = """
    if redis.call("GET", KEYS[1]) == ARGV[1] then
      return redis.call("DEL", KEYS[1])
    else
      return 0
    end
    """

    redis_cmd(["EVAL", script, "1", lock_key, owner])
    :ok
  end

  @impl OmScheduler.Store.Behaviour
  def cleanup_expired_locks do
    # Not needed for Redis - locks auto-expire via TTL!
    {:ok, 0}
  end

  @impl OmScheduler.Store.Behaviour
  def check_unique_conflict(key, _states, _cutoff) do
    lock_key = lock_key(key)

    case redis_cmd(["EXISTS", lock_key]) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      {:error, _} -> {:error, :not_implemented}
    end
  end

  # ============================================
  # Lifeline / Heartbeat Operations
  # ============================================

  @impl OmScheduler.Store.Behaviour
  def record_heartbeat(job_name, _node) do
    # Update heartbeat in a separate key with TTL
    heartbeat_key = "scheduler:heartbeat:#{job_name}"
    now = DateTime.to_iso8601(DateTime.utc_now())

    case redis_cmd(["SET", heartbeat_key, now, "EX", "300"]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def get_stuck_executions(cutoff) do
    # Scan for heartbeat keys and check timestamps
    case redis_cmd(["KEYS", "scheduler:heartbeat:*"]) do
      {:ok, keys} when is_list(keys) ->
        stuck =
          keys
          |> Enum.map(fn key ->
            job_name = String.replace_prefix(key, "scheduler:heartbeat:", "")

            case redis_cmd(["GET", key]) do
              {:ok, timestamp} when is_binary(timestamp) ->
                case DateTime.from_iso8601(timestamp) do
                  {:ok, heartbeat_at, _} ->
                    if DateTime.compare(heartbeat_at, cutoff) == :lt do
                      case get_job(job_name) do
                        {:ok, job} -> %Execution{job_name: job_name, heartbeat_at: heartbeat_at, state: :running, id: job.name}
                        _ -> nil
                      end
                    else
                      nil
                    end

                  _ ->
                    nil
                end

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, stuck}

      _ ->
        {:ok, []}
    end
  end

  @impl OmScheduler.Store.Behaviour
  def mark_execution_rescued(execution_id) do
    # Delete the heartbeat key
    redis_cmd(["DEL", "scheduler:heartbeat:#{execution_id}"])
    publish_event(:job_rescued, execution_id)
    :ok
  end

  # ============================================
  # Pub/Sub for Real-time Notifications
  # ============================================

  @doc """
  Subscribe to job events.

  Events: :job_registered, :job_started, :job_completed, :job_failed, :job_cancelled
  """
  def subscribe do
    # This would be used by monitoring/dashboard
    # For now, just document the capability
    {:ok, @events_channel}
  end

  defp publish_event(event, job_name) do
    message = JSON.encode!(%{event: event, job: job_name, timestamp: DateTime.utc_now()})
    redis_cmd(["PUBLISH", @events_channel, message])
    :ok
  rescue
    _ -> :ok
  end

  # ============================================
  # GenServer Callbacks
  # ============================================

  @impl GenServer
  def init(opts) do
    redis_url = Keyword.get(opts, :redis_url) || Config.get()[:redis_url] || "redis://localhost:6379/0"
    pool_size = Keyword.get(opts, :pool_size, @pool_size)

    # Start pool of connections
    results =
      for i <- 1..pool_size do
        case Redix.start_link(redis_url, name: pool_name(i)) do
          {:ok, pid} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
      end

    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] ->
        Logger.info("OmScheduler Redis store connected with #{pool_size} connections: #{redis_url}")
        {:ok, %{redis_url: redis_url, pool_size: pool_size}}

      [{:error, reason} | _] ->
        Logger.error("Failed to connect to Redis: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    pool_size = Map.get(state, :pool_size, @pool_size)

    for i <- 1..pool_size do
      case Process.whereis(pool_name(i)) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5000)
      end
    end

    :ok
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp redis_cmd(command) do
    Redix.command(random_pool_connection(), command)
  end

  defp redis_pipeline(commands) do
    Redix.pipeline(random_pool_connection(), commands)
  end

  @doc """
  Execute multiple commands in a pipeline for better performance.
  Returns list of results in the same order as commands.
  """
  def batch(commands) when is_list(commands) do
    redis_pipeline(commands)
  end

  defp save_job(job) do
    redis_cmd(["HSET", @jobs_key, job.name, encode(job)])
  end

  defp add_to_due_set(job) do
    if job.next_run_at do
      score = DateTime.to_unix(job.next_run_at, :millisecond)
      redis_cmd(["ZADD", due_key(job.queue), to_string(score), job.name])
    end
  end

  defp update_due_set(job) do
    key = due_key(job.queue)

    if job.next_run_at do
      score = DateTime.to_unix(job.next_run_at, :millisecond)
      redis_cmd(["ZADD", key, to_string(score), job.name])
    else
      redis_cmd(["ZREM", key, job.name])
    end
  end

  defp due_key(queue), do: "#{@due_prefix}#{queue || "default"}"
  defp lock_key(key), do: "#{@lock_prefix}#{key}"
  defp exec_key(job_name), do: "#{@exec_prefix}#{job_name}"

  defp encode(data) do
    data
    |> Map.from_struct()
    |> convert_for_json()
    |> JSON.encode!()
  end

  defp decode(json, struct_module) do
    json
    |> JSON.decode!()
    |> convert_from_json(struct_module)
    |> then(&struct(struct_module, &1))
  end

  defp convert_for_json(map) when is_map(map) do
    Map.new(map, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, v} when is_atom(v) -> {k, to_string(v)}
      {k, v} when is_map(v) -> {k, convert_for_json(v)}
      {k, v} -> {k, v}
    end)
  end

  defp convert_from_json(map, struct_module) do
    fields = struct_module.__struct__() |> Map.keys()

    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k

      value =
        cond do
          key in [:inserted_at, :updated_at, :last_run_at, :next_run_at, :started_at, :completed_at, :heartbeat_at] and is_binary(v) ->
            case DateTime.from_iso8601(v) do
              {:ok, dt, _} -> dt
              _ -> nil
            end

          key in [:state, :schedule_type, :result, :trigger_type] and is_binary(v) ->
            String.to_existing_atom(v)

          key == :name and is_binary(v) and struct_module == Workflow ->
            String.to_atom(v)

          true ->
            v
        end

      if key in fields, do: {key, value}, else: {key, nil}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  rescue
    _ -> map
  end

  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."
  end
end
