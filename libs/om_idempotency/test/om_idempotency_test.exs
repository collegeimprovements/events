defmodule OmIdempotencyTest do
  use OmIdempotency.DataCase, async: true

  alias OmIdempotency
  alias OmIdempotency.Record

  describe "generate_key/0" do
    test "generates a UUIDv7" do
      key = OmIdempotency.generate_key()
      assert is_binary(key)
      assert String.length(key) == 36
    end

    test "generates unique keys" do
      key1 = OmIdempotency.generate_key()
      key2 = OmIdempotency.generate_key()
      assert key1 != key2
    end
  end

  describe "generate_key/2" do
    test "generates deterministic key from operation and params" do
      key1 = OmIdempotency.generate_key(:create_user, user_id: 123, email: "test@example.com")
      key2 = OmIdempotency.generate_key(:create_user, user_id: 123, email: "test@example.com")

      assert key1 == key2
      assert key1 == "create_user:email=test@example.com:user_id=123"
    end

    test "generates different keys for different params" do
      key1 = OmIdempotency.generate_key(:create_user, user_id: 123)
      key2 = OmIdempotency.generate_key(:create_user, user_id: 456)

      assert key1 != key2
    end

    test "includes scope in key" do
      key = OmIdempotency.generate_key(:charge, order_id: 123, scope: "stripe")
      assert key == "stripe:charge:order_id=123"
    end

    test "operation only without params" do
      key = OmIdempotency.generate_key(:send_welcome_email)
      assert key == "send_welcome_email"
    end
  end

  describe "hash_key/3" do
    test "generates deterministic hash key" do
      key1 = OmIdempotency.hash_key(:process, %{data: "test"})
      key2 = OmIdempotency.hash_key(:process, %{data: "test"})

      assert key1 == key2
      assert String.starts_with?(key1, "process:")
    end

    test "generates different keys for different data" do
      key1 = OmIdempotency.hash_key(:process, %{data: "test1"})
      key2 = OmIdempotency.hash_key(:process, %{data: "test2"})

      assert key1 != key2
    end

    test "includes scope in hash key" do
      key = OmIdempotency.hash_key(:webhook, %{event_id: "123"}, scope: "stripe")
      assert String.starts_with?(key, "stripe:webhook:")
    end
  end

  describe "create/2" do
    test "creates a new idempotency record" do
      assert {:ok, record} = OmIdempotency.create("test_key", scope: "test")

      assert record.key == "test_key"
      assert record.scope == "test"
      assert record.state == :pending
      assert record.version == 1
    end

    test "returns error if key already exists" do
      {:ok, _} = OmIdempotency.create("duplicate_key")
      assert {:error, :already_exists} = OmIdempotency.create("duplicate_key")
    end

    test "sets metadata" do
      metadata = %{user_id: 123, ip: "192.168.1.1"}
      {:ok, record} = OmIdempotency.create("meta_key", metadata: metadata)

      assert record.metadata == metadata
    end

    test "sets expires_at from TTL" do
      ttl = :timer.hours(1)
      {:ok, record} = OmIdempotency.create("ttl_key", ttl: ttl)

      now = DateTime.utc_now()
      expected = DateTime.add(now, ttl, :millisecond)

      # Allow 1 second tolerance
      assert DateTime.diff(record.expires_at, expected, :second) <= 1
    end
  end

  describe "get/3" do
    test "returns record when found" do
      {:ok, created} = OmIdempotency.create("get_key")

      assert {:ok, fetched} = OmIdempotency.get("get_key")
      assert fetched.id == created.id
    end

    test "returns not_found when record doesn't exist" do
      assert {:error, :not_found} = OmIdempotency.get("nonexistent")
    end

    test "filters by scope" do
      {:ok, _} = OmIdempotency.create("scoped_key", scope: "stripe")

      assert {:ok, _} = OmIdempotency.get("scoped_key", "stripe")
      assert {:error, :not_found} = OmIdempotency.get("scoped_key", "sendgrid")
      assert {:error, :not_found} = OmIdempotency.get("scoped_key", nil)
    end
  end

  describe "start_processing/2" do
    test "transitions pending to processing" do
      {:ok, record} = OmIdempotency.create("processing_key")

      assert {:ok, processing} = OmIdempotency.start_processing(record)
      assert processing.state == :processing
      assert processing.version == 2
      assert processing.started_at
      assert processing.locked_until
    end

    test "returns error if already processing" do
      {:ok, record} = OmIdempotency.create("dup_key")
      {:ok, processing} = OmIdempotency.start_processing(record)

      assert {:error, :already_processing} = OmIdempotency.start_processing(processing)
    end

    test "returns stale error if version mismatch" do
      {:ok, record} = OmIdempotency.create("stale_key")
      {:ok, _} = OmIdempotency.start_processing(record)

      # Try with stale record
      assert {:error, :stale} = OmIdempotency.start_processing(record)
    end
  end

  describe "complete/3" do
    test "marks record as completed with response" do
      {:ok, record} = OmIdempotency.create("complete_key")
      {:ok, processing} = OmIdempotency.start_processing(record)

      response = %{user_id: 123, status: "success"}
      assert {:ok, completed} = OmIdempotency.complete(processing, response)

      assert completed.state == :completed
      assert completed.response == %{ok: response}
      assert completed.completed_at
    end
  end

  describe "fail/3" do
    test "marks record as failed with error" do
      {:ok, record} = OmIdempotency.create("fail_key")
      {:ok, processing} = OmIdempotency.start_processing(record)

      error = "Connection timeout"
      assert {:ok, failed} = OmIdempotency.fail(processing, error)

      assert failed.state == :failed
      assert failed.error
      assert failed.completed_at
    end
  end

  describe "release/2" do
    test "returns processing record to pending state" do
      {:ok, record} = OmIdempotency.create("release_key")
      {:ok, processing} = OmIdempotency.start_processing(record)

      assert {:ok, released} = OmIdempotency.release(processing)

      assert released.state == :pending
      assert is_nil(released.locked_until)
      assert is_nil(released.started_at)
    end
  end

  describe "execute/3" do
    test "executes function and caches result" do
      key = "exec_key_#{:rand.uniform(10000)}"
      call_count = :counters.new(1, [])

      result =
        OmIdempotency.execute(key, fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "result"}
        end)

      assert {:ok, "result"} = result
      assert :counters.get(call_count, 1) == 1

      # Second call should return cached result without executing
      result2 = OmIdempotency.execute(key, fn ->
        :counters.add(call_count, 1, 1)
        {:ok, "result2"}
      end)

      assert {:ok, "result"} = result2
      assert :counters.get(call_count, 1) == 1
    end

    test "handles error responses" do
      key = "error_key_#{:rand.uniform(10000)}"

      result =
        OmIdempotency.execute(key, fn ->
          {:error, :something_failed}
        end)

      assert {:error, :something_failed} = result
    end

    test "on_duplicate: :return strategy" do
      key = "dup_return_#{:rand.uniform(10000)}"

      # Start long-running operation
      task =
        Task.async(fn ->
          OmIdempotency.execute(key, fn ->
            Process.sleep(500)
            {:ok, "slow"}
          end)
        end)

      # Give it time to start
      Process.sleep(50)

      # Try duplicate
      result =
        OmIdempotency.execute(key, fn ->
          {:ok, "fast"}
        end, on_duplicate: :return)

      assert {:error, {:in_progress, %Record{}}} = result

      Task.await(task)
    end

    test "on_duplicate: :wait strategy" do
      key = "dup_wait_#{:rand.uniform(10000)}"

      # Start operation that will complete
      Task.async(fn ->
        OmIdempotency.execute(key, fn ->
          Process.sleep(200)
          {:ok, "first"}
        end)
      end)

      # Give it time to start
      Process.sleep(50)

      # Wait for completion
      result =
        OmIdempotency.execute(key, fn ->
          {:ok, "second"}
        end,
          on_duplicate: :wait,
          wait_timeout: 1_000
        )

      assert {:ok, "first"} = result
    end

    test "on_duplicate: :error strategy" do
      key = "dup_error_#{:rand.uniform(10000)}"

      Task.async(fn ->
        OmIdempotency.execute(key, fn ->
          Process.sleep(500)
          {:ok, "slow"}
        end)
      end)

      Process.sleep(50)

      result =
        OmIdempotency.execute(key, fn ->
          {:ok, "fast"}
        end, on_duplicate: :error)

      assert {:error, :in_progress} = result
    end

    test "includes metadata in record" do
      key = "meta_exec_#{:rand.uniform(10000)}"
      metadata = %{request_id: "req_123", user_id: 456}

      OmIdempotency.execute(
        key,
        fn -> {:ok, "result"} end,
        metadata: metadata
      )

      {:ok, record} = OmIdempotency.get(key)
      assert record.metadata == metadata
    end
  end

  describe "cleanup_expired/1" do
    test "deletes expired records" do
      # Create expired record
      past = DateTime.add(DateTime.utc_now(), -100, :second)

      {:ok, record} =
        Repo.insert(%Record{
          key: "expired_key",
          state: :completed,
          expires_at: past
        })

      assert {:ok, count} = OmIdempotency.cleanup_expired()
      assert count >= 1

      assert {:error, :not_found} = OmIdempotency.get("expired_key")
    end

    test "does not delete non-expired records" do
      {:ok, _} = OmIdempotency.create("not_expired", ttl: :timer.hours(1))

      {:ok, count_before} =
        Repo.aggregate(Record, :count, :id)
        |> then(&{:ok, &1})

      {:ok, _deleted} = OmIdempotency.cleanup_expired()

      {:ok, count_after} =
        Repo.aggregate(Record, :count, :id)
        |> then(&{:ok, &1})

      assert count_before == count_after
    end
  end

  describe "recover_stale/1" do
    test "recovers stale processing records" do
      past = DateTime.add(DateTime.utc_now(), -100, :second)

      {:ok, record} =
        Repo.insert(%Record{
          key: "stale_key",
          state: :processing,
          locked_until: past,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:ok, count} = OmIdempotency.recover_stale()
      assert count >= 1

      {:ok, recovered} = OmIdempotency.get("stale_key")
      assert recovered.state == :pending
    end

    test "does not recover non-stale records" do
      future = DateTime.add(DateTime.utc_now(), 100, :second)

      {:ok, record} =
        Repo.insert(%Record{
          key: "fresh_key",
          state: :processing,
          locked_until: future,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, _} = OmIdempotency.recover_stale()

      {:ok, still_processing} = OmIdempotency.get("fresh_key")
      assert still_processing.state == :processing
    end
  end
end
