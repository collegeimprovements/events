defmodule OmHealthTest do
  @moduledoc """
  Tests for OmHealth - Declarative health check system.

  OmHealth provides a DSL for defining service health checks with support
  for critical vs non-critical services, proxy detection, and environment info.

  ## Use Cases

  - **Load balancer health**: `/health` endpoint for traffic routing
  - **Kubernetes probes**: Liveness and readiness checks
  - **Service monitoring**: Dashboard showing all dependency statuses
  - **Graceful degradation**: Continue operation when non-critical services fail

  ## Pattern: Declarative Health Definition

      defmodule MyApp.Health do
        use OmHealth

        config do
          app_name :my_app
        end

        services do
          service :database, type: :postgres, critical: true
          service :cache, type: :redis, critical: false
          service :api, type: :custom, check: {ApiClient, :ping}
        end
      end

      # Usage:
      MyApp.Health.overall_status()  # => :healthy | :degraded | :unhealthy
      MyApp.Health.check_all()       # => %{services: [...], environment: ..., proxy: ...}

  Returns :healthy (all ok), :degraded (non-critical failed), or :unhealthy (critical failed).
  """

  use ExUnit.Case, async: true

  describe "DSL" do
    defmodule TestChecks do
      def database_check, do: :ok
      def cache_check, do: {:ok, "Connected"}
      def failing_check, do: {:error, "Connection refused"}
    end

    defmodule TestHealth do
      use OmHealth

      config do
        app_name :test_app
      end

      services do
        service :database,
          type: :custom,
          critical: true,
          check: {OmHealthTest.TestChecks, :database_check}

        service :cache,
          type: :custom,
          critical: false,
          check: {OmHealthTest.TestChecks, :cache_check}
      end
    end

    test "defines __config__/0" do
      config = TestHealth.__config__()
      assert config.app_name == :test_app
    end

    test "defines __services__/0" do
      services = TestHealth.__services__()
      assert length(services) == 2

      [db, cache] = services
      assert db.name == "Database"
      assert db.critical == true

      assert cache.name == "Cache"
      assert cache.critical == false
    end

    test "check_all/0 runs health checks" do
      result = TestHealth.check_all()

      assert %{services: services, environment: env, proxy: proxy} = result
      assert is_list(services)
      assert length(services) == 2
      assert is_map(env)
      assert is_map(proxy)
      assert %DateTime{} = result.timestamp
      assert is_integer(result.duration_ms)
    end

    test "overall_status/0 returns health status" do
      status = TestHealth.overall_status()
      assert status in [:healthy, :degraded, :unhealthy]
    end
  end

  describe "compute_overall_status/1" do
    test "returns :healthy when all services are ok" do
      result = %{
        services: [
          %{name: "DB", status: :ok, critical: true},
          %{name: "Cache", status: :ok, critical: false}
        ]
      }

      assert OmHealth.compute_overall_status(result) == :healthy
    end

    test "returns :unhealthy when critical service fails" do
      result = %{
        services: [
          %{name: "DB", status: :error, critical: true},
          %{name: "Cache", status: :ok, critical: false}
        ]
      }

      assert OmHealth.compute_overall_status(result) == :unhealthy
    end

    test "returns :degraded when only non-critical service fails" do
      result = %{
        services: [
          %{name: "DB", status: :ok, critical: true},
          %{name: "Cache", status: :error, critical: false}
        ]
      }

      assert OmHealth.compute_overall_status(result) == :degraded
    end
  end

  describe "run_checks/2" do
    test "runs custom check with MFA tuple" do
      services = [
        %{name: "Test", type: :custom, critical: false, check: {OmHealthTest.TestChecks, :database_check}}
      ]

      result = OmHealth.run_checks(services, %{})

      assert [service] = result.services
      assert service.status == :ok
      assert service.adapter == "Custom"
    end

    test "handles custom check returning {:ok, info}" do
      services = [
        %{name: "Test", type: :custom, critical: false, check: {OmHealthTest.TestChecks, :cache_check}}
      ]

      result = OmHealth.run_checks(services, %{})

      assert [service] = result.services
      assert service.status == :ok
      assert service.info == "Connected"
    end

    test "handles custom check returning error" do
      services = [
        %{name: "Test", type: :custom, critical: true, check: {OmHealthTest.TestChecks, :failing_check}}
      ]

      result = OmHealth.run_checks(services, %{})

      assert [service] = result.services
      assert service.status == :error
      assert service.info == "Connection refused"
      assert service.impact == "Service unavailable"
    end

    test "handles unknown service types gracefully" do
      services = [
        %{name: "Unknown", type: :unknown_type, critical: false}
      ]

      result = OmHealth.run_checks(services, %{})

      assert [service] = result.services
      assert service.status == :error
      assert service.info =~ "Unknown service type"
    end
  end
end
