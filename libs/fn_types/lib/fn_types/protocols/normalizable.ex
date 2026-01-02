defprotocol FnTypes.Protocols.Normalizable do
  @fallback_to_any true

  @moduledoc """
  Protocol for normalizing errors into a standard `FnTypes.Error` struct.

  Implement this protocol for your error types to enable consistent
  error handling across the application.

  ## Example

      defimpl FnTypes.Protocols.Normalizable, for: MyApp.CustomError do
        def normalize(error, opts) do
          %FnTypes.Error{
            type: :custom_error,
            message: error.message,
            details: %{code: error.code},
            context: Keyword.get(opts, :context, %{})
          }
        end
      end
  """

  @doc """
  Normalize the error into a standard `FnTypes.Error` struct.

  ## Options

  - `:context` - Additional context to include in the error
  - `:include_stacktrace` - Whether to include stacktrace (default: false)
  """
  @spec normalize(t(), keyword()) :: FnTypes.Error.t()
  def normalize(error, opts \\ [])
end
