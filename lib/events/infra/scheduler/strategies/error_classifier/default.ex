defmodule Events.Infra.Scheduler.Strategies.ErrorClassifier.Default do
  @moduledoc """
  Default error classification strategy.

  Combines pattern matching and the `Events.Protocols.Recoverable` protocol
  to classify errors intelligently.

  ## Error Classes

  - **Retryable**: Transient errors that may succeed on retry (timeouts, rate limits)
  - **Transient**: Brief errors expected to self-resolve quickly
  - **Degraded**: Service partially available, limited retries
  - **Terminal**: Permanent errors that should not be retried (validation, auth)

  ## Configuration

      config :events, Events.Infra.Scheduler,
        error_classifier_strategy: Events.Infra.Scheduler.Strategies.ErrorClassifier.Default,
        error_classification: [
          retryable_errors: [:timeout, :connection_refused],
          terminal_errors: [:invalid_args, :not_found],
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
  """

  @behaviour Events.Infra.Scheduler.Strategies.ErrorClassifierStrategy

  alias Events.Protocols.Recoverable

  # Default error patterns for classification
  @default_retryable_patterns [
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

  @default_terminal_patterns [
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

  @default_transient_patterns [
    :busy,
    :overloaded,
    :try_again,
    :temporary_failure
  ]

  # ============================================
  # Behaviour Implementation
  # ============================================

  @impl true
  def init(opts) do
    classification_opts = Keyword.get(opts, :error_classification, [])

    state = %{
      retryable_patterns:
        Keyword.get(classification_opts, :retryable_errors, @default_retryable_patterns),
      terminal_patterns:
        Keyword.get(classification_opts, :terminal_errors, @default_terminal_patterns),
      transient_patterns:
        Keyword.get(classification_opts, :transient_errors, @default_transient_patterns),
      max_retries_by_class:
        Keyword.get(classification_opts, :max_retries_by_class, [
          retryable: 5,
          transient: 3,
          degraded: 2,
          terminal: 0,
          unknown: 3
        ]),
      backoff_by_class:
        Keyword.get(classification_opts, :backoff_by_class, [
          retryable: {:exponential, base: 1000, max: 60_000},
          transient: {:fixed, 500},
          degraded: {:exponential, base: 5000, max: 300_000}
        ])
    }

    {:ok, state}
  end

  @impl true
  def classify(error, state) do
    classification =
      case classify_via_protocol(error) do
        {:ok, classification} ->
          classification

        :error ->
          classify_by_pattern(error, state)
      end

    {classification, state}
  end

  @impl true
  def retryable?(error, state) do
    {classification, state} = classify(error, state)
    {classification.retryable, state}
  end

  @impl true
  def terminal?(error, state) do
    {classification, state} = classify(error, state)
    {classification.class == :terminal, state}
  end

  @impl true
  def retry_delay(error, attempt, state) do
    {classification, state} = classify(error, state)

    delay =
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

    {delay, state}
  end

  @impl true
  def next_action(error, attempt, state) do
    {classification, state} = classify(error, state)

    action =
      cond do
        not classification.retryable ->
          :discard

        attempt >= classification.max_retries ->
          :dead_letter

        true ->
          {delay, _} = retry_delay(error, attempt, state)
          {:retry, delay}
      end

    {action, state}
  end

  @impl true
  def trips_circuit?(error, state) do
    {classification, state} = classify(error, state)
    {classification.trips_circuit, state}
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

  defp classify_by_pattern(error, state) do
    cond do
      matches_pattern?(error, state.terminal_patterns) ->
        terminal_classification(state)

      matches_pattern?(error, state.transient_patterns) ->
        transient_classification(state)

      matches_pattern?(error, state.retryable_patterns) ->
        retryable_classification(state)

      is_exception_error?(error) ->
        retryable_classification(state)

      true ->
        unknown_classification(state)
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

  defp terminal_classification(state) do
    max_retries = get_max_retries(:terminal, state)

    %{
      class: :terminal,
      retryable: false,
      max_retries: max_retries,
      strategy: :none,
      base_delay: 0,
      max_delay: 0,
      trips_circuit: false
    }
  end

  defp transient_classification(state) do
    max_retries = get_max_retries(:transient, state)
    {base_delay, max_delay} = get_backoff(:transient, state)

    %{
      class: :transient,
      retryable: true,
      max_retries: max_retries,
      strategy: :fixed,
      base_delay: base_delay,
      max_delay: max_delay,
      trips_circuit: false
    }
  end

  defp retryable_classification(state) do
    max_retries = get_max_retries(:retryable, state)
    {base_delay, max_delay} = get_backoff(:retryable, state)

    %{
      class: :retryable,
      retryable: true,
      max_retries: max_retries,
      strategy: :exponential,
      base_delay: base_delay,
      max_delay: max_delay,
      trips_circuit: true
    }
  end

  defp unknown_classification(state) do
    max_retries = get_max_retries(:unknown, state)

    %{
      class: :unknown,
      retryable: true,
      max_retries: max_retries,
      strategy: :exponential,
      base_delay: 1_000,
      max_delay: 30_000,
      trips_circuit: false
    }
  end

  defp get_max_retries(class, state) do
    Keyword.get(state.max_retries_by_class, class, 3)
  end

  defp get_backoff(class, state) do
    case Keyword.get(state.backoff_by_class, class) do
      {:exponential, opts} ->
        {Keyword.get(opts, :base, 1000), Keyword.get(opts, :max, 60_000)}

      {:fixed, delay} ->
        {delay, delay}

      nil ->
        {1000, 60_000}
    end
  end
end
