defmodule Events.Infra.Scheduler.Cron.Expression do
  @moduledoc """
  5-field cron expression parser.

  Format: `minute hour day-of-month month day-of-week`

  ## Examples

      iex> Expression.parse("0 * * * *")
      {:ok, %Expression{minute: [0], hour: :all, ...}}

      iex> Expression.parse("*/15 9-17 * * MON-FRI")
      {:ok, %Expression{minute: [0,15,30,45], hour: [9..17], ...}}

      iex> Expression.parse("invalid")
      {:error, :invalid_expression}

  ## Field Ranges

  - minute: 0-59
  - hour: 0-23
  - day_of_month: 1-31
  - month: 1-12 (or JAN-DEC)
  - day_of_week: 0-6 (or SUN-SAT, where 0=Sunday)

  ## Special Characters

  - `*` - Any value
  - `,` - List separator (e.g., `1,15,30`)
  - `-` - Range (e.g., `9-17`)
  - `/` - Step (e.g., `*/15` or `0-30/5`)
  """

  @type field :: :all | [non_neg_integer()] | [Range.t()]

  @type t :: %__MODULE__{
          minute: field(),
          hour: field(),
          day_of_month: field(),
          month: field(),
          day_of_week: field(),
          raw: String.t()
        }

  defstruct [:minute, :hour, :day_of_month, :month, :day_of_week, :raw]

  @minute_range 0..59
  @hour_range 0..23
  @day_of_month_range 1..31
  @month_range 1..12
  @day_of_week_range 0..6

  @month_names %{
    "JAN" => 1,
    "FEB" => 2,
    "MAR" => 3,
    "APR" => 4,
    "MAY" => 5,
    "JUN" => 6,
    "JUL" => 7,
    "AUG" => 8,
    "SEP" => 9,
    "OCT" => 10,
    "NOV" => 11,
    "DEC" => 12
  }

  @day_names %{
    "SUN" => 0,
    "MON" => 1,
    "TUE" => 2,
    "WED" => 3,
    "THU" => 4,
    "FRI" => 5,
    "SAT" => 6
  }

  # ============================================
  # Public API
  # ============================================

  @doc """
  Parses a cron expression string into a structured format.

  ## Examples

      iex> Expression.parse("0 6 * * *")
      {:ok, %Expression{minute: [0], hour: [6], day_of_month: :all, month: :all, day_of_week: :all}}

      iex> Expression.parse("*/15 * * * *")
      {:ok, %Expression{minute: [0, 15, 30, 45], ...}}

      iex> Expression.parse("bad")
      {:error, :invalid_expression}
  """
  @spec parse(String.t()) ::
          {:ok, t()} | {:error, :invalid_expression | {:invalid_field, atom(), String.t()}}
  def parse(expression) when is_binary(expression) do
    expression = String.trim(expression)

    case String.split(expression, ~r/\s+/) do
      [minute, hour, dom, month, dow] ->
        with {:ok, minute_vals} <- parse_field(minute, :minute, @minute_range),
             {:ok, hour_vals} <- parse_field(hour, :hour, @hour_range),
             {:ok, dom_vals} <- parse_field(dom, :day_of_month, @day_of_month_range),
             {:ok, month_vals} <- parse_field(month, :month, @month_range),
             {:ok, dow_vals} <- parse_field(dow, :day_of_week, @day_of_week_range) do
          {:ok,
           %__MODULE__{
             minute: minute_vals,
             hour: hour_vals,
             day_of_month: dom_vals,
             month: month_vals,
             day_of_week: dow_vals,
             raw: expression
           }}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end

  def parse(_), do: {:error, :invalid_expression}

  @doc """
  Parses a cron expression, raising on error.

  ## Examples

      iex> Expression.parse!("0 6 * * *")
      %Expression{...}

      iex> Expression.parse!("bad")
      ** (ArgumentError) Invalid cron expression: bad
  """
  @spec parse!(String.t()) :: t()
  def parse!(expression) do
    case parse(expression) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise ArgumentError, "Invalid cron expression: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if a DateTime matches the cron expression.

  ## Examples

      iex> expr = Expression.parse!("0 6 * * *")
      iex> Expression.matches?(expr, ~U[2024-01-15 06:00:00Z])
      true

      iex> Expression.matches?(expr, ~U[2024-01-15 06:01:00Z])
      false
  """
  @spec matches?(t(), DateTime.t()) :: boolean()
  def matches?(%__MODULE__{} = expr, %DateTime{} = dt) do
    matches_field?(expr.minute, dt.minute) and
      matches_field?(expr.hour, dt.hour) and
      matches_field?(expr.day_of_month, dt.day) and
      matches_field?(expr.month, dt.month) and
      matches_day_of_week?(expr.day_of_week, dt)
  end

  @doc """
  Returns a human-readable description of the expression.

  ## Examples

      iex> Expression.describe(Expression.parse!("0 6 * * *"))
      "At 06:00"

      iex> Expression.describe(Expression.parse!("*/15 * * * *"))
      "Every 15 minutes"
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = expr) do
    cond do
      expr.minute == :all and expr.hour == :all ->
        "Every minute"

      is_step?(expr.minute) and expr.hour == :all ->
        step = detect_step(expr.minute)
        "Every #{step} minutes"

      is_list(expr.minute) and length(expr.minute) == 1 and expr.hour == :all ->
        "Every hour at minute #{hd(expr.minute)}"

      is_list(expr.minute) and length(expr.minute) == 1 and
        is_list(expr.hour) and length(expr.hour) == 1 ->
        "At #{pad(hd(expr.hour))}:#{pad(hd(expr.minute))}"

      true ->
        expr.raw
    end
  end

  @doc """
  Converts expression back to cron string format.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{raw: raw}), do: raw

  # ============================================
  # Field Parsing
  # ============================================

  defp parse_field("*", _field_name, _range), do: {:ok, :all}

  defp parse_field(value, field_name, range) do
    value = normalize_names(value, field_name)

    cond do
      String.contains?(value, ",") ->
        parse_list(value, field_name, range)

      String.contains?(value, "/") ->
        parse_step(value, field_name, range)

      String.contains?(value, "-") ->
        parse_range(value, field_name, range)

      true ->
        parse_single(value, field_name, range)
    end
  end

  defp parse_list(value, field_name, range) do
    parts = String.split(value, ",")

    results =
      Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
        case parse_field(part, field_name, range) do
          {:ok, :all} -> {:cont, {:ok, acc}}
          {:ok, vals} when is_list(vals) -> {:cont, {:ok, acc ++ vals}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case results do
      {:ok, vals} -> {:ok, Enum.sort(Enum.uniq(vals))}
      error -> error
    end
  end

  defp parse_step(value, field_name, range) do
    case String.split(value, "/") do
      [base, step_str] ->
        with {:ok, step} <- parse_integer(step_str),
             {:ok, base_vals} <- parse_step_base(base, field_name, range) do
          vals = generate_step_values(base_vals, step, range)
          {:ok, vals}
        else
          _ -> {:error, {:invalid_field, field_name, value}}
        end

      _ ->
        {:error, {:invalid_field, field_name, value}}
    end
  end

  defp parse_step_base("*", _field_name, range) do
    {:ok, range}
  end

  defp parse_step_base(base, field_name, range) do
    case parse_range(base, field_name, range) do
      {:ok, vals} -> {:ok, Range.new(Enum.min(vals), Enum.max(vals))}
      error -> error
    end
  end

  defp generate_step_values(base_range, step, _full_range) do
    base_range
    |> Enum.take_every(step)
    |> Enum.to_list()
  end

  defp parse_range(value, field_name, range) do
    case String.split(value, "-") do
      [start_str, end_str] ->
        with {:ok, start_val} <- parse_integer(start_str),
             {:ok, end_val} <- parse_integer(end_str),
             true <- start_val in range,
             true <- end_val in range,
             true <- start_val <= end_val do
          {:ok, Enum.to_list(start_val..end_val)}
        else
          _ -> {:error, {:invalid_field, field_name, value}}
        end

      _ ->
        {:error, {:invalid_field, field_name, value}}
    end
  end

  defp parse_single(value, field_name, range) do
    case parse_integer(value) do
      {:ok, int} ->
        if int in range do
          {:ok, [int]}
        else
          {:error, {:invalid_field, field_name, value}}
        end

      _ ->
        {:error, {:invalid_field, field_name, value}}
    end
  end

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  # ============================================
  # Name Normalization (JAN, MON, etc.)
  # ============================================

  defp normalize_names(value, :month) do
    String.upcase(value)
    |> replace_names(@month_names)
  end

  defp normalize_names(value, :day_of_week) do
    String.upcase(value)
    |> replace_names(@day_names)
  end

  defp normalize_names(value, _), do: value

  defp replace_names(value, name_map) do
    Enum.reduce(name_map, value, fn {name, num}, acc ->
      String.replace(acc, name, Integer.to_string(num))
    end)
  end

  # ============================================
  # Matching Helpers
  # ============================================

  defp matches_field?(:all, _value), do: true
  defp matches_field?(allowed, value) when is_list(allowed), do: value in allowed

  defp matches_day_of_week?(:all, _dt), do: true

  defp matches_day_of_week?(allowed, %DateTime{} = dt) do
    # Elixir's Date.day_of_week returns 1-7 (Mon-Sun), we need 0-6 (Sun-Sat)
    dow = Date.day_of_week(dt) |> convert_day_of_week()
    dow in allowed
  end

  # Convert from Elixir (1=Mon, 7=Sun) to cron (0=Sun, 6=Sat)
  defp convert_day_of_week(7), do: 0
  defp convert_day_of_week(n), do: n

  # ============================================
  # Description Helpers
  # ============================================

  defp is_step?(vals) when is_list(vals) and length(vals) > 1 do
    case detect_step(vals) do
      nil -> false
      _ -> true
    end
  end

  defp is_step?(_), do: false

  defp detect_step([_]), do: nil
  defp detect_step([]), do: nil

  defp detect_step(vals) when is_list(vals) do
    diffs =
      vals
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)
      |> Enum.uniq()

    case diffs do
      [step] when step > 0 -> step
      _ -> nil
    end
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: Integer.to_string(n)
end

defimpl String.Chars, for: Events.Infra.Scheduler.Cron.Expression do
  def to_string(expr), do: Events.Infra.Scheduler.Cron.Expression.to_string(expr)
end
