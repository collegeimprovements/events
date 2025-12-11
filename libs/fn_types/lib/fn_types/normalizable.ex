defprotocol FnTypes.Protocols.Normalizable do
  @fallback_to_any true

  @moduledoc """
  Backwards-compatibility alias for `FnTypes.Normalizable`.

  > **Deprecated**: Use `FnTypes.Normalizable` instead.
  > This module exists for backwards compatibility and delegates to the new location.

  See `FnTypes.Normalizable` for full documentation.
  """

  @doc """
  Normalize the error into a standard `FnTypes.Error` struct.

  **Deprecated**: Use `FnTypes.Normalizable.normalize/2` instead.
  """
  @spec normalize(t(), keyword()) :: FnTypes.Error.t()
  def normalize(error, opts \\ [])
end

# Note: Protocol implementations remain in lib/events/protocols/impls/normalizable/
# They implement FnTypes.Protocols.Normalizable which is still the canonical protocol
# used throughout the codebase during the transition period.
