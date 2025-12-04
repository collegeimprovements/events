defmodule Events.Infra.Scheduler.Middleware.ErrorReporter do
  @moduledoc """
  Middleware for reporting job errors to external services.

  Provides integration points for error tracking services like Sentry,
  AppSignal, Honeybadger, etc.

  ## Configuration

      config :events, Events.Infra.Scheduler,
        middleware: [
          {Events.Infra.Scheduler.Middleware.ErrorReporter,
           reporter: &MyApp.ErrorReporter.report/2}
        ]

  ## Options

  - `:reporter` - Function to call with (error, context). Required.
  - `:include_stacktrace` - Include stacktrace in context. Default: true
  - `:include_job` - Include full job struct in context. Default: true
  - `:filter` - Function to filter which errors to report. Default: all errors

  ## Reporter Function

  The reporter function receives:
  - `error` - The error that occurred
  - `context` - Map with job info, stacktrace, etc.

  ## Example Reporter

      defmodule MyApp.ErrorReporter do
        def report(error, context) do
          Sentry.capture_exception(error,
            extra: context,
            tags: %{job: context.job_name, queue: context.queue}
          )
        end
      end
  """

  @behaviour Events.Infra.Scheduler.Middleware

  require Logger

  alias Events.Infra.Scheduler.Job

  @impl true
  def before_execute(%Job{} = _job, context) do
    {:ok, context}
  end

  @impl true
  def after_execute(%Job{} = _job, result, _context) do
    {:ok, result}
  end

  @impl true
  def on_error(%Job{} = job, error, context) do
    case should_report?(error, context) do
      true -> do_report(job, error, context)
      false -> :ok
    end

    {:ok, error}
  end

  @impl true
  def on_complete(%Job{} = _job, _result, _context), do: :ok

  # ============================================
  # Private Helpers
  # ============================================

  defp should_report?(error, context) do
    case Map.get(context, :error_filter) do
      nil -> true
      filter when is_function(filter, 1) -> filter.(error)
      filter when is_function(filter, 2) -> filter.(error, context)
    end
  end

  defp do_report(job, error, context) do
    reporter = Map.get(context, :reporter)

    case reporter do
      nil ->
        Logger.warning("[Scheduler.ErrorReporter] No reporter configured")

      fun when is_function(fun, 2) ->
        report_context = build_report_context(job, error, context)
        safe_call(fun, [error, report_context])

      {module, function} ->
        report_context = build_report_context(job, error, context)
        safe_call(fn e, c -> apply(module, function, [e, c]) end, [error, report_context])
    end
  end

  defp build_report_context(job, error, context) do
    base = %{
      job_name: job.name,
      queue: job.queue,
      module: job.module,
      function: job.function,
      args: job.args,
      attempt: Map.get(context, :attempt, 1),
      error_type: classify_error(error)
    }

    base
    |> maybe_add_job(job, context)
    |> maybe_add_stacktrace(error, context)
  end

  defp maybe_add_job(report_context, job, context) do
    case Map.get(context, :include_job, true) do
      true -> Map.put(report_context, :job, job)
      false -> report_context
    end
  end

  defp maybe_add_stacktrace(report_context, error, context) do
    case Map.get(context, :include_stacktrace, true) do
      true ->
        stacktrace = extract_stacktrace(error)
        Map.put(report_context, :stacktrace, stacktrace)

      false ->
        report_context
    end
  end

  defp extract_stacktrace({:exception, _exception, stacktrace}), do: stacktrace
  defp extract_stacktrace({_kind, _reason, stacktrace}) when is_list(stacktrace), do: stacktrace
  defp extract_stacktrace(_), do: nil

  defp classify_error({:exception, exception, _}), do: exception.__struct__
  defp classify_error({:exit, _}), do: :exit
  defp classify_error({:throw, _}), do: :throw
  defp classify_error(:timeout), do: :timeout
  defp classify_error({:timeout, _}), do: :timeout
  defp classify_error(_), do: :error

  defp safe_call(fun, args) do
    apply(fun, args)
  rescue
    e ->
      Logger.error("[Scheduler.ErrorReporter] Reporter failed: #{inspect(e)}")
  end
end
