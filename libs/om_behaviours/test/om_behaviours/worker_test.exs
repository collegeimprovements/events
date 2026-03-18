defmodule OmBehaviours.WorkerTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.Worker

  # --- Test support modules ---

  defmodule SimpleWorker do
    use OmBehaviours.Worker

    @impl true
    def perform(%{value: value}), do: {:ok, value * 2}
    def perform(%{fail: reason}), do: {:error, reason}
  end

  defmodule ScheduledWorker do
    use OmBehaviours.Worker

    @impl true
    def perform(_args), do: {:ok, :done}

    @impl true
    def schedule, do: "0 3 * * *"

    @impl true
    def backoff(attempt), do: 500 * (attempt + 1)

    @impl true
    def timeout, do: 120_000
  end

  defmodule ManualWorker do
    @behaviour OmBehaviours.Worker

    @impl true
    def perform(%{data: data}), do: {:ok, data}

    @impl true
    def schedule, do: "*/5 * * * *"

    @impl true
    def backoff(attempt), do: 1000 * attempt

    @impl true
    def timeout, do: 10_000
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules using Worker" do
      assert Worker.implements?(SimpleWorker)
      assert Worker.implements?(ScheduledWorker)
    end

    test "returns true for modules with @behaviour directly" do
      assert Worker.implements?(ManualWorker)
    end

    test "returns false for plain modules" do
      refute Worker.implements?(PlainModule)
    end

    test "returns false for non-existent modules" do
      refute Worker.implements?(NonExistent.Worker)
    end
  end

  # --- perform/1 tests ---

  describe "perform/1" do
    test "returns {:ok, result} on success" do
      assert {:ok, 10} = SimpleWorker.perform(%{value: 5})
    end

    test "returns {:error, reason} on failure" do
      assert {:error, :boom} = SimpleWorker.perform(%{fail: :boom})
    end

    test "manual worker performs correctly" do
      assert {:ok, "hello"} = ManualWorker.perform(%{data: "hello"})
    end
  end

  # --- schedule/0 tests ---

  describe "schedule/0" do
    test "default is nil (no schedule)" do
      assert SimpleWorker.schedule() == nil
    end

    test "can be overridden with cron expression" do
      assert ScheduledWorker.schedule() == "0 3 * * *"
    end

    test "manual implementation works" do
      assert ManualWorker.schedule() == "*/5 * * * *"
    end
  end

  # --- backoff/1 tests ---

  describe "backoff/1" do
    test "default uses exponential backoff" do
      assert SimpleWorker.backoff(0) == 1_000
      assert SimpleWorker.backoff(1) == 2_000
      assert SimpleWorker.backoff(2) == 4_000
      assert SimpleWorker.backoff(3) == 8_000
    end

    test "default caps at 30 seconds" do
      assert SimpleWorker.backoff(100) == 30_000
    end

    test "can be overridden" do
      assert ScheduledWorker.backoff(0) == 500
      assert ScheduledWorker.backoff(1) == 1_000
      assert ScheduledWorker.backoff(4) == 2_500
    end

    test "manual implementation works" do
      assert ManualWorker.backoff(0) == 0
      assert ManualWorker.backoff(3) == 3_000
    end
  end

  # --- timeout/0 tests ---

  describe "timeout/0" do
    test "default is 60 seconds" do
      assert SimpleWorker.timeout() == 60_000
    end

    test "can be overridden" do
      assert ScheduledWorker.timeout() == 120_000
    end

    test "manual implementation works" do
      assert ManualWorker.timeout() == 10_000
    end
  end

  # --- __using__ macro ---

  describe "__using__ macro" do
    test "injects @behaviour OmBehaviours.Worker" do
      behaviours =
        SimpleWorker.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert OmBehaviours.Worker in behaviours
    end

    test "provides default schedule, backoff, and timeout" do
      # These are the defaults from `use`
      assert SimpleWorker.schedule() == nil
      assert SimpleWorker.backoff(0) == 1_000
      assert SimpleWorker.timeout() == 60_000
    end

    test "defaults are overridable" do
      # ScheduledWorker overrides all three
      assert ScheduledWorker.schedule() == "0 3 * * *"
      assert ScheduledWorker.backoff(0) == 500
      assert ScheduledWorker.timeout() == 120_000
    end
  end
end
