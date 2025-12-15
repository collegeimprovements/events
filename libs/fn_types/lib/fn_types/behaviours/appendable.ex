defmodule FnTypes.Behaviours.Appendable do
  @moduledoc """
  Behaviour defining the Appendable interface for types that can be combined.

  Also known as **Semigroup** in functional programming terminology.

  An Appendable type has an associative binary operation (`combine/2`).

  ## Appendable Law

  Implementations must satisfy associativity:

      combine(combine(a, b), c) == combine(a, combine(b, c))

  ## Common Appendables

  - Lists: `combine = ++`
  - Numbers: `combine = +` or `combine = *`
  - Strings: `combine = <>`
  - Maps: `combine = Map.merge/2`

  ## Example Implementation

      defmodule Sum do
        @behaviour FnTypes.Behaviours.Appendable

        defstruct [:value]

        @impl true
        def combine(%Sum{value: a}, %Sum{value: b}), do: %Sum{value: a + b}
      end

  ## Implementations

  - `FnTypes.NonEmptyList` - Concatenation
  - `FnTypes.Validation` - Error accumulation
  - `FnTypes.Ior` - Value/warning accumulation
  """

  @doc """
  Combines two values together.

  The operation must be associative: `combine(combine(a, b), c) == combine(a, combine(b, c))`

  ## Examples

      NonEmptyList.combine(nel1, nel2)
      #=> combined non-empty list

      Validation.combine(v1, v2)
      #=> combined validation (errors accumulated)
  """
  @callback combine(appendable :: term(), appendable :: term()) :: term()

  @doc """
  Optional: Combines multiple values together.

  Default implementation uses `fold_left` with `combine/2`.
  """
  @callback concat(list(term())) :: term()

  @optional_callbacks [concat: 1]
end
