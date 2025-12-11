defimpl FnTypes.Protocols.Recoverable, for: Any do
  @moduledoc """
  Fallback Recoverable implementation for any value.

  By default, unknown error types are NOT recoverable. This is the safe
  default - if we don't know what an error is, we shouldn't retry it.

  ## Deriving Recoverable

  You can derive Recoverable for your custom error structs:

      defmodule MyApp.CustomError do
        @derive {FnTypes.Protocols.Recoverable,
          recoverable: true,
          strategy: :retry_with_backoff,
          max_attempts: 3
        }
        defstruct [:message, :code]
      end

  ## Derive Options

  - `:recoverable` - Whether errors are recoverable (default: false)
  - `:strategy` - Recovery strategy (default: :fail_fast)
  - `:max_attempts` - Maximum retry attempts (default: 1)
  - `:base_delay` - Base delay for backoff in ms (default: 1000)
  - `:max_delay` - Maximum delay cap in ms (default: 30000)
  - `:trips_circuit` - Whether to trip circuit breaker (default: false)
  - `:severity` - Error severity level (default: :permanent)

  ## Custom Implementation

  For more control, implement the protocol directly:

      defimpl FnTypes.Protocols.Recoverable, for: MyApp.APIError do
        def recoverable?(%{status: status}) when status >= 500, do: true
        def recoverable?(_), do: false

        def strategy(%{status: 429}), do: :wait_until
        def strategy(_), do: :retry_with_backoff

        # ... other callbacks
      end
  """

  alias FnTypes.Protocols.Recoverable.Backoff

  # Default options for derived implementations
  @default_opts [
    recoverable: false,
    strategy: :fail_fast,
    max_attempts: 1,
    base_delay: 1_000,
    max_delay: 30_000,
    trips_circuit: false,
    severity: :permanent
  ]

  defmacro __deriving__(module, _struct, opts) do
    opts = Keyword.merge(@default_opts, opts)

    recoverable = Keyword.fetch!(opts, :recoverable)
    strategy = Keyword.fetch!(opts, :strategy)
    max_attempts = Keyword.fetch!(opts, :max_attempts)
    base_delay = Keyword.fetch!(opts, :base_delay)
    max_delay = Keyword.fetch!(opts, :max_delay)
    trips_circuit = Keyword.fetch!(opts, :trips_circuit)
    severity = Keyword.fetch!(opts, :severity)

    quote do
      defimpl FnTypes.Protocols.Recoverable, for: unquote(module) do
        alias FnTypes.Protocols.Recoverable.Backoff

        @impl true
        def recoverable?(_), do: unquote(recoverable)

        @impl true
        def strategy(_), do: unquote(strategy)

        @impl true
        def retry_delay(_, attempt) do
          case unquote(strategy) do
            :retry ->
              Backoff.fixed(attempt, delay: unquote(base_delay))

            :retry_with_backoff ->
              Backoff.exponential(attempt, base: unquote(base_delay), max: unquote(max_delay))

            _ ->
              0
          end
        end

        @impl true
        def max_attempts(_), do: unquote(max_attempts)

        @impl true
        def trips_circuit?(_), do: unquote(trips_circuit)

        @impl true
        def severity(_), do: unquote(severity)

        @impl true
        def fallback(_), do: nil
      end
    end
  end

  @doc """
  By default, unknown errors are not recoverable.

  This is the safe default - we don't know what this error represents,
  so we shouldn't assume it's safe to retry.
  """
  @impl true
  def recoverable?(_), do: false

  @doc """
  Unknown errors use fail_fast strategy.
  """
  @impl true
  def strategy(_), do: :fail_fast

  @doc """
  No delay for unknown errors (they won't be retried).
  """
  @impl true
  def retry_delay(_, _), do: 0

  @doc """
  Single attempt for unknown errors.
  """
  @impl true
  def max_attempts(_), do: 1

  @doc """
  Unknown errors don't trip the circuit breaker.

  We don't know if this error indicates a systemic issue,
  so we err on the side of not affecting the circuit.
  """
  @impl true
  def trips_circuit?(_), do: false

  @doc """
  Unknown errors are treated as permanent.
  """
  @impl true
  def severity(_), do: :permanent

  @doc """
  No fallback for unknown errors.
  """
  @impl true
  def fallback(_), do: nil
end
