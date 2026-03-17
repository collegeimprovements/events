defmodule Dag.Runnable do
  @moduledoc """
  A self-contained, dispatchable unit of work.

  Runnables are produced by the prepare phase and contain everything needed
  to execute a component in isolation. They can be:
  - Executed locally with `execute/1`
  - Sent to a worker pool
  - Dispatched to a job queue (Oban, Broadway)
  - Distributed across nodes

  ## Three-Phase Model

      # 1. Prepare - extract runnables from workflow
      {workflow, runnables} = Dag.Workflow.prepare_for_dispatch(workflow)

      # 2. Execute - run in isolation (parallelizable)
      results = Enum.map(runnables, &Dag.Runnable.execute/1)

      # 3. Apply - fold results back
      workflow = Enum.reduce(results, workflow, fn {id, result}, w ->
        Dag.Workflow.apply_result(w, id, result)
      end)

  The key insight: execute is decoupled from the workflow. A Runnable
  carries its function, inputs, and context - nothing else. This means
  execution can happen anywhere without workflow state.
  """

  @type result :: {:ok, term()} | {:error, term()}

  @type t :: %__MODULE__{
          component_id: Dag.node_id(),
          function: (map(), map() -> result()),
          inputs: map(),
          context: map(),
          metadata: map()
        }

  defstruct [:component_id, :function, :inputs, context: %{}, metadata: %{}]

  @doc """
  Creates a new runnable.

  ## Options

  - `:context` - Resolved context for this component
  - `:metadata` - Tracing, timeout, retry info
  """
  @spec new(Dag.node_id(), function(), map(), keyword()) :: t()
  def new(component_id, function, inputs, opts \\ []) do
    %__MODULE__{
      component_id: component_id,
      function: function,
      inputs: inputs,
      context: Keyword.get(opts, :context, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Executes the runnable in isolation.

  Returns `{component_id, result}` where result is `{:ok, value}` or `{:error, reason}`.
  Non-tuple returns are wrapped in `{:ok, value}`.
  Exceptions are caught and returned as `{:error, {exception, stacktrace}}`.
  """
  @spec execute(t()) :: {Dag.node_id(), result()}
  def execute(%__MODULE__{
        component_id: id,
        function: fun,
        inputs: inputs,
        context: context
      }) do
    result =
      try do
        case fun.(inputs, context) do
          {:ok, _} = ok -> ok
          {:error, _} = err -> err
          value -> {:ok, value}
        end
      rescue
        e -> {:error, {e, __STACKTRACE__}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
        :throw, value -> {:error, {:throw, value}}
      end

    {id, result}
  end
end
