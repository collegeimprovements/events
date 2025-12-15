defmodule FnTypes.Behaviours.Defaultable do
  @moduledoc """
  Behaviour defining the Defaultable interface for types with an identity element.

  Also known as **Monoid** in functional programming terminology.

  A Defaultable type extends Appendable (Semigroup) with an identity element (`empty/0`)
  such that combining any value with the identity returns the original value.

  ## Defaultable Laws

  Implementations must satisfy:

  1. **Right Identity**: `combine(x, empty()) == x`
  2. **Left Identity**: `combine(empty(), x) == x`
  3. **Associativity** (inherited from Appendable): `combine(combine(a, b), c) == combine(a, combine(b, c))`

  ## Common Defaultables

  - Lists: `empty = []`, `combine = ++`
  - Strings: `empty = ""`, `combine = <>`
  - Numbers (sum): `empty = 0`, `combine = +`
  - Numbers (product): `empty = 1`, `combine = *`
  - Maps: `empty = %{}`, `combine = Map.merge/2`

  ## Example Implementation

      defmodule Sum do
        @behaviour FnTypes.Behaviours.Defaultable

        defstruct [:value]

        @impl true
        def empty(), do: %Sum{value: 0}

        @impl true
        def combine(%Sum{value: a}, %Sum{value: b}), do: %Sum{value: a + b}
      end

  ## Why Defaultable?

  The identity element enables operations that don't require an initial value:

      # Without identity (Appendable only)
      Enum.reduce(items, initial, &combine/2)

      # With identity (Defaultable)
      Defaultable.concat(items)  # uses empty() as initial value

  ## Implementations

  - `FnTypes.Validation` - Empty is `{:ok, []}` for error lists
  - Lists, Strings, Maps via protocol implementations
  """

  @doc """
  Returns the identity element for this type.

  The identity element must satisfy:
  - `combine(x, empty()) == x`
  - `combine(empty(), x) == x`

  ## Examples

      Defaultable.empty(List)
      #=> []

      Defaultable.empty(String)
      #=> ""
  """
  @callback empty() :: term()

  @doc """
  Combines two values (inherited concept from Appendable).

  Included here so Defaultable can be used standalone without
  requiring explicit Appendable implementation.
  """
  @callback combine(term(), term()) :: term()

  @doc """
  Combines a list of values using the identity as the starting point.

  Equivalent to `Enum.reduce(list, empty(), &combine/2)`.

  ## Examples

      Defaultable.concat([[1, 2], [3, 4], [5]])
      #=> [1, 2, 3, 4, 5]

      Defaultable.concat([])
      #=> []  # returns empty()
  """
  @callback concat(list(term())) :: term()

  @optional_callbacks [concat: 1]
end
