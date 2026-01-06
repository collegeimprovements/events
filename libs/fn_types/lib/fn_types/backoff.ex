defmodule FnTypes.Backoff do
  @moduledoc """
  Configurable backoff strategies for retry logic.

  Provides a single source of truth for backoff calculations across all libraries,
  eliminating duplication and ensuring consistent behavior.

  ## Design Principles

  - **Strategy-based**: Multiple backoff algorithms (exponential, linear, constant, etc.)
  - **Composable**: Struct-based configuration with sensible defaults
  - **Observable**: Returns explicit delay values for logging/telemetry
  - **Testable**: Pure functions with deterministic behavior (given fixed random seed)

  ## Backoff Strategies

  | Strategy | Formula | Use Case |
  |----------|---------|----------|
  | `:exponential` | `base * 2^(attempt-1)` | Most APIs, default choice |
  | `:linear` | `base * attempt` | Gradual backoff |
  | `:constant` | `base` | Fixed intervals |
  | `:decorrelated` | AWS-style jitter | Distributed systems, thundering herd prevention |
  | `:full_jitter` | Random up to exponential | Maximum jitter, collision avoidance |
  | `:equal_jitter` | Half exponential + half random | Balance between predictability and jitter |

  ## Quick Start

      alias FnTypes.Backoff

      # Create a backoff strategy
      backoff = Backoff.exponential(initial: 100, max: 5_000, jitter: 0.25)

      # Calculate delay for attempt N
      {:ok, delay_ms} = Backoff.delay(backoff, attempt: 1)
      #=> {:ok, ~100}  # ~100ms with jitter

      {:ok, delay_ms} = Backoff.delay(backoff, attempt: 3)
      #=> {:ok, ~400}  # ~400ms with jitter

  ## Usage Examples

      # Exponential backoff (recommended for most cases)
      backoff = Backoff.exponential()
      {:ok, delay} = Backoff.delay(backoff, attempt: 2)

      # Linear backoff
      backoff = Backoff.linear(initial: 500, max: 10_000)
      {:ok, delay} = Backoff.delay(backoff, attempt: 3)
      #=> {:ok, 1500}  # 500 * 3

      # Constant delay
      backoff = Backoff.constant(1000)
      {:ok, delay} = Backoff.delay(backoff, attempt: 99)
      #=> {:ok, 1000}  # Always 1000ms

      # AWS-recommended decorrelated jitter
      backoff = Backoff.decorrelated(base: 100, max: 10_000)
      {:ok, delay} = Backoff.delay(backoff, attempt: 2, previous_delay: 300)
      #=> {:ok, ~450}  # Random between base and previous * 3

      # Full jitter (maximum randomization)
      backoff = Backoff.full_jitter(base: 1000)
      {:ok, delay} = Backoff.delay(backoff, attempt: 3)
      #=> {:ok, ~random}  # 0 to (1000 * 2^3) = 0-8000ms

  ## Integration Examples

  ### With FnTypes.Retry

      alias FnTypes.{Retry, Backoff}

      backoff = Backoff.exponential(initial: 200, max: 10_000)

      Retry.execute(fn -> api_call() end,
        backoff: backoff,
        max_attempts: 5
      )

  ### With Effect.Retry

      backoff = Backoff.decorrelated(base: 100)

      Effect.Retry.execute(fn -> step() end,
        backoff: backoff,
        max: 3
      )

  ### With OmApiClient

      backoff = Backoff.exponential(initial: 1000, jitter: 0.25)

      OmApiClient.request(:get, "/api/resource",
        retry: [backoff: backoff, max_attempts: 3]
      )

  ## Jitter Explained

  Jitter adds randomness to backoff delays to prevent synchronized retry attempts
  (thundering herd problem). The jitter factor determines how much randomness:

  - `0.0` - No jitter (deterministic delays)
  - `0.25` - ±25% jitter (recommended default)
  - `0.5` - ±50% jitter (higher variance)
  - `1.0` - ±100% jitter (maximum randomization)

  Example with jitter=0.25 and base=1000:
  - Base delay: 1000ms
  - Jitter range: ±250ms (1000 * 0.25)
  - Actual delay: 750-1250ms

  ## Custom Backoff Functions

  You can provide a custom function for advanced backoff logic:

      custom_backoff = %Backoff{
        strategy: fn attempt, opts ->
          base = Keyword.get(opts, :base, 100)
          # Your custom formula here
          base * :math.log(attempt + 1)
        end,
        initial_delay: 100,
        max_delay: 30_000
      }

      {:ok, delay} = Backoff.delay(custom_backoff, attempt: 5)
  """

  defstruct strategy: :exponential,
            initial_delay: 100,
            max_delay: 30_000,
            jitter_factor: 0.25,
            multiplier: 2

  @type strategy ::
          :exponential
          | :linear
          | :constant
          | :decorrelated
          | :full_jitter
          | :equal_jitter
          | (attempt :: pos_integer(), opts :: keyword() -> non_neg_integer())

  @type t :: %__MODULE__{
          strategy: strategy(),
          initial_delay: pos_integer(),
          max_delay: pos_integer(),
          jitter_factor: float(),
          multiplier: number()
        }

  @type delay_opts :: [
          attempt: pos_integer(),
          previous_delay: pos_integer() | nil
        ]

  # ============================================
  # Constructor Functions
  # ============================================

  @doc """
  Creates an exponential backoff strategy.

  Doubles the delay with each attempt: `base * 2^(attempt-1)`

  ## Options

  - `:initial` - Initial delay in milliseconds (default: 100)
  - `:max` - Maximum delay cap (default: 30_000)
  - `:jitter` - Jitter factor 0.0-1.0 (default: 0.25)
  - `:multiplier` - Base multiplier (default: 2, try 1.5 for gentler growth)

  ## Examples

      # Default exponential (100ms initial, 2x growth, max 30s)
      backoff = Backoff.exponential()

      # Custom exponential
      backoff = Backoff.exponential(initial: 500, max: 60_000, jitter: 0.1)

      # Gentler growth (1.5x instead of 2x)
      backoff = Backoff.exponential(multiplier: 1.5)
  """
  @spec exponential(keyword()) :: t()
  def exponential(opts \\ []) do
    %__MODULE__{
      strategy: :exponential,
      initial_delay: Keyword.get(opts, :initial, 100),
      max_delay: Keyword.get(opts, :max, 30_000),
      jitter_factor: Keyword.get(opts, :jitter, 0.25),
      multiplier: Keyword.get(opts, :multiplier, 2)
    }
  end

  @doc """
  Creates a linear backoff strategy.

  Increases delay linearly: `base * attempt`

  ## Options

  - `:initial` - Initial delay in milliseconds (default: 100)
  - `:max` - Maximum delay cap (default: 30_000)

  ## Examples

      # Default linear (100ms, 200ms, 300ms, ...)
      backoff = Backoff.linear()

      # Custom linear (500ms, 1000ms, 1500ms, ...)
      backoff = Backoff.linear(initial: 500)
  """
  @spec linear(keyword()) :: t()
  def linear(opts \\ []) do
    %__MODULE__{
      strategy: :linear,
      initial_delay: Keyword.get(opts, :initial, 100),
      max_delay: Keyword.get(opts, :max, 30_000),
      jitter_factor: 0.0
    }
  end

  @doc """
  Creates a constant backoff strategy.

  Returns the same delay for every attempt.

  ## Examples

      # Always 2 seconds
      backoff = Backoff.constant(2000)

      # Always 500ms
      backoff = Backoff.constant(500)
  """
  @spec constant(pos_integer()) :: t()
  def constant(delay) when is_integer(delay) and delay > 0 do
    %__MODULE__{
      strategy: :constant,
      initial_delay: delay,
      max_delay: delay,
      jitter_factor: 0.0
    }
  end

  @doc """
  Creates a decorrelated jitter backoff strategy (AWS recommended).

  Uses decorrelated jitter to prevent synchronized retries in distributed systems.
  Formula: `base + random(0, min(cap, previous * 3))`

  ## Options

  - `:base` - Base delay in milliseconds (default: 100)
  - `:max` - Maximum delay cap (default: 30_000)

  ## Examples

      backoff = Backoff.decorrelated(base: 100, max: 10_000)

  ## References

  - AWS Architecture Blog: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
  """
  @spec decorrelated(keyword()) :: t()
  def decorrelated(opts \\ []) do
    %__MODULE__{
      strategy: :decorrelated,
      initial_delay: Keyword.get(opts, :base, 100),
      max_delay: Keyword.get(opts, :max, 30_000),
      jitter_factor: 1.0
    }
  end

  @doc """
  Creates a full jitter backoff strategy.

  Returns a random delay between 0 and the exponential cap: `random(0, base * 2^attempt)`

  This provides maximum jitter for collision avoidance.

  ## Options

  - `:base` - Base delay in milliseconds (default: 100)
  - `:max` - Maximum delay cap (default: 30_000)

  ## Examples

      backoff = Backoff.full_jitter(base: 1000)
  """
  @spec full_jitter(keyword()) :: t()
  def full_jitter(opts \\ []) do
    %__MODULE__{
      strategy: :full_jitter,
      initial_delay: Keyword.get(opts, :base, 100),
      max_delay: Keyword.get(opts, :max, 30_000),
      jitter_factor: 1.0
    }
  end

  @doc """
  Creates an equal jitter backoff strategy.

  Returns half exponential + half random: `exp/2 + random(0, exp/2)`

  This balances predictability with jitter.

  ## Options

  - `:base` - Base delay in milliseconds (default: 100)
  - `:max` - Maximum delay cap (default: 30_000)

  ## Examples

      backoff = Backoff.equal_jitter(base: 500)
  """
  @spec equal_jitter(keyword()) :: t()
  def equal_jitter(opts \\ []) do
    %__MODULE__{
      strategy: :equal_jitter,
      initial_delay: Keyword.get(opts, :base, 100),
      max_delay: Keyword.get(opts, :max, 30_000),
      jitter_factor: 0.5
    }
  end

  # ============================================
  # Delay Calculation
  # ============================================

  @doc """
  Calculates the backoff delay for a given attempt.

  ## Options

  - `:attempt` - Current attempt number (required, starts at 1)
  - `:previous_delay` - Previous delay value (used by decorrelated strategy)

  ## Returns

  `{:ok, delay_ms}` where delay_ms is the calculated delay in milliseconds.

  ## Examples

      backoff = Backoff.exponential()

      {:ok, delay} = Backoff.delay(backoff, attempt: 1)
      #=> {:ok, ~100}

      {:ok, delay} = Backoff.delay(backoff, attempt: 3)
      #=> {:ok, ~400}

      # Decorrelated requires previous_delay
      backoff = Backoff.decorrelated()
      {:ok, delay} = Backoff.delay(backoff, attempt: 2, previous_delay: 200)
      #=> {:ok, ~450}
  """
  @spec delay(t(), delay_opts()) :: {:ok, non_neg_integer()}
  def delay(%__MODULE__{strategy: :exponential} = config, opts) do
    attempt = Keyword.fetch!(opts, :attempt)

    base_delay = config.initial_delay * :math.pow(config.multiplier, attempt - 1)
    delay_with_jitter = apply_jitter(base_delay, config.jitter_factor)
    final_delay = min(round(delay_with_jitter), config.max_delay)

    {:ok, final_delay}
  end

  def delay(%__MODULE__{strategy: :linear} = config, opts) do
    attempt = Keyword.fetch!(opts, :attempt)

    base_delay = config.initial_delay * attempt
    final_delay = min(base_delay, config.max_delay)

    {:ok, final_delay}
  end

  def delay(%__MODULE__{strategy: :constant} = config, _opts) do
    {:ok, config.initial_delay}
  end

  def delay(%__MODULE__{strategy: :decorrelated} = config, opts) do
    _attempt = Keyword.fetch!(opts, :attempt)
    previous = Keyword.get(opts, :previous_delay, config.initial_delay)

    # AWS decorrelated jitter: random between base and min(previous * 3, cap)
    min_delay = config.initial_delay
    max_delay = min(previous * 3, config.max_delay)

    calculated =
      if max_delay > min_delay do
        min_delay + :rand.uniform() * (max_delay - min_delay)
      else
        min_delay
      end

    {:ok, round(calculated)}
  end

  def delay(%__MODULE__{strategy: :full_jitter} = config, opts) do
    attempt = Keyword.fetch!(opts, :attempt)

    # Random between 0 and exponential cap
    upper = config.initial_delay * :math.pow(2, attempt)
    calculated = :rand.uniform() * upper
    final_delay = min(round(calculated), config.max_delay)

    {:ok, final_delay}
  end

  def delay(%__MODULE__{strategy: :equal_jitter} = config, opts) do
    attempt = Keyword.fetch!(opts, :attempt)

    # Half exponential + half random
    exp_delay = config.initial_delay * :math.pow(2, attempt - 1)
    half = exp_delay / 2
    calculated = half + :rand.uniform() * half
    final_delay = min(round(calculated), config.max_delay)

    {:ok, final_delay}
  end

  def delay(%__MODULE__{strategy: custom_fn} = config, opts) when is_function(custom_fn, 2) do
    attempt = Keyword.fetch!(opts, :attempt)
    calculated = custom_fn.(attempt, config: config, opts: opts)
    final_delay = min(calculated, config.max_delay)

    {:ok, final_delay}
  end

  @doc """
  Applies jitter to a delay value.

  Adds random variance to prevent synchronized retry attempts (thundering herd).

  ## Algorithm

  For jitter factor `j`:
  - Creates a jitter range of `delay * j`
  - Adds a random offset in the range `[-jitter_range, +jitter_range]`
  - Ensures result is never negative

  ## Examples

      # No jitter
      iex> FnTypes.Backoff.apply_jitter(1000, +0.0)
      1000.0

      # 25% jitter (±250ms for 1000ms delay)
      iex> delay = FnTypes.Backoff.apply_jitter(1000, 0.25)
      iex> delay >= 750 and delay <= 1250
      true

      # 50% jitter
      iex> delay = FnTypes.Backoff.apply_jitter(1000, 0.5)
      iex> delay >= 500 and delay <= 1500
      true
  """
  @spec apply_jitter(number(), float()) :: float()
  def apply_jitter(delay, +0.0), do: delay * 1.0

  def apply_jitter(delay, jitter) when jitter > 0 and jitter <= 1 do
    jitter_range = delay * jitter
    # Random offset between -jitter_range and +jitter_range
    offset = :rand.uniform() * 2 * jitter_range - jitter_range
    max(0, delay + offset)
  end

  @doc """
  Converts various delay formats to milliseconds.

  Useful for parsing user input or configuration values.

  ## Supported Formats

  - Integer (seconds) - `5` → 5000ms
  - String (seconds) - `"5"` → 5000ms
  - Tuple (value, unit) - `{500, :milliseconds}` → 500ms

  ## Examples

      iex> FnTypes.Backoff.parse_delay(5)
      5000

      iex> FnTypes.Backoff.parse_delay("5")
      5000

      iex> FnTypes.Backoff.parse_delay({500, :milliseconds})
      500

      iex> FnTypes.Backoff.parse_delay({5, :seconds})
      5000

      iex> FnTypes.Backoff.parse_delay({1, :minutes})
      60000

      iex> FnTypes.Backoff.parse_delay("invalid")
      nil
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
end
