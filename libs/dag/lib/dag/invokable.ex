defprotocol Dag.Invokable do
  @moduledoc """
  Protocol for executable components in a DAG workflow.

  Implements the three-phase execution model:

  1. **activates?** - Can this component fire given the available facts?
  2. **prepare** - Produce a `Dag.Runnable` from component + inputs + context
  3. *(execute)* - Run the runnable in isolation (via `Dag.Runnable.execute/1`)
  4. **apply_result** - Convert result into `Dag.Fact`s for downstream

  The separation enables:
  - Parallel execution of independent components
  - External dispatch to job queues or distributed workers
  - Replay by re-executing from cached facts

  ## Why not put execute on the protocol?

  Execute is deliberately on `Dag.Runnable`, not on the protocol. A Runnable
  is a self-contained unit that carries its function, inputs, and context.
  It doesn't need the component or workflow to execute. This means you can
  serialize runnables, send them to other nodes, or queue them in Oban.
  """

  @doc """
  Checks if this component can activate given available input facts.

  A component activates when all its required inputs are satisfied.
  The engine calls this after checking structural readiness (predecessors complete).
  """
  @spec activates?(t(), %{Dag.node_id() => [Dag.Fact.t()]}, map()) :: boolean()
  def activates?(component, available_facts, context)

  @doc """
  Prepares a `Dag.Runnable` from the component.

  Extracts the minimal inputs and context needed for isolated execution.
  The runnable should be self-contained - no references to workflow state.
  """
  @spec prepare(t(), %{Dag.node_id() => [Dag.Fact.t()]}, map()) :: Dag.Runnable.t()
  def prepare(component, inputs, context)

  @doc """
  Applies an execution result to produce new facts.

  Returns `{:ok, [Dag.Fact.t()]}` on success or `{:error, reason}` on failure.
  """
  @spec apply_result(t(), Dag.Runnable.result()) :: {:ok, [Dag.Fact.t()]} | {:error, term()}
  def apply_result(component, result)
end
