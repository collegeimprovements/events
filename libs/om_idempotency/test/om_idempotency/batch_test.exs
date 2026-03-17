defmodule OmIdempotency.BatchTest do
  use OmIdempotency.DataCase, async: true

  alias OmIdempotency
  alias OmIdempotency.Batch

  describe "create_all/2" do
    test "creates multiple records in bulk" do
      key_opts_pairs = [
        {"batch_key_1", scope: "test", metadata: %{index: 1}},
        {"batch_key_2", scope: "test", metadata: %{index: 2}},
        {"batch_key_3", scope: "test", metadata: %{index: 3}}
      ]

      assert {:ok, records} = Batch.create_all(key_opts_pairs)
      assert length(records) == 3

      # Verify all were created
      assert {:ok, _} = OmIdempotency.get("batch_key_1", "test")
      assert {:ok, _} = OmIdempotency.get("batch_key_2", "test")
      assert {:ok, _} = OmIdempotency.get("batch_key_3", "test")
    end

    test "handles duplicate keys gracefully" do
      {:ok, _} = OmIdempotency.create("existing_key", scope: "test")

      key_opts_pairs = [
        {"existing_key", scope: "test"},
        {"new_key", scope: "test"}
      ]

      # Should use on_conflict: :nothing, so it doesn't error
      assert {:ok, records} = Batch.create_all(key_opts_pairs)
    end
  end

  describe "complete_all/2" do
    test "completes multiple records in a transaction" do
      {:ok, r1} = OmIdempotency.create("complete_1")
      {:ok, r2} = OmIdempotency.create("complete_2")

      {:ok, p1} = OmIdempotency.start_processing(r1)
      {:ok, p2} = OmIdempotency.start_processing(r2)

      record_response_pairs = [
        {p1, %{result: "success1"}},
        {p2, %{result: "success2"}}
      ]

      assert {:ok, results} = Batch.complete_all(record_response_pairs)
      assert map_size(results) == 2

      {:ok, completed1} = OmIdempotency.get("complete_1")
      {:ok, completed2} = OmIdempotency.get("complete_2")

      assert completed1.state == :completed
      assert completed2.state == :completed
    end
  end

  describe "fail_all/2" do
    test "fails multiple records in a transaction" do
      {:ok, r1} = OmIdempotency.create("fail_1")
      {:ok, r2} = OmIdempotency.create("fail_2")

      {:ok, p1} = OmIdempotency.start_processing(r1)
      {:ok, p2} = OmIdempotency.start_processing(r2)

      record_error_pairs = [
        {p1, "Error 1"},
        {p2, "Error 2"}
      ]

      assert {:ok, results} = Batch.fail_all(record_error_pairs)

      {:ok, failed1} = OmIdempotency.get("fail_1")
      {:ok, failed2} = OmIdempotency.get("fail_2")

      assert failed1.state == :failed
      assert failed2.state == :failed
    end
  end

  describe "check_many/2" do
    test "checks multiple keys in parallel" do
      {:ok, _} = OmIdempotency.create("check_1", scope: "test")
      {:ok, _} = OmIdempotency.create("check_2", scope: "test")

      key_scope_pairs = [
        {"check_1", "test"},
        {"check_2", "test"},
        {"nonexistent", "test"}
      ]

      assert {:ok, results} = Batch.check_many(key_scope_pairs)
      assert length(results) == 3

      assert match?({:ok, %OmIdempotency.Record{}}, Enum.at(results, 0))
      assert match?({:ok, %OmIdempotency.Record{}}, Enum.at(results, 1))
      assert match?({:error, :not_found}, Enum.at(results, 2))
    end
  end

  describe "execute_all/2" do
    test "executes multiple operations in parallel" do
      operations = [
        {"exec_1", fn -> {:ok, "result1"} end, [scope: "test"]},
        {"exec_2", fn -> {:ok, "result2"} end, [scope: "test"]},
        {"exec_3", fn -> {:ok, "result3"} end, [scope: "test"]}
      ]

      assert {:ok, results} = Batch.execute_all(operations)
      assert results == [{:ok, "result1"}, {:ok, "result2"}, {:ok, "result3"}]
    end

    test "handles mixed success and failure" do
      operations = [
        {"mixed_1", fn -> {:ok, "success"} end, []},
        {"mixed_2", fn -> {:error, "failed"} end, []}
      ]

      assert {:ok, results} = Batch.execute_all(operations)
      assert results == [{:ok, "success"}, {:error, "failed"}]
    end
  end

  describe "release_all/2" do
    test "releases multiple locks in a transaction" do
      {:ok, r1} = OmIdempotency.create("release_1")
      {:ok, r2} = OmIdempotency.create("release_2")

      {:ok, p1} = OmIdempotency.start_processing(r1)
      {:ok, p2} = OmIdempotency.start_processing(r2)

      assert {:ok, _} = Batch.release_all([p1, p2])

      {:ok, released1} = OmIdempotency.get("release_1")
      {:ok, released2} = OmIdempotency.get("release_2")

      assert released1.state == :pending
      assert released2.state == :pending
    end
  end
end
