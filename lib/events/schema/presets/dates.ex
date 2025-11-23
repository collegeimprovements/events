defmodule Events.Schema.Presets.Dates do
  @moduledoc """
  Date and DateTime field presets for common use cases.

  ## Usage

      import Events.Schema.Presets.Dates

      schema "events" do
        field :event_date, :date, preset: future_date()
        field :birth_date, :date, preset: past_date()
        field :created_at, :utc_datetime_usec, preset: timestamp()
        field :expires_at, :utc_datetime_usec, preset: future_datetime()
        field :starts_at, :utc_datetime_usec, preset: scheduled_datetime()
      end
  """

  @doc """
  Past date preset - date must be in the past.

  Common use: birth dates, historical dates

  Options:
  - `past: true`
  - `required: false`
  """
  def past_date(custom_opts \\ []) do
    [
      past: true,
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Future date preset - date must be in the future.

  Common use: event dates, expiration dates, deadlines

  Options:
  - `future: true`
  - `required: false`
  """
  def future_date(custom_opts \\ []) do
    [
      future: true,
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Birth date preset with age validation.

  Options:
  - `past: true`
  - `after: {:today, days: -(365 * 120)}` - Max age 120 years
  - `before: {:today, days: -(365 * 13)}` - Min age 13 years
  - `required: false`
  """
  def birth_date(custom_opts \\ []) do
    [
      past: true,
      after: {:today, days: -(365 * 120)},  # Born within last 120 years
      before: {:today, days: -(365 * 13)},  # At least 13 years old
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Adult birth date preset (18+ years).

  Options:
  - `past: true`
  - `before: {:today, days: -(365 * 18)}` - Must be 18+
  - `required: false`
  """
  def adult_birth_date(custom_opts \\ []) do
    [
      past: true,
      before: {:today, days: -(365 * 18)},  # At least 18 years old
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Expiration date preset - must be in the future.

  Common use: credit cards, subscriptions, tokens

  Options:
  - `future: true`
  - `after: {:today, days: 0}` - Must be today or later
  - `required: true`
  """
  def expiration_date(custom_opts \\ []) do
    [
      future: true,
      after: {:today, days: 0},
      required: true
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Timestamp preset for created_at/updated_at fields.

  Options:
  - `required: false` - Usually auto-set by database
  """
  def timestamp(custom_opts \\ []) do
    [
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Past datetime preset - must be in the past.

  Common use: completed_at, archived_at, deleted_at

  Options:
  - `past: true`
  - `required: false`
  """
  def past_datetime(custom_opts \\ []) do
    [
      past: true,
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Future datetime preset - must be in the future.

  Common use: scheduled_at, publish_at, expires_at

  Options:
  - `future: true`
  - `required: false`
  """
  def future_datetime(custom_opts \\ []) do
    [
      future: true,
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Scheduled datetime preset - must be at least 1 hour in the future.

  Common use: scheduled jobs, appointments, meetings

  Options:
  - `after: {:now, hours: 1}` - At least 1 hour from now
  - `required: false`
  """
  def scheduled_datetime(custom_opts \\ []) do
    [
      after: {:now, hours: 1},
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Recent datetime preset - within last N days (default 30).

  Common use: recent activity, recent changes

  Options:
  - `after: {:now, days: -30}` - Within last 30 days
  - `before: {:now, hours: 0}` - Not in future
  - `required: false`
  """
  def recent_datetime(custom_opts \\ []) do
    days = Keyword.get(custom_opts, :within_days, 30)

    [
      after: {:now, days: -days},
      before: {:now, hours: 0},
      required: false
    ]
    |> merge_opts(Keyword.delete(custom_opts, :within_days))
  end

  @doc """
  Date range start preset - must be before end_date field.

  Common use: start_date, begin_date, from_date

  Options:
  - `before: {:field, :end_date}` - Must be before end_date
  - `required: false`

  ## Example

      field :start_date, :date, preset: date_range_start(before: {:field, :end_date})
      field :end_date, :date, preset: date_range_end(after: {:field, :start_date})
  """
  def date_range_start(custom_opts \\ []) do
    [
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  @doc """
  Date range end preset - must be after start_date field.

  Common use: end_date, finish_date, to_date

  Options:
  - `after: {:field, :start_date}` - Must be after start_date
  - `required: false`
  """
  def date_range_end(custom_opts \\ []) do
    [
      required: false
    ]
    |> merge_opts(custom_opts)
  end

  defp merge_opts(defaults, custom_opts) do
    # Custom options override defaults
    Keyword.merge(defaults, custom_opts)
  end
end
