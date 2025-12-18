defmodule Effect.Telemetry do
  @moduledoc """
  Telemetry integration for Effect execution.

  Emits telemetry events at key points during effect execution:

  ## Events

  - `[:effect, :run, :start]` - Effect execution started
  - `[:effect, :run, :stop]` - Effect execution completed successfully
  - `[:effect, :run, :exception]` - Effect execution failed with exception

  - `[:effect, :step, :start]` - Step execution started
  - `[:effect, :step, :stop]` - Step execution completed
  - `[:effect, :step, :exception]` - Step execution failed

  - `[:effect, :step, :retry]` - Step is being retried
  - `[:effect, :step, :rollback, :start]` - Rollback started
  - `[:effect, :step, :rollback, :stop]` - Rollback completed

  ## Measurements

  Events include timing measurements:
  - `:duration` - Duration in native time units
  - `:monotonic_time` - Monotonic time when event occurred

  ## Metadata

  Events include relevant metadata:
  - `:effect_name` - Name of the effect
  - `:execution_id` - Unique execution identifier
  - `:step` - Step name (for step events)
  - `:attempt` - Attempt number (for retry events)
  - `:result` - Execution result (:ok, :error, :halted)

  ## Example Handler

      :telemetry.attach(
        "effect-logger",
        [:effect, :run, :stop],
        fn _event, measurements, metadata, _config ->
          Logger.info("Effect \#{metadata.effect_name} completed in \#{measurements.duration}ns")
        end,
        nil
      )

  ## Custom Prefix

  You can customize the event prefix per-effect:

      Effect.new(:order, telemetry: [:myapp, :order])
      # Emits [:myapp, :order, :run, :start] etc.
  """

  @default_prefix [:effect]

  @doc """
  Executes a function with telemetry span events.

  Emits :start before, and :stop/:exception after execution.
  """
  @spec span(list(), map(), (() -> result)) :: result when result: term()
  def span(event_prefix, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    emit(event_prefix ++ [:start], %{monotonic_time: start_time}, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      emit(
        event_prefix ++ [:stop],
        %{duration: duration, monotonic_time: System.monotonic_time()},
        Map.put(metadata, :result, result_status(result))
      )

      result
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        emit(
          event_prefix ++ [:exception],
          %{duration: duration, monotonic_time: System.monotonic_time()},
          Map.merge(metadata, %{exception: exception, stacktrace: __STACKTRACE__})
        )

        reraise exception, __STACKTRACE__
    end
  end

  @doc """
  Emits a telemetry event.
  """
  @spec emit(list(), map(), map()) :: :ok
  def emit(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Returns the event prefix for an effect.
  """
  @spec prefix(atom() | list() | nil) :: list()
  def prefix(nil), do: @default_prefix
  def prefix(prefix) when is_list(prefix), do: prefix
  def prefix(name) when is_atom(name), do: @default_prefix ++ [name]

  @doc """
  Emits an effect run start event.
  """
  @spec emit_run_start(list(), atom(), String.t(), map()) :: :ok
  def emit_run_start(prefix, effect_name, execution_id, ctx) do
    emit(
      prefix ++ [:run, :start],
      %{monotonic_time: System.monotonic_time()},
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        context_keys: Map.keys(ctx)
      }
    )
  end

  @doc """
  Emits an effect run stop event.
  """
  @spec emit_run_stop(list(), atom(), String.t(), term(), non_neg_integer()) :: :ok
  def emit_run_stop(prefix, effect_name, execution_id, result, duration_ms) do
    emit(
      prefix ++ [:run, :stop],
      %{
        duration: duration_ms * 1_000_000,
        monotonic_time: System.monotonic_time()
      },
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        result: result_status(result)
      }
    )
  end

  @doc """
  Emits a step start event.
  """
  @spec emit_step_start(list(), atom(), String.t(), atom()) :: :ok
  def emit_step_start(prefix, effect_name, execution_id, step_name) do
    emit(
      prefix ++ [:step, :start],
      %{monotonic_time: System.monotonic_time()},
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        step: step_name
      }
    )
  end

  @doc """
  Emits a step stop event.
  """
  @spec emit_step_stop(list(), atom(), String.t(), atom(), term(), non_neg_integer()) :: :ok
  def emit_step_stop(prefix, effect_name, execution_id, step_name, result, duration_ms) do
    emit(
      prefix ++ [:step, :stop],
      %{
        duration: duration_ms * 1_000_000,
        monotonic_time: System.monotonic_time()
      },
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        step: step_name,
        result: result_status(result)
      }
    )
  end

  @doc """
  Emits a step retry event.
  """
  @spec emit_step_retry(list(), atom(), String.t(), atom(), pos_integer(), term()) :: :ok
  def emit_step_retry(prefix, effect_name, execution_id, step_name, attempt, reason) do
    emit(
      prefix ++ [:step, :retry],
      %{monotonic_time: System.monotonic_time()},
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        step: step_name,
        attempt: attempt,
        reason: reason
      }
    )
  end

  @doc """
  Emits a rollback start event.
  """
  @spec emit_rollback_start(list(), atom(), String.t(), atom()) :: :ok
  def emit_rollback_start(prefix, effect_name, execution_id, step_name) do
    emit(
      prefix ++ [:step, :rollback, :start],
      %{monotonic_time: System.monotonic_time()},
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        step: step_name
      }
    )
  end

  @doc """
  Emits a rollback stop event.
  """
  @spec emit_rollback_stop(list(), atom(), String.t(), atom(), :ok | :error, non_neg_integer()) :: :ok
  def emit_rollback_stop(prefix, effect_name, execution_id, step_name, result, duration_ms) do
    emit(
      prefix ++ [:step, :rollback, :stop],
      %{
        duration: duration_ms * 1_000_000,
        monotonic_time: System.monotonic_time()
      },
      %{
        effect_name: effect_name,
        execution_id: execution_id,
        step: step_name,
        result: result
      }
    )
  end

  # Determine result status from various return types
  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, _}), do: :error
  defp result_status({:halted, _}), do: :halted
  defp result_status(:ok), do: :ok
  defp result_status(:error), do: :error
  defp result_status(_), do: :unknown
end
