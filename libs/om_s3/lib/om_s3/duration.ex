defmodule OmS3.Duration do
  @moduledoc """
  Shared duration normalization utilities for S3 operations.

  Converts human-readable duration tuples to seconds or milliseconds.

  ## Examples

      Duration.to_seconds({5, :minutes})
      #=> 300

      Duration.to_ms({2, :minutes})
      #=> 120_000
  """

  @type duration :: pos_integer() | {pos_integer(), unit()}
  @type unit ::
          :second
          | :seconds
          | :minute
          | :minutes
          | :hour
          | :hours
          | :day
          | :days
          | :week
          | :weeks
          | :month
          | :months
          | :year
          | :years

  @doc """
  Converts a duration to seconds.

  ## Examples

      iex> OmS3.Duration.to_seconds(60)
      60

      iex> OmS3.Duration.to_seconds({5, :minutes})
      300

      iex> OmS3.Duration.to_seconds({1, :hour})
      3600
  """
  @spec to_seconds(duration()) :: pos_integer()
  def to_seconds({n, :second}), do: n
  def to_seconds({n, :seconds}), do: n
  def to_seconds({n, :minute}), do: n * 60
  def to_seconds({n, :minutes}), do: n * 60
  def to_seconds({n, :hour}), do: n * 3600
  def to_seconds({n, :hours}), do: n * 3600
  def to_seconds({n, :day}), do: n * 86_400
  def to_seconds({n, :days}), do: n * 86_400
  def to_seconds({n, :week}), do: n * 604_800
  def to_seconds({n, :weeks}), do: n * 604_800
  def to_seconds({n, :month}), do: n * 2_592_000
  def to_seconds({n, :months}), do: n * 2_592_000
  def to_seconds({n, :year}), do: n * 31_536_000
  def to_seconds({n, :years}), do: n * 31_536_000
  def to_seconds(seconds) when is_integer(seconds), do: seconds

  @doc """
  Converts a duration to milliseconds.

  ## Examples

      iex> OmS3.Duration.to_ms(60)
      60

      iex> OmS3.Duration.to_ms({5, :minutes})
      300_000

      iex> OmS3.Duration.to_ms({1, :hour})
      3_600_000
  """
  @spec to_ms(duration()) :: pos_integer()
  def to_ms({_n, _unit} = duration), do: to_seconds(duration) * 1000
  def to_ms(ms) when is_integer(ms), do: ms

  @doc """
  Formats seconds as a human-readable string.

  ## Examples

      iex> OmS3.Duration.format(300)
      "5 minutes"

      iex> OmS3.Duration.format(3661)
      "1 hour, 1 minute, 1 second"
  """
  @spec format(pos_integer()) :: String.t()
  def format(seconds) when is_integer(seconds) and seconds >= 0 do
    {hours, rem} = {div(seconds, 3600), rem(seconds, 3600)}
    {minutes, secs} = {div(rem, 60), rem(rem, 60)}

    parts =
      []
      |> maybe_add_unit(hours, "hour")
      |> maybe_add_unit(minutes, "minute")
      |> maybe_add_unit(secs, "second")

    case parts do
      [] -> "0 seconds"
      _ -> Enum.join(parts, ", ")
    end
  end

  defp maybe_add_unit(parts, 0, _unit), do: parts
  defp maybe_add_unit(parts, 1, unit), do: parts ++ ["1 #{unit}"]
  defp maybe_add_unit(parts, n, unit), do: parts ++ ["#{n} #{unit}s"]
end
