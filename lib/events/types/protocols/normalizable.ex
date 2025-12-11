defprotocol Events.Types.Normalizable do
  @fallback_to_any true

  @moduledoc """
  Protocol for normalizing various error types into `Events.Types.Error`.

  This protocol provides a unified interface for converting errors from any source
  (Ecto, HTTP, AWS, Stripe, POSIX, custom business logic, etc.) into the standard
  `Events.Types.Error` struct.

  ## Why Use This Protocol?

  1. **Single dispatch point** - Call `Normalizable.normalize/2` on any error type
  2. **Extensibility** - Add implementations for new error types without modifying core code
  3. **Consistency** - All errors normalized through the same interface
  4. **Integration** - Works seamlessly with `Recoverable` protocol and Result/Pipeline modules

  ## Implementing the Protocol

  To make your custom error type normalizable:

      defmodule MyApp.PaymentError do
        defstruct [:code, :amount, :retry_after]
      end

      defimpl Events.Types.Normalizable, for: MyApp.PaymentError do
        def normalize(%{code: code, amount: amount}, opts) do
          Events.Types.Error.new(:unprocessable, code,
            message: "Payment failed",
            details: %{amount: amount},
            source: :payment,
            context: Keyword.get(opts, :context, %{})
          )
        end
      end

  ## Using @derive

  For simple cases, you can derive the implementation:

      defmodule MyApp.CustomException do
        @derive {Events.Types.Normalizable, type: :business, code: :custom_error}
        defexception [:message, :details]
      end

  ## Usage

      # Direct normalization
      Events.Types.Normalizable.normalize(changeset)
      Events.Types.Normalizable.normalize(stripe_error, context: %{user_id: 123})

      # In pipelines
      {:error, reason}
      |> Events.Types.Result.map_error(&Events.Types.Normalizable.normalize/1)

      # With try/rescue
      try do
        risky_operation()
      rescue
        e -> {:error, Events.Types.Normalizable.normalize(e, stacktrace: __STACKTRACE__)}
      end

  ## Options

  All implementations should support these standard options:

  - `:context` - Map of contextual information (user_id, request_id, etc.)
  - `:stacktrace` - Stacktrace for exceptions
  - `:step` - Pipeline step where error occurred
  - `:source` - Override the default source
  - `:message` - Override the default message
  """

  @doc """
  Normalize the error into a standard `Events.Types.Error` struct.

  ## Options

  - `:context` - Additional context to attach to the error
  - `:stacktrace` - Stacktrace to attach (for exceptions)
  - `:step` - Pipeline step where the error occurred
  - `:source` - Override the source field
  - `:message` - Override the default message

  ## Examples

      iex> Events.Types.Normalizable.normalize(%Ecto.Changeset{valid?: false})
      %Events.Types.Error{type: :validation, code: :changeset_invalid}

      iex> Events.Types.Normalizable.normalize(:not_found)
      %Events.Types.Error{type: :not_found, code: :not_found}

      iex> Events.Types.Normalizable.normalize(error, context: %{user_id: 123})
      %Events.Types.Error{context: %{user_id: 123}, ...}
  """
  @spec normalize(t(), keyword()) :: Events.Types.Error.t()
  def normalize(error, opts \\ [])
end
