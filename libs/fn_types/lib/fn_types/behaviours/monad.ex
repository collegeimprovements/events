defmodule FnTypes.Behaviours.Monad do
  @moduledoc """
  Behaviour defining the Monad interface for functional types.

  A Monad is a type that supports:
  - `pure/1` (return/unit) - Wrapping a value in the monadic context
  - `bind/2` (flatMap/and_then) - Chaining operations that return monadic values
  - `map/2` (fmap) - Applying a function to the wrapped value

  ## Monad Laws

  Implementations should satisfy the monad laws:

  1. **Left Identity**: `pure(a) |> bind(f) == f.(a)`
  2. **Right Identity**: `m |> bind(&pure/1) == m`
  3. **Associativity**: `m |> bind(f) |> bind(g) == m |> bind(fn x -> f.(x) |> bind(g) end)`

  ## Example Implementation

      defmodule MyMonad do
        @behaviour FnTypes.Behaviours.Monad

        @impl true
        def pure(value), do: {:ok, value}

        @impl true
        def bind({:ok, value}, fun), do: fun.(value)
        def bind({:error, _} = error, _fun), do: error

        @impl true
        def map({:ok, value}, fun), do: {:ok, fun.(value)}
        def map({:error, _} = error, _fun), do: error
      end

  ## Implementations

  The following FnTypes modules implement this behaviour:
  - `FnTypes.Result` - Result monad for error handling
  - `FnTypes.Maybe` - Maybe/Option monad for optional values
  - `FnTypes.Validation` - Validation applicative with error accumulation
  - `FnTypes.Ior` - Inclusive-Or type with warning accumulation
  """

  @doc """
  Chains a monadic computation (flatMap/and_then).

  Takes a monadic value and a function that returns a monadic value,
  applies the function to the unwrapped value if in success state.

  ## Examples

      {:ok, 5}
      |> Result.bind(fn x -> {:ok, x * 2} end)
      #=> {:ok, 10}

      {:error, :failed}
      |> Result.bind(fn x -> {:ok, x * 2} end)
      #=> {:error, :failed}
  """
  @callback bind(monad :: term(), (term() -> term())) :: term()

  @doc """
  Optional callback for extracting value with a default.

  Returns the wrapped value if in success state, otherwise the default.
  """
  @callback unwrap_or(monad :: term(), default :: term()) :: term()

  @optional_callbacks [unwrap_or: 2]
end
