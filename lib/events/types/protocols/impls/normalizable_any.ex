defimpl Events.Types.Normalizable, for: Any do
  @moduledoc """
  Fallback implementation for Events.Types.Normalizable.

  Delegates to Events.Protocols.Normalizable if implemented for the type,
  otherwise provides a default normalization.
  """

  def normalize(error, opts) do
    # Delegate to the old protocol location for backwards compatibility
    # This allows existing implementations to work with the new protocol
    Events.Protocols.Normalizable.normalize(error, opts)
  end
end
