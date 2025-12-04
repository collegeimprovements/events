defmodule Events.Infra.Scheduler.ErrorClassifier do
  @moduledoc """
  Classifies job errors to determine retry behavior.

  Error classification enables smart retry decisions:
  - **Retryable**: Transient errors that may succeed on retry (timeouts, rate limits)
  - **Terminal**: Permanent errors that should not be retried (validation, auth)
  - **Transient**: Brief errors expected to self-resolve quickly
  - **Degraded**: Service partially available, limited retries

  ## Configuration

      config :events, Events.Infra.Scheduler,
        error_classification: [
          retryable_errors: [:timeout, :connection_refused, :rate_limited],
          terminal_errors: [:invalid_args, :not_found, :unauthorized],
          max_retries_by_class: [
            retryable: 5,
            transient: 3,
            degraded: 2,
            terminal: 0
          ],
          backoff_by_class: [
            retryable: {:exponential, base: 1000, max: 60_000},
            transient: {:fixed, 500},
            degraded: {:exponential, base: 5000, max: 300_000}
          ]
        ]

  ## Usage with Jobs

      @decorate scheduled(
        cron: "0 * * * *",
        error_classification: :smart  # Enable smart classification
      )
      def sync_data do
        ExternalApi.sync()
      end

  ## Custom Error Classification

  Implement the `Events.Protocols.Recoverable` protocol for custom errors:

      defimpl Events.Protocols.Recoverable, for: MyApp.PaymentError do
        def recoverable?(%{code: :soft_decline}), do: true
        def recoverable?(_), do: false

        def strategy(%{code: :soft_decline}), do: :retry_with_backoff
        def strategy(_), do: :fail_fast

        def severity(%{code: :soft_decline}), do: :transient
        def severity(_), do: :permanent
      end
  """

  alias Events.Protocols.Recoverable

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

  # Default error patterns for classification
  @retryable_patterns [
    :timeout,
    :connection_refused,
    :connection_closed,
    :econnrefused,
    :econnreset,
    :etimedout,
    :rate_limited,
    :service_unavailable,
    :bad_gateway,
    :gateway_timeout,
    {:exit, :timeout},
    {:exit, :noproc}
  ]

  @terminal_patterns [
    :invalid_args,
    :invalid_argument,
    :not_found,
    :unauthorized,
    :forbidden,
    :bad_request,
    :validation_error,
    :schema_error,
    :undefined_function
  ]

  @transient_patterns [
    :busy,
    :overloaded,
    :try_again,
    :temporary_failure
  ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Classifies an error and returns retry behavior.

  ## Examples

      ErrorClassifier.classify(:timeout)
      #=> %{class: :retryable, retryable: true, max_retries: 5, ...}

      ErrorClassifier.classify(:not_found)
      #=> %{class: :terminal, retryable: false, max_retries: 0, ...}
  """
  @spec classify(term()) :: classification()
  def classify(error) do
    # First try the Recoverable protocol
    case classify_via_protocol(error) do
      {:ok, classification} ->
        classification

      :error ->
        # Fall back to pattern-based classification
        classify_by_pattern(error)
    end
  end

  @doc """
  Determines if an error is retryable.

  ## Examples

      ErrorClassifier.retryable?(:timeout)       #=> true
      ErrorClassifier.retryable?(:not_found)     #=> false
  """
  @spec retryable?(term()) :: boolean()
  def retryable?(error) do
    classify(error).retryable
  end

  @doc """
  Determines if an error is terminal (should not be retried).

  ## Examples

      ErrorClassifier.terminal?(:unauthorized)   #=> true
      ErrorClassifier.terminal?(:timeout)        #=> false
  """
  @spec terminal?(term()) :: boolean()
  def terminal?(error) do
    classify(error).class == :terminal
  end

  @doc """
  Gets the error class for an error.

  ## Examples

      ErrorClassifier.get_class(:timeout)        #=> :retryable
      ErrorClassifier.get_class(:not_found)      #=> :terminal
      ErrorClassifier.get_class(:busy)           #=> :transient
  """
  @spec get_class(term()) :: error_class()
  def get_class(error) do
    classify(error).class
  end

  @doc """
  Calculates retry delay based on error classification and attempt.

  ## Examples

      ErrorClassifier.retry_delay(:timeout, 1)   #=> 1000
      ErrorClassifier.retry_delay(:timeout, 3)   #=> 4000
      ErrorClassifier.retry_delay(:not_found, 1) #=> 0
  """
  @spec retry_delay(term(), pos_integer()) :: non_neg_integer()
  def retry_delay(error, attempt) do
    classification = classify(error)

    case classification.strategy do
      :none ->
        0

      :fixed ->
        classification.base_delay

      :exponential ->
        base = classification.base_delay
        max = classification.max_delay
        delay = base * :math.pow(2, attempt - 1)
        jitter = :rand.uniform() * delay * 0.1
        min(round(delay + jitter), max)
    end
  end

  @doc """
  Determines if retries are exhausted based on error class.

  ## Examples

      ErrorClassifier.exhausted?(:timeout, 5)    #=> true (max 5)
      ErrorClassifier.exhausted?(:timeout, 3)    #=> false
      ErrorClassifier.exhausted?(:not_found, 1)  #=> true (max 0)
  """
  @spec exhausted?(term(), pos_integer()) :: boolean()
  def exhausted?(error, attempt) do
    classification = classify(error)
    attempt >= classification.max_retries
  end

  @doc """
  Determines the next action based on error and attempt count.

  Returns:
  - `{:retry, delay}` - Retry after delay milliseconds
  - `:dead_letter` - Send to dead letter queue
  - `:discard` - Discard without retry

  ## Examples

      ErrorClassifier.next_action(:timeout, 1)
      #=> {:retry, 1000}

      ErrorClassifier.next_action(:timeout, 6)
      #=> :dead_letter

      ErrorClassifier.next_action(:not_found, 1)
      #=> :discard
  """
  @spec next_action(term(), pos_integer()) :: {:retry, non_neg_integer()} | :dead_letter | :discard
  def next_action(error, attempt) do
    classification = classify(error)

    cond do
      not classification.retryable ->
        :discard

      attempt >= classification.max_retries ->
        :dead_letter

      true ->
        delay = retry_delay(error, attempt)
        {:retry, delay}
    end
  end

  @doc """
  Checks if an error should trip the circuit breaker.

  ## Examples

      ErrorClassifier.trips_circuit?(:timeout)      #=> true
      ErrorClassifier.trips_circuit?(:not_found)    #=> false
  """
  @spec trips_circuit?(term()) :: boolean()
  def trips_circuit?(error) do
    classify(error).trips_circuit
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp classify_via_protocol(error) do
    try do
      recoverable = Recoverable.recoverable?(error)
      strategy = Recoverable.strategy(error)
      severity = Recoverable.severity(error)
      max_attempts = Recoverable.max_attempts(error)
      trips_circuit = Recoverable.trips_circuit?(error)

      classification = %{
        class: severity_to_class(severity),
        retryable: recoverable,
        max_retries: max_attempts,
        strategy: strategy_to_retry_strategy(strategy),
        base_delay: 1000,
        max_delay: 60_000,
        trips_circuit: trips_circuit
      }

      {:ok, classification}
    rescue
      # Protocol not implemented for this error type
      Protocol.UndefinedError -> :error
      _ -> :error
    end
  end

  defp severity_to_class(:transient), do: :transient
  defp severity_to_class(:degraded), do: :degraded
  defp severity_to_class(:critical), do: :retryable
  defp severity_to_class(:permanent), do: :terminal
  defp severity_to_class(_), do: :unknown

  defp strategy_to_retry_strategy(:retry), do: :fixed
  defp strategy_to_retry_strategy(:retry_with_backoff), do: :exponential
  defp strategy_to_retry_strategy(:wait_until), do: :fixed
  defp strategy_to_retry_strategy(:circuit_break), do: :none
  defp strategy_to_retry_strategy(:fail_fast), do: :none
  defp strategy_to_retry_strategy(:fallback), do: :none
  defp strategy_to_retry_strategy(_), do: :exponential

  defp classify_by_pattern(error) do
    cond do
      matches_pattern?(error, @terminal_patterns) ->
        terminal_classification()

      matches_pattern?(error, @transient_patterns) ->
        transient_classification()

      matches_pattern?(error, @retryable_patterns) ->
        retryable_classification()

      is_exception_error?(error) ->
        # Most exceptions are retryable (infrastructure issues)
        retryable_classification()

      true ->
        unknown_classification()
    end
  end

  defp matches_pattern?(error, patterns) do
    Enum.any?(patterns, fn pattern ->
      match_error?(error, pattern)
    end)
  end

  defp match_error?(error, pattern) when is_atom(pattern) do
    case error do
      ^pattern -> true
      {^pattern, _} -> true
      %{code: ^pattern} -> true
      %{reason: ^pattern} -> true
      %{type: ^pattern} -> true
      _ -> false
    end
  end

  defp match_error?(error, {kind, reason}) do
    case error do
      {^kind, ^reason} -> true
      {^kind, ^reason, _} -> true
      _ -> false
    end
  end

  defp match_error?(_, _), do: false

  defp is_exception_error?({:exception, _, _}), do: true
  defp is_exception_error?(%{__exception__: true}), do: true
  defp is_exception_error?(_), do: false

  defp terminal_classification do
    %{
      class: :terminal,
      retryable: false,
      max_retries: 0,
      strategy: :none,
      base_delay: 0,
      max_delay: 0,
      trips_circuit: false
    }
  end

  defp transient_classification do
    %{
      class: :transient,
      retryable: true,
      max_retries: 3,
      strategy: :fixed,
      base_delay: 500,
      max_delay: 5_000,
      trips_circuit: false
    }
  end

  defp retryable_classification do
    %{
      class: :retryable,
      retryable: true,
      max_retries: 5,
      strategy: :exponential,
      base_delay: 1_000,
      max_delay: 60_000,
      trips_circuit: true
    }
  end

  defp unknown_classification do
    %{
      class: :unknown,
      retryable: true,
      max_retries: 3,
      strategy: :exponential,
      base_delay: 1_000,
      max_delay: 30_000,
      trips_circuit: false
    }
  end
end
