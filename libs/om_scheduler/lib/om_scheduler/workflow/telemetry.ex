defmodule OmScheduler.Workflow.Telemetry do
  @moduledoc """
  Telemetry events for the workflow system.

  The telemetry prefix is configurable via:

      config :om_scheduler.Workflow.Telemetry, telemetry_prefix: [:my_app, :scheduler, :workflow]

  Default prefix: `[:om_scheduler, :workflow]`

  ## Workflow Events

  - `[:om_scheduler, :workflow, :start]` - Workflow execution started
  - `[:om_scheduler, :workflow, :stop]` - Workflow execution completed
  - `[:om_scheduler, :workflow, :exception]` - Workflow execution raised
  - `[:om_scheduler, :workflow, :pause]` - Workflow paused (awaiting approval)
  - `[:om_scheduler, :workflow, :resume]` - Workflow resumed
  - `[:om_scheduler, :workflow, :cancel]` - Workflow cancelled
  - `[:om_scheduler, :workflow, :fail]` - Workflow failed

  ## Step Events

  - `[:om_scheduler, :workflow, :step, :start]` - Step execution started
  - `[:om_scheduler, :workflow, :step, :stop]` - Step execution completed
  - `[:om_scheduler, :workflow, :step, :exception]` - Step execution raised
  - `[:om_scheduler, :workflow, :step, :skip]` - Step skipped (condition false)
  - `[:om_scheduler, :workflow, :step, :retry]` - Step being retried
  - `[:om_scheduler, :workflow, :step, :cancel]` - Step cancelled

  ## Rollback Events

  - `[:om_scheduler, :workflow, :rollback, :start]` - Rollback started
  - `[:om_scheduler, :workflow, :rollback, :stop]` - Rollback completed
  - `[:om_scheduler, :workflow, :rollback, :exception]` - Rollback failed

  ## Graft Events

  - `[:om_scheduler, :workflow, :graft, :expand]` - Graft expanded to steps

  ## Usage

      :telemetry.attach_many(
        "workflow-logger",
        [
          [:om_scheduler, :workflow, :start],
          [:om_scheduler, :workflow, :stop],
          [:om_scheduler, :workflow, :step, :start],
          [:om_scheduler, :workflow, :step, :stop]
        ],
        &MyApp.Telemetry.handle_workflow_event/4,
        nil
      )

  ## Metadata

  Workflow events include:
  - `workflow_name` - The workflow name (atom)
  - `execution_id` - The execution ID
  - `trigger_type` - How the workflow was triggered (:manual, :scheduled, :event)

  Step events also include:
  - `step_name` - The step name (atom)
  - `attempt` - Current retry attempt number
  - `context` - Step execution context

  ## Example Handler

      defmodule MyApp.Telemetry do
        require Logger

        def handle_workflow_event(
          [:om_scheduler, :workflow, :start],
          _measurements,
          %{workflow_name: name, execution_id: id},
          _config
        ) do
          Logger.info("Workflow \#{name} started (\#{id})")
        end

        def handle_workflow_event(
          [:om_scheduler, :workflow, :stop],
          %{duration: duration},
          %{workflow_name: name, execution_id: id},
          _config
        ) do
          Logger.info("Workflow \#{name} completed in \#{duration / 1_000_000}ms (\#{id})")
        end

        def handle_workflow_event(
          [:om_scheduler, :workflow, :step, :stop],
          %{duration: duration},
          %{workflow_name: name, step_name: step, execution_id: id},
          _config
        ) do
          Logger.debug("Step \#{step} in \#{name} completed in \#{duration / 1_000_000}ms")
        end
      end
  """

  @prefix Application.compile_env(:om_scheduler, [__MODULE__, :telemetry_prefix], [
            :om_scheduler,
            :workflow
          ])

  # ============================================
  # Span Functions
  # ============================================

  @doc """
  Executes a workflow within a telemetry span.

  Automatically emits start/stop/exception events.
  """
  @spec span(list() | atom(), map(), (-> term())) :: term()
  def span(suffix, meta, fun) when is_atom(suffix) do
    span([suffix], meta, fun)
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
  # Workflow Events
  # ============================================

  @doc """
  Emits a workflow start event.
  """
  @spec workflow_start(atom(), String.t(), map()) :: :ok
  def workflow_start(workflow_name, execution_id, meta \\ %{}) do
    execute(
      [:start],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id
      })
    )
  end

  @doc """
  Emits a workflow stop event.
  """
  @spec workflow_stop(atom(), String.t(), pos_integer(), map()) :: :ok
  def workflow_stop(workflow_name, execution_id, duration, meta \\ %{}) do
    execute(
      [:stop],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id
      })
    )
  end

  @doc """
  Emits a workflow exception event.
  """
  @spec workflow_exception(atom(), String.t(), pos_integer(), term(), term(), list()) :: :ok
  def workflow_exception(workflow_name, execution_id, duration, kind, reason, stacktrace) do
    execute(
      [:exception],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      }
    )
  end

  @doc """
  Emits a workflow pause event (awaiting approval).
  """
  @spec workflow_pause(atom(), String.t(), atom(), map()) :: :ok
  def workflow_pause(workflow_name, execution_id, step_name, meta \\ %{}) do
    execute(
      [:pause],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        awaiting_step: step_name
      })
    )
  end

  @doc """
  Emits a workflow resume event.
  """
  @spec workflow_resume(atom(), String.t(), map()) :: :ok
  def workflow_resume(workflow_name, execution_id, meta \\ %{}) do
    execute(
      [:resume],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id
      })
    )
  end

  @doc """
  Emits a workflow cancel event.
  """
  @spec workflow_cancel(atom(), String.t(), term(), map()) :: :ok
  def workflow_cancel(workflow_name, execution_id, reason, meta \\ %{}) do
    execute(
      [:cancel],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        cancel_reason: reason
      })
    )
  end

  @doc """
  Emits a workflow fail event.
  """
  @spec workflow_fail(atom(), String.t(), term(), atom() | nil, map()) :: :ok
  def workflow_fail(workflow_name, execution_id, error, error_step \\ nil, meta \\ %{}) do
    execute(
      [:fail],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        error: error,
        error_step: error_step
      })
    )
  end

  # ============================================
  # Step Events
  # ============================================

  @doc """
  Emits a step start event.
  """
  @spec step_start(atom(), String.t(), atom(), non_neg_integer(), map()) :: :ok
  def step_start(workflow_name, execution_id, step_name, attempt, meta \\ %{}) do
    execute(
      [:step, :start],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        attempt: attempt
      })
    )
  end

  @doc """
  Emits a step stop event.
  """
  @spec step_stop(atom(), String.t(), atom(), pos_integer(), term(), map()) :: :ok
  def step_stop(workflow_name, execution_id, step_name, duration, result, meta \\ %{}) do
    execute(
      [:step, :stop],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        result: result
      })
    )
  end

  @doc """
  Emits a step exception event.
  """
  @spec step_exception(atom(), String.t(), atom(), pos_integer(), term(), term(), list()) :: :ok
  def step_exception(workflow_name, execution_id, step_name, duration, kind, reason, stacktrace) do
    execute(
      [:step, :exception],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      }
    )
  end

  @doc """
  Emits a step skip event.
  """
  @spec step_skip(atom(), String.t(), atom(), term(), map()) :: :ok
  def step_skip(workflow_name, execution_id, step_name, reason, meta \\ %{}) do
    execute(
      [:step, :skip],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        skip_reason: reason
      })
    )
  end

  @doc """
  Emits a step retry event.
  """
  @spec step_retry(atom(), String.t(), atom(), non_neg_integer(), term(), pos_integer(), map()) ::
          :ok
  def step_retry(workflow_name, execution_id, step_name, attempt, error, delay_ms, meta \\ %{}) do
    execute(
      [:step, :retry],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        attempt: attempt,
        error: error,
        delay_ms: delay_ms
      })
    )
  end

  @doc """
  Emits a step cancel event.
  """
  @spec step_cancel(atom(), String.t(), atom(), map()) :: :ok
  def step_cancel(workflow_name, execution_id, step_name, meta \\ %{}) do
    execute(
      [:step, :cancel],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name
      })
    )
  end

  # ============================================
  # Rollback Events
  # ============================================

  @doc """
  Emits a rollback start event.
  """
  @spec rollback_start(atom(), String.t(), [atom()], map()) :: :ok
  def rollback_start(workflow_name, execution_id, steps_to_rollback, meta \\ %{}) do
    execute(
      [:rollback, :start],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        steps: steps_to_rollback,
        step_count: length(steps_to_rollback)
      })
    )
  end

  @doc """
  Emits a rollback stop event.
  """
  @spec rollback_stop(atom(), String.t(), pos_integer(), map()) :: :ok
  def rollback_stop(workflow_name, execution_id, duration, meta \\ %{}) do
    execute(
      [:rollback, :stop],
      %{duration: duration, monotonic_time: System.monotonic_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id
      })
    )
  end

  @doc """
  Emits a rollback exception event.
  """
  @spec rollback_exception(atom(), String.t(), atom(), term(), term(), list()) :: :ok
  def rollback_exception(workflow_name, execution_id, step_name, kind, reason, stacktrace) do
    execute(
      [:rollback, :exception],
      %{system_time: System.system_time()},
      %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      }
    )
  end

  # ============================================
  # Graft Events
  # ============================================

  @doc """
  Emits a graft expand event.
  """
  @spec graft_expand(atom(), String.t(), atom(), [atom()], map()) :: :ok
  def graft_expand(workflow_name, execution_id, graft_name, expanded_steps, meta \\ %{}) do
    execute(
      [:graft, :expand],
      %{system_time: System.system_time()},
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        graft_name: graft_name,
        expanded_steps: expanded_steps,
        step_count: length(expanded_steps)
      })
    )
  end

  # ============================================
  # Convenience Spans
  # ============================================

  @doc """
  Wraps a workflow execution in a telemetry span.
  """
  @spec workflow_span(atom(), String.t(), map(), (-> term())) :: term()
  def workflow_span(workflow_name, execution_id, meta, fun) do
    span(
      [],
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id
      }),
      fun
    )
  end

  @doc """
  Wraps a step execution in a telemetry span.
  """
  @spec step_span(atom(), String.t(), atom(), non_neg_integer(), map(), (-> term())) :: term()
  def step_span(workflow_name, execution_id, step_name, attempt, meta, fun) do
    span(
      [:step],
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        step_name: step_name,
        attempt: attempt
      }),
      fun
    )
  end

  @doc """
  Wraps a rollback execution in a telemetry span.
  """
  @spec rollback_span(atom(), String.t(), [atom()], map(), (-> term())) :: term()
  def rollback_span(workflow_name, execution_id, steps, meta, fun) do
    span(
      [:rollback],
      Map.merge(meta, %{
        workflow_name: workflow_name,
        execution_id: execution_id,
        steps: steps
      }),
      fun
    )
  end
end
