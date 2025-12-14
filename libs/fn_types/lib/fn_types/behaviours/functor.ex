defmodule FnTypes.Behaviours.Functor do
  @moduledoc """
  Behaviour defining the Functor interface for mappable types.

  A Functor is a type that can be mapped over. It provides a way to apply
  a function to a wrapped value without unwrapping it.

  ## Functor Laws

  Implementations must satisfy:

  1. **Identity**: `map(fa, &Function.identity/1) == fa`
  2. **Composition**: `map(fa, fn x -> g.(f.(x)) end) == map(map(fa, f), g)`

  ## Example Implementation

      defmodule Box do
        @behaviour FnTypes.Behaviours.Functor

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
  @callback map(functor :: term(), (term() -> term())) :: term()
end
