defimpl FnTypes.Normalizable, for: Any do
  @moduledoc """
  Fallback implementation for FnTypes.Normalizable.

  Delegates to FnTypes.Protocols.Normalizable if implemented for the type,
  otherwise provides a default normalization.
  """

  def normalize(error, opts) do
    # Delegate to the old protocol location for backwards compatibility
    # This allows existing implementations to work with the new protocol
    FnTypes.Protocols.Normalizable.normalize(error, opts)
  end
end
