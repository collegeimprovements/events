defmodule Dag.Fact do
  @moduledoc """
  Represents a unit of data flowing through a workflow.

  Facts are immutable, typed values produced by components. They carry
  provenance information (source component, timestamp) enabling data
  lineage tracking and replay.

  ## Examples

      fact = Dag.Fact.new("hello", source: :tokenizer, type: :string)
      fact.value  #=> "hello"
      fact.source #=> :tokenizer

  ## Why Facts?

  Traditional workflows pass a mutable context map through all steps.
  Facts provide:
  - **Data lineage** - trace which component produced which value
  - **Shared computation** - diamond dependencies read the same facts
  - **Replay** - re-execute from any point using cached facts
  - **Type tagging** - downstream components match on fact types
  """

  @type t :: %__MODULE__{
          id: reference() | term(),
          value: term(),
          source: Dag.node_id() | nil,
          type: atom() | nil,
          timestamp: integer(),
          metadata: map()
        }

  defstruct [:id, :value, :source, :type, :timestamp, metadata: %{}]

  @doc """
  Creates a new fact.

  ## Options

  - `:id` - Custom identifier (default: `make_ref()`)
  - `:source` - Component that produced this fact
  - `:type` - Type tag for pattern matching / conditional routing
  - `:timestamp` - Production timestamp (default: `System.monotonic_time()`)
  - `:metadata` - Arbitrary metadata

  ## Examples

      Dag.Fact.new("hello")
      Dag.Fact.new(42, source: :compute, type: :count)
  """
  @spec new(term(), keyword()) :: t()
  def new(value, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, make_ref()),
      value: value,
      source: Keyword.get(opts, :source),
      type: Keyword.get(opts, :type),
      timestamp: Keyword.get(opts, :timestamp, System.monotonic_time()),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a fact from a component's output, tagging it with the source.

  ## Examples

      Dag.Fact.from_output(:tokenizer, ["hello", "world"])
      Dag.Fact.from_output(:branch, %{tag: :high}, type: :high)
  """
  @spec from_output(Dag.node_id(), term(), keyword()) :: t()
  def from_output(component_id, value, opts \\ []) do
    new(value, Keyword.put(opts, :source, component_id))
  end

  @doc """
  Extracts the raw value from a fact.
  """
  @spec value(t()) :: term()
  def value(%__MODULE__{value: v}), do: v

  @doc """
  Returns true if the fact matches the given type.
  """
  @spec type?(t(), atom()) :: boolean()
  def type?(%__MODULE__{type: type}, expected), do: type == expected
end
