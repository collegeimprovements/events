defimpl Events.Identifiable, for: Events.Error do
  @moduledoc """
  Identifiable implementation for Events.Error structs.

  Each error has a unique ID generated at creation time, making errors
  trackable across the system for debugging, logging, and correlation.

  ## Identity Format

  - **Type**: The error's type atom (`:validation`, `:not_found`, etc.)
  - **ID**: The error's unique ID (e.g., `"err_a1b2c3d4e5f6g7h8"`)

  ## Examples

      error = Events.Error.new(:validation, :invalid_email,
        message: "Email format is invalid"
      )

      Identifiable.entity_type(error)
      #=> :validation

      Identifiable.id(error)
      #=> "err_a1b2c3d4e5f6g7h8"

      Identifiable.identity(error)
      #=> {:validation, "err_a1b2c3d4e5f6g7h8"}

  ## Use Cases

  ### Error Correlation

  Track errors across distributed systems using the identity:

      {:type, error_id} = Identifiable.identity(error)
      Logger.error("Failed operation", error_id: error_id, error_type: type)

  ### Error Deduplication

  Prevent duplicate error notifications:

      error_key = Identifiable.identity(error)
      unless already_notified?(error_key) do
        send_notification(error)
        mark_notified(error_key)
      end

  ### Error Storage Lookup

      # Store error for later analysis
      {:type, error_id} = Identifiable.identity(error)
      ErrorStore.put(error_id, error)

      # Later: retrieve by ID
      error = ErrorStore.get("err_a1b2c3d4e5f6g7h8")

  ## Notes

  The error type (`:validation`, `:not_found`, etc.) is used as the
  entity_type rather than a generic `:error` to allow for more specific
  filtering and grouping in logs and metrics.
  """

  @doc """
  Returns the error's type as the entity type.

  Using the specific error type (`:validation`, `:not_found`) rather than
  a generic `:error` enables more granular filtering and analysis.

  ## Examples

      Identifiable.entity_type(validation_error)
      #=> :validation

      Identifiable.entity_type(not_found_error)
      #=> :not_found
  """
  @impl true
  def entity_type(%Events.Error{type: type}), do: type

  @doc """
  Returns the error's unique ID.

  Error IDs are generated at creation time with the format `err_<hex>`.

  ## Examples

      Identifiable.id(error)
      #=> "err_a1b2c3d4e5f6g7h8"
  """
  @impl true
  def id(%Events.Error{id: id}), do: id

  @doc """
  Returns the compound identity `{error_type, error_id}`.

  ## Examples

      Identifiable.identity(error)
      #=> {:validation, "err_a1b2c3d4e5f6g7h8"}
  """
  @impl true
  def identity(%Events.Error{type: type, id: id}) do
    {type, id}
  end
end
