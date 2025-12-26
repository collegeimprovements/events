defmodule OmScheduler.Middleware.Logging do
  @moduledoc """
  Middleware for logging job execution.

  Logs job start, completion, and errors with configurable log levels.

  ## Configuration

      config :om_scheduler,
        middleware: [
          {OmScheduler.Middleware.Logging, level: :info}
        ]

  ## Options

  - `:level` - Log level for normal events (:debug, :info, :warning, :error). Default: :info
  - `:error_level` - Log level for errors. Default: :error
  - `:include_args` - Include job args in logs. Default: false
  - `:include_result` - Include job result in logs. Default: false
  """

  @behaviour OmScheduler.Middleware

  require Logger

  alias OmScheduler.Job

  @impl true
  def before_execute(%Job{} = job, context) do
    level = Map.get(context, :log_level, :info)
    include_args = Map.get(context, :include_args, false)

    message = build_start_message(job, include_args)
    Logger.log(level, message)

    {:ok, Map.put(context, :middleware_logged_at, System.monotonic_time())}
  end

  @impl true
  def after_execute(%Job{} = job, result, context) do
    level = Map.get(context, :log_level, :info)
    include_result = Map.get(context, :include_result, false)
    started_at = Map.get(context, :middleware_logged_at, System.monotonic_time())

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - started_at,
        :native,
        :millisecond
      )

    message = build_complete_message(job, result, duration_ms, include_result)
    Logger.log(level, message)

    {:ok, result}
  end

  @impl true
  def on_error(%Job{} = job, error, context) do
    error_level = Map.get(context, :error_level, :error)
    started_at = Map.get(context, :middleware_logged_at, System.monotonic_time())

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - started_at,
        :native,
        :millisecond
      )

    message = build_error_message(job, error, duration_ms)
    Logger.log(error_level, message)

    {:ok, error}
  end

  @impl true
  def on_complete(%Job{} = _job, _result, _context), do: :ok

  # ============================================
  # Private Helpers
  # ============================================

  defp build_start_message(job, include_args) do
    base = "[Scheduler] Starting job=#{job.name} queue=#{job.queue}"

    case include_args do
      true -> "#{base} args=#{inspect(job.args)}"
      false -> base
    end
  end

  defp build_complete_message(job, result, duration_ms, include_result) do
    base = "[Scheduler] Completed job=#{job.name} duration=#{duration_ms}ms"

    case include_result do
      true -> "#{base} result=#{inspect(result)}"
      false -> base
    end
  end

  defp build_error_message(job, error, duration_ms) do
    "[Scheduler] Failed job=#{job.name} duration=#{duration_ms}ms error=#{inspect(error)}"
  end
end
