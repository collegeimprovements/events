defimpl Events.Types.Recoverable, for: Any do
  @moduledoc """
  Fallback implementation for Events.Types.Recoverable.

  Delegates to Events.Protocols.Recoverable if implemented for the type,
  otherwise provides default values.
  """

  def recoverable?(error) do
    Events.Protocols.Recoverable.recoverable?(error)
  end

  def strategy(error) do
    Events.Protocols.Recoverable.strategy(error)
  end

  def retry_delay(error, attempt) do
    Events.Protocols.Recoverable.retry_delay(error, attempt)
  end

  def max_attempts(error) do
    Events.Protocols.Recoverable.max_attempts(error)
  end

  def trips_circuit?(error) do
    Events.Protocols.Recoverable.trips_circuit?(error)
  end

  def severity(error) do
    Events.Protocols.Recoverable.severity(error)
  end

  def fallback(error) do
    Events.Protocols.Recoverable.fallback(error)
  end
end
