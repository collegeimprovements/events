defprotocol Dag.Component do
  @moduledoc """
  Protocol for DAG workflow components.

  Components are typed nodes with behavior. Any struct implementing this
  protocol can be added to a `Dag.Workflow`.

  ## Built-in Component Types

  | Type | Purpose |
  |------|---------|
  | `Dag.Components.Step` | Basic function application |
  | `Dag.Components.Rule` | Pattern-matching conditional |
  | `Dag.Components.Accumulator` | Reduce across multiple inputs |
  | `Dag.Components.Branch` | Conditional routing |
  | `Dag.Components.Saga` | Compensatable transaction step |

  ## Implementing Custom Components

      defmodule MyComponent do
        defstruct [:id, :name, :config]

        defimpl Dag.Component do
          def id(c), do: c.id
          def name(c), do: c.name || to_string(c.id)
          def validate(c), do: if(c.id, do: :ok, else: {:error, :missing_id})
        end

        defimpl Dag.Invokable do
          def prepare(c, inputs, context) do
            Dag.Runnable.new(c.id, &my_function/2, inputs, context: context)
          end

          def activates?(_c, facts, _context), do: map_size(facts) > 0

          def apply_result(c, {:ok, value}) do
            {:ok, [Dag.Fact.from_output(c.id, value)]}
          end

          def apply_result(_c, {:error, _} = err), do: err
        end
      end
  """

  @doc "Returns the component's unique identifier."
  @spec id(t()) :: Dag.node_id()
  def id(component)

  @doc "Returns the component's human-readable name."
  @spec name(t()) :: String.t()
  def name(component)

  @doc "Validates the component configuration."
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(component)
end
