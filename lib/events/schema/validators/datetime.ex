defmodule Events.Schema.Validators.DateTime do
  @moduledoc """
  Date/time-specific validations for enhanced schema fields.

  Provides past/future and before/after validations with support for relative times.
  """

  @doc """
  Apply all datetime validations to a changeset.
  """
  def validate(changeset, field_name, opts) do
    changeset
    |> validate_past_future(field_name, opts)
    |> validate_range(field_name, opts)
  end

  # Past/Future validation

  defp validate_past_future(changeset, field_name, opts) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil ->
        changeset

      value ->
        now = DateTime.utc_now()

        cond do
          opts[:past] && compare_datetime(value, now) != :lt ->
            Ecto.Changeset.add_error(changeset, field_name, "must be in the past")

          opts[:future] && compare_datetime(value, now) != :gt ->
            Ecto.Changeset.add_error(changeset, field_name, "must be in the future")

          true ->
            changeset
        end
    end
  end

  # Range validation (after/before)

  defp validate_range(changeset, field_name, opts) do
    case Ecto.Changeset.get_change(changeset, field_name) do
      nil ->
        changeset

      value ->
        changeset
        |> validate_after(field_name, value, opts[:after])
        |> validate_before(field_name, value, opts[:before])
    end
  end

  defp validate_after(changeset, _field_name, _value, nil), do: changeset

  defp validate_after(changeset, field_name, value, after_value) do
    compare_value = resolve_datetime_value(after_value)

    if compare_datetime(value, compare_value) != :gt do
      Ecto.Changeset.add_error(changeset, field_name, "must be after #{inspect(compare_value)}")
    else
      changeset
    end
  end

  defp validate_before(changeset, _field_name, _value, nil), do: changeset

  defp validate_before(changeset, field_name, value, before_value) do
    compare_value = resolve_datetime_value(before_value)

    if compare_datetime(value, compare_value) != :lt do
      Ecto.Changeset.add_error(changeset, field_name, "must be before #{inspect(compare_value)}")
    else
      changeset
    end
  end

  # Relative datetime resolution

  defp resolve_datetime_value({:now, opts}) do
    now = DateTime.utc_now()
    add_time_offset(now, opts)
  end

  defp resolve_datetime_value({:today, opts}) do
    today = Date.utc_today()
    add_date_offset(today, opts)
  end

  defp resolve_datetime_value(value), do: value

  defp add_time_offset(datetime, opts) do
    datetime
    |> maybe_add_seconds(opts[:seconds])
    |> maybe_add_minutes(opts[:minutes])
    |> maybe_add_hours(opts[:hours])
    |> maybe_add_days(opts[:days])
  end

  defp add_date_offset(date, opts) do
    if days = opts[:days] do
      Date.add(date, days)
    else
      date
    end
  end

  defp maybe_add_seconds(dt, nil), do: dt
  defp maybe_add_seconds(dt, seconds), do: DateTime.add(dt, seconds, :second)

  defp maybe_add_minutes(dt, nil), do: dt
  defp maybe_add_minutes(dt, minutes), do: DateTime.add(dt, minutes * 60, :second)

  defp maybe_add_hours(dt, nil), do: dt
  defp maybe_add_hours(dt, hours), do: DateTime.add(dt, hours * 3600, :second)

  defp maybe_add_days(dt, nil), do: dt
  defp maybe_add_days(dt, days), do: DateTime.add(dt, days * 86400, :second)

  # Datetime comparison

  defp compare_datetime(%Date{} = d1, %Date{} = d2) do
    case Date.compare(d1, d2) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  defp compare_datetime(%DateTime{} = dt1, %DateTime{} = dt2) do
    case DateTime.compare(dt1, dt2) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  defp compare_datetime(%NaiveDateTime{} = ndt1, %NaiveDateTime{} = ndt2) do
    case NaiveDateTime.compare(ndt1, ndt2) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  # Convert between types for comparison
  defp compare_datetime(%Date{} = d, %DateTime{} = dt) do
    date_from_dt = DateTime.to_date(dt)
    compare_datetime(d, date_from_dt)
  end

  defp compare_datetime(%DateTime{} = dt, %Date{} = d) do
    date_from_dt = DateTime.to_date(dt)
    compare_datetime(date_from_dt, d)
  end

  defp compare_datetime(_, _), do: :eq
end
