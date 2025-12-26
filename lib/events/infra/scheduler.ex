defmodule Events.Infra.Scheduler do
  @moduledoc """
  Events-specific scheduler wrapper over OmScheduler.

  This module provides a thin wrapper that delegates to `OmScheduler` with
  Events-specific defaults (repo, telemetry prefix, etc.).

  ## Usage

      # Configure in config.exs
      config :om_scheduler,
        repo: Events.Core.Repo,
        telemetry_prefix: [:events, :scheduler]

      # Start scheduler in application.ex
      children = [
        {OmScheduler.Supervisor, name: Events.Infra.Scheduler}
      ]

      # Use the scheduler
      Events.Infra.Scheduler.insert(%{
        name: "cleanup",
        module: MyApp.Jobs,
        function: :cleanup,
        cron: "0 3 * * *"
      })

  ## Workflow Support

  See `OmScheduler.Workflow` for DAG-based workflow orchestration.

  See `OmScheduler` for full documentation.
  """

  # Re-export main OmScheduler functions
  defdelegate insert(attrs), to: OmScheduler
  defdelegate get_job(name), to: OmScheduler
  defdelegate run_now(name), to: OmScheduler
  defdelegate cancel_job(name, opts \\ []), to: OmScheduler
  defdelegate pause_job(name), to: OmScheduler
  defdelegate resume_job(name), to: OmScheduler
  defdelegate pause_queue(queue), to: OmScheduler
  defdelegate resume_queue(queue), to: OmScheduler
end

# Namespace aliases for convenience
defmodule Events.Infra.Scheduler.Job do
  @moduledoc false
  defdelegate __struct__(), to: OmScheduler.Job
  defdelegate __struct__(kv), to: OmScheduler.Job
end

defmodule Events.Infra.Scheduler.Supervisor do
  @moduledoc false
  defdelegate child_spec(opts), to: OmScheduler.Supervisor
  defdelegate start_link(opts \\ []), to: OmScheduler.Supervisor
end

defmodule Events.Infra.Scheduler.Workflow do
  @moduledoc """
  Events-specific workflow wrapper over OmScheduler.Workflow.

  See `OmScheduler.Workflow` for full documentation.
  """
  defdelegate start(name, context \\ %{}), to: OmScheduler.Workflow
  defdelegate get_state(execution_id), to: OmScheduler.Workflow
  defdelegate cancel(execution_id, opts \\ []), to: OmScheduler.Workflow
  defdelegate pause(execution_id), to: OmScheduler.Workflow
  defdelegate resume(execution_id, opts \\ []), to: OmScheduler.Workflow
end

defmodule Events.Infra.Scheduler.Cron do
  @moduledoc false
  defdelegate parse(expression), to: OmScheduler.Cron
  defdelegate next_run(cron, from \\ DateTime.utc_now()), to: OmScheduler.Cron
end

defmodule Events.Infra.Scheduler.Config do
  @moduledoc false
  defdelegate get(), to: OmScheduler.Config
  defdelegate get!(), to: OmScheduler.Config
  defdelegate repo(), to: OmScheduler.Config
end

defmodule Events.Infra.Scheduler.Workflow.Registry do
  @moduledoc false
  defdelegate list_workflows(), to: OmScheduler.Workflow.Registry
  defdelegate list_running_executions(opts \\ []), to: OmScheduler.Workflow.Registry
  defdelegate get_execution(id), to: OmScheduler.Workflow.Registry
  defdelegate get_stats(), to: OmScheduler.Workflow.Registry
end

defmodule Events.Infra.Scheduler.Workflow.Store do
  @moduledoc false
  defdelegate list_running_executions(opts \\ []), to: OmScheduler.Workflow.Store
  defdelegate list_executions(workflow_name, opts \\ []), to: OmScheduler.Workflow.Store
  defdelegate get_execution(id), to: OmScheduler.Workflow.Store
  defdelegate get_stats(), to: OmScheduler.Workflow.Store
end
