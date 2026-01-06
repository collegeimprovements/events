defmodule Effect.Retry do
  @moduledoc """
  Retry logic for Effect steps with configurable backoff strategies.

  Delegates backoff calculations to `FnTypes.Backoff` for consistency across the codebase.

  ## Backoff Strategies

  - `:fixed` - Constant delay between attempts
  - `:linear` - `delay * attempt`
  - `:exponential` - `delay * 2^(attempt-1)` (default)
  - `:decorrelated_jitter` - AWS-style decorrelated jitter

  ## Configuration

  Retry is configured per-step via the `:retry` option:

      Effect.step(effect, :api_call, &call_api/1,
        retry: [
          max: 3,              # Maximum attempts (required)
          delay: 100,          # Base delay in ms (default: 100)
          backoff: :exponential, # Strategy (default: :exponential)
          max_delay: 30_000,   # Delay cap (default: 30_000)
          jitter: 0.25,        # Jitter factor 0.0-1.0 (default: 0.25)
          when: &retryable?/1  # Predicate for retryable errors
        ]
      )

  ## Examples

      # Simple retry with defaults
      retry: [max: 3]

      # Exponential backoff with custom settings
      retry: [max: 5, delay: 200, backoff: :exponential, max_delay: 10_000]

      # Only retry specific errors
      retry: [max: 3, when: fn
        {:error, :timeout} -> true
        {:error, :connection_refused} -> true
        _ -> false
      end]
  """

  alias FnTypes.Backoff

  @type backoff_strategy :: :fixed | :linear | :exponential | :decorrelated_jitter

  @type retry_opts :: [
          max: pos_integer(),
          delay: pos_integer(),
          backoff: backoff_strategy(),
          max_delay: pos_integer(),
          jitter: float(),
          when: (term() -> boolean())
        ]

  @default_delay 100
  @default_max_delay 30_000
  @default_backoff :exponential
  @default_jitter 0.25

  @doc """
  Executes a function with retry logic based on the given options.

  Returns `{:ok, result}` on success or `{:error, reason}` after all
  attempts are exhausted. Also returns the attempt count.

  ## Returns

  - `{:ok, result, attempts}` - Succeeded after `attempts` tries
  - `{:error, reason, attempts}` - Failed after `attempts` tries
  """
  @spec execute((-> term()), retry_opts()) ::
          {:ok, term(), pos_integer()} | {:error, term(), pos_integer()}
  def execute(fun, opts) when is_function(fun, 0) and is_list(opts) do
    max_attempts = Keyword.fetch!(opts, :max)
    do_execute(fun, opts, 1, max_attempts)
  end

  @doc """
  Calculates the delay for a given attempt using the specified strategy.

  Delegates to `FnTypes.Backoff` for consistency across the codebase.

  ## Examples

      iex> Effect.Retry.calculate_delay(1, :fixed, delay: 100)
      100

      iex> Effect.Retry.calculate_delay(3, :linear, delay: 100)
      300

      # Exponential: ~400ms (with jitter)
      iex> delay = Effect.Retry.calculate_delay(3, :exponential, delay: 100)
      iex> delay >= 300 and delay <= 500
      true
  """
  @spec calculate_delay(pos_integer(), backoff_strategy(), keyword()) :: non_neg_integer()
  def calculate_delay(attempt, strategy, opts \\ []) do
    backoff = build_backoff_config(strategy, opts)

    # Only pass previous_delay if provided (don't pass nil)
    backoff_opts =
      case Keyword.get(opts, :previous_delay) do
        nil -> [attempt: attempt]
        previous -> [attempt: attempt, previous_delay: previous]
      end

    {:ok, delay} = Backoff.delay(backoff, backoff_opts)
    delay
  end

  @doc """
  Checks if an error is retryable based on the retry options.

  Uses the `:when` predicate if provided, otherwise defaults to true
  (all errors are retryable).
  """
  @spec retryable?(term(), retry_opts()) :: boolean()
  def retryable?(error, opts) do
    case Keyword.get(opts, :when) do
      nil -> true
      predicate when is_function(predicate, 1) -> predicate.(error)
    end
  end

  @doc """
  Applies jitter to a delay value.

  Delegates to `FnTypes.Backoff.apply_jitter/2`.

  ## Examples

      iex> delay = Effect.Retry.apply_jitter(1000, +0.0)
      iex> delay == 1000.0
      true

      iex> delay = Effect.Retry.apply_jitter(1000, 0.25)
      iex> delay >= 750 and delay <= 1250
      true
  """
  @spec apply_jitter(number(), float()) :: float()
  def apply_jitter(delay, jitter) do
    Backoff.apply_jitter(delay, jitter)
  end

  # Private implementation

  defp build_backoff_config(strategy, opts) do
    delay = Keyword.get(opts, :delay, @default_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    jitter = Keyword.get(opts, :jitter, @default_jitter)

    case strategy do
      :fixed -> Backoff.constant(delay)
      :linear -> Backoff.linear(initial: delay, max: max_delay)
      :exponential -> Backoff.exponential(initial: delay, max: max_delay, jitter: jitter)
      :decorrelated_jitter -> Backoff.decorrelated(base: delay, max: max_delay)
    end
  end

  defp do_execute(_fun, _opts, attempt, max_attempts) when attempt > max_attempts do
    # This shouldn't happen, but handle it gracefully
    {:error, :max_attempts_exceeded, max_attempts}
  end

  defp do_execute(fun, opts, attempt, max_attempts) do
    result = safe_execute(fun)

    case result do
      {:ok, _} ->
        # Return the full step result (e.g., {:ok, %{map}}) as-is
        {:ok, result, attempt}

      {:error, reason} ->
        if attempt < max_attempts and retryable?(reason, opts) do
          strategy = get_backoff(opts)
          delay = calculate_delay(attempt, strategy, opts)
          Process.sleep(delay)
          do_execute(fun, opts, attempt + 1, max_attempts)
        else
          {:error, reason, attempt}
        end
    end
  end

  defp safe_execute(fun) do
    case fun.() do
      {:ok, _} = success -> success
      {:error, _} = error -> error
      :ok -> {:ok, :ok}
      nil -> {:ok, nil}
      other -> {:ok, other}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp get_backoff(opts) do
    Keyword.get(opts, :backoff, @default_backoff)
  end
end
