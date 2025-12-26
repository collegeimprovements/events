defmodule OmScheduler.Middleware.Telemetry do
  @moduledoc """
  Middleware for emitting telemetry events during job execution.

  Complements the built-in telemetry with middleware-specific events
  that include timing and context data.

  ## Configuration

      config :om_scheduler,
        middleware: [
          OmScheduler.Middleware.Telemetry
        ]

  ## Events Emitted

  - `[:scheduler, :middleware, :before]` - Before job starts
  - `[:scheduler, :middleware, :after]` - After job completes successfully
  - `[:scheduler, :middleware, :error]` - When job fails
  - `[:scheduler, :middleware, :complete]` - Always (success or failure)

  ## Measurements

  - `:duration` - Execution duration in native time units
  - `:duration_ms` - Execution duration in milliseconds

  ## Metadata

  - `:job` - The job struct
  - `:job_name` - Job name
  - `:queue` - Queue name
  - `:result` - Job result (after/complete events)
  - `:error` - Error reason (error events)
  """

  @behaviour OmScheduler.Middleware

  alias OmScheduler.Job

  @impl true
  def before_execute(%Job{} = job, context) do
    start_time = System.monotonic_time()

    meta = %{
      job: job,
      job_name: job.name,
      queue: job.queue
    }

    :telemetry.execute(
      [:scheduler, :middleware, :before],
      %{system_time: System.system_time()},
      meta
    )

    {:ok, Map.put(context, :middleware_start_time, start_time)}
  end

  @impl true
  def after_execute(%Job{} = job, result, context) do
    duration = calculate_duration(context)

    meta = %{
      job: job,
      job_name: job.name,
      queue: job.queue,
      result: result
    }

    :telemetry.execute(
      [:scheduler, :middleware, :after],
      %{duration: duration, duration_ms: to_ms(duration)},
      meta
    )

    {:ok, result}
  end

  @impl true
  def on_error(%Job{} = job, error, context) do
    duration = calculate_duration(context)

    meta = %{
      job: job,
      job_name: job.name,
      queue: job.queue,
      error: error
    }

    :telemetry.execute(
      [:scheduler, :middleware, :error],
      %{duration: duration, duration_ms: to_ms(duration)},
      meta
    )

    {:ok, error}
  end

  @impl true
  def on_complete(%Job{} = job, result, context) do
    duration = calculate_duration(context)

    meta = %{
      job: job,
      job_name: job.name,
      queue: job.queue,
      result: result
    }

    :telemetry.execute(
      [:scheduler, :middleware, :complete],
      %{duration: duration, duration_ms: to_ms(duration)},
      meta
    )

    :ok
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp calculate_duration(context) do
    case Map.get(context, :middleware_start_time) do
      nil -> 0
      start_time -> System.monotonic_time() - start_time
    end
  end

  defp to_ms(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end
end
