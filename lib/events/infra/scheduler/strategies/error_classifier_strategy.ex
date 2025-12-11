defmodule Events.Infra.Scheduler.Strategies.ErrorClassifierStrategy do
  @moduledoc """
  Behaviour for error classification strategies.

  Enables pluggable error classification to determine retry behavior.
  Implement this behaviour to provide custom error classification logic.

  ## Built-in Implementations

  - `Events.Infra.Scheduler.Strategies.ErrorClassifier.Default` - Pattern + protocol-based
  - `Events.Infra.Scheduler.Strategies.ErrorClassifier.Simple` - Simple retryable/terminal

  ## Configuration

      config :events, Events.Infra.Scheduler,
        error_classifier_strategy: Events.Infra.Scheduler.Strategies.ErrorClassifier.Default,
        error_classification: [
          retryable_errors: [:timeout, :connection_refused],
          terminal_errors: [:not_found, :unauthorized],
          max_retries_by_class: [
            retryable: 5,
            terminal: 0
          ]
        ]

  ## Implementing a Custom Strategy

      defmodule MyApp.DomainErrorClassifier do
        @behaviour Events.Infra.Scheduler.Strategies.ErrorClassifierStrategy

        @impl true
        def classify(%MyApp.PaymentError{code: :soft_decline}) do
          %{class: :transient, retryable: true, max_retries: 3, ...}
        end

        @impl true
        def classify(_error) do
          # Default classification
        end
      end
  """

  @type error_class :: :retryable | :transient | :degraded | :terminal | :unknown
  @type retry_strategy :: :immediate | :fixed | :exponential | :none

  @type classification :: %{
          class: error_class(),
          retryable: boolean(),
          max_retries: non_neg_integer(),
          strategy: retry_strategy(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          trips_circuit: boolean()
        }

  @type state :: map()
  @type opts :: keyword()

  @doc """
  Initializes the error classifier strategy.

  Called once when the scheduler starts. Returns initial state.
  """
  @callback init(opts()) :: {:ok, state()} | {:error, term()}

  @doc """
  Classifies an error and returns retry behavior.

  Returns a classification map with:
  - `:class` - Error class (retryable, transient, terminal, etc.)
  - `:retryable` - Whether the error can be retried
  - `:max_retries` - Maximum retry attempts
  - `:strategy` - Retry strategy (exponential, fixed, none)
  - `:base_delay` - Base delay between retries
  - `:max_delay` - Maximum delay cap
  - `:trips_circuit` - Whether this error should trip circuit breakers
  """
  @callback classify(term(), state()) :: {classification(), state()}

  @doc """
  Determines if an error is retryable.
  """
  @callback retryable?(term(), state()) :: {boolean(), state()}

  @doc """
  Determines if an error is terminal (should not be retried).
  """
  @callback terminal?(term(), state()) :: {boolean(), state()}

  @doc """
  Calculates retry delay based on error and attempt count.
  """
  @callback retry_delay(term(), pos_integer(), state()) :: {non_neg_integer(), state()}

  @doc """
  Determines the next action based on error and attempt count.

  Returns:
  - `{:retry, delay}` - Retry after delay milliseconds
  - `:dead_letter` - Send to dead letter queue
  - `:discard` - Discard without retry
  """
  @callback next_action(term(), pos_integer(), state()) ::
              {{:retry, non_neg_integer()} | :dead_letter | :discard, state()}

  @doc """
  Checks if an error should trip circuit breakers.
  """
  @callback trips_circuit?(term(), state()) :: {boolean(), state()}
end
