defmodule FnTypes.Behaviours.Combinable do
  @moduledoc """
  Behaviour defining the Combinable interface for independent computations.

  Also known as **Applicative Functor** in functional programming terminology.

  A Combinable type extends Mappable with the ability to:
  - Lift values into the context (`pure/1`)
  - Apply wrapped functions to wrapped values (`ap/2`)

  This is more powerful than Mappable (which only has `map`) but less
  powerful than Chainable (which has `bind`).

  ## Combinable Laws

  Implementations should satisfy:

  1. **Identity**: `pure(&Function.identity/1) |> ap(v) == v`
  2. **Homomorphism**: `pure(f) |> ap(pure(x)) == pure(f.(x))`
  3. **Interchange**: `u |> ap(pure(y)) == pure(fn f -> f.(y) end) |> ap(u)`
  4. **Composition**: `pure(&Function.compose/2) |> ap(u) |> ap(v) |> ap(w) == u |> ap(v |> ap(w))`

  ## When to Use Combinable vs Chainable

  - Use **Combinable** when operations are independent and can run in parallel
  - Use **Chainable** when later operations depend on earlier results

  ## Example

      # Combinable: validations are independent
      Validation.pure(&create_user/3)
      |> Validation.ap(validate_name(params))
      |> Validation.ap(validate_email(params))
      |> Validation.ap(validate_age(params))
      # All validations run, errors accumulate

      # Chainable: each step depends on the previous
      params
      |> Result.and_then(&validate_name/1)
      |> Result.and_then(&validate_email/1)
      # Stops at first error

  ## Implementations

  - `FnTypes.Validation` - Error-accumulating combinable
  - `FnTypes.Result` - Short-circuiting combinable
  - `FnTypes.Maybe` - Optional value combinable
  """

  @doc """
  Lifts a value into the combinable context.

  Same as Chainable's `pure/1`.
  """
  @callback pure(value :: term()) :: term()

  @doc """
  Applies a wrapped function to a wrapped value.

  If both are in the success state, applies the function.
  The key difference from Chainable is how failures combine.

  ## Examples

      # Result (short-circuits)
      {:ok, fn x -> x * 2 end}
      |> Result.ap({:ok, 5})
      #=> {:ok, 10}

      # Validation (accumulates errors)
      {:errors, [:name_invalid]}
      |> Validation.ap({:errors, [:email_invalid]})
      #=> {:errors, [:name_invalid, :email_invalid]}
  """
  @callback ap(combinable_fn :: term(), combinable_val :: term()) :: term()

  @doc """
  Optional: Combines two values using a function.

  Equivalent to `pure(fun) |> ap(a) |> ap(b)` but often more efficient.
  """
  @callback map2(
              combinable_a :: term(),
              combinable_b :: term(),
              (term(), term() -> term())
            ) :: term()

  @optional_callbacks [map2: 3]
end
