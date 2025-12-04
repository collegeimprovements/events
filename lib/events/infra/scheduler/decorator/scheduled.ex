defmodule Events.Infra.Scheduler.Decorator.Scheduled do
  @moduledoc """
  Decorator implementation for `@decorate scheduled(...)`.

  Collects scheduled job definitions at compile time and registers them
  with the scheduler.

  ## Usage

      defmodule MyApp.Jobs do
        use Events.Infra.Scheduler

        @decorate scheduled(cron: "0 6 * * *")
        def daily_report, do: Reports.generate()

        @decorate scheduled(every: {5, :minutes}, unique: true)
        def sync_data, do: Sync.run()
      end

  ## Options

  - `:cron` - Cron expression(s) or macro (@hourly, @daily, etc.)
  - `:every` - Interval: `{5, :minutes}`, `{30, :seconds}`
  - `:zone` - Timezone for cron (default: "Etc/UTC")
  - `:queue` - Queue name (default: :default)
  - `:timeout` - Execution timeout
  - `:max_retries` - Max retry attempts (default: 3)
  - `:unique` - Prevent overlapping executions
  - `:tags` - Tags for filtering
  - `:priority` - Priority 0-9 (lower is higher)
  """

  alias Events.Infra.Scheduler.Job

  @doc """
  Decorator transformation for scheduled functions.

  Called by the decorator system at compile time.
  """
  def scheduled(opts, body, context) do
    %{module: module, name: function_name, arity: arity} = context

    # Only decorate 0-arity functions
    if arity != 0 do
      raise CompileError,
        description: "@decorate scheduled can only be used on 0-arity functions",
        file: context.file,
        line: context.line
    end

    # Build job spec
    job_spec = Job.from_decorator_opts(module, function_name, opts)

    # Register the job spec in module attribute
    quote do
      @__scheduled_jobs__ unquote(Macro.escape(job_spec))

      # Return the original body unchanged
      unquote(body)
    end
  end

  @doc """
  Called when module is compiled to collect all scheduled jobs.
  """
  defmacro __before_compile__(env) do
    jobs = Module.get_attribute(env.module, :__scheduled_jobs__, [])

    quote do
      @doc false
      def __scheduled_jobs__ do
        unquote(Macro.escape(jobs))
      end
    end
  end
end
