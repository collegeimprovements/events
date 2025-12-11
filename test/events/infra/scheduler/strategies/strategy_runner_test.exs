defmodule Events.Infra.Scheduler.Strategies.StrategyRunnerTest do
  use ExUnit.Case, async: true

  alias Events.Infra.Scheduler.Strategies.StrategyRunner

  describe "init/1" do
    test "initializes with default strategies" do
      conf = []
      {:ok, state} = GenServer.start_link(StrategyRunner, conf: conf)
      assert is_pid(state)
      GenServer.stop(state)
    end

    test "initializes with custom circuit breakers" do
      conf = [
        circuit_breakers: [
          test_circuit: [failure_threshold: 3, reset_timeout: 1000]
        ]
      ]

      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: conf)
      assert StrategyRunner.circuit_state(:test_circuit, pid) != nil
      GenServer.stop(pid)
    end

    test "initializes with rate limits" do
      conf = [
        rate_limits: [
          {:queue, :test_queue, limit: 10, period: {1, :second}}
        ]
      ]

      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: conf)
      status = StrategyRunner.rate_status(pid)
      assert Map.has_key?(status, {:queue, :test_queue})
      GenServer.stop(pid)
    end
  end

  describe "circuit breaker operations" do
    setup do
      conf = [
        circuit_breakers: [
          test_cb: [failure_threshold: 2, success_threshold: 1, reset_timeout: 100]
        ]
      ]

      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: conf)
      {:ok, pid: pid}
    end

    test "allows when circuit is closed", %{pid: pid} do
      assert :ok = StrategyRunner.circuit_allow?(:test_cb, pid)
    end

    test "opens circuit after threshold failures", %{pid: pid} do
      # Record failures to trip circuit
      StrategyRunner.circuit_failure(:test_cb, :error1, pid)
      StrategyRunner.circuit_failure(:test_cb, :error2, pid)

      # Give GenServer time to process casts
      Process.sleep(10)

      assert {:error, :circuit_open} = StrategyRunner.circuit_allow?(:test_cb, pid)
    end

    test "records success and closes half-open circuit", %{pid: pid} do
      # Trip the circuit
      StrategyRunner.circuit_failure(:test_cb, :error1, pid)
      StrategyRunner.circuit_failure(:test_cb, :error2, pid)
      Process.sleep(10)

      # Wait for reset timeout
      Process.sleep(150)

      # Should be half-open now, allow one execution
      assert :ok = StrategyRunner.circuit_allow?(:test_cb, pid)

      # Record success to close
      StrategyRunner.circuit_success(:test_cb, pid)
      Process.sleep(10)

      # Should be closed now
      state = StrategyRunner.circuit_state(:test_cb, pid)
      assert state.state == :closed
    end

    test "resets circuit manually", %{pid: pid} do
      # Trip the circuit
      StrategyRunner.circuit_failure(:test_cb, :error1, pid)
      StrategyRunner.circuit_failure(:test_cb, :error2, pid)
      Process.sleep(10)

      assert {:error, :circuit_open} = StrategyRunner.circuit_allow?(:test_cb, pid)

      # Reset
      :ok = StrategyRunner.circuit_reset(:test_cb, pid)

      assert :ok = StrategyRunner.circuit_allow?(:test_cb, pid)
    end

    test "unknown circuit allows by default", %{pid: pid} do
      assert :ok = StrategyRunner.circuit_allow?(:unknown_circuit, pid)
    end
  end

  describe "rate limiter operations" do
    setup do
      conf = [
        rate_limits: [
          {:queue, :limited_queue, limit: 2, period: {1, :second}}
        ]
      ]

      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: conf)
      {:ok, pid: pid}
    end

    test "allows when tokens available", %{pid: pid} do
      assert :ok = StrategyRunner.rate_acquire(:queue, :limited_queue, pid)
    end

    test "rate limits when tokens exhausted", %{pid: pid} do
      # Exhaust tokens
      assert :ok = StrategyRunner.rate_acquire(:queue, :limited_queue, pid)
      assert :ok = StrategyRunner.rate_acquire(:queue, :limited_queue, pid)

      # Third should be rate limited
      assert {:error, :rate_limited, retry_after} =
               StrategyRunner.rate_acquire(:queue, :limited_queue, pid)

      assert retry_after > 0
    end

    test "check doesn't consume tokens", %{pid: pid} do
      assert :ok = StrategyRunner.rate_check(:queue, :limited_queue, pid)
      assert :ok = StrategyRunner.rate_check(:queue, :limited_queue, pid)
      assert :ok = StrategyRunner.rate_check(:queue, :limited_queue, pid)

      # Still have tokens since check doesn't consume
      assert :ok = StrategyRunner.rate_acquire(:queue, :limited_queue, pid)
    end

    test "unconfigured scope returns ok", %{pid: pid} do
      # Global not configured, should return ok
      assert :ok = StrategyRunner.rate_acquire(:global, nil, pid)
    end
  end

  describe "error classifier operations" do
    setup do
      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: [])
      {:ok, pid: pid}
    end

    test "classifies errors using Recoverable protocol", %{pid: pid} do
      # Unknown atoms fall through to Recoverable protocol for Any
      # which returns terminal by default (safe default)
      classification = StrategyRunner.classify_error(:some_error, pid)
      assert classification.class == :terminal
      assert classification.retryable == false
    end

    test "classifies terminal errors consistently", %{pid: pid} do
      classification = StrategyRunner.classify_error(:not_found, pid)
      assert classification.class == :terminal
      assert classification.retryable == false
    end

    test "returns next action based on classification", %{pid: pid} do
      # Terminal errors should discard (not retry)
      assert :discard = StrategyRunner.next_action(:not_found, 1, pid)
      assert :discard = StrategyRunner.next_action(:unknown_error, 1, pid)
    end

    test "returns zero delay for non-retryable errors", %{pid: pid} do
      # Terminal errors have zero delay
      delay = StrategyRunner.error_retry_delay(:not_found, 1, pid)
      assert delay == 0
    end

    test "trips_circuit? returns false for terminal errors", %{pid: pid} do
      # Terminal errors don't trip circuit (they're not infrastructure issues)
      assert StrategyRunner.error_trips_circuit?(:not_found, pid) == false
      assert StrategyRunner.error_trips_circuit?(:unknown_error, pid) == false
    end
  end

  describe "combined operations" do
    setup do
      conf = [
        circuit_breakers: [
          api: [failure_threshold: 2, reset_timeout: 1000]
        ],
        rate_limits: [
          {:queue, :default, limit: 10, period: {1, :second}}
        ]
      ]

      {:ok, pid} = GenServer.start_link(StrategyRunner, conf: conf)
      {:ok, pid: pid}
    end

    test "pre_execute_check passes when all ok", %{pid: pid} do
      job = %{module: "TestModule", queue: "default"}
      assert :ok = StrategyRunner.pre_execute_check(job, :api, pid)
    end

    test "record_result updates circuit breaker on success", %{pid: pid} do
      # Record success
      StrategyRunner.record_result(:api, {:ok, :success}, pid)
      Process.sleep(10)

      state = StrategyRunner.circuit_state(:api, pid)
      assert state.total_successes == 1
    end

    test "record_result does not increment failures for non-tripping errors", %{pid: pid} do
      # Record failure with a terminal error (doesn't trip circuit)
      StrategyRunner.record_result(:api, {:error, :not_found}, pid)
      Process.sleep(10)

      # Terminal errors don't trip circuit, so failure count stays 0
      state = StrategyRunner.circuit_state(:api, pid)
      assert state.total_failures == 0
    end
  end
end
