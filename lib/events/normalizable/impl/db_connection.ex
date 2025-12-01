defimpl Events.Normalizable, for: DBConnection.ConnectionError do
  @moduledoc """
  Normalizable implementation for DBConnection.ConnectionError.

  Handles database connection pool errors including:
  - Connection pool exhaustion
  - Connection timeouts
  - Disconnection errors
  """

  alias Events.Error

  def normalize(%DBConnection.ConnectionError{message: message} = error, opts) do
    {type, code, recoverable} = classify_connection_error(message)

    Error.new(type, code,
      message: message,
      source: DBConnection,
      recoverable: recoverable,
      details: %{
        severity: error.severity,
        reason: error.reason
      },
      stacktrace: Keyword.get(opts, :stacktrace),
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp classify_connection_error(message) when is_binary(message) do
    cond do
      message =~ ~r/connection not available|pool/i ->
        {:external, :pool_exhausted, true}

      message =~ ~r/timeout|timed out/i ->
        {:timeout, :connection_timeout, true}

      message =~ ~r/disconnect|closed|not connected/i ->
        {:network, :connection_lost, true}

      message =~ ~r/checkout/i ->
        {:external, :checkout_failed, true}

      message =~ ~r/owner/i ->
        {:internal, :ownership_error, false}

      true ->
        {:external, :connection_error, true}
    end
  end

  defp classify_connection_error(_), do: {:external, :connection_error, true}
end
