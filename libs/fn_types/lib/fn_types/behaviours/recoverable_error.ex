defmodule FnTypes.Behaviours.RecoverableError do
  @moduledoc """
  Behaviour for error types that can determine their own recovery strategy.

  This behaviour provides a contract for error types to indicate whether
  they are recoverable and what strategy should be used to handle them.

  ## Recovery Strategies

  - `:retry` - Retry immediately
  - `:retry_with_backoff` - Retry with exponential backoff
  - `:wait_until` - Wait for a specific time before retrying
  - `:circuit_break` - Trip the circuit breaker
  - `:fail_fast` - Do not retry, fail immediately

  ## Severity Levels

  - `:transient` - Brief, self-resolving (e.g., network hiccup)
  - `:degraded` - Service partially available
  - `:critical` - Serious error requiring attention
  - `:permanent` - Will not resolve without intervention

  ## Example Implementation

      defmodule MyApp.ApiError do
        @behaviour FnTypes.Behaviours.RecoverableError

        defstruct [:code, :message, :retryable]

        @impl true
        def recoverable?(%{retryable: true}), do: true
        def recoverable?(_), do: false

        @impl true
        def strategy(%{code: 429}), do: :wait_until
        def strategy(%{code: code}) when code in 500..599, do: :retry_with_backoff
        def strategy(_), do: :fail_fast

        @impl true
        def retry_delay(%{headers: %{"retry-after" => delay}}, _attempt), do: delay * 1000
        def retry_delay(_, attempt), do: min(1000 * :math.pow(2, attempt), 30_000) |> round()

        @impl true
        def max_attempts(%{code: 429}), do: 5
        def max_attempts(_), do: 3

        @impl true
        def severity(%{code: code}) when code in 500..599, do: :critical
        def severity(%{code: 429}), do: :degraded
        def severity(_), do: :permanent
      end

  ## Relationship to FnTypes.Protocols.Recoverable

  This behaviour defines the contract that struct modules should implement.
  The `FnTypes.Protocols.Recoverable` protocol then dispatches to these
  implementations, allowing for polymorphic error handling.
  """

  @type strategy ::
          :retry
          | :retry_with_backoff
          | :wait_until
          | :circuit_break
          | :fail_fast

  @type severity ::
          :transient
          | :degraded
          | :critical
          | :permanent

  @doc """
  Returns whether this error is potentially recoverable.

  Recoverable errors can be retried; non-recoverable errors should
  fail immediately.
  """
  @callback recoverable?(error :: term()) :: boolean()

  @doc """
  Returns the recommended recovery strategy for this error.

  See module documentation for available strategies.
  """
  @callback strategy(error :: term()) :: strategy()

  @doc """
  Calculates the delay before the next retry attempt.

  Returns delay in milliseconds. The `attempt` parameter indicates
  which retry attempt this would be (1-indexed).
  """
  @callback retry_delay(error :: term(), attempt :: pos_integer()) :: non_neg_integer()

  @doc """
  Returns the maximum number of retry attempts for this error.

  Returns 1 for non-retryable errors.
  """
  @callback max_attempts(error :: term()) :: pos_integer()

  @doc """
  Returns the severity level of this error.

  Used for logging, alerting, and circuit breaker decisions.
  """
  @callback severity(error :: term()) :: severity()

  @doc """
  Optional: Returns whether this error should trip the circuit breaker.

  Defaults to checking if severity is `:critical`.
  """
  @callback trips_circuit?(error :: term()) :: boolean()

  @doc """
  Optional: Returns a fallback value to use instead of retrying.

  Returns `nil` if no fallback is available.
  """
  @callback fallback(error :: term()) :: term() | nil

  @optional_callbacks [trips_circuit?: 1, fallback: 1]
end
