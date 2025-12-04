defmodule Events.Infra.Scheduler.Cron do
  @moduledoc """
  Cron expression parsing and scheduling utilities.

  This module provides a unified API for working with cron expressions,
  including parsing, validation, and next run time calculation.

  ## Quick Start

      alias Events.Infra.Scheduler.Cron

      # Parse and validate
      {:ok, expr} = Cron.parse("0 6 * * *")

      # Get next run time
      {:ok, next} = Cron.next_run(expr, DateTime.utc_now())

      # Check if a time matches
      Cron.matches?(expr, ~U[2024-01-15 06:00:00Z])
      #=> true

  ## Submodules

  - `Cron.Expression` - Expression struct and parsing
  - `Cron.Macros` - Built-in macros (@hourly, @daily, etc.)
  - `Cron.NextRun` - Next run time calculation

  ## Expression Format

  5-field format: `minute hour day-of-month month day-of-week`

  ```
  ┌───────────── minute (0-59)
  │ ┌───────────── hour (0-23)
  │ │ ┌───────────── day of month (1-31)
  │ │ │ ┌───────────── month (1-12 or JAN-DEC)
  │ │ │ │ ┌───────────── day of week (0-6 or SUN-SAT)
  │ │ │ │ │
  * * * * *
  ```

  ## Examples

      # Every hour
      "0 * * * *"

      # Daily at 6 AM
      "0 6 * * *"

      # Every 15 minutes
      "*/15 * * * *"

      # Weekdays at 9 AM
      "0 9 * * MON-FRI"

      # Multiple times
      "0 6,12,18 * * *"
  """

  alias Events.Infra.Scheduler.Cron.{Expression, Macros, NextRun}

  # Re-export types
  @type expression :: Expression.t()
  @type schedule :: String.t() | :reboot | [String.t()]

  # ============================================
  # Parsing
  # ============================================

  @doc """
  Parses a cron expression string.

  Accepts either a standard cron expression or a built-in macro.

  ## Examples

      iex> Cron.parse("0 6 * * *")
      {:ok, %Expression{...}}

      iex> Cron.parse("invalid")
      {:error, :invalid_expression}
  """
  @spec parse(String.t()) :: {:ok, Expression.t()} | {:error, term()}
  defdelegate parse(expression), to: Expression

  @doc """
  Parses a cron expression, raising on error.
  """
  @spec parse!(String.t()) :: Expression.t()
  defdelegate parse!(expression), to: Expression

  @doc """
  Validates a schedule value (expression, macro, or list).

  ## Examples

      iex> Cron.valid?("0 6 * * *")
      true

      iex> Cron.valid?(:reboot)
      true

      iex> Cron.valid?(["0 6 * * *", "0 18 * * *"])
      true

      iex> Cron.valid?("invalid")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(:reboot), do: true

  def valid?(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def valid?(expressions) when is_list(expressions) do
    Enum.all?(expressions, &valid?/1)
  end

  def valid?(_), do: false

  # ============================================
  # Next Run Calculation
  # ============================================

  @doc """
  Calculates the next run time for a schedule.

  Handles single expressions, lists of expressions, strings, and the :reboot macro.

  ## Options

  - `:timezone` - Timezone for evaluation (default: "Etc/UTC")
  - `:now` - Override current time (for testing)

  ## Examples

      # With string (parses automatically)
      iex> Cron.next_run("0 6 * * *")
      {:ok, ~U[...]}

      # With parsed expression
      iex> {:ok, expr} = Cron.parse("0 6 * * *")
      iex> Cron.next_run(expr, ~U[2024-01-15 05:00:00Z])
      {:ok, ~U[2024-01-15 06:00:00Z]}

      # With timezone
      iex> Cron.next_run(expr, DateTime.utc_now(), timezone: "America/New_York")
      {:ok, ~U[...]}
  """
  @spec next_run(Expression.t() | [Expression.t()] | String.t(), DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def next_run(expr_or_exprs, from \\ DateTime.utc_now(), opts \\ [])

  # String input - parse first
  def next_run(expression, from, opts) when is_binary(expression) do
    case parse(expression) do
      {:ok, expr} -> next_run(expr, from, opts)
      error -> error
    end
  end

  def next_run(%Expression{} = expr, %DateTime{} = from, opts) do
    NextRun.next(expr, from, opts)
  end

  def next_run(expressions, %DateTime{} = from, opts) when is_list(expressions) do
    # For multiple expressions, find the earliest next run
    expressions
    |> Enum.map(&next_run(&1, from, opts))
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, dt} -> dt end)
    |> case do
      [] -> {:error, :no_next_run}
      dts -> {:ok, Enum.min(dts, DateTime)}
    end
  end

  @doc """
  Calculates multiple upcoming run times.

  ## Examples

      iex> {:ok, expr} = Cron.parse("0 * * * *")
      iex> Cron.next_runs(expr, DateTime.utc_now(), 5)
      {:ok, [~U[...], ~U[...], ~U[...], ~U[...], ~U[...]]}
  """
  @spec next_runs(Expression.t(), DateTime.t(), pos_integer(), keyword()) ::
          {:ok, [DateTime.t()]} | {:error, term()}
  def next_runs(expr, from, count, opts \\ []) do
    NextRun.next_n(expr, from, count, opts)
  end

  @doc """
  Calculates the previous run time.

  ## Examples

      iex> {:ok, expr} = Cron.parse("0 6 * * *")
      iex> Cron.previous_run(expr, ~U[2024-01-15 10:00:00Z])
      {:ok, ~U[2024-01-15 06:00:00Z]}
  """
  @spec previous_run(Expression.t(), DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def previous_run(expr, from, opts \\ []) do
    NextRun.previous(expr, from, opts)
  end

  # ============================================
  # Matching
  # ============================================

  @doc """
  Checks if a datetime matches the cron expression.

  ## Examples

      iex> {:ok, expr} = Cron.parse("0 6 * * *")
      iex> Cron.matches?(expr, ~U[2024-01-15 06:00:00Z])
      true

      iex> Cron.matches?(expr, ~U[2024-01-15 06:01:00Z])
      false
  """
  @spec matches?(Expression.t(), DateTime.t()) :: boolean()
  defdelegate matches?(expression, datetime), to: Expression

  # ============================================
  # Macros
  # ============================================

  @doc """
  Checks if a value is the :reboot macro.
  """
  @spec reboot?(term()) :: boolean()
  defdelegate reboot?(value), to: Macros

  @doc """
  Checks if a value is a known macro.
  """
  @spec macro?(term()) :: boolean()
  defdelegate macro?(value), to: Macros

  @doc """
  Returns the name of a macro, if the value matches one.
  """
  @spec macro_name(term()) :: {:ok, atom()} | :error
  defdelegate macro_name(value), to: Macros

  @doc """
  Returns all available macro definitions.
  """
  @spec macros() :: map()
  def macros, do: Macros.all()

  # ============================================
  # Description
  # ============================================

  @doc """
  Returns a human-readable description of the expression.

  ## Examples

      iex> {:ok, expr} = Cron.parse("0 6 * * *")
      iex> Cron.describe(expr)
      "At 06:00"

      iex> {:ok, expr} = Cron.parse("*/15 * * * *")
      iex> Cron.describe(expr)
      "Every 15 minutes"
  """
  @spec describe(Expression.t()) :: String.t()
  defdelegate describe(expression), to: Expression

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts a schedule to a list of parsed expressions.

  Handles strings, lists of strings, and returns empty for :reboot.

  ## Examples

      iex> Cron.to_expressions("0 6 * * *")
      {:ok, [%Expression{...}]}

      iex> Cron.to_expressions(["0 6 * * *", "0 18 * * *"])
      {:ok, [%Expression{...}, %Expression{...}]}

      iex> Cron.to_expressions(:reboot)
      {:ok, []}
  """
  @spec to_expressions(schedule()) :: {:ok, [Expression.t()]} | {:error, term()}
  def to_expressions(:reboot), do: {:ok, []}

  def to_expressions(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, expr} -> {:ok, [expr]}
      error -> error
    end
  end

  def to_expressions(expressions) when is_list(expressions) do
    results = Enum.map(expressions, &parse/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, expr} -> expr end)}
      error -> error
    end
  end
end
