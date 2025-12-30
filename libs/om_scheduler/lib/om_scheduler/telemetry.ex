defmodule OmScheduler.Telemetry do
  @moduledoc """
  Telemetry events for the scheduler.

  The telemetry prefix is configurable via:

      config :om_scheduler.Telemetry, telemetry_prefix: [:my_app, :scheduler]

  Default prefix: `[:om_scheduler]`

  ## Job Events

  - `[:om_scheduler, :job, :start]` - Job execution started
  - `[:om_scheduler, :job, :stop]` - Job execution completed
  - `[:om_scheduler, :job, :exception]` - Job execution raised
  - `[:om_scheduler, :job, :skip]` - Job skipped (unique conflict, paused)
  - `[:om_scheduler, :job, :discard]` - Job discarded (max retries)
  - `[:om_scheduler, :job, :cancel]` - Job cancelled
  - `[:om_scheduler, :job, :rescue]` - Stuck job rescued by lifeline

  ## Batch Events

  - `[:om_scheduler, :batch, :start]` - Batch processing started
  - `[:om_scheduler, :batch, :stop]` - Batch processing completed

  ## Peer Events

  - `[:om_scheduler, :peer, :election]` - Node became leader
  - `[:om_scheduler, :peer, :resignation]` - Node lost leadership

  ## Queue Events

  - `[:om_scheduler, :queue, :pause]` - Queue paused
  - `[:om_scheduler, :queue, :resume]` - Queue resumed
  - `[:om_scheduler, :queue, :scale]` - Queue concurrency changed

  ## Rate Limiting Events

  - `[:om_scheduler, :rate_limit, :exceeded]` - Rate limit exceeded

  ## Plugin Events

  - `[:om_scheduler, :plugin, :start]` - Plugin action started
  - `[:om_scheduler, :plugin, :stop]` - Plugin action completed
  - `[:om_scheduler, :plugin, :exception]` - Plugin action failed

  ## Usage

      :telemetry.attach_many(
        "scheduler-logger",
        [
          [:om_scheduler, :job, :start],
          [:om_scheduler, :job, :stop],
          [:om_scheduler, :job, :exception]
        ],
        &MyApp.Telemetry.handle_scheduler_event/4,
        nil
      )
  """

  @prefix Application.compile_env(:om_scheduler, [__MODULE__, :telemetry_prefix], [:om_scheduler])

  @doc """
  Executes a job within a telemetry span.

  Automatically emits start/stop/exception events.
  """
  @spec span(atom(), map(), (-> term())) :: term()
  def span(event, meta, fun) when is_atom(event) do
    span([event], meta, fun)
  end

  def span(suffix, meta, fun) when is_list(suffix) and is_function(fun, 0) do
    start_time = System.monotonic_time()
    start_meta = Map.put(meta, :system_time, System.system_time())

    execute(suffix ++ [:start], %{system_time: System.system_time()}, start_meta)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      execute(
        suffix ++ [:stop],
        %{duration: duration, monotonic_time: System.monotonic_time()},
        Map.put(meta, :result, result)
      )

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        execute(
          suffix ++ [:exception],
          %{duration: duration, monotonic_time: System.monotonic_time()},
          Map.merge(meta, %{
            kind: :error,
            reason: exception,
            stacktrace: __STACKTRACE__
          })
        )

        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        duration = System.monotonic_time() - start_time

        execute(
          suffix ++ [:exception],
          %{duration: duration, monotonic_time: System.monotonic_time()},
          Map.merge(meta, %{
            kind: kind,
            reason: reason,
            stacktrace: __STACKTRACE__
          })
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Executes a telemetry event.
  """
  @spec execute(list() | atom(), map(), map()) :: :ok
  def execute(suffix, measurements, meta) when is_atom(suffix) do
    execute([suffix], measurements, meta)
  end

  def execute(suffix, measurements, meta) when is_list(suffix) do
    :telemetry.execute(@prefix ++ suffix, measurements, meta)
  end

  # ============================================
  # Convenience Functions
  # ============================================

  @doc """
  Emits a job start event.
  """
  @spec job_start(map()) :: :ok
  def job_start(meta) do
    execute([:job, :start], %{system_time: System.system_time()}, meta)
  end

  @doc """
  Emits a job stop event.
  """
  @spec job_stop(map(), pos_integer()) :: :ok
  def job_stop(meta, duration) do
    execute(
      [:job, :stop],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      meta
    )
  end

  @doc """
  Emits a job exception event.
  """
  @spec job_exception(map(), pos_integer(), term(), term(), list()) :: :ok
  def job_exception(meta, duration, kind, reason, stacktrace) do
    execute(
      [:job, :exception],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      Map.merge(meta, %{kind: kind, reason: reason, stacktrace: stacktrace})
    )
  end

  @doc """
  Emits a job skip event.
  """
  @spec job_skip(map(), atom()) :: :ok
  def job_skip(meta, reason) do
    execute(
      [:job, :skip],
      %{system_time: System.system_time()},
      Map.put(meta, :skip_reason, reason)
    )
  end

  @doc """
  Emits a job discard event.
  """
  @spec job_discard(map(), term()) :: :ok
  def job_discard(meta, reason) do
    execute(
      [:job, :discard],
      %{system_time: System.system_time()},
      Map.put(meta, :discard_reason, reason)
    )
  end

  @doc """
  Emits a job cancel event.
  """
  @spec job_cancel(map(), term()) :: :ok
  def job_cancel(meta, reason) do
    execute(
      [:job, :cancel],
      %{system_time: System.system_time()},
      Map.put(meta, :cancel_reason, reason)
    )
  end

  @doc """
  Emits a queue event.
  """
  @spec queue_event(atom(), atom(), map()) :: :ok
  def queue_event(event, queue, meta \\ %{}) do
    execute(
      [:queue, event],
      %{system_time: System.system_time()},
      Map.put(meta, :queue, queue)
    )
  end

  @doc """
  Emits a peer event.
  """
  @spec peer_event(atom(), map()) :: :ok
  def peer_event(event, meta \\ %{}) do
    execute(
      [:peer, event],
      %{system_time: System.system_time()},
      Map.put(meta, :node, node())
    )
  end

  @doc """
  Emits a plugin event.
  """
  @spec plugin_event(atom(), atom(), map()) :: :ok
  def plugin_event(event, plugin, meta \\ %{}) do
    execute(
      [:plugin, event],
      %{system_time: System.system_time()},
      Map.put(meta, :plugin, plugin)
    )
  end
end
