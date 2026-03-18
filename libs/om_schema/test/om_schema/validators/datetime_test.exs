defmodule OmSchema.Validators.DateTimeTest do
  use ExUnit.Case, async: true

  alias OmSchema.Validators.DateTime, as: DateTimeValidator

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :starts_at, :utc_datetime
      field :ends_at, :utc_datetime
      field :event_date, :date
      field :created_at, :naive_datetime
    end

    @fields [:starts_at, :ends_at, :event_date, :created_at]

    def changeset(struct \\ %__MODULE__{}, attrs) do
      cast(struct, attrs, @fields)
    end
  end

  defp changeset(attrs), do: TestSchema.changeset(attrs)

  # Helpers for creating test datetimes
  defp past_datetime(seconds_ago \\ 86400) do
    DateTime.utc_now() |> DateTime.add(-seconds_ago, :second)
  end

  defp future_datetime(seconds_ahead \\ 86400) do
    DateTime.utc_now() |> DateTime.add(seconds_ahead, :second)
  end

  # ============================================
  # Behaviour Callbacks
  # ============================================

  describe "field_types/0" do
    test "returns datetime-related types" do
      types = DateTimeValidator.field_types()

      assert :utc_datetime in types
      assert :utc_datetime_usec in types
      assert :naive_datetime in types
      assert :date in types
      assert :time in types
    end
  end

  describe "supported_options/0" do
    test "returns all supported option keys" do
      opts = DateTimeValidator.supported_options()

      assert :past in opts
      assert :future in opts
      assert :after in opts
      assert :before in opts
      assert length(opts) == 4
    end
  end

  # ============================================
  # :past validation
  # ============================================

  describe "validate/3 with past: true" do
    test "passes for a past datetime" do
      cs =
        changeset(%{starts_at: past_datetime()})
        |> DateTimeValidator.validate(:starts_at, past: true)

      assert cs.valid?
    end

    test "fails for a future datetime" do
      cs =
        changeset(%{starts_at: future_datetime()})
        |> DateTimeValidator.validate(:starts_at, past: true)

      refute cs.valid?
      {msg, _} = cs.errors[:starts_at]
      assert msg == "must be in the past"
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> DateTimeValidator.validate(:starts_at, past: true)

      assert cs.valid?
    end

    test "passes for a datetime well in the past" do
      far_past = DateTime.utc_now() |> DateTime.add(-365 * 86400, :second)

      cs =
        changeset(%{starts_at: far_past})
        |> DateTimeValidator.validate(:starts_at, past: true)

      assert cs.valid?
    end
  end

  # ============================================
  # :future validation
  # ============================================

  describe "validate/3 with future: true" do
    test "passes for a future datetime" do
      cs =
        changeset(%{starts_at: future_datetime()})
        |> DateTimeValidator.validate(:starts_at, future: true)

      assert cs.valid?
    end

    test "fails for a past datetime" do
      cs =
        changeset(%{starts_at: past_datetime()})
        |> DateTimeValidator.validate(:starts_at, future: true)

      refute cs.valid?
      {msg, _} = cs.errors[:starts_at]
      assert msg == "must be in the future"
    end

    test "passes when field is nil (no change)" do
      cs = changeset(%{}) |> DateTimeValidator.validate(:starts_at, future: true)

      assert cs.valid?
    end

    test "passes for a datetime well in the future" do
      far_future = DateTime.utc_now() |> DateTime.add(365 * 86400, :second)

      cs =
        changeset(%{starts_at: far_future})
        |> DateTimeValidator.validate(:starts_at, future: true)

      assert cs.valid?
    end
  end

  # ============================================
  # :after validation with static datetime
  # ============================================

  describe "validate/3 with after: static datetime" do
    test "passes when value is after reference" do
      reference = ~U[2024-01-01 00:00:00Z]
      value = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: reference)

      assert cs.valid?
    end

    test "fails when value is before reference" do
      reference = ~U[2024-06-15 00:00:00Z]
      value = ~U[2024-01-01 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: reference)

      refute cs.valid?
      {msg, _} = cs.errors[:starts_at]
      assert msg =~ "must be after"
    end

    test "fails when value equals reference" do
      reference = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: reference})
        |> DateTimeValidator.validate(:starts_at, after: reference)

      refute cs.valid?
    end

    test "passes when field is nil (no change)" do
      reference = ~U[2024-01-01 00:00:00Z]

      cs = changeset(%{}) |> DateTimeValidator.validate(:starts_at, after: reference)

      assert cs.valid?
    end
  end

  # ============================================
  # :before validation with static datetime
  # ============================================

  describe "validate/3 with before: static datetime" do
    test "passes when value is before reference" do
      reference = ~U[2024-12-31 23:59:59Z]
      value = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, before: reference)

      assert cs.valid?
    end

    test "fails when value is after reference" do
      reference = ~U[2024-01-01 00:00:00Z]
      value = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, before: reference)

      refute cs.valid?
      {msg, _} = cs.errors[:starts_at]
      assert msg =~ "must be before"
    end

    test "fails when value equals reference" do
      reference = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: reference})
        |> DateTimeValidator.validate(:starts_at, before: reference)

      refute cs.valid?
    end
  end

  # ============================================
  # :after with relative {:now, opts}
  # ============================================

  describe "validate/3 with after: {:now, opts}" do
    test "passes when value is after now + offset" do
      # 2 hours from now should be after {:now, hours: 1}
      value = DateTime.utc_now() |> DateTime.add(2 * 3600, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:now, hours: 1})

      assert cs.valid?
    end

    test "fails when value is before now + offset" do
      # 30 minutes from now should fail {:now, hours: 1}
      value = DateTime.utc_now() |> DateTime.add(30 * 60, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:now, hours: 1})

      refute cs.valid?
    end

    test "supports seconds offset" do
      value = DateTime.utc_now() |> DateTime.add(120, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:now, seconds: 60})

      assert cs.valid?
    end

    test "supports minutes offset" do
      value = DateTime.utc_now() |> DateTime.add(2 * 3600, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:now, minutes: 30})

      assert cs.valid?
    end

    test "supports days offset" do
      value = DateTime.utc_now() |> DateTime.add(3 * 86400, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:now, days: 2})

      assert cs.valid?
    end
  end

  # ============================================
  # :before with relative {:now, opts}
  # ============================================

  describe "validate/3 with before: {:now, opts}" do
    test "passes when value is before now + offset" do
      # 30 minutes from now should be before {:now, hours: 1}
      value = DateTime.utc_now() |> DateTime.add(30 * 60, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, before: {:now, hours: 1})

      assert cs.valid?
    end

    test "fails when value is after now + offset" do
      # 2 hours from now should fail before: {:now, hours: 1}
      value = DateTime.utc_now() |> DateTime.add(2 * 3600, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, before: {:now, hours: 1})

      refute cs.valid?
    end
  end

  # ============================================
  # :after / :before with relative {:today, opts}
  # ============================================

  describe "validate/3 with after/before: {:today, opts}" do
    test "after {:today, days: 7} passes for date 10 days from now" do
      value = DateTime.utc_now() |> DateTime.add(10 * 86400, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:today, days: 7})

      assert cs.valid?
    end

    test "after {:today, days: 7} fails for date 3 days from now" do
      value = DateTime.utc_now() |> DateTime.add(3 * 86400, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: {:today, days: 7})

      refute cs.valid?
    end

    test "before {:today, days: 7} passes for date 3 days from now" do
      value = DateTime.utc_now() |> DateTime.add(3 * 86400, :second)

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, before: {:today, days: 7})

      assert cs.valid?
    end
  end

  # ============================================
  # Combined after and before (range)
  # ============================================

  describe "validate/3 with combined after and before" do
    test "passes when value is within range" do
      start_ref = ~U[2024-01-01 00:00:00Z]
      end_ref = ~U[2024-12-31 23:59:59Z]
      value = ~U[2024-06-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: start_ref, before: end_ref)

      assert cs.valid?
    end

    test "fails when value is before range start" do
      start_ref = ~U[2024-06-01 00:00:00Z]
      end_ref = ~U[2024-12-31 23:59:59Z]
      value = ~U[2024-01-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: start_ref, before: end_ref)

      refute cs.valid?
    end

    test "fails when value is after range end" do
      start_ref = ~U[2024-01-01 00:00:00Z]
      end_ref = ~U[2024-06-01 00:00:00Z]
      value = ~U[2024-08-15 12:00:00Z]

      cs =
        changeset(%{starts_at: value})
        |> DateTimeValidator.validate(:starts_at, after: start_ref, before: end_ref)

      refute cs.valid?
    end
  end

  # ============================================
  # No options (passthrough)
  # ============================================

  describe "validate/3 with no options" do
    test "returns changeset unchanged" do
      cs =
        changeset(%{starts_at: DateTime.utc_now()})
        |> DateTimeValidator.validate(:starts_at, [])

      assert cs.valid?
    end
  end

  # ============================================
  # past: false / future: false (no-op)
  # ============================================

  describe "validate/3 with past: false or future: false" do
    test "does not validate past when past: false" do
      cs =
        changeset(%{starts_at: future_datetime()})
        |> DateTimeValidator.validate(:starts_at, past: false)

      assert cs.valid?
    end

    test "does not validate future when future: false" do
      cs =
        changeset(%{starts_at: past_datetime()})
        |> DateTimeValidator.validate(:starts_at, future: false)

      assert cs.valid?
    end
  end
end
