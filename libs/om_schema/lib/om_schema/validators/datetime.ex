defmodule OmSchema.Validators.DateTime do
  @moduledoc """
  Date/time-specific validations for enhanced schema fields.

  Provides past/future and before/after validations with support for relative times.

  Implements `OmSchema.Behaviours.Validator` behavior.
  """

  @behaviour OmSchema.Behaviours.Validator

  alias OmSchema.Utils.Comparison

  @impl true
  def field_types, do: [:utc_datetime, :utc_datetime_usec, :naive_datetime, :date, :time]

  @impl true
  def supported_options, do: [:past, :future, :after, :before]

  @doc """
  Apply all datetime validations to a changeset.
  """
  @impl true
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
        cond do
          opts[:past] && !Comparison.datetime_past?(value) ->
            Ecto.Changeset.add_error(changeset, field_name, "must be in the past")

          opts[:future] && !Comparison.datetime_future?(value) ->
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

    if !Comparison.datetime_after?(value, compare_value) do
      Ecto.Changeset.add_error(changeset, field_name, "must be after #{inspect(compare_value)}")
    else
      changeset
    end
  end

  defp validate_before(changeset, _field_name, _value, nil), do: changeset

  defp validate_before(changeset, field_name, value, before_value) do
    compare_value = resolve_datetime_value(before_value)

    if !Comparison.datetime_before?(value, compare_value) do
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
end
