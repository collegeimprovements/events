defmodule Events.Recoverable.Backoff do
  @moduledoc """
  Backoff calculation utilities for the Recoverable protocol.

  Provides various backoff strategies that implementations can use:
  - Exponential backoff with jitter
  - Linear backoff
  - Fixed delay
  - Decorrelated jitter (AWS-style)

  ## Usage

      defimpl Events.Recoverable, for: MyError do
        import Events.Recoverable.Backoff

        def retry_delay(error, attempt) do
          exponential(attempt, base: 1000, max: 30_000)
        end
      end
  """

  @default_base 1_000
  @default_max 30_000
  @default_jitter 0.25

  @doc """
  Calculates exponential backoff with jitter.

  Formula: `base * 2^(attempt-1) * (1 ± jitter)`

  ## Options

  - `:base` - Base delay in milliseconds (default: 1000)
  - `:max` - Maximum delay cap in milliseconds (default: 30000)
  - `:jitter` - Jitter factor 0.0-1.0 (default: 0.25)

  ## Examples

      exponential(1)                    #=> ~1000
      exponential(2)                    #=> ~2000
      exponential(3)                    #=> ~4000
      exponential(10)                   #=> ~30000 (capped)
      exponential(1, base: 500)         #=> ~500
      exponential(2, max: 5000)         #=> ~2000
  """
  @spec exponential(pos_integer(), keyword()) :: non_neg_integer()
  def exponential(attempt, opts \\ []) do
    base = Keyword.get(opts, :base, @default_base)
    max = Keyword.get(opts, :max, @default_max)
    jitter = Keyword.get(opts, :jitter, @default_jitter)

    delay = base * :math.pow(2, attempt - 1)
    delay_with_jitter = apply_jitter(delay, jitter)

    min(round(delay_with_jitter), max)
  end

  @doc """
  Calculates linear backoff.

  Formula: `base * attempt`

  ## Options

  - `:base` - Base delay in milliseconds (default: 1000)
  - `:max` - Maximum delay cap in milliseconds (default: 30000)

  ## Examples

      linear(1)             #=> 1000
      linear(2)             #=> 2000
      linear(3)             #=> 3000
      linear(1, base: 500)  #=> 500
  """
  @spec linear(pos_integer(), keyword()) :: non_neg_integer()
  def linear(attempt, opts \\ []) do
    base = Keyword.get(opts, :base, @default_base)
    max = Keyword.get(opts, :max, @default_max)

    min(base * attempt, max)
  end

  @doc """
  Returns a fixed delay regardless of attempt number.

  ## Options

  - `:delay` - Fixed delay in milliseconds (default: 1000)

  ## Examples

      fixed(1)                  #=> 1000
      fixed(5)                  #=> 1000
      fixed(1, delay: 5000)     #=> 5000
  """
  @spec fixed(pos_integer(), keyword()) :: non_neg_integer()
  def fixed(_attempt, opts \\ []) do
    Keyword.get(opts, :delay, @default_base)
  end

  @doc """
  Calculates decorrelated jitter backoff (AWS recommended).

  This strategy provides better distribution than simple exponential
  backoff, reducing thundering herd effects.

  Formula: `min(max, random(base, previous_delay * 3))`

  ## Options

  - `:base` - Base delay in milliseconds (default: 1000)
  - `:max` - Maximum delay cap in milliseconds (default: 30000)

  ## Examples

      decorrelated(1)  #=> ~1000-3000
      decorrelated(2)  #=> varies based on randomization
  """
  @spec decorrelated(pos_integer(), keyword()) :: non_neg_integer()
  def decorrelated(attempt, opts \\ []) do
    base = Keyword.get(opts, :base, @default_base)
    max = Keyword.get(opts, :max, @default_max)

    # Calculate the range for this attempt
    upper = base * :math.pow(3, attempt - 1)
    delay = base + :rand.uniform() * (upper - base)

    min(round(delay), max)
  end

  @doc """
  Applies jitter to a delay value.

  ## Examples

      apply_jitter(1000, 0.25)  #=> 750-1250
      apply_jitter(1000, 0.0)   #=> 1000
      apply_jitter(1000, 0.5)   #=> 500-1500
  """
  @spec apply_jitter(number(), float()) :: float()
  def apply_jitter(delay, jitter) when jitter == 0.0, do: delay

  def apply_jitter(delay, jitter) when jitter > 0 and jitter <= 1 do
    jitter_range = delay * jitter
    offset = :rand.uniform() * 2 * jitter_range - jitter_range
    max(0, delay + offset)
  end

  @doc """
  Calculates full jitter backoff (no correlation between attempts).

  Formula: `random(0, base * 2^attempt)`

  Good for high-contention scenarios.

  ## Examples

      full_jitter(1)  #=> 0-2000
      full_jitter(2)  #=> 0-4000
  """
  @spec full_jitter(pos_integer(), keyword()) :: non_neg_integer()
  def full_jitter(attempt, opts \\ []) do
    base = Keyword.get(opts, :base, @default_base)
    max = Keyword.get(opts, :max, @default_max)

    upper = base * :math.pow(2, attempt)
    delay = :rand.uniform() * upper

    min(round(delay), max)
  end

  @doc """
  Calculates equal jitter backoff.

  Formula: `(base * 2^attempt) / 2 + random(0, (base * 2^attempt) / 2)`

  Provides a balance between predictability and jitter.

  ## Examples

      equal_jitter(1)  #=> 1000-2000
      equal_jitter(2)  #=> 2000-4000
  """
  @spec equal_jitter(pos_integer(), keyword()) :: non_neg_integer()
  def equal_jitter(attempt, opts \\ []) do
    base = Keyword.get(opts, :base, @default_base)
    max = Keyword.get(opts, :max, @default_max)

    exp_delay = base * :math.pow(2, attempt - 1)
    half = exp_delay / 2
    delay = half + :rand.uniform() * half

    min(round(delay), max)
  end

  @doc """
  Parses a delay from various input formats.

  Useful for handling Retry-After headers and configuration.

  ## Examples

      parse_delay(5)                    #=> 5000 (seconds to ms)
      parse_delay("5")                  #=> 5000
      parse_delay({5, :seconds})        #=> 5000
      parse_delay({500, :milliseconds}) #=> 500
      parse_delay({1, :minutes})        #=> 60000
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

  def parse_delay({value, :milliseconds}) when is_integer(value), do: value
  def parse_delay({value, :seconds}) when is_integer(value), do: value * 1000
  def parse_delay({value, :minutes}) when is_integer(value), do: value * 60 * 1000

  def parse_delay(_), do: nil
end
