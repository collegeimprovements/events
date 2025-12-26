defmodule OmScheduler.Decorator do
  @moduledoc """
  Decorator support for OmScheduler.

  This module provides the `@decorate` attribute for scheduler-related decorators:
  - `scheduled` - Cron job scheduling
  - `step` - Workflow step definition
  - `graft` - Dynamic workflow grafting
  - `subworkflow` - Nested workflows

  It also includes all FnDecorator decorators (caching, telemetry, debugging, etc.)
  for a complete decorator experience.

  ## Usage

      defmodule MyApp.Jobs do
        use OmScheduler

        @decorate scheduled(cron: "0 6 * * *")
        def daily_report do
          Reports.generate()
        end

        @decorate scheduled(every: {5, :minutes})
        @decorate telemetry_span([:my_app, :jobs, :sync])
        def sync_data do
          Sync.run()
        end
      end

  ## Available Decorators

  ### Scheduler Decorators

  - `@decorate scheduled(opts)` - Schedule a job with cron or interval
  - `@decorate step(opts)` - Define a workflow step
  - `@decorate graft(opts)` - Dynamic workflow grafting
  - `@decorate subworkflow(name, opts)` - Nested workflow

  ### FnDecorator Decorators (included)

  All FnDecorator decorators are available:
  - Caching: `cacheable`, `cache_put`, `cache_evict`
  - Telemetry: `telemetry_span`, `log_call`, `log_if_slow`
  - Types: `returns_result`, `returns_maybe`
  - And more...

  See `FnDecorator` for the complete list.
  """

  @doc """
  Sets up decorator support for a module.
  """
  defmacro __using__(_opts) do
    quote do
      use OmScheduler.Decorator.Define

      # Make utilities available
      alias FnDecorator.Support.AST
      alias FnDecorator.Support.Context
    end
  end
end
