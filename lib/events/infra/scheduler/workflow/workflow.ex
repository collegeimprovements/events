defmodule Events.Infra.Scheduler.Workflow do
  @moduledoc """
  Workflow definition for multi-step job orchestration.

  A workflow is a DAG (Directed Acyclic Graph) of steps with dependencies,
  conditions, timeouts, and rollback support.

  ## Quick Start

  ### Decorator API (Recommended)

      defmodule MyApp.Onboarding do
        use Events.Infra.Scheduler.Workflow, name: :user_onboarding

        @decorate step()
        def create_account(ctx), do: {:ok, %{user_id: Users.create!(ctx.email)}}

        @decorate step(after: :create_account)
        def send_welcome(ctx), do: Mailer.send_welcome(ctx.user_id)
      end

  ### Builder API

      alias Events.Infra.Scheduler.Workflow

      Workflow.new(:user_onboarding)
      |> Workflow.step(:create_account, &create_account/1)
      |> Workflow.step(:send_welcome, &send_welcome/1, after: :create_account)
      |> Workflow.build!()

  ## Features

  - Sequential and parallel step execution
  - Fan-out/fan-in patterns
  - Conditional branching
  - Human-in-the-loop (snooze/pause)
  - Dynamic workflow expansion (grafting)
  - Nested sub-workflows
  - Saga-pattern rollbacks
  - Configurable timeouts and retries
  """

  alias Events.Infra.Scheduler.Workflow.Step
  alias Events.Infra.Scheduler.Config

  @type state :: :pending | :running | :completed | :failed | :cancelled | :paused
  @type trigger_type :: :manual | :scheduled | :event
  @type schedule_opts :: keyword()

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: atom(),
          version: pos_integer(),
          steps: %{atom() => Step.t()},
          adjacency: %{atom() => [atom()]},
          execution_order: [atom()],
          groups: %{atom() => [atom()]},
          grafts: %{atom() => map()},
          nested_workflows: %{atom() => atom()},
          context: map(),
          state: state(),
          trigger_type: trigger_type(),
          schedule: schedule_opts(),
          event_triggers: [String.t()],
          on_failure: atom() | nil,
          on_success: atom() | nil,
          on_cancel: atom() | nil,
          on_step_error: atom() | nil,
          timeout: pos_integer() | :infinity,
          max_retries: non_neg_integer(),
          retry_delay: pos_integer(),
          retry_backoff:
            :fixed | :exponential | :linear | (pos_integer(), pos_integer() -> pos_integer()),
          step_timeout: pos_integer(),
          step_max_retries: non_neg_integer(),
          step_retry_delay: pos_integer(),
          dead_letter: boolean(),
          dead_letter_ttl: pos_integer() | nil,
          metadata: map(),
          tags: [String.t()],
          module: module() | nil
        }

  defstruct [
    :id,
    :name,
    :module,
    :on_failure,
    :on_success,
    :on_cancel,
    :on_step_error,
    :dead_letter_ttl,
    version: 1,
    steps: %{},
    adjacency: %{},
    execution_order: [],
    groups: %{},
    grafts: %{},
    nested_workflows: %{},
    context: %{},
    state: :pending,
    trigger_type: :manual,
    schedule: [],
    event_triggers: [],
    timeout: :timer.minutes(30),
    max_retries: 0,
    retry_delay: :timer.seconds(5),
    retry_backoff: :exponential,
    step_timeout: :timer.minutes(5),
    step_max_retries: 3,
    step_retry_delay: :timer.seconds(1),
    dead_letter: false,
    metadata: %{},
    tags: []
  ]

  # ============================================
  # Using Macro
  # ============================================

  @doc """
  Sets up a module for workflow definition using decorators.

  ## Options

  - `:name` - Workflow name (required)
  - `:timeout` - Total workflow timeout (default: 30 minutes)
  - `:max_retries` - Workflow-level retries (default: 0)
  - `:retry_delay` - Delay before workflow retry (default: 5 seconds)
  - `:retry_backoff` - Backoff strategy (default: :exponential)
  - `:step_timeout` - Default timeout for steps (default: 5 minutes)
  - `:step_max_retries` - Default retries per step (default: 3)
  - `:step_retry_delay` - Default delay between step retries (default: 1 second)
  - `:on_failure` - Function name for failure handler
  - `:on_success` - Function name for success handler
  - `:on_cancel` - Function name for cancellation handler
  - `:on_step_error` - Function name for step error callback
  - `:schedule` - Schedule options (cron, every, at, in, on_event)
  - `:dead_letter` - Send to DLQ on final failure (default: false)
  - `:dead_letter_ttl` - TTL for DLQ entries
  - `:tags` - Tags for filtering

  ## Example

      defmodule MyApp.DataPipeline do
        use Events.Infra.Scheduler.Workflow,
          name: :data_pipeline,
          timeout: {1, :hour},
          step_timeout: {5, :minutes},
          schedule: [cron: "0 6 * * *"],
          on_failure: :cleanup

        @decorate step()
        def fetch_data(ctx), do: ...
      end
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Events.Infra.Decorator

      @workflow_name Keyword.fetch!(opts, :name)
      @workflow_opts Keyword.delete(opts, :name)

      Module.register_attribute(__MODULE__, :__workflow_steps__, accumulate: true)
      Module.register_attribute(__MODULE__, :__workflow_grafts__, accumulate: true)
      Module.register_attribute(__MODULE__, :__workflow_nested__, accumulate: true)

      @before_compile Events.Infra.Scheduler.Workflow
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :__workflow_steps__, [])
    grafts = Module.get_attribute(env.module, :__workflow_grafts__, [])
    nested = Module.get_attribute(env.module, :__workflow_nested__, [])
    workflow_name = Module.get_attribute(env.module, :workflow_name)
    workflow_opts = Module.get_attribute(env.module, :workflow_opts, [])

    quote do
      @doc false
      def __workflow__ do
        Events.Infra.Scheduler.Workflow.from_module(
          __MODULE__,
          unquote(Macro.escape(steps)),
          unquote(Macro.escape(grafts)),
          unquote(Macro.escape(nested)),
          unquote(Macro.escape(workflow_opts))
        )
      end

      @doc false
      def __workflow_name__, do: unquote(workflow_name)

      @doc false
      def __workflow_steps__, do: unquote(Macro.escape(steps))
    end
  end

  # ============================================
  # Builder API
  # ============================================

  @doc """
  Creates a new workflow.

  ## Examples

      Workflow.new(:user_onboarding)
      Workflow.new(:data_pipeline, timeout: {1, :hour})
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    %__MODULE__{
      name: name,
      timeout: normalize_timeout(Keyword.get(opts, :timeout, :timer.minutes(30))),
      max_retries: Keyword.get(opts, :max_retries, 0),
      retry_delay: normalize_timeout(Keyword.get(opts, :retry_delay, :timer.seconds(5))),
      retry_backoff: Keyword.get(opts, :retry_backoff, :exponential),
      step_timeout: normalize_timeout(Keyword.get(opts, :step_timeout, :timer.minutes(5))),
      step_max_retries: Keyword.get(opts, :step_max_retries, 3),
      step_retry_delay: normalize_timeout(Keyword.get(opts, :step_retry_delay, :timer.seconds(1))),
      on_failure: Keyword.get(opts, :on_failure),
      on_success: Keyword.get(opts, :on_success),
      on_cancel: Keyword.get(opts, :on_cancel),
      on_step_error: Keyword.get(opts, :on_step_error),
      schedule: Keyword.get(opts, :schedule, []),
      dead_letter: Keyword.get(opts, :dead_letter, false),
      dead_letter_ttl: normalize_timeout(Keyword.get(opts, :dead_letter_ttl)),
      tags: Keyword.get(opts, :tags, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Adds a step to the workflow.

  ## Options

  - `:after` - Step(s) this depends on (all must complete)
  - `:after_any` - Step(s) where any completing triggers this step
  - `:after_group` - Wait for all steps in a parallel group
  - `:after_graft` - Wait for graft expansion to complete
  - `:group` - Add to a parallel group
  - `:when` - Condition function `(ctx -> boolean)`
  - `:rollback` - Rollback function for saga pattern
  - `:timeout` - Step timeout (overrides workflow default)
  - `:max_retries` - Max retries (overrides workflow default)
  - `:retry_delay` - Retry delay (overrides workflow default)
  - `:retry_backoff` - Backoff strategy
  - `:retry_max_delay` - Maximum delay for exponential backoff
  - `:retry_jitter` - Add jitter to retry delays
  - `:retry_on` - Error types to retry on
  - `:no_retry_on` - Error types to never retry
  - `:on_error` - `:fail`, `:skip`, or `:continue`
  - `:await_approval` - Pause for human approval
  - `:context_key` - Key to store result (defaults to step name)

  ## Examples

      workflow
      |> Workflow.step(:fetch, &fetch/1)
      |> Workflow.step(:process, &process/1, after: :fetch, timeout: {10, :minutes})
  """
  @spec step(t(), atom(), Step.job_spec(), keyword()) :: t()
  def step(%__MODULE__{} = workflow, name, job, opts \\ []) when is_atom(name) do
    step_struct = Step.new(name, job, merge_step_defaults(workflow, opts))

    deps = extract_dependencies(opts)

    workflow
    |> add_step(step_struct)
    |> add_dependencies(name, deps)
    |> maybe_add_to_group(name, Keyword.get(opts, :group))
  end

  @doc """
  Adds multiple parallel steps (fan-out pattern).

  ## Example

      workflow
      |> Workflow.step(:fetch, &fetch/1)
      |> Workflow.parallel(:fetch, [
           {:upload_s3, &upload_s3/1},
           {:upload_gcs, &upload_gcs/1}
         ])
  """
  @spec parallel(t(), atom(), [{atom(), Step.job_spec()}], keyword()) :: t()
  def parallel(%__MODULE__{} = workflow, after_step, steps, opts \\ []) do
    group_name = Keyword.get(opts, :group, :"parallel_#{after_step}")

    Enum.reduce(steps, workflow, fn {name, job}, acc ->
      step(acc, name, job, Keyword.merge(opts, after: after_step, group: group_name))
    end)
  end

  @doc """
  Fan-out from a single step to multiple parallel steps.

  ## Example

      workflow
      |> Workflow.step(:transform, &transform/1, after: :fetch)
      |> Workflow.fan_out(:transform, [
           {:upload_s3, S3Worker},
           {:upload_gcs, GCSWorker}
         ])
  """
  @spec fan_out(t(), atom(), [{atom(), Step.job_spec()}], keyword()) :: t()
  def fan_out(%__MODULE__{} = workflow, from_step, to_steps, opts \\ []) do
    parallel(workflow, from_step, to_steps, opts)
  end

  @doc """
  Fan-in from multiple parallel steps to a single step.

  ## Example

      workflow
      |> Workflow.fan_in([:upload_s3, :upload_gcs], :notify, NotifyWorker)
  """
  @spec fan_in(t(), [atom()], atom(), Step.job_spec(), keyword()) :: t()
  def fan_in(%__MODULE__{} = workflow, from_steps, to_step, job, opts \\ []) do
    step(workflow, to_step, job, Keyword.put(opts, :after, from_steps))
  end

  @doc """
  Adds conditional branching from a step.

  ## Example

      workflow
      |> Workflow.branch(:check_stock, [
           {:charge, condition: &in_stock?/1, job: &charge/1},
           {:backorder, condition: &out_of_stock?/1, job: &backorder/1}
         ])
  """
  @spec branch(t(), atom(), [{atom(), keyword()}]) :: t()
  def branch(%__MODULE__{} = workflow, from_step, branches) do
    Enum.reduce(branches, workflow, fn {name, opts}, acc ->
      condition = Keyword.fetch!(opts, :condition)
      job = Keyword.fetch!(opts, :job)
      step(acc, name, job, after: from_step, when: condition)
    end)
  end

  @doc """
  Adds a graft placeholder for dynamic workflow expansion.

  ## Example

      workflow
      |> Workflow.step(:fetch_accounts, &fetch_accounts/1)
      |> Workflow.add_graft(:process_accounts, deps: :fetch_accounts)
      |> Workflow.step(:summarize, &summarize/1, after_graft: :process_accounts)
  """
  @spec add_graft(t(), atom(), keyword()) :: t()
  def add_graft(%__MODULE__{} = workflow, name, opts \\ []) do
    deps = Keyword.get(opts, :deps, [])
    deps = if is_list(deps), do: deps, else: [deps]

    graft = %{
      name: name,
      deps: deps,
      expanded: false,
      expansion: []
    }

    %{workflow | grafts: Map.put(workflow.grafts, name, graft)}
    |> add_dependencies(name, deps)
  end

  @doc """
  Adds a nested sub-workflow as a step.

  ## Example

      workflow
      |> Workflow.step(:create_user, &create_user/1)
      |> Workflow.add_workflow(:notify, :send_notification, after: :create_user)
  """
  @spec add_workflow(t(), atom(), atom(), keyword()) :: t()
  def add_workflow(%__MODULE__{} = workflow, name, nested_workflow_name, opts \\ []) do
    nested_step = Step.new(name, {:workflow, nested_workflow_name}, opts)

    workflow
    |> add_step(nested_step)
    |> add_dependencies(name, extract_dependencies(opts))
    |> Map.update!(:nested_workflows, &Map.put(&1, name, nested_workflow_name))
  end

  @doc """
  Sets the failure handler step.
  """
  @spec on_failure(t(), atom()) :: t()
  def on_failure(%__MODULE__{} = workflow, handler) when is_atom(handler) do
    %{workflow | on_failure: handler}
  end

  @doc """
  Sets the success handler step.
  """
  @spec on_success(t(), atom()) :: t()
  def on_success(%__MODULE__{} = workflow, handler) when is_atom(handler) do
    %{workflow | on_success: handler}
  end

  @doc """
  Sets the cancellation handler step.
  """
  @spec on_cancel(t(), atom()) :: t()
  def on_cancel(%__MODULE__{} = workflow, handler) when is_atom(handler) do
    %{workflow | on_cancel: handler}
  end

  @doc """
  Configures scheduling for the workflow.

  ## Options

  - `:cron` - Cron expression or list of expressions
  - `:every` - Interval tuple like `{5, :minutes}`
  - `:at` - Specific DateTime
  - `:in` - Relative delay like `{30, :minutes}`
  - `:start_at` - Start date for interval
  - `:end_at` - End date for interval
  - `:on_event` - Event name(s) to trigger on

  ## Examples

      workflow
      |> Workflow.schedule(cron: "0 6 * * *")
      |> Workflow.schedule(cron: ["0 6 * * *", "0 18 * * *"])
      |> Workflow.schedule(every: {30, :minutes})
      |> Workflow.schedule(at: ~U[2025-12-25 00:00:00Z])
      |> Workflow.schedule(on_event: "user.created")
  """
  @spec schedule(t(), schedule_opts()) :: t()
  def schedule(%__MODULE__{} = workflow, opts) do
    trigger_type =
      cond do
        Keyword.has_key?(opts, :on_event) -> :event
        Keyword.has_key?(opts, :cron) or Keyword.has_key?(opts, :every) -> :scheduled
        true -> :manual
      end

    event_triggers =
      case Keyword.get(opts, :on_event) do
        nil -> workflow.event_triggers
        event when is_binary(event) -> [event | workflow.event_triggers]
        events when is_list(events) -> events ++ workflow.event_triggers
      end

    %{workflow | schedule: opts, trigger_type: trigger_type, event_triggers: event_triggers}
  end

  @doc """
  Configures event triggers.
  """
  @spec on_event(t(), String.t() | [String.t()]) :: t()
  def on_event(%__MODULE__{} = workflow, events) when is_binary(events) or is_list(events) do
    schedule(workflow, on_event: events)
  end

  @doc """
  Validates and builds the workflow.

  Returns `{:ok, workflow}` or `{:error, reason}`.
  """
  @spec build(t()) :: {:ok, t()} | {:error, term()}
  def build(%__MODULE__{} = workflow) do
    with :ok <- validate_no_cycles(workflow),
         :ok <- validate_dependencies_exist(workflow),
         {:ok, order} <- topological_sort(workflow) do
      {:ok, %{workflow | execution_order: order, state: :pending}}
    end
  end

  @doc """
  Validates and builds the workflow, raising on error.
  """
  @spec build!(t()) :: t()
  def build!(%__MODULE__{} = workflow) do
    case build(workflow) do
      {:ok, built} -> built
      {:error, reason} -> raise ArgumentError, "Invalid workflow: #{inspect(reason)}"
    end
  end

  @doc """
  Registers the workflow with the scheduler.
  """
  @spec register(t()) :: {:ok, t()} | {:error, term()}
  def register(%__MODULE__{} = workflow) do
    with {:ok, built} <- build(workflow) do
      store().register_workflow(built)
    end
  end

  # ============================================
  # Runtime API
  # ============================================

  @doc """
  Starts a workflow execution immediately.

  ## Example

      {:ok, execution_id} = Workflow.start(:user_onboarding, %{email: "user@example.com"})
  """
  @spec start(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def start(workflow_name, context \\ %{}) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.start_workflow(workflow_name, context)
  end

  @doc """
  Schedules a workflow for future execution.

  ## Options

  - `:context` - Initial context map
  - `:at` - Specific DateTime to run
  - `:in` - Relative delay like `{30, :minutes}`

  ## Examples

      Workflow.schedule(:user_onboarding, context: %{email: "user@example.com"}, at: ~U[2025-12-25 00:00:00Z])
      Workflow.schedule(:user_onboarding, context: %{email: "user@example.com"}, in: {30, :minutes})
  """
  @spec schedule_execution(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def schedule_execution(workflow_name, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.schedule_workflow(workflow_name, opts)
  end

  @doc """
  Cancels a running workflow execution.

  ## Options

  - `:reason` - Cancellation reason
  - `:cleanup` - Run on_cancel handler (default: true)
  - `:rollback` - Run rollbacks for completed steps (default: false)
  """
  @spec cancel(String.t(), keyword()) :: :ok | {:error, term()}
  def cancel(execution_id, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.cancel(execution_id, opts)
  end

  @doc """
  Cancels all running executions of a workflow.
  """
  @spec cancel_all(atom(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cancel_all(workflow_name, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.cancel_all(workflow_name, opts)
  end

  @doc """
  Pauses a running workflow (can be resumed).
  """
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(execution_id) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.pause(execution_id)
  end

  @doc """
  Resumes a paused workflow.

  ## Options

  - `:context` - Additional context to merge
  """
  @spec resume(String.t(), keyword()) :: :ok | {:error, term()}
  def resume(execution_id, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.resume(execution_id, opts)
  end

  @doc """
  Gets the current state of a workflow execution.
  """
  @spec get_state(String.t()) :: {:ok, map()} | {:error, term()}
  def get_state(execution_id) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.get_state(execution_id)
  end

  @doc """
  Lists all running executions of a workflow.
  """
  @spec list_running(atom()) :: [map()]
  def list_running(workflow_name) do
    alias Events.Infra.Scheduler.Workflow.Engine
    Engine.list_running(workflow_name)
  end

  @doc """
  Checks if the current execution is being cancelled.
  Called from within step functions.
  """
  @spec cancelled?() :: boolean()
  def cancelled? do
    case Process.get(:__workflow_cancelled__) do
      true -> true
      _ -> false
    end
  end

  @doc """
  Gets the cancellation reason if cancelled.
  """
  @spec cancellation_reason() :: term() | nil
  def cancellation_reason do
    Process.get(:__workflow_cancellation_reason__)
  end

  # ============================================
  # Introspection API
  # ============================================

  @doc """
  Gets a summary of a workflow.
  """
  @spec summary(atom()) :: map() | nil
  def summary(workflow_name) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Summary
    Summary.summary(workflow_name)
  end

  @doc """
  Gets a detailed report of a workflow.
  """
  @spec report(atom()) :: map() | nil
  def report(workflow_name) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Summary
    Summary.report(workflow_name)
  end

  @doc """
  Generates a Mermaid diagram of the workflow.
  """
  @spec to_mermaid(atom(), keyword()) :: String.t()
  def to_mermaid(workflow_name, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Mermaid
    Mermaid.to_mermaid(workflow_name, opts)
  end

  @doc """
  Generates a DOT (Graphviz) diagram of the workflow.
  """
  @spec to_dot(atom(), keyword()) :: String.t()
  def to_dot(workflow_name, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Dot
    Dot.to_dot(workflow_name, opts)
  end

  @doc """
  Generates an ASCII table representation of the workflow.
  """
  @spec to_table(atom(), keyword()) :: String.t()
  def to_table(workflow_name, opts \\ []) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Table
    Table.to_table(workflow_name, opts)
  end

  @doc """
  Lists all registered workflows.
  """
  @spec list_all() :: [map()]
  def list_all do
    store().list_workflows()
  end

  @doc """
  Gets execution timeline for a specific execution.
  """
  @spec execution_timeline(String.t()) :: map() | nil
  def execution_timeline(execution_id) do
    alias Events.Infra.Scheduler.Workflow.Introspection.Summary
    Summary.execution_timeline(execution_id)
  end

  # ============================================
  # Internal Functions
  # ============================================

  @doc false
  def from_module(module, steps, grafts, nested, opts) do
    workflow_name = Module.get_attribute(module, :workflow_name)

    workflow =
      new(workflow_name, Keyword.put(opts, :module, module))
      |> add_steps_from_module(steps)
      |> add_grafts_from_module(grafts)
      |> add_nested_from_module(nested)

    case build(workflow) do
      {:ok, built} -> built
      {:error, reason} -> raise CompileError, description: "Invalid workflow: #{inspect(reason)}"
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp add_step(%__MODULE__{} = workflow, %Step{} = step) do
    %{workflow | steps: Map.put(workflow.steps, step.name, step)}
  end

  defp add_dependencies(%__MODULE__{} = workflow, step_name, deps) when is_list(deps) do
    current = Map.get(workflow.adjacency, step_name, [])
    %{workflow | adjacency: Map.put(workflow.adjacency, step_name, Enum.uniq(deps ++ current))}
  end

  defp maybe_add_to_group(workflow, _name, nil), do: workflow

  defp maybe_add_to_group(%__MODULE__{} = workflow, name, group) do
    current = Map.get(workflow.groups, group, [])
    %{workflow | groups: Map.put(workflow.groups, group, [name | current])}
  end

  defp extract_dependencies(opts) do
    deps = []

    # Only :after goes in adjacency (requires ALL to complete)
    # :after_any is stored on the Step struct and checked separately (requires ANY to complete)
    deps =
      case Keyword.get(opts, :after) do
        nil -> deps
        dep when is_atom(dep) -> [dep | deps]
        deps_list when is_list(deps_list) -> deps_list ++ deps
      end

    deps =
      case Keyword.get(opts, :after_group) do
        nil -> deps
        group -> [{:group, group} | deps]
      end

    case Keyword.get(opts, :after_graft) do
      nil -> deps
      graft -> [{:graft, graft} | deps]
    end
  end

  defp merge_step_defaults(%__MODULE__{} = workflow, opts) do
    Keyword.merge(
      [
        timeout: workflow.step_timeout,
        max_retries: workflow.step_max_retries,
        retry_delay: workflow.step_retry_delay
      ],
      opts
    )
  end

  defp add_steps_from_module(workflow, steps) do
    Enum.reduce(steps, workflow, fn step_spec, acc ->
      {name, job, opts} = step_spec
      step(acc, name, job, opts)
    end)
  end

  defp add_grafts_from_module(workflow, grafts) do
    Enum.reduce(grafts, workflow, fn {name, opts}, acc ->
      add_graft(acc, name, opts)
    end)
  end

  defp add_nested_from_module(workflow, nested) do
    Enum.reduce(nested, workflow, fn {name, nested_name, opts}, acc ->
      add_workflow(acc, name, nested_name, opts)
    end)
  end

  defp validate_no_cycles(%__MODULE__{} = workflow) do
    case detect_cycle(workflow) do
      nil -> :ok
      cycle -> {:error, {:cycle_detected, cycle}}
    end
  end

  defp detect_cycle(%__MODULE__{steps: steps, adjacency: adj}) do
    step_names = Map.keys(steps)

    Enum.reduce_while(step_names, {MapSet.new(), MapSet.new(), nil}, fn step, {visited, stack, _} ->
      case dfs_cycle(step, adj, visited, stack, []) do
        {:cycle, path} -> {:halt, {visited, stack, path}}
        {:ok, new_visited} -> {:cont, {new_visited, stack, nil}}
      end
    end)
    |> elem(2)
  end

  defp dfs_cycle(node, adj, visited, stack, path) do
    cond do
      MapSet.member?(stack, node) ->
        {:cycle, Enum.reverse([node | path])}

      MapSet.member?(visited, node) ->
        {:ok, visited}

      true ->
        deps =
          Map.get(adj, node, [])
          |> Enum.map(fn
            {:group, _} -> []
            {:graft, _} -> []
            dep -> dep
          end)
          |> List.flatten()

        new_stack = MapSet.put(stack, node)
        new_path = [node | path]

        result =
          Enum.reduce_while(deps, {:ok, visited}, fn dep, {:ok, v} ->
            case dfs_cycle(dep, adj, v, new_stack, new_path) do
              {:cycle, _} = cycle -> {:halt, cycle}
              {:ok, new_v} -> {:cont, {:ok, new_v}}
            end
          end)

        case result do
          {:cycle, _} = cycle -> cycle
          {:ok, new_visited} -> {:ok, MapSet.put(new_visited, node)}
        end
    end
  end

  defp validate_dependencies_exist(%__MODULE__{steps: steps, adjacency: adj, grafts: grafts}) do
    step_names = MapSet.new(Map.keys(steps))
    graft_names = MapSet.new(Map.keys(grafts))

    missing =
      adj
      |> Enum.flat_map(fn {_step, deps} ->
        Enum.filter(deps, fn
          {:group, _} -> false
          {:graft, name} -> not MapSet.member?(graft_names, name)
          dep -> not MapSet.member?(step_names, dep) and not MapSet.member?(graft_names, dep)
        end)
      end)
      |> Enum.uniq()

    case missing do
      [] -> :ok
      deps -> {:error, {:missing_dependencies, deps}}
    end
  end

  defp topological_sort(%__MODULE__{steps: steps, adjacency: adj, groups: groups}) do
    step_names = Map.keys(steps)

    # Expand group dependencies
    expanded_adj =
      Enum.reduce(adj, %{}, fn {step, deps}, acc ->
        expanded_deps =
          Enum.flat_map(deps, fn
            {:group, group_name} -> Map.get(groups, group_name, [])
            {:graft, _} = graft -> [graft]
            dep -> [dep]
          end)

        Map.put(acc, step, expanded_deps)
      end)

    # Kahn's algorithm
    in_degree =
      Enum.reduce(step_names, %{}, fn name, acc ->
        Map.put(acc, name, 0)
      end)

    in_degree =
      Enum.reduce(expanded_adj, in_degree, fn {_step, deps}, outer_acc ->
        Enum.reduce(deps, outer_acc, fn
          {:graft, _}, inner_acc -> inner_acc
          dep, inner_acc -> Map.update(inner_acc, dep, 1, &(&1 + 1))
        end)
      end)

    queue =
      in_degree
      |> Enum.filter(fn {_name, degree} -> degree == 0 end)
      |> Enum.map(fn {name, _} -> name end)

    do_topological_sort(queue, expanded_adj, in_degree, [])
  end

  defp do_topological_sort([], _adj, in_degree, result) do
    remaining = Enum.filter(in_degree, fn {_k, v} -> v > 0 end)

    case remaining do
      [] -> {:ok, Enum.reverse(result)}
      _ -> {:error, :cycle_detected}
    end
  end

  defp do_topological_sort([node | rest], adj, in_degree, result) do
    deps = Map.get(adj, node, [])

    {new_queue, new_in_degree} =
      Enum.reduce(deps, {rest, in_degree}, fn
        {:graft, _}, acc ->
          acc

        dep, {q, deg} ->
          new_deg = Map.update!(deg, dep, &(&1 - 1))

          if new_deg[dep] == 0 do
            {[dep | q], new_deg}
          else
            {q, new_deg}
          end
      end)

    do_topological_sort(new_queue, adj, Map.delete(new_in_degree, node), [node | result])
  end

  defp normalize_timeout(nil), do: nil
  defp normalize_timeout(:infinity), do: :infinity
  defp normalize_timeout(ms) when is_integer(ms), do: ms
  defp normalize_timeout({n, unit}), do: Config.to_ms({n, unit})

  defp store do
    Config.get_store_module(Config.get())
  end
end
