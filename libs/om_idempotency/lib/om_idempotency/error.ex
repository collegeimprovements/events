defmodule OmIdempotency.Error do
  @moduledoc """
  Enhanced error handling for OmIdempotency using FnTypes.Error.

  Provides structured error types with consistent formatting and metadata.

  ## Error Types

  - `:already_processing` - Operation is already being processed by another request
  - `:stale_record` - Record was modified by another process (optimistic locking failure)
  - `:wait_timeout` - Timed out waiting for operation to complete
  - `:idempotency_conflict` - Idempotency key conflict detected
  - `:permanent_failure` - Operation failed permanently and cannot be retried
  - `:not_found` - Idempotency record not found
  - `:invalid_state` - Invalid state transition attempted
  - `:expired` - Idempotency record has expired
  """

  @type error_type ::
          :already_processing
          | :stale_record
          | :wait_timeout
          | :idempotency_conflict
          | :permanent_failure
          | :not_found
          | :invalid_state
          | :expired
          | :repo_not_configured
          | :validation_error

  @doc """
  Creates an error with additional context.

  ## Examples

      Error.new(:already_processing, key: "order_123", scope: "payments")
      #=> %Error{type: :already_processing, message: "...", metadata: %{key: "order_123", scope: "payments"}}
  """
  def new(type, metadata \\ []) do
    FnTypes.Error.new(:idempotency, type,
      message: message(type),
      details: Map.new(metadata),
      source: __MODULE__
    )
  end

  @doc """
  Wraps an Ecto changeset error.
  """
  def from_changeset(%Ecto.Changeset{} = changeset) do
    FnTypes.Error.new(:idempotency, :validation_error,
      message: "Validation failed",
      details: %{errors: changeset.errors},
      source: __MODULE__
    )
  end

  @doc """
  Returns the error message for a given error type.
  """
  def message(:already_processing), do: "Operation is already being processed"
  def message(:stale_record), do: "Record was modified by another process"
  def message(:wait_timeout), do: "Timed out waiting for operation to complete"
  def message(:idempotency_conflict), do: "Idempotency key conflict detected"
  def message(:permanent_failure), do: "Operation failed permanently"
  def message(:not_found), do: "Idempotency record not found"
  def message(:invalid_state), do: "Invalid state transition"
  def message(:expired), do: "Idempotency record has expired"
  def message(:repo_not_configured), do: "No repo configured for OmIdempotency"
  def message(_), do: "Unknown idempotency error"
end
