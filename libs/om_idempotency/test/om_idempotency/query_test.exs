defmodule OmIdempotency.QueryTest do
  use OmIdempotency.DataCase, async: true

  alias OmIdempotency
  alias OmIdempotency.{Query, Record}

  setup do
    # Create test records in different states
    {:ok, pending} = OmIdempotency.create("pending_1", scope: "test")

    {:ok, processing_record} = OmIdempotency.create("processing_1", scope: "test")
    {:ok, processing} = OmIdempotency.start_processing(processing_record)

    {:ok, completed_record} = OmIdempotency.create("completed_1", scope: "test")
    {:ok, processing_temp} = OmIdempotency.start_processing(completed_record)
    {:ok, completed} = OmIdempotency.complete(processing_temp, %{status: "ok"})

    {:ok, failed_record} = OmIdempotency.create("failed_1", scope: "test")
    {:ok, processing_temp2} = OmIdempotency.start_processing(failed_record)
    {:ok, failed} = OmIdempotency.fail(processing_temp2, "some error")

    %{
      pending: pending,
      processing: processing,
      completed: completed,
      failed: failed
    }
  end

  describe "list_by_state/2" do
    test "lists records by state", %{pending: pending, processing: processing} do
      assert {:ok, records} = Query.list_by_state(:pending)
      assert length(records) >= 1
      assert Enum.any?(records, &(&1.id == pending.id))

      assert {:ok, records} = Query.list_by_state(:processing)
      assert length(records) >= 1
      assert Enum.any?(records, &(&1.id == processing.id))
    end

    test "filters by scope" do
      {:ok, _} = OmIdempotency.create("other_scope", scope: "other")

      assert {:ok, records} = Query.list_by_state(:pending, scope: "test")
      assert Enum.all?(records, &(&1.scope == "test"))
    end

    test "respects limit option" do
      assert {:ok, records} = Query.list_by_state(:pending, limit: 1)
      assert length(records) <= 1
    end
  end

  describe "list_stale_processing/1" do
    test "lists only stale processing records" do
      # Create stale record
      past = DateTime.add(DateTime.utc_now(), -100, :second)

      {:ok, stale} =
        Repo.insert(%Record{
          key: "stale_processing",
          state: :processing,
          locked_until: past,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:ok, records} = Query.list_stale_processing()
      assert Enum.any?(records, &(&1.id == stale.id))
    end

    test "does not list fresh processing records" do
      {:ok, record} = OmIdempotency.create("fresh_processing")
      {:ok, processing} = OmIdempotency.start_processing(record)

      assert {:ok, records} = Query.list_stale_processing()
      assert not Enum.any?(records, &(&1.id == processing.id))
    end
  end

  describe "list_expired/1" do
    test "lists expired records" do
      past = DateTime.add(DateTime.utc_now(), -100, :second)

      {:ok, expired} =
        Repo.insert(%Record{
          key: "expired_record",
          state: :completed,
          expires_at: past
        })

      assert {:ok, records} = Query.list_expired()
      assert Enum.any?(records, &(&1.id == expired.id))
    end
  end

  describe "stats/1" do
    test "returns statistics grouped by state" do
      assert {:ok, stats} = Query.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :pending) or Map.has_key?(stats, :processing)
    end
  end

  describe "stats_by_scope/1" do
    test "returns statistics grouped by scope and state" do
      assert {:ok, stats} = Query.stats_by_scope()

      assert is_map(stats)
      # Should have "test" scope from setup
      assert Map.has_key?(stats, "test")
      assert is_map(stats["test"])
    end
  end

  describe "list_older_than/2" do
    test "lists records older than specified age" do
      # Records created in setup are very recent
      age_ms = 100  # 100ms

      # Create an old record
      {:ok, old_record} =
        Repo.insert(%Record{
          key: "old_record",
          state: :completed,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          inserted_at: DateTime.add(DateTime.utc_now(), -1000, :second)
        })

      assert {:ok, records} = Query.list_older_than(500)
      assert Enum.any?(records, &(&1.id == old_record.id))
    end
  end

  describe "search_by_key/2" do
    test "searches records by key pattern" do
      {:ok, _} = OmIdempotency.create("order_123_charge")
      {:ok, _} = OmIdempotency.create("order_456_charge")
      {:ok, _} = OmIdempotency.create("user_789_update")

      assert {:ok, records} = Query.search_by_key("order_%")
      assert length(records) >= 2
      assert Enum.all?(records, &String.starts_with?(&1.key, "order_"))
    end

    test "searches with scope filter" do
      {:ok, _} = OmIdempotency.create("test_key", scope: "stripe")
      {:ok, _} = OmIdempotency.create("test_key", scope: "sendgrid")

      assert {:ok, records} = Query.search_by_key("test_%", scope: "stripe")
      assert Enum.all?(records, &(&1.scope == "stripe"))
    end
  end
end
