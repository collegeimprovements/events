defmodule Events.Infra.Scheduler.Cron.NextRun do
  @moduledoc """
  Calculates the next run time for cron expressions.

  ## Usage

      iex> expr = Expression.parse!("0 6 * * *")
      iex> NextRun.next(expr, ~U[2024-01-15 05:30:00Z])
      {:ok, ~U[2024-01-15 06:00:00Z]}

      iex> NextRun.next(expr, ~U[2024-01-15 06:30:00Z])
      {:ok, ~U[2024-01-16 06:00:00Z]}

  ## Timezone Support

      iex> NextRun.next(expr, DateTime.utc_now(), "America/New_York")
      {:ok, ~U[...]}
  """

  alias Events.Infra.Scheduler.Cron.Expression

  @max_iterations 366 * 24 * 60
  @default_timezone "Etc/UTC"

  @type opts :: [
          timezone: String.t(),
          max_iterations: pos_integer()
        ]

  # ============================================
  # Public API
  # ============================================

  @doc """
  Calculates the next run time after the given datetime.

  Returns the next datetime that matches the cron expression.
  The result is always in UTC.

  ## Options

  - `:timezone` - Timezone for evaluation (default: "Etc/UTC")
  - `:max_iterations` - Max iterations before giving up (default: 525,600)

  ## Examples

      iex> expr = Expression.parse!("0 6 * * *")
      iex> NextRun.next(expr, ~U[2024-01-15 05:00:00Z])
      {:ok, ~U[2024-01-15 06:00:00Z]}

      iex> NextRun.next(expr, ~U[2024-01-15 06:30:00Z])
      {:ok, ~U[2024-01-16 06:00:00Z]}
  """
  @spec next(Expression.t(), DateTime.t(), String.t() | opts()) ::
          {:ok, DateTime.t()} | {:error, :no_next_run | :invalid_timezone}
  def next(expr, from, timezone_or_opts \\ @default_timezone)

  def next(%Expression{} = expr, %DateTime{} = from, timezone) when is_binary(timezone) do
    next(expr, from, timezone: timezone)
  end

  def next(%Expression{} = expr, %DateTime{} = from, opts) when is_list(opts) do
    timezone = Keyword.get(opts, :timezone, @default_timezone)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    case convert_to_timezone(from, timezone) do
      {:ok, local_from} ->
        # Start from the next minute
        candidate = advance_minute(local_from)
        find_next(expr, candidate, timezone, max_iter)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Same as `next/3` but raises on error.
  """
  @spec next!(Expression.t(), DateTime.t(), String.t() | opts()) :: DateTime.t()
  def next!(%Expression{} = expr, %DateTime{} = from, timezone_or_opts \\ @default_timezone) do
    case next(expr, from, timezone_or_opts) do
      {:ok, dt} -> dt
      {:error, reason} -> raise ArgumentError, "Cannot calculate next run: #{inspect(reason)}"
    end
  end

  @doc """
  Calculates multiple upcoming run times.

  ## Examples

      iex> expr = Expression.parse!("0 * * * *")
      iex> NextRun.next_n(expr, ~U[2024-01-15 05:30:00Z], 3)
      {:ok, [~U[2024-01-15 06:00:00Z], ~U[2024-01-15 07:00:00Z], ~U[2024-01-15 08:00:00Z]]}
  """
  @spec next_n(Expression.t(), DateTime.t(), pos_integer(), String.t() | opts()) ::
          {:ok, [DateTime.t()]} | {:error, term()}
  def next_n(expr, from, count, timezone_or_opts \\ @default_timezone)

  def next_n(%Expression{} = expr, %DateTime{} = from, count, timezone_or_opts)
      when is_integer(count) and count > 0 do
    collect_next_n(expr, from, count, timezone_or_opts, [])
  end

  @doc """
  Calculates the previous run time before the given datetime.

  Useful for determining if a job was missed.

  ## Examples

      iex> expr = Expression.parse!("0 6 * * *")
      iex> NextRun.previous(expr, ~U[2024-01-15 10:00:00Z])
      {:ok, ~U[2024-01-15 06:00:00Z]}
  """
  @spec previous(Expression.t(), DateTime.t(), String.t() | opts()) ::
          {:ok, DateTime.t()} | {:error, :no_previous_run | :invalid_timezone}
  def previous(%Expression{} = expr, %DateTime{} = from, timezone_or_opts \\ @default_timezone) do
    opts = normalize_opts(timezone_or_opts)
    timezone = Keyword.get(opts, :timezone, @default_timezone)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    case convert_to_timezone(from, timezone) do
      {:ok, local_from} ->
        candidate = rewind_minute(local_from)
        find_previous(expr, candidate, timezone, max_iter)

      {:error, _} = error ->
        error
    end
  end

  # ============================================
  # Core Algorithm
  # ============================================

  defp find_next(_expr, _candidate, _timezone, 0) do
    {:error, :no_next_run}
  end

  defp find_next(%Expression{} = expr, %DateTime{} = candidate, timezone, iterations_left) do
    cond do
      not month_matches?(expr, candidate) ->
        # Skip to next month
        next_candidate = advance_to_next_month(candidate)
        find_next(expr, next_candidate, timezone, iterations_left - 1)

      not day_matches?(expr, candidate) ->
        # Skip to next day
        next_candidate = advance_to_next_day(candidate)
        find_next(expr, next_candidate, timezone, iterations_left - 1)

      not hour_matches?(expr, candidate) ->
        # Skip to next hour
        next_candidate = advance_to_next_hour(candidate)
        find_next(expr, next_candidate, timezone, iterations_left - 1)

      not minute_matches?(expr, candidate) ->
        # Skip to next minute
        next_candidate = advance_minute(candidate)
        find_next(expr, next_candidate, timezone, iterations_left - 1)

      true ->
        # All fields match - convert back to UTC
        convert_to_utc(candidate, timezone)
    end
  end

  defp find_previous(_expr, _candidate, _timezone, 0) do
    {:error, :no_previous_run}
  end

  defp find_previous(%Expression{} = expr, %DateTime{} = candidate, timezone, iterations_left) do
    if Expression.matches?(expr, candidate) do
      convert_to_utc(candidate, timezone)
    else
      find_previous(expr, rewind_minute(candidate), timezone, iterations_left - 1)
    end
  end

  # ============================================
  # Field Matching
  # ============================================

  defp month_matches?(%Expression{month: :all}, _dt), do: true
  defp month_matches?(%Expression{month: months}, dt), do: dt.month in months

  defp day_matches?(%Expression{day_of_month: dom, day_of_week: dow}, dt) do
    dom_match = dom == :all or dt.day in dom
    dow_match = dow == :all or day_of_week(dt) in dow

    # If both are specified (not :all), either can match (OR logic per cron spec)
    # If only one is specified, that one must match
    cond do
      dom == :all and dow == :all -> true
      dom == :all -> dow_match
      dow == :all -> dom_match
      true -> dom_match or dow_match
    end
  end

  defp hour_matches?(%Expression{hour: :all}, _dt), do: true
  defp hour_matches?(%Expression{hour: hours}, dt), do: dt.hour in hours

  defp minute_matches?(%Expression{minute: :all}, _dt), do: true
  defp minute_matches?(%Expression{minute: minutes}, dt), do: dt.minute in minutes

  # ============================================
  # Time Advancement
  # ============================================

  defp advance_minute(dt) do
    dt
    |> Map.put(:second, 0)
    |> Map.put(:microsecond, {0, 0})
    |> DateTime.add(60, :second)
  end

  defp rewind_minute(dt) do
    dt
    |> Map.put(:second, 0)
    |> Map.put(:microsecond, {0, 0})
    |> DateTime.add(-60, :second)
  end

  defp advance_to_next_hour(dt) do
    dt
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
    |> Map.put(:microsecond, {0, 0})
    |> DateTime.add(3600, :second)
  end

  defp advance_to_next_day(dt) do
    dt
    |> Map.put(:hour, 0)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
    |> Map.put(:microsecond, {0, 0})
    |> DateTime.add(86400, :second)
  end

  defp advance_to_next_month(dt) do
    {year, month} =
      if dt.month == 12 do
        {dt.year + 1, 1}
      else
        {dt.year, dt.month + 1}
      end

    %{dt | year: year, month: month, day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
  end

  # ============================================
  # Timezone Handling
  # ============================================

  defp convert_to_timezone(dt, "Etc/UTC"), do: {:ok, dt}
  defp convert_to_timezone(dt, "UTC"), do: {:ok, dt}

  defp convert_to_timezone(dt, timezone) do
    case DateTime.shift_zone(dt, timezone) do
      {:ok, shifted} -> {:ok, shifted}
      {:error, _} -> {:error, :invalid_timezone}
    end
  end

  defp convert_to_utc(dt, "Etc/UTC"), do: {:ok, dt}
  defp convert_to_utc(dt, "UTC"), do: {:ok, dt}

  defp convert_to_utc(dt, _timezone) do
    case DateTime.shift_zone(dt, "Etc/UTC") do
      {:ok, shifted} -> {:ok, shifted}
      {:error, _} -> {:error, :invalid_timezone}
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp day_of_week(dt) do
    # Convert from Elixir (1=Mon, 7=Sun) to cron (0=Sun, 6=Sat)
    case Date.day_of_week(dt) do
      7 -> 0
      n -> n
    end
  end

  defp collect_next_n(_expr, _from, 0, _opts, acc), do: {:ok, Enum.reverse(acc)}

  defp collect_next_n(expr, from, count, opts, acc) do
    case next(expr, from, opts) do
      {:ok, next_dt} ->
        collect_next_n(expr, next_dt, count - 1, opts, [next_dt | acc])

      {:error, _} = error ->
        error
    end
  end

  defp normalize_opts(timezone) when is_binary(timezone), do: [timezone: timezone]
  defp normalize_opts(opts) when is_list(opts), do: opts
end
