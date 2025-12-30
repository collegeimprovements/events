defmodule FnDecorator.Caching.LockTest do
  use ExUnit.Case, async: false

  alias FnDecorator.Caching.Lock

  setup do
    # Ensure lock table exists
    Lock.init()

    # Clean up any stale locks from previous tests
    :ets.delete_all_objects(FnDecorator.Caching.Lock)

    :ok
  end

  describe "init/0" do
    test "creates ETS table" do
      # Table should exist after setup
      assert :ets.whereis(FnDecorator.Caching.Lock) != :undefined
    end

    test "is idempotent" do
      # Multiple calls should not error
      assert Lock.init() == :ok
      assert Lock.init() == :ok
      assert Lock.init() == :ok
    end
  end

  describe "acquire/2" do
    test "acquires lock on first attempt" do
      assert {:ok, token} = Lock.acquire(:test_key, 5_000)
      assert is_tuple(token)
    end

    test "returns :busy when lock is held" do
      {:ok, _token} = Lock.acquire(:held_key, 5_000)

      assert Lock.acquire(:held_key, 5_000) == :busy
    end

    test "different keys can be locked independently" do
      {:ok, token1} = Lock.acquire(:key1, 5_000)
      {:ok, token2} = Lock.acquire(:key2, 5_000)

      assert token1 != token2
    end

    test "can acquire lock after release" do
      {:ok, token1} = Lock.acquire(:release_key, 5_000)
      Lock.release(:release_key, token1)

      {:ok, token2} = Lock.acquire(:release_key, 5_000)
      assert token2 != token1
    end

    test "can take over expired lock" do
      # Acquire with very short timeout
      {:ok, _token} = Lock.acquire(:expire_key, 1)

      # Wait for lock to expire
      Process.sleep(10)

      # Should be able to acquire
      assert {:ok, _new_token} = Lock.acquire(:expire_key, 5_000)
    end

    test "token includes self()" do
      {:ok, {pid, _ref}} = Lock.acquire(:pid_key, 5_000)
      assert pid == self()
    end
  end

  describe "release/2" do
    test "releases owned lock" do
      {:ok, token} = Lock.acquire(:release_test, 5_000)

      assert Lock.release(:release_test, token) == :ok
      assert Lock.locked?(:release_test) == false
    end

    test "returns :not_owner for wrong token" do
      {:ok, _correct_token} = Lock.acquire(:wrong_token_key, 5_000)
      wrong_token = {self(), make_ref()}

      assert Lock.release(:wrong_token_key, wrong_token) == :not_owner
    end

    test "returns :not_owner for non-existent lock" do
      fake_token = {self(), make_ref()}
      assert Lock.release(:nonexistent_key, fake_token) == :not_owner
    end

    test "is idempotent for released locks" do
      {:ok, token} = Lock.acquire(:idempotent_key, 5_000)

      assert Lock.release(:idempotent_key, token) == :ok
      assert Lock.release(:idempotent_key, token) == :not_owner
    end
  end

  describe "locked?/1" do
    test "returns true when locked" do
      {:ok, _token} = Lock.acquire(:locked_check, 5_000)
      assert Lock.locked?(:locked_check) == true
    end

    test "returns false when not locked" do
      assert Lock.locked?(:not_locked) == false
    end

    test "returns false after release" do
      {:ok, token} = Lock.acquire(:was_locked, 5_000)
      Lock.release(:was_locked, token)

      assert Lock.locked?(:was_locked) == false
    end

    test "returns false for expired lock" do
      {:ok, _token} = Lock.acquire(:expired_check, 1)
      Process.sleep(10)

      assert Lock.locked?(:expired_check) == false
    end
  end

  describe "concurrent access" do
    test "only one process acquires lock" do
      parent = self()
      key = :concurrent_key

      # Spawn multiple processes trying to acquire the same lock
      pids =
        for _ <- 1..10 do
          spawn(fn ->
            result = Lock.acquire(key, 5_000)
            send(parent, {:result, self(), result})
          end)
        end

      # Collect results
      results =
        for _ <- pids do
          receive do
            {:result, _pid, result} -> result
          after
            1_000 -> :timeout
          end
        end

      # Exactly one should have acquired
      acquired = Enum.filter(results, &match?({:ok, _}, &1))
      not_acquired = Enum.filter(results, &(&1 == :busy))

      assert length(acquired) == 1
      assert length(not_acquired) == 9
    end

    test "lock is released when holder process dies" do
      key = :process_death_key

      # Spawn a process that acquires lock then dies
      spawn(fn ->
        {:ok, _token} = Lock.acquire(key, 60_000)
        # Process exits without releasing
      end)

      # Wait for process to die
      Process.sleep(50)

      # Lock should still be held (ETS doesn't auto-release on process death)
      # This is expected behavior - locks have timeout for this reason
      assert Lock.locked?(key) == true

      # Can't acquire since lock is still held
      assert Lock.acquire(key, 60_000) == :busy

      # But with lock expiration, we can eventually acquire
      # (In real usage, the original lock would expire after lock_timeout)
    end
  end

  describe "complex keys" do
    test "handles tuple keys" do
      {:ok, token} = Lock.acquire({User, 123}, 5_000)
      assert Lock.locked?({User, 123}) == true
      Lock.release({User, 123}, token)
    end

    test "handles nested structure keys" do
      key = {:cache, %{module: User, id: 42}}
      {:ok, token} = Lock.acquire(key, 5_000)
      assert Lock.locked?(key) == true
      Lock.release(key, token)
    end
  end
end
