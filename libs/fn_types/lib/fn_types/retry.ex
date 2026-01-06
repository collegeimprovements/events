defmodule FnTypes.Retry do
  @moduledoc """
  Unified retry engine with pluggable backoff strategies.

  Consolidates retry logic from across the codebase into a single, reusable module
  that integrates with the `Recoverable` protocol for error-aware retry decisions.

  ## Design Principles

  - **Protocol-aware**: Uses `Recoverable` protocol for smart retry decisions
  - **Composable**: Backoff strategies are functions, easily composed
  - **Observable**: Emits telemetry events for monitoring
  - **Configurable**: Sensible defaults with full customization

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `execute/2` | Retry any function with options |
  | `with_backoff/3` | Explicit backoff strategy |
  | `transaction/2` | Retry database transactions |

  ## Usage

      alias FnTypes.Retry

      # Simple retry with defaults
      Retry.execute(fn -> api_call() end)

      # Custom options
      Retry.execute(fn -> api_call() end,
        max_attempts: 5,
        initial_delay: 500,
        on_retry: fn error, attempt, delay ->
          Logger.warn("Retrying: \#{inspect(error)}")
        end
      )

      # With explicit backoff strategy
      Retry.with_backoff(fn -> api_call() end, :exponential,
        base: 1000,
        max: 30_000,
        jitter: 0.25
      )

      # Database transaction with retry
      Retry.transaction(fn ->
        user = Repo.get!(User, id)
        Repo.update(User.changeset(user, attrs))
      end)

  ## Backoff Strategies

  - `:exponential` - `base * 2^(attempt-1)` with optional jitter
  - `:linear` - `base * attempt`
  - `:fixed` - Constant delay
  - `:decorrelated` - AWS-style decorrelated jitter
  - `:full_jitter` - Random delay up to exponential cap
  - `:equal_jitter` - Half exponential + half random

  ## Telemetry Events

  - `[:events, :retry, :attempt]` - Each retry attempt
  - `[:events, :retry, :exhausted]` - All attempts exhausted
  - `[:events, :retry, :success]` - Operation succeeded
  """

  require Logger

  alias FnTypes.{Backoff, Protocols.Recoverable}

  # ============================================
  # Types
  # ============================================

  @type backoff_strategy ::
          :exponential
          | :linear
          | :fixed
          | :decorrelated
          | :full_jitter
          | :equal_jitter
          | (attempt :: pos_integer(), opts :: keyword() -> non_neg_integer())

  @type opts :: [
          max_attempts: pos_integer(),
          initial_delay: pos_integer(),
          max_delay: pos_integer(),
          jitter: float(),
          backoff: backoff_strategy(),
          when: (term() -> boolean()),
          on_retry: (term(), pos_integer(), pos_integer() -> any()),
          telemetry_prefix: [atom()]
        ]

  @type result(a) :: {:ok, a} | {:error, {:max_retries, term()}}

  # ============================================
  # Defaults
  # ============================================

  @default_max_attempts 3
  @default_initial_delay 100
  @default_max_delay 30_000
  @default_jitter 0.25
  @default_backoff :exponential

  # Configurable defaults - can be overridden via application config
  # config :events, FnTypes.Retry, telemetry_prefix: [:my_app, :retry], default_repo: MyApp.Repo
  @default_telemetry_prefix Application.compile_env(:fn_types, [__MODULE__, :telemetry_prefix], [:events, :retry])
  @default_repo Application.compile_env(:fn_types, [__MODULE__, :default_repo], nil)

  # ============================================
  # Public API
  # ============================================

  @doc """
  Executes a function with automatic retry on recoverable errors.

  Uses the `Recoverable` protocol to determine if an error should be retried
  and what delay to use. Falls back to configured backoff strategy.

  ## Options

  - `:max_attempts` - Maximum retry attempts (default: 3)
  - `:initial_delay` - Initial delay in milliseconds (default: 100)
  - `:max_delay` - Maximum delay cap (default: 30000)
  - `:jitter` - Jitter factor 0.0-1.0 (default: 0.25)
  - `:backoff` - Backoff strategy (default: :exponential)
  - `:when` - Predicate function to determine if error is retryable
  - `:on_retry` - Callback `(error, attempt, delay) -> any`
  - `:telemetry_prefix` - Custom telemetry event prefix

  Note: `:base_delay` is accepted as a deprecated alias for `:initial_delay`.

  ## Examples

      # Basic retry
      Retry.execute(fn -> external_api_call() end)

      # Custom configuration
      Retry.execute(fn -> database_query() end,
        max_attempts: 5,
        initial_delay: 50,
        backoff: :exponential
      )

      # With retry callback
      Retry.execute(fn -> http_request() end,
        on_retry: fn error, attempt, delay ->
          Logger.warning("Attempt \#{attempt} failed, retrying in \#{delay}ms")
        end
      )

      # Custom retry predicate (in addition to Recoverable protocol)
      Retry.execute(fn -> risky_operation() end,
        when: fn
          {:error, :temporary} -> true
          _ -> false
        end
      )
  """
  @spec execute((-> term()), opts()) :: result(term())
  def execute(fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)
    do_execute(fun, 1, config)
  end

  @doc """
  Executes with an explicit backoff strategy.

  ## Strategies

  - `:exponential` - Doubles delay each attempt
  - `:linear` - Increases delay linearly
  - `:fixed` - Constant delay
  - `:decorrelated` - AWS-recommended decorrelated jitter
  - `:full_jitter` - Random up to exponential cap
  - `:equal_jitter` - Half exponential + half random

  ## Examples

      Retry.with_backoff(fn -> api_call() end, :exponential, base: 1000)
      Retry.with_backoff(fn -> api_call() end, :linear, base: 500)
      Retry.with_backoff(fn -> api_call() end, :fixed, delay: 2000)
  """
  @spec with_backoff((-> term()), backoff_strategy(), keyword()) :: result(term())
  def with_backoff(fun, strategy, opts \\ []) when is_function(fun, 0) do
    execute(fun, Keyword.put(opts, :backoff, strategy))
  end

  @doc """
  Executes a database transaction with retry.

  Wraps the function in a Repo.transaction and retries on transient
  database errors (deadlocks, connection issues, etc.).

  ## Options

  All options from `execute/2` plus:
  - `:repo` - Repo module (required, or configure default via app config)
  - `:transaction_opts` - Options passed to Repo.transaction

  Configure default repo in config:

      config :events, FnTypes.Retry, default_repo: MyApp.Repo

  ## Examples

      Retry.transaction(fn ->
        user = Repo.get!(User, id)
        Repo.update(User.changeset(user, %{name: "new"}))
      end)

      Retry.transaction(fn -> ... end,
        max_attempts: 5,
        transaction_opts: [timeout: 30_000]
      )
  """
  @spec transaction((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def transaction(fun, opts \\ []) when is_function(fun, 0) do
    repo = Keyword.get_lazy(opts, :repo, fn -> @default_repo || raise "No repo configured. Pass :repo option or configure default_repo in config." end)
    transaction_opts = Keyword.get(opts, :transaction_opts, [])
    retry_opts = Keyword.drop(opts, [:repo, :transaction_opts])

    execute(
      fn -> repo.transaction(fun, transaction_opts) end,
      retry_opts
    )
  end

  @doc """
  Checks if an error is recoverable.

  Uses the `Recoverable` protocol and any custom `:when` predicate.

  ## Examples

      Retry.recoverable?(%Postgrex.Error{postgres: %{code: :deadlock_detected}})
      #=> true

      Retry.recoverable?(%Ecto.NoResultsError{})
      #=> false
  """
  @spec recoverable?(term(), keyword()) :: boolean()
  def recoverable?(error, opts \\ []) do
    custom_predicate = Keyword.get(opts, :when, fn _ -> false end)
    Recoverable.recoverable?(error) or custom_predicate.(error)
  end

  @doc """
  Calculates the delay for a given attempt using the specified strategy.

  Delegates to `FnTypes.Backoff` for backoff calculations.

  ## Examples

      Retry.calculate_delay(1, :exponential, base: 1000)
      #=> ~1000 (with jitter)

      Retry.calculate_delay(3, :linear, base: 500)
      #=> 1500

      Retry.calculate_delay(5, :fixed, delay: 2000)
      #=> 2000
  """
  @spec calculate_delay(pos_integer(), backoff_strategy(), keyword()) :: non_neg_integer()
  def calculate_delay(attempt, strategy, opts \\ []) do
    backoff = build_backoff_config(strategy, opts)

    # Only pass previous_delay if it's provided (don't pass nil)
    backoff_opts =
      case Keyword.get(opts, :previous_delay) do
        nil -> [attempt: attempt]
        previous -> [attempt: attempt, previous_delay: previous]
      end

    {:ok, delay} = Backoff.delay(backoff, backoff_opts)
    delay
  end

  @doc """
  Applies jitter to a delay value.

  Delegates to `FnTypes.Backoff.apply_jitter/2`.

  ## Examples

      Retry.apply_jitter(1000, 0.25)  #=> 750-1250
      Retry.apply_jitter(1000, +0.0)  #=> 1000.0
  """
  @spec apply_jitter(number(), float()) :: float()
  def apply_jitter(delay, jitter) do
    Backoff.apply_jitter(delay, jitter)
  end

  @doc """
  Parses a delay from various input formats.

  ## Examples

      Retry.parse_delay(5)                    #=> 5000 (seconds to ms)
      Retry.parse_delay("5")                  #=> 5000
      Retry.parse_delay({5, :seconds})        #=> 5000
      Retry.parse_delay({500, :milliseconds}) #=> 500
      Retry.parse_delay({1, :minutes})        #=> 60000
  """
  @spec parse_delay(term()) :: non_neg_integer() | nil
  def parse_delay(seconds) when is_integer(seconds) and seconds >= 0 do
    seconds * 1000
  end

  def parse_delay(seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {n, ""} when n >= 0 -> n * 1000
      _ -> nil
    end
  end

  def parse_delay({value, :milliseconds}) when is_integer(value) and value >= 0, do: value
  def parse_delay({value, :seconds}) when is_integer(value) and value >= 0, do: value * 1000
  def parse_delay({value, :minutes}) when is_integer(value) and value >= 0, do: value * 60 * 1000
  def parse_delay({value, :hours}) when is_integer(value) and value >= 0, do: value * 3600 * 1000
  def parse_delay(_), do: nil

  # ============================================
  # Private Implementation
  # ============================================

  defp build_config(opts) do
    # Support both :initial_delay and deprecated :base_delay
    initial_delay = Keyword.get(opts, :initial_delay, Keyword.get(opts, :base_delay, @default_initial_delay))
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    jitter = Keyword.get(opts, :jitter, @default_jitter)

    # Build Backoff struct or use provided one
    backoff =
      case Keyword.get(opts, :backoff, @default_backoff) do
        %Backoff{} = backoff -> backoff
        strategy -> build_backoff_config(strategy, initial: initial_delay, max: max_delay, jitter: jitter)
      end

    %{
      max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts),
      backoff: backoff,
      when: Keyword.get(opts, :when),
      on_retry: Keyword.get(opts, :on_retry),
      telemetry_prefix: Keyword.get(opts, :telemetry_prefix, @default_telemetry_prefix)
    }
  end

  defp build_backoff_config(strategy, opts) when is_atom(strategy) do
    initial = Keyword.get(opts, :initial, Keyword.get(opts, :base, @default_initial_delay))
    max = Keyword.get(opts, :max, @default_max_delay)
    jitter = Keyword.get(opts, :jitter, @default_jitter)

    case strategy do
      :exponential -> Backoff.exponential(initial: initial, max: max, jitter: jitter)
      :linear -> Backoff.linear(initial: initial, max: max)
      :fixed -> Backoff.constant(Keyword.get(opts, :delay, initial))
      :decorrelated -> Backoff.decorrelated(base: initial, max: max)
      :full_jitter -> Backoff.full_jitter(base: initial, max: max)
      :equal_jitter -> Backoff.equal_jitter(base: initial, max: max)
      _ -> Backoff.exponential(initial: initial, max: max, jitter: jitter)
    end
  end

  defp build_backoff_config(custom_fn, opts) when is_function(custom_fn, 2) do
    initial = Keyword.get(opts, :initial, Keyword.get(opts, :base, @default_initial_delay))
    max = Keyword.get(opts, :max, @default_max_delay)

    %Backoff{
      strategy: custom_fn,
      initial_delay: initial,
      max_delay: max
    }
  end

  defp do_execute(fun, attempt, config) do
    case safe_execute(fun) do
      {:ok, _} = success ->
        emit_telemetry(config.telemetry_prefix ++ [:success], %{attempt: attempt}, %{})
        success

      {:error, reason} when attempt >= config.max_attempts ->
        emit_telemetry(
          config.telemetry_prefix ++ [:exhausted],
          %{attempts: attempt},
          %{error: reason}
        )

        {:error, {:max_retries, reason}}

      {:error, reason} ->
        if should_retry?(reason, config) do
          delay = get_delay(reason, attempt, config)
          maybe_call_on_retry(config.on_retry, reason, attempt, delay)

          emit_telemetry(
            config.telemetry_prefix ++ [:attempt],
            %{attempt: attempt, delay: delay},
            %{error: reason}
          )

          Process.sleep(delay)
          do_execute(fun, attempt + 1, config)
        else
          {:error, {:max_retries, reason}}
        end
    end
  end

  defp safe_execute(fun) do
    case fun.() do
      {:ok, _} = success -> success
      {:error, _} = error -> error
      :ok -> {:ok, :ok}
      other -> {:ok, other}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp should_retry?(error, config) do
    protocol_recoverable = Recoverable.recoverable?(error)

    custom_recoverable =
      case config.when do
        nil -> false
        predicate when is_function(predicate, 1) -> predicate.(error)
      end

    protocol_recoverable or custom_recoverable
  end

  defp get_delay(error, attempt, config) do
    # Try protocol-defined delay first
    protocol_delay = Recoverable.retry_delay(error, attempt)

    if protocol_delay > 0 do
      protocol_delay
    else
      {:ok, delay} = Backoff.delay(config.backoff, attempt: attempt)
      delay
    end
  end

  defp maybe_call_on_retry(nil, _error, _attempt, _delay), do: :ok

  defp maybe_call_on_retry(callback, error, attempt, delay) when is_function(callback, 3) do
    callback.(error, attempt, delay)
  end

  defp emit_telemetry(event, measurements, metadata) do
    FnTypes.Telemetry.execute(event, measurements, metadata)
  rescue
    # Don't let telemetry errors break retry logic
    _ -> :ok
  end
end
