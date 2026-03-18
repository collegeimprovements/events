defmodule OmBehaviours.HealthCheckTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.HealthCheck

  # --- Test support modules ---

  defmodule HealthyCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :healthy_service

    @impl true
    def severity, do: :critical

    @impl true
    def check, do: {:ok, %{latency_ms: 1, connections: 5}}
  end

  defmodule UnhealthyCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :unhealthy_service

    @impl true
    def severity, do: :critical

    @impl true
    def check, do: {:error, :connection_refused}
  end

  defmodule WarningCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :cache

    @impl true
    def severity, do: :warning

    @impl true
    def check, do: {:ok, %{hit_rate: 0.95}}

    @impl true
    def timeout, do: 2_000
  end

  defmodule InfoCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :disk_usage

    @impl true
    def severity, do: :info

    @impl true
    def check, do: {:ok, %{used_percent: 42}}
  end

  defmodule SlowCheck do
    use OmBehaviours.HealthCheck

    @impl true
    def name, do: :slow_service

    @impl true
    def severity, do: :warning

    @impl true
    def check do
      Process.sleep(10_000)
      {:ok, %{}}
    end

    @impl true
    def timeout, do: 100
  end

  defmodule ManualCheck do
    @behaviour OmBehaviours.HealthCheck

    @impl true
    def name, do: :manual

    @impl true
    def severity, do: :info

    @impl true
    def check, do: {:ok, %{manual: true}}

    @impl true
    def timeout, do: 5_000
  end

  defmodule PlainModule do
    def hello, do: :world
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules using HealthCheck" do
      assert HealthCheck.implements?(HealthyCheck)
      assert HealthCheck.implements?(UnhealthyCheck)
      assert HealthCheck.implements?(WarningCheck)
      assert HealthCheck.implements?(InfoCheck)
    end

    test "returns true for modules with @behaviour directly" do
      assert HealthCheck.implements?(ManualCheck)
    end

    test "returns false for plain modules" do
      refute HealthCheck.implements?(PlainModule)
    end

    test "returns false for non-existent modules" do
      refute HealthCheck.implements?(NonExistent.HealthCheck)
    end
  end

  # --- name/0 tests ---

  describe "name/0" do
    test "returns the configured atom name" do
      assert HealthyCheck.name() == :healthy_service
      assert UnhealthyCheck.name() == :unhealthy_service
      assert WarningCheck.name() == :cache
      assert InfoCheck.name() == :disk_usage
    end
  end

  # --- severity/0 tests ---

  describe "severity/0" do
    test "returns :critical for critical checks" do
      assert HealthyCheck.severity() == :critical
      assert UnhealthyCheck.severity() == :critical
    end

    test "returns :warning for warning checks" do
      assert WarningCheck.severity() == :warning
    end

    test "returns :info for informational checks" do
      assert InfoCheck.severity() == :info
    end
  end

  # --- check/0 tests ---

  describe "check/0" do
    test "returns {:ok, details} when healthy" do
      assert {:ok, %{latency_ms: 1, connections: 5}} = HealthyCheck.check()
    end

    test "returns {:error, reason} when unhealthy" do
      assert {:error, :connection_refused} = UnhealthyCheck.check()
    end

    test "returns {:ok, details} with metrics" do
      assert {:ok, %{hit_rate: 0.95}} = WarningCheck.check()
    end
  end

  # --- timeout/0 tests ---

  describe "timeout/0" do
    test "default is 5 seconds" do
      assert HealthyCheck.timeout() == 5_000
    end

    test "can be overridden" do
      assert WarningCheck.timeout() == 2_000
    end

    test "manual implementation works" do
      assert ManualCheck.timeout() == 5_000
    end
  end

  # --- __using__ macro ---

  describe "__using__ macro" do
    test "injects @behaviour OmBehaviours.HealthCheck" do
      behaviours =
        HealthyCheck.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert OmBehaviours.HealthCheck in behaviours
    end

    test "provides default timeout of 5 seconds" do
      assert HealthyCheck.timeout() == 5_000
    end

    test "timeout is overridable" do
      assert WarningCheck.timeout() == 2_000
    end
  end

  # --- run/1 tests ---

  describe "run/1" do
    test "returns healthy result with details" do
      {:ok, result} = HealthCheck.run(HealthyCheck)

      assert result.name == :healthy_service
      assert result.severity == :critical
      assert result.status == :healthy
      assert result.details == %{latency_ms: 1, connections: 5}
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "returns unhealthy result with error" do
      {:ok, result} = HealthCheck.run(UnhealthyCheck)

      assert result.name == :unhealthy_service
      assert result.severity == :critical
      assert result.status == :unhealthy
      assert result.error == :connection_refused
      assert is_integer(result.duration_ms)
    end

    test "returns timeout result for slow checks" do
      {:ok, result} = HealthCheck.run(SlowCheck)

      assert result.name == :slow_service
      assert result.severity == :warning
      assert result.status == :timeout
      assert is_integer(result.duration_ms)
    end

    test "includes duration_ms in all results" do
      {:ok, healthy} = HealthCheck.run(HealthyCheck)
      {:ok, unhealthy} = HealthCheck.run(UnhealthyCheck)

      assert is_integer(healthy.duration_ms)
      assert is_integer(unhealthy.duration_ms)
    end
  end

  # --- run_all/1 tests ---

  describe "run_all/1" do
    test "runs multiple checks concurrently" do
      results = HealthCheck.run_all([HealthyCheck, UnhealthyCheck, WarningCheck, InfoCheck])

      assert length(results) == 4

      names = Enum.map(results, & &1.name)
      assert :healthy_service in names
      assert :unhealthy_service in names
      assert :cache in names
      assert :disk_usage in names
    end

    test "returns correct status for each check" do
      results = HealthCheck.run_all([HealthyCheck, UnhealthyCheck])

      healthy = Enum.find(results, &(&1.name == :healthy_service))
      unhealthy = Enum.find(results, &(&1.name == :unhealthy_service))

      assert healthy.status == :healthy
      assert unhealthy.status == :unhealthy
    end

    test "returns empty list for no checks" do
      assert [] = HealthCheck.run_all([])
    end

    test "handles timeout checks in run_all" do
      results = HealthCheck.run_all([HealthyCheck, SlowCheck])

      assert length(results) == 2

      slow = Enum.find(results, &(&1.name == :slow_service))
      assert slow.status == :timeout
    end
  end
end
