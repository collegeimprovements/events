defmodule Events.APIClient.MiddlewareTest do
  use ExUnit.Case, async: true

  alias Events.APIClient.Middleware.{Retry, CircuitBreaker, RateLimiter}

  describe "Retry" do
    test "options/0 returns default retry options" do
      opts = Retry.options()

      assert is_function(opts[:retry])
      assert is_function(opts[:retry_delay])
      assert opts[:max_retries] == 2
    end

    test "options/1 with custom max_attempts" do
      opts = Retry.options(max_attempts: 5)
      assert opts[:max_retries] == 4
    end

    test "calculate_delay/1 uses exponential backoff" do
      delay1 = Retry.calculate_delay(1, jitter: 0)
      delay2 = Retry.calculate_delay(2, jitter: 0)
      delay3 = Retry.calculate_delay(3, jitter: 0)

      assert delay1 == 1000
      assert delay2 == 2000
      assert delay3 == 4000
    end

    test "calculate_delay/2 respects max_delay" do
      delay = Retry.calculate_delay(10, max_delay: 5000, jitter: 0)
      assert delay == 5000
    end

    test "should_retry?/1 returns true for 429" do
      assert Retry.should_retry?({:ok, %{status: 429}})
    end

    test "should_retry?/1 returns true for 5xx" do
      assert Retry.should_retry?({:ok, %{status: 500}})
      assert Retry.should_retry?({:ok, %{status: 502}})
      assert Retry.should_retry?({:ok, %{status: 503}})
    end

    test "should_retry?/1 returns false for 4xx (except 429, 408)" do
      refute Retry.should_retry?({:ok, %{status: 400}})
      refute Retry.should_retry?({:ok, %{status: 404}})
      refute Retry.should_retry?({:ok, %{status: 422}})
    end

    test "should_retry?/1 returns false for success" do
      refute Retry.should_retry?({:ok, %{status: 200}})
      refute Retry.should_retry?({:ok, %{status: 201}})
    end

    test "extract_retry_after/1 parses seconds" do
      response = %{headers: [{"retry-after", "5"}]}
      assert Retry.extract_retry_after(response) == 5000
    end

    test "extract_retry_after/1 returns nil when no header" do
      response = %{headers: []}
      assert Retry.extract_retry_after(response) == nil
    end
  end

  describe "CircuitBreaker" do
    setup do
      name = :"test_breaker_#{:erlang.unique_integer()}"
      {:ok, _pid} = CircuitBreaker.start_link(name: name, failure_threshold: 3, reset_timeout: 100)
      {:ok, name: name}
    end

    test "starts in closed state", %{name: name} do
      state = CircuitBreaker.get_state(name)
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "allows requests in closed state", %{name: name} do
      assert CircuitBreaker.allow_request?(name) == :ok
    end

    test "opens after threshold failures", %{name: name} do
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)

      # Give GenServer time to process
      :timer.sleep(10)

      state = CircuitBreaker.get_state(name)
      assert state.state == :open
    end

    test "rejects requests when open", %{name: name} do
      # Open the circuit
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      :timer.sleep(10)

      assert CircuitBreaker.allow_request?(name) == {:error, :circuit_open}
    end

    test "transitions to half-open after reset timeout", %{name: name} do
      # Open the circuit
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      :timer.sleep(10)

      # Wait for reset timeout
      :timer.sleep(150)

      state = CircuitBreaker.get_state(name)
      assert state.state == :half_open
    end

    test "closes after success in half-open state", %{name: name} do
      # Open the circuit
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      :timer.sleep(10)

      # Wait for half-open
      :timer.sleep(150)

      # Record successes
      CircuitBreaker.record_success(name)
      CircuitBreaker.record_success(name)
      :timer.sleep(10)

      state = CircuitBreaker.get_state(name)
      assert state.state == :closed
    end

    test "call/2 executes function when closed", %{name: name} do
      result = CircuitBreaker.call(name, fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "call/2 records success on {:ok, _}", %{name: name} do
      CircuitBreaker.call(name, fn -> {:ok, "success"} end)
      :timer.sleep(10)

      state = CircuitBreaker.get_state(name)
      assert state.failure_count == 0
    end

    test "call/2 records failure on {:error, _}", %{name: name} do
      CircuitBreaker.call(name, fn -> {:error, "failed"} end)
      :timer.sleep(10)

      state = CircuitBreaker.get_state(name)
      assert state.failure_count == 1
    end

    test "call/2 returns circuit_open error when open", %{name: name} do
      # Open the circuit
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      :timer.sleep(10)

      result = CircuitBreaker.call(name, fn -> {:ok, "won't run"} end)
      assert result == {:error, :circuit_open}
    end

    test "reset/1 resets to closed state", %{name: name} do
      # Open the circuit
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      CircuitBreaker.record_failure(name)
      :timer.sleep(10)

      assert CircuitBreaker.get_state(name).state == :open

      CircuitBreaker.reset(name)

      assert CircuitBreaker.get_state(name).state == :closed
    end
  end

  describe "RateLimiter" do
    setup do
      name = :"test_limiter_#{:erlang.unique_integer()}"

      {:ok, _pid} =
        RateLimiter.start_link(
          name: name,
          bucket_size: 10,
          refill_rate: 5,
          refill_interval: 100
        )

      {:ok, name: name}
    end

    test "starts with full bucket", %{name: name} do
      state = RateLimiter.get_state(name)
      assert state.tokens == 10
    end

    test "acquire/1 decrements tokens", %{name: name} do
      :ok = RateLimiter.acquire(name)

      state = RateLimiter.get_state(name)
      assert state.tokens == 9
    end

    test "acquire/1 multiple times drains tokens", %{name: name} do
      for _ <- 1..5 do
        :ok = RateLimiter.acquire(name)
      end

      state = RateLimiter.get_state(name)
      assert state.tokens == 5
    end

    test "refills tokens over time", %{name: name} do
      # Drain some tokens
      for _ <- 1..8 do
        :ok = RateLimiter.acquire(name)
      end

      assert RateLimiter.get_state(name).tokens == 2

      # Wait for refill
      :timer.sleep(150)

      state = RateLimiter.get_state(name)
      assert state.tokens >= 5
    end

    test "update_from_headers/2 updates API limits", %{name: name} do
      headers = [
        {"x-ratelimit-limit", "1000"},
        {"x-ratelimit-remaining", "995"},
        {"x-ratelimit-reset", "1705334400"}
      ]

      RateLimiter.update_from_headers(name, headers)
      :timer.sleep(10)

      state = RateLimiter.get_state(name)
      assert state.api_limit == 1000
      assert state.api_remaining == 995
      assert state.api_reset == 1_705_334_400
    end

    test "syncs tokens with API remaining", %{name: name} do
      headers = [{"x-ratelimit-remaining", "5"}]

      RateLimiter.update_from_headers(name, headers)
      :timer.sleep(10)

      state = RateLimiter.get_state(name)
      assert state.tokens == 5
    end
  end
end
