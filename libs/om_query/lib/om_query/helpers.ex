defmodule OmQuery.Helpers do
  @moduledoc """
  Helpful utilities for building queries.

  ## Usage

      import OmQuery.Helpers

      query Post do
        filter :created_at, :gte, last_week()
        filter :updated_at, :gte, hours_ago(24)
      end

  ## Date/Time Helpers

  All date/time helpers return values in UTC.

  - `today()` - Current date
  - `yesterday()` - Yesterday's date
  - `tomorrow()` - Tomorrow's date
  - `last_n_days(n)` - N days ago
  - `last_week()` - 7 days ago
  - `last_month()` - 30 days ago
  - `last_year()` - 365 days ago
  - `now()` - Current DateTime (UTC)
  - `minutes_ago(n)` - N minutes ago
  - `hours_ago(n)` - N hours ago
  - `days_ago(n)` - N days ago (DateTime, not Date)
  - `start_of_day(date)` - Start of day (00:00:00)
  - `end_of_day(date)` - End of day (23:59:59)
  - `start_of_week()` - Start of current week (Monday)
  - `start_of_month()` - Start of current month
  - `start_of_year()` - Start of current year

  ## Query Helpers

  - `dynamic_filters(token, filters, mapping)` - Apply filters dynamically
  - `ensure_limit(token, default)` - Ensure query has a limit
  - `sort_by(token, sort_param)` - Parse and apply sort strings
  """

  ## Date Helpers (return Date)

  @doc "Current date in UTC"
  @spec today() :: Date.t()
  def today, do: Date.utc_today()

  @doc "Yesterday's date"
  @spec yesterday() :: Date.t()
  def yesterday, do: Date.add(today(), -1)

  @doc "Tomorrow's date"
  @spec tomorrow() :: Date.t()
  def tomorrow, do: Date.add(today(), 1)

  @doc "Date N days ago"
  @spec last_n_days(integer()) :: Date.t()
  def last_n_days(n) when is_integer(n) and n >= 0 do
    Date.add(today(), -n)
  end

  @doc "7 days ago"
  @spec last_week() :: Date.t()
  def last_week, do: last_n_days(7)

  @doc "30 days ago"
  @spec last_month() :: Date.t()
  def last_month, do: last_n_days(30)

  @doc "90 days ago"
  @spec last_quarter() :: Date.t()
  def last_quarter, do: last_n_days(90)

  @doc "365 days ago"
  @spec last_year() :: Date.t()
  def last_year, do: last_n_days(365)

  ## DateTime Helpers (return DateTime)

  @doc "Current DateTime in UTC"
  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now()

  @doc "DateTime N minutes ago"
  @spec minutes_ago(integer()) :: DateTime.t()
  def minutes_ago(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), -n * 60, :second)
  end

  @doc "DateTime N hours ago"
  @spec hours_ago(integer()) :: DateTime.t()
  def hours_ago(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), -n * 3600, :second)
  end

  @doc "DateTime N days ago"
  @spec days_ago(integer()) :: DateTime.t()
  def days_ago(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), -n * 86400, :second)
  end

  @doc "DateTime N weeks ago"
  @spec weeks_ago(integer()) :: DateTime.t()
  def weeks_ago(n) when is_integer(n) and n >= 0 do
    days_ago(n * 7)
  end

  ## Future DateTime Helpers

  @doc "DateTime N minutes from now"
  @spec minutes_from_now(integer()) :: DateTime.t()
  def minutes_from_now(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), n * 60, :second)
  end

  @doc "DateTime N hours from now"
  @spec hours_from_now(integer()) :: DateTime.t()
  def hours_from_now(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), n * 3600, :second)
  end

  @doc "DateTime N days from now"
  @spec days_from_now(integer()) :: DateTime.t()
  def days_from_now(n) when is_integer(n) and n >= 0 do
    DateTime.add(now(), n * 86400, :second)
  end

  @doc "DateTime N weeks from now"
  @spec weeks_from_now(integer()) :: DateTime.t()
  def weeks_from_now(n) when is_integer(n) and n >= 0 do
    days_from_now(n * 7)
  end

  @doc "Date N days from now"
  @spec next_n_days(integer()) :: Date.t()
  def next_n_days(n) when is_integer(n) and n >= 0 do
    Date.add(today(), n)
  end

  ## Time Period Helpers

  @doc """
  Start of day (00:00:00) for a given date.

  Returns a DateTime in UTC.

  ## Examples

      iex> start_of_day(~D[2024-01-15])
      ~U[2024-01-15 00:00:00Z]
  """
  @spec start_of_day(Date.t()) :: DateTime.t()
  def start_of_day(%Date{} = date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  @doc """
  End of day (23:59:59.999999) for a given date.

  Returns a DateTime in UTC.

  ## Examples

      iex> end_of_day(~D[2024-01-15])
      ~U[2024-01-15 23:59:59.999999Z]
  """
  @spec end_of_day(Date.t()) :: DateTime.t()
  def end_of_day(%Date{} = date) do
    DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")
  end

  @doc "Start of current week (Monday at 00:00:00)"
  @spec start_of_week() :: DateTime.t()
  def start_of_week do
    today = today()
    days_since_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_since_monday)
    start_of_day(monday)
  end

  @doc "Start of current month (1st day at 00:00:00)"
  @spec start_of_month() :: DateTime.t()
  def start_of_month do
    today = today()
    first_of_month = %{today | day: 1}
    start_of_day(first_of_month)
  end

  @doc "Start of current year (Jan 1st at 00:00:00)"
  @spec start_of_year() :: DateTime.t()
  def start_of_year do
    today = today()
    jan_first = %{today | month: 1, day: 1}
    start_of_day(jan_first)
  end

  ## Query Helpers

  @doc """
  Apply filters dynamically based on a map of filters.

  ## Parameters

  - `token` - The query token
  - `filters` - Map of filter values (e.g., %{status: "active", min_age: 18})
  - `mapping` - Map defining how to apply filters

  ## Examples

      mapping = %{
        status: {:eq, :status},
        min_age: {:gte, :age},
        search: {:ilike, :name}
      }

      token
      |> dynamic_filters(params, mapping)

      # If params = %{status: "active", min_age: 18}
      # Applies: filter(:status, :eq, "active") and filter(:age, :gte, 18)
  """
  @spec dynamic_filters(OmQuery.Token.t(), map(), map()) :: OmQuery.Token.t()
  def dynamic_filters(token, filters, mapping) when is_map(filters) and is_map(mapping) do
    Enum.reduce(mapping, token, fn {param_key, {op, field}}, acc ->
      case Map.get(filters, param_key) do
        nil -> acc
        value -> OmQuery.where(acc, field, op, value)
      end
    end)
  end

  @doc """
  Ensure query has a limit, applying default if needed.

  ## Examples

      token
      |> ensure_limit(20)

      # If no limit/pagination, adds: limit(20)
      # If already has limit/pagination, unchanged
  """
  @spec ensure_limit(OmQuery.Token.t(), pos_integer()) :: OmQuery.Token.t()
  def ensure_limit(token, default_limit) do
    has_limit =
      Enum.any?(token.operations, fn
        {:limit, _} -> true
        {:paginate, _} -> true
        _ -> false
      end)

    if has_limit do
      token
    else
      OmQuery.limit(token, default_limit)
    end
  end

  @doc """
  Parse and apply sorting from string parameters.

  Supports formats:
  - "field" or "+field" - ascending
  - "-field" - descending
  - "field1,-field2,+field3" - multiple fields

  ## Examples

      sort_by(token, "created_at")           # asc: :created_at
      sort_by(token, "-created_at")          # desc: :created_at
      sort_by(token, "name,-created_at,id")  # asc: :name, desc: :created_at, asc: :id
  """
  @spec sort_by(OmQuery.Token.t(), String.t() | nil) :: OmQuery.Token.t()
  def sort_by(token, nil), do: token

  def sort_by(token, sort_string) when is_binary(sort_string) do
    sort_string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(token, fn field_spec, acc ->
      case field_spec do
        "-" <> field ->
          OmQuery.order_by(acc, String.to_existing_atom(field), :desc)

        "+" <> field ->
          OmQuery.order_by(acc, String.to_existing_atom(field), :asc)

        field ->
          OmQuery.order_by(acc, String.to_existing_atom(field), :asc)
      end
    end)
  rescue
    # Invalid atom, skip sorting
    ArgumentError -> token
  end

  @doc """
  Parse sort string safely (doesn't raise on invalid atoms).

  Returns `{:ok, token}` or `{:error, :invalid_field}`.
  """
  @spec safe_sort_by(OmQuery.Token.t(), String.t() | nil) ::
          {:ok, OmQuery.Token.t()} | {:error, :invalid_field}
  def safe_sort_by(token, sort_string) do
    {:ok, sort_by(token, sort_string)}
  rescue
    ArgumentError -> {:error, :invalid_field}
  end

  @doc """
  Apply pagination from request parameters.

  ## Examples

      paginate_from_params(token, %{"limit" => "25", "cursor" => "abc123"})
      paginate_from_params(token, %{"limit" => "50", "offset" => "100"})
  """
  @spec paginate_from_params(OmQuery.Token.t(), map()) :: OmQuery.Token.t()
  def paginate_from_params(token, params) when is_map(params) do
    limit = parse_int(params["limit"], 20)

    cond do
      cursor = params["cursor"] ->
        OmQuery.paginate(token, :cursor, limit: limit, after: cursor)

      offset = params["offset"] ->
        offset_int = parse_int(offset, 0)
        OmQuery.paginate(token, :offset, limit: limit, offset: offset_int)

      true ->
        OmQuery.paginate(token, :cursor, limit: limit)
    end
  end

  # Parse integer with default fallback
  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_, default), do: default
end
