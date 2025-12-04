defprotocol Events.Infra.Scheduler.Workflow.Step.Executable do
  @moduledoc """
  Protocol for executing workflow steps.

  Allows steps to be defined as:
  - Anonymous functions
  - Module atoms implementing the Worker behaviour
  - MFA tuples
  - Nested workflow references

  ## Implementations

  - `Function` - Anonymous functions `fn ctx -> result end`
  - `Atom` - Module implementing `perform/1`
  - `Tuple` - Various forms including MFA and special types
  """

  @doc """
  Executes the step with the given context.

  Returns one of:
  - `{:ok, map}` - Success with context updates
  - `:ok` - Success without context updates
  - `{:error, reason}` - Failure
  - `{:skip, reason}` - Skip step
  - `{:await, opts}` - Human-in-the-loop
  - `{:expand, steps}` - Graft expansion
  - `{:snooze, duration}` - Pause and retry later
  """
  @spec execute(t(), map()) :: term()
  def execute(step_job, context)

  @doc """
  Executes rollback for the step.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec rollback(t(), map()) :: :ok | {:error, term()}
  def rollback(step_job, context)

  @doc """
  Checks if the step has a rollback function.
  """
  @spec has_rollback?(t()) :: boolean()
  def has_rollback?(step_job)
end

# ============================================
# Function Implementation
# ============================================

defimpl Events.Infra.Scheduler.Workflow.Step.Executable, for: Function do
  def execute(fun, context) when is_function(fun, 1) do
    try do
      fun.(context)
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      :throw, value -> {:error, {:throw, value}}
    end
  end

  def rollback(_fun, _context), do: :ok

  def has_rollback?(_fun), do: false
end

# ============================================
# Atom (Module) Implementation
# ============================================

defimpl Events.Infra.Scheduler.Workflow.Step.Executable, for: Atom do
  def execute(module, context) when is_atom(module) do
    if function_exported?(module, :perform, 1) do
      try do
        module.perform(context)
      rescue
        e -> {:error, {:exception, e, __STACKTRACE__}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
        :throw, value -> {:error, {:throw, value}}
      end
    else
      {:error, {:undefined_function, {module, :perform, 1}}}
    end
  end

  def rollback(module, context) when is_atom(module) do
    if function_exported?(module, :rollback, 1) do
      try do
        module.rollback(context)
      rescue
        e ->
          require Logger
          Logger.error("Rollback failed for #{inspect(module)}: #{Exception.message(e)}")
          {:error, {:exception, e, __STACKTRACE__}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
        :throw, value -> {:error, {:throw, value}}
      end
    else
      :ok
    end
  end

  def has_rollback?(module) when is_atom(module) do
    function_exported?(module, :rollback, 1)
  end
end

# ============================================
# Tuple Implementation
# ============================================

defimpl Events.Infra.Scheduler.Workflow.Step.Executable, for: Tuple do
  alias Events.Infra.Scheduler.Workflow.Step.Executable

  # {:function, module, function_name} - Function reference from decorator
  def execute({:function, module, function_name}, context) do
    try do
      apply(module, function_name, [context])
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      :throw, value -> {:error, {:throw, value}}
    end
  end

  # {:nested_workflow, workflow_name, module, context_fn} - Nested workflow
  def execute({:nested_workflow, workflow_name, module, context_fn}, context) do
    # Get additional context from the context function
    additional_context =
      try do
        apply(module, context_fn, [context])
      rescue
        _ -> %{}
      end

    merged_context =
      case additional_context do
        map when is_map(map) -> Map.merge(context, map)
        _ -> context
      end

    # Start the nested workflow and wait for completion
    alias Events.Infra.Scheduler.Workflow.Engine

    case Engine.start_workflow_sync(workflow_name, merged_context) do
      {:ok, result_context} -> {:ok, result_context}
      {:error, reason} -> {:error, {:nested_workflow_failed, workflow_name, reason}}
    end
  end

  # {:workflow, workflow_name} - Simple workflow reference
  def execute({:workflow, workflow_name}, context) do
    alias Events.Infra.Scheduler.Workflow.Engine

    case Engine.start_workflow_sync(workflow_name, context) do
      {:ok, result_context} -> {:ok, result_context}
      {:error, reason} -> {:error, {:nested_workflow_failed, workflow_name, reason}}
    end
  end

  # {module, function} - MF tuple
  def execute({module, function}, context) when is_atom(module) and is_atom(function) do
    try do
      apply(module, function, [context])
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      :throw, value -> {:error, {:throw, value}}
    end
  end

  # {module, function, args} - MFA tuple
  def execute({module, function, args}, context)
      when is_atom(module) and is_atom(function) and is_list(args) do
    try do
      apply(module, function, [context | args])
    rescue
      e -> {:error, {:exception, e, __STACKTRACE__}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      :throw, value -> {:error, {:throw, value}}
    end
  end

  # Rollback implementations
  def rollback({:function, _module, _function_name}, _context), do: :ok
  def rollback({:nested_workflow, _name, _module, _fn}, _context), do: :ok
  def rollback({:workflow, _name}, _context), do: :ok

  def rollback({module, _function}, context) when is_atom(module),
    do: Executable.rollback(module, context)

  def rollback({module, _function, _args}, context) when is_atom(module),
    do: Executable.rollback(module, context)

  # has_rollback? implementations
  def has_rollback?({:function, _module, _function_name}), do: false
  def has_rollback?({:nested_workflow, _name, _module, _fn}), do: false
  def has_rollback?({:workflow, _name}), do: false
  def has_rollback?({module, _function}) when is_atom(module), do: Executable.has_rollback?(module)

  def has_rollback?({module, _function, _args}) when is_atom(module),
    do: Executable.has_rollback?(module)
end
