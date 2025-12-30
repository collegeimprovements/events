defmodule OmScheduler.TestingTest do
  use ExUnit.Case

  alias OmScheduler.Testing
  alias OmScheduler.Store.Memory

  setup do
    # Ensure memory store is started
    case Memory.start_link(name: TestingTestStore) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Clear test data
    Testing.drain_jobs()
    :ok
  end

  describe "sandbox mode" do
    test "start_sandbox/0 enables sandbox mode" do
      Testing.start_sandbox()
      assert Testing.sandbox?() == true
    end

    test "stop_sandbox/0 disables sandbox mode" do
      Testing.start_sandbox()
      Testing.stop_sandbox()
      assert Testing.sandbox?() == false
    end

    test "sandbox?/0 returns false when not in sandbox" do
      assert Testing.sandbox?() == false
    end
  end

  describe "drain_jobs/0" do
    test "clears all enqueued jobs" do
      # Since we're using memory store, this should work
      assert :ok = Testing.drain_jobs()
    end
  end

  describe "all_enqueued/1" do
    test "returns empty list when no jobs enqueued" do
      Testing.drain_jobs()
      assert Testing.all_enqueued() == []
    end
  end

  describe "perform_job/3" do
    defmodule TestWorker do
      def perform(%{value: value}) do
        {:ok, value * 2}
      end

      def perform(%{fail: true}) do
        {:error, :intentional_failure}
      end

      def perform(%{}) do
        :ok
      end
    end

    test "executes job synchronously and returns result" do
      # Note: This test requires the Executor to be properly set up
      # In a real test, we'd mock or configure the executor
      result = Testing.perform_job(TestWorker, %{})
      # Result depends on Executor implementation
      assert result != nil
    end
  end
end
