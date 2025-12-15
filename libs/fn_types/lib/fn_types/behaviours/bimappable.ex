defmodule FnTypes.Behaviours.BiMappable do
  @moduledoc """
  Behaviour for types that can transform both success and error values.

  Also known as **Bifunctor** in functional programming terminology.

  A BiMappable type has two "slots" (like Result's value and error) and provides
  functions to transform either or both independently using an expressive keyword API.

  ## Expressive Keyword API

  Instead of positional arguments, use explicit keywords that clearly express intent:

      # Result uses on_ok/on_error
      Result.bimap(result,
        on_ok: &format_response/1,
        on_error: &normalize_error/1
      )

      # Ior uses on_success/on_failure
      Ior.bimap(outcome,
        on_success: &process/1,
        on_failure: &log_warning/1
      )

      # Can omit either side - only transforms what you specify
      Result.bimap(result, on_error: &normalize/1)
      Result.bimap(result, on_ok: &format/1)

  ## BiMappable Laws

  Implementations must satisfy:

  1. **Identity**: `bimap(x, on_ok: &identity/1, on_error: &identity/1) == x`
  2. **Composition**: Mapping composed functions equals composing mapped results

  ## Example Implementation

      defmodule MyResult do
        @behaviour FnTypes.Behaviours.BiMappable

        @impl true
        def bimap({:ok, value}, opts) do
          case Keyword.get(opts, :on_ok) do
            nil -> {:ok, value}
            fun -> {:ok, fun.(value)}
          end
        end

        def bimap({:error, reason}, opts) do
          case Keyword.get(opts, :on_error) do
            nil -> {:error, reason}
            fun -> {:error, fun.(reason)}
          end
        end

        @impl true
        def map_error({:error, reason}, fun), do: {:error, fun.(reason)}
        def map_error({:ok, _} = ok, _fun), do: ok
      end

  ## Implementations

  - `FnTypes.Result` - `on_ok:`, `on_error:`
  - `FnTypes.Ior` - `on_success:`, `on_failure:`
  - `FnTypes.Validation` - `on_ok:`, `on_error:`

  ## Use Cases

  - **API Response Formatting**: Transform both success data and errors to API format
  - **Error Normalization**: Convert different error types to a common format
  - **Logging Side Effects**: Log errors while keeping them in the pipeline
  - **Type Conversion**: Convert internal types to external representations
  """

  @typedoc """
  Options for bimap transformation.

  For Result/Validation:
  - `on_ok` - Function to transform success value
  - `on_error` - Function to transform error value

  For Ior:
  - `on_success` - Function to transform success value
  - `on_failure` - Function to transform failure/warnings
  """
  @type transform_opts :: [
          on_ok: (term() -> term()),
          on_error: (term() -> term()),
          on_success: (term() -> term()),
          on_failure: (term() -> term())
        ]

  @doc """
  Transforms both success and error values using keyword options.

  The key insight is that you can transform both sides independently in a single
  call, or omit one side to only transform the other.

  ## Examples

      # Transform both sides
      Result.bimap(result,
        on_ok: fn user -> %{id: user.id, name: user.name} end,
        on_error: fn error -> %{code: 500, message: inspect(error)} end
      )

      # Transform only errors (success passes through unchanged)
      Result.bimap(result, on_error: &normalize_error/1)

      # Transform only success (errors pass through unchanged)
      Result.bimap(result, on_ok: &format_response/1)

      # Ior with warnings
      Ior.bimap(outcome,
        on_success: &process_value/1,
        on_failure: &format_warning/1
      )
  """
  @callback bimap(container :: term(), opts :: transform_opts()) :: term()

  @doc """
  Transforms only the error/failure value.

  For Result/Validation, this is `map_error/2`.
  For Ior, this is `map_failure/2`.

  ## Examples

      {:error, :not_found}
      |> Result.map_error(fn :not_found -> "User not found" end)
      #=> {:error, "User not found"}

      {:ok, value}
      |> Result.map_error(&normalize/1)
      #=> {:ok, value}  # Unchanged
  """
  @callback map_error(container :: term(), (term() -> term())) :: term()

  @doc """
  Optional: Transforms only the success/ok value.

  Usually the same as `Mappable.map/2`, so this is optional.
  Provided for symmetry with `map_error/2`.
  """
  @callback map_ok(container :: term(), (term() -> term())) :: term()

  @optional_callbacks [map_ok: 2]
end
