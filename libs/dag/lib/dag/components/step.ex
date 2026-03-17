defmodule Dag.Components.Step do
  @moduledoc """
  Basic function step component.

  A Step takes input facts, applies a function, and produces output facts.
  This is the most common component type - the workhorse of any workflow.

  ## Function Signatures

  Steps accept functions with 1 or 2 arity:

      # 1-arity: receives the input value directly (simple transforms)
      Step.new(:upcase, fn value -> {:ok, String.upcase(value)} end)

      # 2-arity: receives (inputs_map, context)
      Step.new(:fetch, fn inputs, ctx -> {:ok, fetch(inputs, ctx[:api_key])} end)

  For **root steps** (no predecessors), the 1-arity form receives the raw
  workflow input. The 2-arity form receives `%{__input__: value}`.

  For **non-root steps**, the 1-arity form receives the single predecessor's
  output (only valid with exactly one predecessor). The 2-arity form receives
  `%{predecessor_id => value}`.

  ## Examples

      # Simple 1-arity (clean for linear pipelines)
      Step.new(:upcase, fn text -> {:ok, String.upcase(text)} end)

      # 2-arity with context
      Step.new(:fetch, fn _inputs, ctx -> {:ok, fetch(ctx[:url])} end,
        name: "Fetch Data",
        timeout: 5000
      )

      # 2-arity with multiple predecessors (diamond pattern)
      Step.new(:merge, fn inputs, _ctx ->
        {:ok, %{users: inputs.fetch_users, orders: inputs.fetch_orders}}
      end)
  """

  @type t :: %__MODULE__{
          id: Dag.node_id(),
          name: String.t() | nil,
          function: (map(), map() -> Dag.Runnable.result()),
          opts: map()
        }

  defstruct [:id, :name, :function, opts: %{}]

  @doc """
  Creates a new step.

  Accepts 1-arity or 2-arity functions. 1-arity functions are
  automatically wrapped to extract the single input value.

  ## Options

  - `:name` - Human-readable name
  - `:timeout` - Execution timeout in ms (enforced by engine)
  - `:retries` - Number of retry attempts on failure
  - `:retry_delay` - Base delay between retries in ms (default: 100)
  - `:retry_backoff` - `:fixed`, `:linear`, or `:exponential` (default: `:fixed`)
  - Any other key-value pairs are stored in `opts`
  """
  @spec new(Dag.node_id(), function(), keyword()) :: t()
  def new(id, function, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    %__MODULE__{
      id: id,
      name: name,
      function: Dag.Components.Helpers.normalize_fun(function),
      opts: Map.new(opts)
    }
  end

  defimpl Dag.Component do
    def id(%{id: id}), do: id
    def name(%{name: nil, id: id}), do: to_string(id)
    def name(%{name: name}), do: name

    def validate(%{id: nil}), do: {:error, :missing_id}
    def validate(%{function: nil}), do: {:error, :missing_function}
    def validate(%{function: f}) when not is_function(f), do: {:error, :invalid_function}
    def validate(_), do: :ok
  end

  defimpl Dag.Invokable do
    def activates?(_step, available_facts, _context) do
      map_size(available_facts) > 0
    end

    def prepare(%{id: id, function: fun, opts: opts}, inputs, context) do
      input_values = Dag.Components.Helpers.flatten_inputs(inputs)
      metadata = Map.take(opts, [:timeout, :retries])
      Dag.Runnable.new(id, fun, input_values, context: context, metadata: metadata)
    end

    def apply_result(%{id: id}, {:ok, value}) do
      {:ok, [Dag.Fact.from_output(id, value)]}
    end

    def apply_result(_step, {:error, _} = error), do: error
  end

  defimpl Inspect do
    def inspect(%{id: id, name: name}, _opts) do
      "#Step<#{name || id}>"
    end
  end
end
