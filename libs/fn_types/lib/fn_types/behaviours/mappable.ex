defmodule FnTypes.Behaviours.Mappable do
  @moduledoc """
  Behaviour defining the Mappable interface for types that can be mapped over.

  Also known as **Functor** in functional programming terminology.

  A Mappable type provides a way to apply a function to a wrapped value
  without unwrapping it.

  ## Mappable Laws

  Implementations must satisfy:

  1. **Identity**: `map(fa, &Function.identity/1) == fa`
  2. **Composition**: `map(fa, fn x -> g.(f.(x)) end) == map(map(fa, f), g)`

  ## Example Implementation

      defmodule Box do
        @behaviour FnTypes.Behaviours.Mappable

        defstruct [:value]

        @impl true
        def map(%Box{value: v}, fun), do: %Box{value: fun.(v)}
      end

  ## Implementations

  - `FnTypes.Result` - Maps over the success value
  - `FnTypes.Maybe` - Maps over the present value
  - `FnTypes.Validation` - Maps over the success value
  - `FnTypes.Ior` - Maps over the right/both value
  - `FnTypes.NonEmptyList` - Maps over all elements
  """

  @doc """
  Applies a function to the wrapped value.

  The function is only applied if the container is in a "success" state.
  For failure states, the container is returned unchanged.

  ## Examples

      {:ok, 5}
      |> Result.map(fn x -> x * 2 end)
      #=> {:ok, 10}

      {:some, "hello"}
      |> Maybe.map(&String.upcase/1)
      #=> {:some, "HELLO"}

      :none
      |> Maybe.map(&String.upcase/1)
      #=> :none
  """
  @callback map(mappable :: term(), (term() -> term())) :: term()
end
