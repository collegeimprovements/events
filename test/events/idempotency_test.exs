defmodule Events.Infra.IdempotencyTest do
  use ExUnit.Case, async: true

  alias Events.Infra.Idempotency
  alias Events.Infra.Idempotency.Record

  # ============================================
  # Key Generation Tests
  # ============================================

  describe "generate_key/0" do
    test "generates a UUID" do
      key = Idempotency.generate_key()
      assert is_binary(key)
      assert String.length(key) == 36
      assert String.contains?(key, "-")
    end

    test "generates unique keys" do
      keys = for _ <- 1..100, do: Idempotency.generate_key()
      assert length(Enum.uniq(keys)) == 100
    end
  end

  describe "generate_key/2" do
    test "generates key from operation name" do
      key = Idempotency.generate_key(:create_customer)
      assert key == "create_customer"
    end

    test "generates key from operation and params" do
      key = Idempotency.generate_key(:create_customer, user_id: 123)
      assert key == "create_customer:user_id=123"
    end

    test "sorts params for deterministic keys" do
      key1 = Idempotency.generate_key(:charge, amount: 100, user_id: 123)
      key2 = Idempotency.generate_key(:charge, user_id: 123, amount: 100)
      assert key1 == key2
      assert key1 == "charge:amount=100:user_id=123"
    end

    test "adds scope prefix" do
      key = Idempotency.generate_key(:create_charge, order_id: 456, scope: "stripe")
      assert key == "stripe:create_charge:order_id=456"
    end

    test "handles multiple params" do
      key = Idempotency.generate_key(:transfer, from: "acc_1", to: "acc_2", amount: 500)
      assert key == "transfer:amount=500:from=acc_1:to=acc_2"
    end
  end

  describe "hash_key/3" do
    test "generates deterministic hash from params" do
      key1 = Idempotency.hash_key(:create_customer, %{email: "user@example.com"})
      key2 = Idempotency.hash_key(:create_customer, %{email: "user@example.com"})
      assert key1 == key2
    end

    test "different params produce different hashes" do
      key1 = Idempotency.hash_key(:create_customer, %{email: "user1@example.com"})
      key2 = Idempotency.hash_key(:create_customer, %{email: "user2@example.com"})
      refute key1 == key2
    end

    test "includes operation in key" do
      key = Idempotency.hash_key(:create_customer, %{email: "user@example.com"})
      assert String.starts_with?(key, "create_customer:")
    end

    test "hash is 32 characters" do
      key = Idempotency.hash_key(:op, %{data: "test"})
      [_op, hash] = String.split(key, ":")
      assert String.length(hash) == 32
    end

    test "adds scope prefix" do
      key = Idempotency.hash_key(:charge, %{amount: 100}, scope: "stripe")
      assert String.starts_with?(key, "stripe:charge:")
    end
  end

  # ============================================
  # Record State Tests
  # ============================================

  describe "Record.terminal?/1" do
    test "completed is terminal" do
      assert Record.terminal?(%Record{state: :completed})
    end

    test "failed is terminal" do
      assert Record.terminal?(%Record{state: :failed})
    end

    test "expired is terminal" do
      assert Record.terminal?(%Record{state: :expired})
    end

    test "pending is not terminal" do
      refute Record.terminal?(%Record{state: :pending})
    end

    test "processing is not terminal" do
      refute Record.terminal?(%Record{state: :processing})
    end
  end

  describe "Record.retriable?/1" do
    test "pending is retriable" do
      assert Record.retriable?(%Record{state: :pending})
    end

    test "processing with expired lock is retriable" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      assert Record.retriable?(%Record{state: :processing, locked_until: past})
    end

    test "processing with active lock is not retriable" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      refute Record.retriable?(%Record{state: :processing, locked_until: future})
    end

    test "completed is not retriable" do
      refute Record.retriable?(%Record{state: :completed})
    end

    test "failed is not retriable" do
      refute Record.retriable?(%Record{state: :failed})
    end
  end

  describe "Record.expired?/1" do
    test "past expiration is expired" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      assert Record.expired?(%Record{expires_at: past})
    end

    test "future expiration is not expired" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      refute Record.expired?(%Record{expires_at: future})
    end
  end

  # ============================================
  # Integration Tests (require database)
  # ============================================

  # These tests are tagged as :integration and require database setup
  # They test the full execute/3 flow

  describe "execute/3 integration" do
    @describetag :integration

    setup do
      # Would set up database sandbox here
      :ok
    end

    @tag :skip
    test "executes function on first call" do
      key = Idempotency.generate_key()

      result =
        Idempotency.execute(key, fn ->
          {:ok, %{id: "cus_123", email: "user@example.com"}}
        end)

      assert {:ok, %{id: "cus_123"}} = result
    end

    @tag :skip
    test "returns cached response on duplicate call" do
      key = Idempotency.generate_key()

      # First call
      Idempotency.execute(key, fn ->
        {:ok, %{id: "cus_123"}}
      end)

      # Second call - should not execute function
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Idempotency.execute(key, fn ->
          Agent.update(counter, &(&1 + 1))
          {:ok, %{id: "cus_456"}}
        end)

      assert {:ok, %{id: "cus_123"}} = result
      assert Agent.get(counter, & &1) == 0
      Agent.stop(counter)
    end

    @tag :skip
    test "scoped keys are independent" do
      key = Idempotency.generate_key(:create, user_id: 1)

      Idempotency.execute(key, fn -> {:ok, %{scope: "stripe"}} end, scope: "stripe")
      Idempotency.execute(key, fn -> {:ok, %{scope: "sendgrid"}} end, scope: "sendgrid")

      {:ok, stripe_record} = Idempotency.get(key, "stripe")
      {:ok, sendgrid_record} = Idempotency.get(key, "sendgrid")

      assert stripe_record.response != sendgrid_record.response
    end
  end
end
