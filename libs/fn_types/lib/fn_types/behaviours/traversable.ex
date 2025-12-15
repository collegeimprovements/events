defmodule FnTypes.Behaviours.Traversable do
  @moduledoc """
  Behaviour defining the Traversable interface for mapping with effects.

  Also known as **Traversable** in functional programming terminology.

  A Traversable type can be traversed while applying an effectful function,
  collecting all the effects. This is the generalization of patterns like
  `Result.traverse/2` and `Result.collect/1`.

  ## Core Concept

  The key insight is transforming `Container(a)` with `(a -> Effect(b))`
  into `Effect(Container(b))`:

      # Regular map: [a] -> (a -> b) -> [b]
      Enum.map([1, 2, 3], &to_string/1)
      #=> ["1", "2", "3"]

      # Traverse: [a] -> (a -> Result(b)) -> Result([b])
      Traversable.traverse([1, 2, 3], &parse/1)
      #=> {:ok, [1, 2, 3]} or {:error, reason}

  ## Traversable Laws

  Implementations should satisfy:

  1. **Identity**: `traverse(t, &{:ok, &1}) == {:ok, t}`
  2. **Naturality**: For any natural transformation `nt`,
     `nt(traverse(t, f)) == traverse(t, &nt(f.(&1)))`

  ## Example Implementation

      defmodule MyList do
        @behaviour FnTypes.Behaviours.Traversable

        @impl true
        def traverse([], _fun), do: {:ok, []}
        def traverse([head | tail], fun) do
          with {:ok, h} <- fun.(head),
               {:ok, t} <- traverse(tail, fun) do
            {:ok, [h | t]}
          end
        end

        @impl true
        def sequence(list), do: traverse(list, & &1)
      end

  ## Use Cases

  - Validating a list of inputs, collecting all errors
  - Fetching multiple resources, failing if any fails
  - Parsing a list of values
  - Running multiple async operations

  ## Implementations

  - `FnTypes.Result` - `traverse/2`, `collect/1`
  - `FnTypes.Maybe` - `traverse/2`, `sequence/1`
  - `FnTypes.Validation` - `traverse/2` with error accumulation
  """

  @doc """
  Maps an effectful function over a traversable, collecting effects.

  Takes a traversable structure and a function that returns an effectful
  value (like Result or Maybe), applies the function to each element,
  and collects all the effects into a single effectful result.

  ## Examples

      # Parse all strings, fail on first error
      ["1", "2", "3"]
      |> Result.traverse(&parse_int/1)
      #=> {:ok, [1, 2, 3]}

      ["1", "bad", "3"]
      |> Result.traverse(&parse_int/1)
      #=> {:error, :invalid_integer}

      # With Validation (accumulates ALL errors)
      ["1", "bad", "worse"]
      |> Validation.traverse(&parse_int/1)
      #=> {:error, [:invalid_integer, :invalid_integer]}
  """
  @callback traverse(traversable :: term(), (term() -> term())) :: term()

  @doc """
  Sequences a traversable of effects into an effect of traversable.

  This is `traverse` with the identity function - it "flips" the nesting
  of the container and the effect.

  ## Examples

      # Turn list of Results into Result of list
      [{:ok, 1}, {:ok, 2}, {:ok, 3}]
      |> Result.sequence()
      #=> {:ok, [1, 2, 3]}

      [{:ok, 1}, {:error, :oops}, {:ok, 3}]
      |> Result.sequence()
      #=> {:error, :oops}

      # Turn list of Maybes into Maybe of list
      [{:some, 1}, {:some, 2}]
      |> Maybe.sequence()
      #=> {:some, [1, 2]}

      [{:some, 1}, :none, {:some, 3}]
      |> Maybe.sequence()
      #=> :none
  """
  @callback sequence(traversable :: term()) :: term()

  @optional_callbacks [sequence: 1]
end
