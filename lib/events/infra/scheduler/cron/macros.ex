defmodule Events.Infra.Scheduler.Cron.Macros do
  @moduledoc """
  Built-in cron expression macros for common scheduling patterns.

  ## Usage

  These macros are automatically available when you `use Events.Infra.Scheduler`:

      defmodule MyApp.Jobs do
        use Events.Infra.Scheduler

        @decorate scheduled(cron: @hourly)
        def every_hour, do: ...

        @decorate scheduled(cron: @daily)
        def every_day, do: ...
      end

  ## Available Macros

  | Macro | Expression | Description |
  |-------|------------|-------------|
  | `@yearly` / `@annually` | `0 0 1 1 *` | January 1st at midnight |
  | `@monthly` | `0 0 1 * *` | 1st of month at midnight |
  | `@weekly` | `0 0 * * 0` | Sunday at midnight |
  | `@daily` / `@midnight` | `0 0 * * *` | Every day at midnight |
  | `@hourly` | `0 * * * *` | Every hour at minute 0 |
  | `@reboot` | `:reboot` | Once at application start |

  ## Custom Macros

  You can define your own macros using module attributes:

      @business_hours "0 9-17 * * MON-FRI"

      @decorate scheduled(cron: @business_hours)
      def during_business_hours, do: ...
  """

  @yearly "0 0 1 1 *"
  @annually @yearly
  @monthly "0 0 1 * *"
  @weekly "0 0 * * 0"
  @daily "0 0 * * *"
  @midnight @daily
  @hourly "0 * * * *"
  @reboot :reboot

  @doc """
  Returns the cron expression for yearly/annually.

  Runs at midnight on January 1st.
  """
  @spec yearly() :: String.t()
  def yearly, do: @yearly

  @doc """
  Alias for `yearly/0`.
  """
  @spec annually() :: String.t()
  def annually, do: @annually

  @doc """
  Returns the cron expression for monthly.

  Runs at midnight on the 1st of each month.
  """
  @spec monthly() :: String.t()
  def monthly, do: @monthly

  @doc """
  Returns the cron expression for weekly.

  Runs at midnight on Sunday.
  """
  @spec weekly() :: String.t()
  def weekly, do: @weekly

  @doc """
  Returns the cron expression for daily.

  Runs at midnight every day.
  """
  @spec daily() :: String.t()
  def daily, do: @daily

  @doc """
  Alias for `daily/0`.
  """
  @spec midnight() :: String.t()
  def midnight, do: @midnight

  @doc """
  Returns the cron expression for hourly.

  Runs at minute 0 of every hour.
  """
  @spec hourly() :: String.t()
  def hourly, do: @hourly

  @doc """
  Returns the reboot atom.

  Used to run a job once when the application starts.
  """
  @spec reboot() :: :reboot
  def reboot, do: @reboot

  @doc """
  Checks if the given value is a reboot schedule.

  ## Examples

      iex> Macros.reboot?(:reboot)
      true

      iex> Macros.reboot?("0 * * * *")
      false
  """
  @spec reboot?(term()) :: boolean()
  def reboot?(:reboot), do: true
  def reboot?(_), do: false

  @doc """
  Checks if the given value is a known macro.

  ## Examples

      iex> Macros.macro?("0 0 * * *")
      true

      iex> Macros.macro?("5 4 * * *")
      false
  """
  @spec macro?(term()) :: boolean()
  def macro?(:reboot), do: true
  def macro?(@yearly), do: true
  def macro?(@monthly), do: true
  def macro?(@weekly), do: true
  def macro?(@daily), do: true
  def macro?(@hourly), do: true
  def macro?(_), do: false

  @doc """
  Returns the name of a macro expression, if it matches one.

  ## Examples

      iex> Macros.macro_name("0 0 * * *")
      {:ok, :daily}

      iex> Macros.macro_name("5 4 * * *")
      :error
  """
  @spec macro_name(term()) :: {:ok, atom()} | :error
  def macro_name(:reboot), do: {:ok, :reboot}
  def macro_name(@yearly), do: {:ok, :yearly}
  def macro_name(@monthly), do: {:ok, :monthly}
  def macro_name(@weekly), do: {:ok, :weekly}
  def macro_name(@daily), do: {:ok, :daily}
  def macro_name(@hourly), do: {:ok, :hourly}
  def macro_name(_), do: :error

  @doc """
  Returns all available macro definitions.

  ## Examples

      iex> Macros.all()
      %{
        yearly: "0 0 1 1 *",
        annually: "0 0 1 1 *",
        monthly: "0 0 1 * *",
        weekly: "0 0 * * 0",
        daily: "0 0 * * *",
        midnight: "0 0 * * *",
        hourly: "0 * * * *",
        reboot: :reboot
      }
  """
  @spec all() :: map()
  def all do
    %{
      yearly: @yearly,
      annually: @annually,
      monthly: @monthly,
      weekly: @weekly,
      daily: @daily,
      midnight: @midnight,
      hourly: @hourly,
      reboot: @reboot
    }
  end

  @doc """
  Macro for injecting cron macros as module attributes.

  ## Usage

      defmodule MyModule do
        use Events.Infra.Scheduler.Cron.Macros

        # Now you can use @hourly, @daily, etc.
        def schedule, do: @daily
      end
  """
  defmacro __using__(_opts) do
    quote do
      @yearly unquote(@yearly)
      @annually unquote(@annually)
      @monthly unquote(@monthly)
      @weekly unquote(@weekly)
      @daily unquote(@daily)
      @midnight unquote(@midnight)
      @hourly unquote(@hourly)
      @reboot unquote(@reboot)
    end
  end
end
