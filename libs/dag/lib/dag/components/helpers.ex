defmodule Dag.Components.Helpers do
  @moduledoc false
  # Shared helpers for component implementations.

  @doc """
  Flattens a map of `%{source_id => [Fact.t()]}` into `%{source_id => value}`.

  Single-element lists are unwrapped to their value.
  Multi-element lists are kept as lists of values.
  """
  @spec flatten_inputs(%{Dag.node_id() => [Dag.Fact.t()]}) :: map()
  def flatten_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {source_id, facts} ->
      values = Enum.map(facts, & &1.value)

      value =
        case values do
          [single] -> single
          multiple -> multiple
        end

      {source_id, value}
    end)
  end

  @doc """
  Normalizes a 1-arity function to the standard 2-arity `(inputs, ctx)` interface.

  For 1-arity functions, extracts the single value from the inputs map:
  - If inputs has exactly one key, passes that value
  - Otherwise passes the full inputs map

  2-arity functions are returned as-is.
  """
  @spec normalize_fun(function()) :: (map(), map() -> term())
  def normalize_fun(fun) when is_function(fun, 2), do: fun

  def normalize_fun(fun) when is_function(fun, 1) do
    fn inputs, _ctx ->
      value =
        case Map.values(inputs) do
          [single] -> single
          _multiple -> inputs
        end

      fun.(value)
    end
  end

  def normalize_fun(fun), do: fun
end
