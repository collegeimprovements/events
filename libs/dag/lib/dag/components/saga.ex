defmodule Dag.Components.Saga do
  @moduledoc """
  Compensatable transaction step.

  A Saga has both an execute function and a compensate function.
  If the saga (or a downstream step) fails, the compensate function
  can be called to undo the work.

  ## Function Signatures

  The `execute` function accepts 1 or 2 arity:

      # 1-arity: receives the single predecessor's output (or raw input for roots)
      Saga.new(:charge, execute: fn order -> {:ok, Payments.charge(order)} end)

      # 2-arity: receives (inputs_map, context)
      Saga.new(:charge, execute: fn inputs, ctx -> {:ok, Payments.charge(inputs.order, ctx[:key])} end)

  The `compensate` function is always 3-arity: `fn inputs, result, ctx -> :ok end`.

  ## Examples

      saga = Dag.Components.Saga.new(:charge_payment,
        execute: fn order -> {:ok, Payments.charge(order)} end,
        compensate: fn _inputs, result, _ctx ->
          Payments.refund(result.charge_id)
          :ok
        end
      )

  ## Compensation

  The workflow engine tracks saga results. On failure, compensation
  runs in reverse order (last completed saga first):

      # If step 3 fails:
      #   compensate step 2 (reverse_inventory)
      #   compensate step 1 (refund_payment)
  """

  @type t :: %__MODULE__{
          id: Dag.node_id(),
          name: String.t() | nil,
          execute: (map(), map() -> Dag.Runnable.result()),
          compensate: (map(), term(), map() -> :ok | {:error, term()}) | nil,
          opts: map()
        }

  defstruct [:id, :name, :execute, :compensate, opts: %{}]

  @doc """
  Creates a new saga.

  Accepts 1-arity or 2-arity execute functions.

  ## Required Options

  - `:execute` - `fn value -> result` or `fn inputs, ctx -> result`

  ## Optional

  - `:compensate` - `fn inputs, result, ctx -> :ok | {:error, reason}` (always 3-arity)
  - `:name` - Human-readable name
  - `:timeout` - Execution timeout in ms
  - `:retries` - Number of retry attempts on failure
  - `:retry_delay` - Base delay between retries in ms (default: 100)
  - `:retry_backoff` - `:fixed`, `:linear`, or `:exponential` (default: `:fixed`)
  """
  @spec new(Dag.node_id(), keyword()) :: t()
  def new(id, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    {execute, opts} = Keyword.pop!(opts, :execute)
    {compensate, opts} = Keyword.pop(opts, :compensate)

    %__MODULE__{
      id: id,
      name: name,
      execute: Dag.Components.Helpers.normalize_fun(execute),
      compensate: compensate,
      opts: Map.new(opts)
    }
  end

  @doc """
  Returns true if this saga has a compensation function.
  """
  @spec compensatable?(t()) :: boolean()
  def compensatable?(%__MODULE__{compensate: nil}), do: false
  def compensatable?(%__MODULE__{}), do: true

  defimpl Dag.Component do
    def id(%{id: id}), do: id
    def name(%{name: nil, id: id}), do: to_string(id)
    def name(%{name: name}), do: name

    def validate(%{id: nil}), do: {:error, :missing_id}
    def validate(%{execute: nil}), do: {:error, :missing_execute}
    def validate(%{execute: e}) when not is_function(e), do: {:error, :invalid_execute}
    def validate(_), do: :ok
  end

  defimpl Dag.Invokable do
    def activates?(_saga, available_facts, _context) do
      map_size(available_facts) > 0
    end

    def prepare(%{id: id, execute: execute_fn, opts: opts}, inputs, context) do
      input_values = Dag.Components.Helpers.flatten_inputs(inputs)
      metadata = Map.take(opts, [:timeout, :retries])
      Dag.Runnable.new(id, execute_fn, input_values, context: context, metadata: metadata)
    end

    def apply_result(%{id: id}, {:ok, value}) do
      {:ok, [Dag.Fact.from_output(id, value)]}
    end

    def apply_result(_saga, {:error, _} = error), do: error
  end

  defimpl Inspect do
    def inspect(%{id: id, name: name}, _opts) do
      "#Saga<#{name || id}>"
    end
  end
end
