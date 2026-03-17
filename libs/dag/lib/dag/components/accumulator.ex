defmodule Dag.Components.Accumulator do
  @moduledoc """
  Accumulator component that reduces across multiple inputs.

  An Accumulator collects values from predecessor components and reduces
  them into a single output. Ideal for fan-in patterns where multiple
  parallel branches must merge.

  ## Emit Conditions

  - `:all_received` (default) - Emit when all predecessors have produced facts
  - Custom function `fn accumulated, received_count, expected_count -> boolean()`

  ## Examples

      # Sum values from parallel branches
      acc = Dag.Components.Accumulator.new(:total,
        reducer: fn value, acc -> acc + value end,
        initial: 0
      )

      # Collect into a list
      acc = Dag.Components.Accumulator.new(:collect,
        reducer: fn value, acc -> [value | acc] end,
        initial: []
      )

      # Emit early when threshold reached
      acc = Dag.Components.Accumulator.new(:fast_collect,
        reducer: fn value, acc -> [value | acc] end,
        initial: [],
        emit_when: fn acc, _received, _expected -> length(acc) >= 3 end
      )
  """

  @type emit_condition ::
          :all_received | (term(), non_neg_integer(), non_neg_integer() -> boolean())

  @type t :: %__MODULE__{
          id: Dag.node_id(),
          name: String.t() | nil,
          reducer: (term(), term() -> term()),
          initial: term(),
          emit_when: emit_condition(),
          opts: map()
        }

  defstruct [:id, :name, :reducer, :initial, emit_when: :all_received, opts: %{}]

  @doc """
  Creates a new accumulator.

  ## Required Options

  - `:reducer` - `fn value, acc -> acc` - reduction function

  ## Optional

  - `:initial` - Initial accumulator value (default: nil)
  - `:emit_when` - `:all_received` or custom `fn accumulated, received, expected -> bool`
  - `:name` - Human-readable name
  - `:timeout` - Execution timeout in ms
  - `:retries` - Number of retry attempts on failure
  - `:retry_delay` - Base delay between retries in ms (default: 100)
  - `:retry_backoff` - `:fixed`, `:linear`, or `:exponential` (default: `:fixed`)
  """
  @spec new(Dag.node_id(), keyword()) :: t()
  def new(id, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    {reducer, opts} = Keyword.pop!(opts, :reducer)
    {initial, opts} = Keyword.pop(opts, :initial)
    {emit_when, opts} = Keyword.pop(opts, :emit_when, :all_received)

    %__MODULE__{
      id: id,
      name: name,
      reducer: reducer,
      initial: initial,
      emit_when: emit_when,
      opts: Map.new(opts)
    }
  end

  defimpl Dag.Component do
    def id(%{id: id}), do: id
    def name(%{name: nil, id: id}), do: to_string(id)
    def name(%{name: name}), do: name

    def validate(%{id: nil}), do: {:error, :missing_id}
    def validate(%{reducer: nil}), do: {:error, :missing_reducer}
    def validate(%{reducer: r}) when not is_function(r), do: {:error, :invalid_reducer}
    def validate(_), do: :ok
  end

  defimpl Dag.Invokable do
    def activates?(%{emit_when: :all_received}, available_facts, _context) do
      map_size(available_facts) > 0
    end

    def activates?(%{emit_when: emit_fn, reducer: reducer, initial: initial}, available_facts, _context)
        when is_function(emit_fn, 3) do
      input_values = Dag.Components.Helpers.flatten_inputs(available_facts)
      values = Map.values(input_values)
      accumulated = Enum.reduce(values, initial, reducer)
      emit_fn.(accumulated, length(values), map_size(available_facts))
    end

    def prepare(%{id: id, reducer: reducer, initial: initial, opts: opts}, inputs, context) do
      fun = fn input_map, _ctx ->
        # Reduce over one value per predecessor (not flattening lists)
        result =
          input_map
          |> Map.values()
          |> Enum.reduce(initial, reducer)

        {:ok, result}
      end

      input_values = Dag.Components.Helpers.flatten_inputs(inputs)
      metadata = Map.take(opts, [:timeout, :retries])
      Dag.Runnable.new(id, fun, input_values, context: context, metadata: metadata)
    end

    def apply_result(%{id: id}, {:ok, value}) do
      {:ok, [Dag.Fact.from_output(id, value)]}
    end

    def apply_result(_acc, {:error, _} = error), do: error
  end

  defimpl Inspect do
    def inspect(%{id: id, name: name}, _opts) do
      "#Accumulator<#{name || id}>"
    end
  end
end
