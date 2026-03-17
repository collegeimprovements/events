defmodule Dag.Components.Rule do
  @moduledoc """
  Pattern-matching conditional component.

  A Rule fires only when its condition matches the input facts.
  This enables reactive, data-driven workflows where components
  activate based on the shape of available data.

  Unlike a Step (which always fires when inputs are ready), a Rule
  evaluates its condition first. If the condition returns false,
  the rule does not fire and downstream components may be skipped.

  ## Function Signatures

  Both `condition` and `action` accept 1 or 2 arity:

      # 1-arity: receives the single predecessor's output (or raw input for roots)
      Rule.new(:guard,
        condition: fn value -> value > 10 end,
        action: fn value -> {:ok, value * 2} end
      )

      # 2-arity: receives (inputs_map, context)
      Rule.new(:guard,
        condition: fn inputs, ctx -> inputs[:__input__] > ctx[:threshold] end,
        action: fn inputs, _ctx -> {:ok, inputs[:__input__] * 2} end
      )

  For rules with **multiple predecessors**, the 1-arity form receives
  the full `%{pred_a: value, pred_b: value}` map. Use 2-arity for
  explicit control over multi-predecessor inputs.

  ## Examples

      # Simple guard on input value
      Rule.new(:high_value,
        condition: fn value -> value > 100 end,
        action: fn value -> {:ok, {:alert, value}} end
      )

      # With context
      Rule.new(:threshold_check,
        condition: fn inputs, ctx ->
          inputs |> Map.values() |> Enum.any?(fn v -> v > ctx[:threshold] end)
        end,
        action: fn inputs, _ctx ->
          {:ok, {:alert, Map.values(inputs)}}
        end
      )
  """

  @type t :: %__MODULE__{
          id: Dag.node_id(),
          name: String.t() | nil,
          condition: (map(), map() -> boolean()),
          action: (map(), map() -> Dag.Runnable.result()),
          opts: map()
        }

  defstruct [:id, :name, :condition, :action, opts: %{}]

  @doc """
  Creates a new rule.

  Accepts 1-arity or 2-arity functions for both condition and action.

  ## Required Options

  - `:condition` - `fn value -> bool` or `fn inputs, ctx -> bool` - when to fire
  - `:action` - `fn value -> result` or `fn inputs, ctx -> result` - what to do

  ## Optional

  - `:name` - Human-readable name
  - `:timeout` - Execution timeout in ms
  - `:retries` - Number of retry attempts on failure
  - `:retry_delay` - Base delay between retries in ms (default: 100)
  - `:retry_backoff` - `:fixed`, `:linear`, or `:exponential` (default: `:fixed`)
  """
  @spec new(Dag.node_id(), keyword()) :: t()
  def new(id, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    {condition, opts} = Keyword.pop!(opts, :condition)
    {action, opts} = Keyword.pop!(opts, :action)

    %__MODULE__{
      id: id,
      name: name,
      condition: Dag.Components.Helpers.normalize_fun(condition),
      action: Dag.Components.Helpers.normalize_fun(action),
      opts: Map.new(opts)
    }
  end

  defimpl Dag.Component do
    def id(%{id: id}), do: id
    def name(%{name: nil, id: id}), do: to_string(id)
    def name(%{name: name}), do: name

    def validate(%{id: nil}), do: {:error, :missing_id}
    def validate(%{condition: nil}), do: {:error, :missing_condition}
    def validate(%{condition: c}) when not is_function(c), do: {:error, :invalid_condition}
    def validate(%{action: nil}), do: {:error, :missing_action}
    def validate(%{action: a}) when not is_function(a), do: {:error, :invalid_action}
    def validate(_), do: :ok
  end

  defimpl Dag.Invokable do
    def activates?(%{condition: condition}, available_facts, context) do
      map_size(available_facts) > 0 and
        condition.(Dag.Components.Helpers.flatten_inputs(available_facts), context)
    end

    def prepare(%{id: id, action: action, opts: opts}, inputs, context) do
      input_values = Dag.Components.Helpers.flatten_inputs(inputs)
      metadata = Map.take(opts, [:timeout, :retries])
      Dag.Runnable.new(id, action, input_values, context: context, metadata: metadata)
    end

    def apply_result(%{id: id}, {:ok, value}) do
      {:ok, [Dag.Fact.from_output(id, value)]}
    end

    def apply_result(_rule, {:error, _} = error), do: error
  end

  defimpl Inspect do
    def inspect(%{id: id, name: name}, _opts) do
      "#Rule<#{name || id}>"
    end
  end
end
