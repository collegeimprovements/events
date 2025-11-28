defmodule Events.Schema.DatePresetsTest do
  use Events.TestCase, async: true

  import Events.Schema.Presets.Dates

  defmodule Event do
    use Events.Schema

    schema "events" do
      field :event_date, :date, preset: future_date()
      field :birth_date, :date, preset: birth_date()
      field :created_at, :utc_datetime_usec, preset: timestamp()
      field :scheduled_at, :utc_datetime_usec, preset: scheduled_datetime()
    end

    def changeset(event, attrs) do
      event
      |> Ecto.Changeset.cast(attrs, __cast_fields__())
      |> __apply_field_validations__()
    end
  end

  describe "future_date preset" do
    test "accepts future dates" do
      tomorrow = Date.add(Date.utc_today(), 1)

      changeset =
        Event.changeset(%Event{}, %{
          event_date: tomorrow
        })

      assert changeset.valid?
    end

    test "rejects past dates" do
      yesterday = Date.add(Date.utc_today(), -1)

      changeset =
        Event.changeset(%Event{}, %{
          event_date: yesterday
        })

      refute changeset.valid?

      assert {:event_date, {"must be in the future", _}} =
               List.keyfind(changeset.errors, :event_date, 0)
    end
  end

  describe "birth_date preset" do
    test "accepts valid birth dates (13+ years old)" do
      twenty_years_ago = Date.add(Date.utc_today(), -(365 * 20))

      changeset =
        Event.changeset(%Event{}, %{
          birth_date: twenty_years_ago
        })

      assert changeset.valid?
    end

    test "rejects dates for people under 13" do
      ten_years_ago = Date.add(Date.utc_today(), -(365 * 10))

      changeset =
        Event.changeset(%Event{}, %{
          birth_date: ten_years_ago
        })

      refute changeset.valid?
    end

    test "rejects future dates" do
      tomorrow = Date.add(Date.utc_today(), 1)

      changeset =
        Event.changeset(%Event{}, %{
          birth_date: tomorrow
        })

      refute changeset.valid?
    end
  end

  describe "scheduled_datetime preset" do
    test "accepts datetimes at least 1 hour in future" do
      two_hours_from_now = DateTime.add(DateTime.utc_now(), 2 * 3600, :second)

      changeset =
        Event.changeset(%Event{}, %{
          scheduled_at: two_hours_from_now
        })

      assert changeset.valid?
    end

    test "rejects datetimes less than 1 hour away" do
      thirty_minutes_from_now = DateTime.add(DateTime.utc_now(), 30 * 60, :second)

      changeset =
        Event.changeset(%Event{}, %{
          scheduled_at: thirty_minutes_from_now
        })

      refute changeset.valid?
    end
  end
end
