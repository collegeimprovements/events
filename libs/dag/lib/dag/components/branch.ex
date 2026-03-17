defmodule Dag.Components.Branch do
  @moduledoc """
  Conditional routing component.

  A Branch evaluates a condition and produces a tagged fact. Downstream
  components can use edge conditions (`when: :tag`) to only activate
  on matching branches.

  ## Function Signatures

  The condition accepts 1 or 2 arity:

      # 1-arity: receives the single predecessor's output (or raw input for roots)
      Branch.new(:check, condition: fn amount -> if amount > 1000, do: :high, else: :low end)

      # 2-arity: receives (inputs_map, context)
      Branch.new(:check, condition: fn inputs, ctx -> ... end)

  ## Examples

      # Route based on amount (1-arity)
      branch = Branch.new(:check_amount,
        condition: fn amount -> if amount > 1000, do: :high, else: :low end
      )

      # Downstream components with edge conditions:
      workflow
      |> Workflow.add(branch)
      |> Workflow.add(Step.new(:high_handler, &handle_high/1), after: :check_amount, edge: %{when: :high})
      |> Workflow.add(Step.new(:low_handler, &handle_low/1), after: :check_amount, edge: %{when: :low})
  """

  @type t :: %__MODULE__{
          id: Dag.node_id(),
          name: String.t() | nil,
          condition: (map(), map() -> atom()),
          opts: map()
        }

  defstruct [:id, :name, :condition, opts: %{}]

  @doc """
  Creates a new branch.

  Accepts 1-arity or 2-arity condition functions.

  ## Required Options

  - `:condition` - `fn value -> atom` or `fn inputs, ctx -> atom` - returns a tag for routing

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

    %__MODULE__{
      id: id,
      name: name,
      condition: Dag.Components.Helpers.normalize_fun(condition),
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
    def validate(_), do: :ok
  end

  defimpl Dag.Invokable do
    def activates?(_branch, available_facts, _context) do
      map_size(available_facts) > 0
    end

    def prepare(%{id: id, condition: condition, opts: opts}, inputs, context) do
      fun = fn input_map, ctx ->
        tag = condition.(input_map, ctx)
        values = Map.values(input_map)

        value =
          case values do
            [single] -> single
            multiple -> multiple
          end

        {:ok, %{branch: tag, value: value}}
      end

      input_values = Dag.Components.Helpers.flatten_inputs(inputs)
      metadata = Map.take(opts, [:timeout, :retries])
      Dag.Runnable.new(id, fun, input_values, context: context, metadata: metadata)
    end

    def apply_result(%{id: id}, {:ok, %{branch: tag} = value}) do
      {:ok, [Dag.Fact.from_output(id, value, type: tag)]}
    end

    def apply_result(%{id: id}, {:ok, value}) do
      {:ok, [Dag.Fact.from_output(id, value)]}
    end

    def apply_result(_branch, {:error, _} = error), do: error
  end

  defimpl Inspect do
    def inspect(%{id: id, name: name}, _opts) do
      "#Branch<#{name || id}>"
    end
  end
end
