defmodule FnTypes.Behaviours.Foldable do
  @moduledoc """
  Behaviour defining the Foldable interface for types that can be reduced.

  A Foldable type can be collapsed into a single value using a binary function.
  This is the functional programming equivalent of Elixir's `Enum.reduce/3`.

  ## Foldable Laws

  Implementations should be consistent with these properties:

  1. **fold_right with cons**: `fold_right(t, [], &[&1 | &2]) == to_list(t)`
  2. **fold_left with snoc**: `fold_left(t, [], &(&2 ++ [&1])) == to_list(t)`

  ## Example Implementation

      defmodule MyContainer do
        @behaviour FnTypes.Behaviours.Foldable

        @impl true
        def fold_left({:some, value}, acc, fun), do: fun.(value, acc)
        def fold_left(:none, acc, _fun), do: acc

        @impl true
        def fold_right({:some, value}, acc, fun), do: fun.(value, acc)
        def fold_right(:none, acc, _fun), do: acc
      end

  ## Implementations

  The following FnTypes modules implement this behaviour:
  - `FnTypes.Result` - Folds over the success value
  - `FnTypes.Maybe` - Folds over the present value
  - `FnTypes.NonEmptyList` - Folds over all elements
  - `FnTypes.Ior` - Folds over the right/both value
  """

  @doc """
  Left-associative fold over the structure.

  Reduces the structure from left to right, applying the function
  to each element and an accumulator.

  ## Examples

      Result.fold_left({:ok, 5}, 0, &+/2)
      #=> 5

      NonEmptyList.fold_left(nel, 0, &+/2)
      #=> sum of all elements
  """
  @callback fold_left(foldable :: term(), acc :: term(), (term(), term() -> term())) :: term()

  @doc """
  Right-associative fold over the structure.

  Reduces the structure from right to left, applying the function
  to each element and an accumulator.

  ## Examples

      NonEmptyList.fold_right(nel, [], fn x, acc -> [x | acc] end)
      #=> list of all elements in order
  """
  @callback fold_right(foldable :: term(), acc :: term(), (term(), term() -> term())) :: term()

  @doc """
  Optional callback to convert the foldable to a list.
  """
  @callback to_list(foldable :: term()) :: list()

  @doc """
  Optional callback to check if the foldable is empty.
  """
  @callback empty?(foldable :: term()) :: boolean()

  @optional_callbacks [to_list: 1, empty?: 1]
end
