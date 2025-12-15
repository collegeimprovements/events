defmodule FnTypes.Behaviours.Chainable do
  @moduledoc """
  Behaviour defining the Chainable interface for types that support sequential operations.

  Also known as **Monad** in functional programming terminology.

  A Chainable type supports:
  - `pure/1` (return/unit) - Wrapping a value in the context
  - `bind/2` (flatMap/and_then) - Chaining operations that return wrapped values
  - `map/2` - Applying a function to the wrapped value

  ## Chainable Laws

  Implementations should satisfy:

  1. **Left Identity**: `pure(a) |> bind(f) == f.(a)`
  2. **Right Identity**: `m |> bind(&pure/1) == m`
  3. **Associativity**: `m |> bind(f) |> bind(g) == m |> bind(fn x -> f.(x) |> bind(g) end)`

  ## Example Implementation

      defmodule MyChainable do
        @behaviour FnTypes.Behaviours.Chainable

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
  - `FnTypes.Result` - Result type for error handling
  - `FnTypes.Maybe` - Maybe/Option type for optional values
  - `FnTypes.Validation` - Validation with error accumulation
  - `FnTypes.Ior` - Inclusive-Or type with warning accumulation
  """

  @doc """
  Chains a computation (flatMap/and_then).

  Takes a wrapped value and a function that returns a wrapped value,
  applies the function to the unwrapped value if in success state.

  ## Examples

      {:ok, 5}
      |> Result.bind(fn x -> {:ok, x * 2} end)
      #=> {:ok, 10}

      {:error, :failed}
      |> Result.bind(fn x -> {:ok, x * 2} end)
      #=> {:error, :failed}
  """
  @callback bind(chainable :: term(), (term() -> term())) :: term()

  @doc """
  Optional callback for extracting value with a default.

  Returns the wrapped value if in success state, otherwise the default.
  """
  @callback unwrap_or(chainable :: term(), default :: term()) :: term()

  @optional_callbacks [unwrap_or: 2]
end
