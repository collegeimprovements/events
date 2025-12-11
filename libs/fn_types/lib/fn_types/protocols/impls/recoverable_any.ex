defimpl FnTypes.Recoverable, for: Any do
  @moduledoc """
  Fallback implementation for FnTypes.Recoverable.

  Delegates to FnTypes.Protocols.Recoverable if implemented for the type,
  otherwise provides default values.
  """

  def recoverable?(error) do
    FnTypes.Protocols.Recoverable.recoverable?(error)
  end

  def strategy(error) do
    FnTypes.Protocols.Recoverable.strategy(error)
  end

  def retry_delay(error, attempt) do
    FnTypes.Protocols.Recoverable.retry_delay(error, attempt)
  end

  def max_attempts(error) do
    FnTypes.Protocols.Recoverable.max_attempts(error)
  end

  def trips_circuit?(error) do
    FnTypes.Protocols.Recoverable.trips_circuit?(error)
  end

  def severity(error) do
    FnTypes.Protocols.Recoverable.severity(error)
  end

  def fallback(error) do
    FnTypes.Protocols.Recoverable.fallback(error)
  end
end
