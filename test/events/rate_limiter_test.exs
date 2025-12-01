defmodule Events.Types.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Events.Types.RateLimiter

  describe "token_bucket/1" do
    test "creates limiter with defaults" do
      state = RateLimiter.token_bucket()

      assert state.algorithm == :token_bucket
      assert state.config.capacity == 10
      assert state.config.refill_rate == 1.0
      assert state.data.tokens == 10.0
    end

    test "accepts custom options" do
      state = RateLimiter.token_bucket(capacity: 50, refill_rate: 5.0, initial_tokens: 25)

      assert state.config.capacity == 50
      assert state.config.refill_rate == 5.0
      assert state.data.tokens == 25.0
    end

    test "allows requests when tokens available" do
      state = RateLimiter.token_bucket(capacity: 10)

      {:allow, state1} = RateLimiter.check(state)
      {:allow, state2} = RateLimiter.check(state1)
      {:allow, state3} = RateLimiter.check(state2)

      assert state3.data.tokens < state.data.tokens
    end

    test "denies when tokens exhausted" do
      state = RateLimiter.token_bucket(capacity: 2, initial_tokens: 2)

      {:allow, state1} = RateLimiter.check(state)
      {:allow, state2} = RateLimiter.check(state1)
      {:deny, _state3, retry_after} = RateLimiter.check(state2)

      assert retry_after > 0
    end

    test "refills tokens over time" do
      now = 1000
      # Create state with known last_update
      state = %{
        algorithm: :token_bucket,
        config: %{capacity: 10, refill_rate: 10.0},
        data: %{tokens: 1.0},
        last_update: now
      }

      # Check at t=now - should allow (have 1 token)
      {:allow, state1} = RateLimiter.check(state, now: now)
      assert state1.data.tokens == 0.0

      # Check at t=now again - should deny (no tokens left)
      {:deny, state2, _} = RateLimiter.check(state1, now: now)

      # Check at t=now+100ms (should have 1 token from refill: 10/sec * 0.1s = 1)
      {:allow, state3} = RateLimiter.check(state2, now: now + 100)
      # Consumed the token
      assert state3.data.tokens < 1.0

      # Check at t=now+1000ms (should have ~9 more tokens)
      status = RateLimiter.status(state3, now: now + 1000)
      assert status.remaining >= 9
    end

    test "respects cost parameter" do
      state = RateLimiter.token_bucket(capacity: 10, initial_tokens: 5)

      # Request with cost 3
      {:allow, state1} = RateLimiter.check(state, cost: 3)
      assert state1.data.tokens == 2.0

      # Request with cost 3 again - should be denied
      {:deny, _state2, _retry} = RateLimiter.check(state1, cost: 3)
    end
  end

  describe "sliding_window/1" do
    test "creates limiter with defaults" do
      state = RateLimiter.sliding_window()

      assert state.algorithm == :sliding_window
      assert state.config.max_requests == 100
      assert state.config.window_ms == 60_000
      assert state.data.timestamps == []
    end

    test "allows requests under limit" do
      state = RateLimiter.sliding_window(max_requests: 5, window_ms: 1000)

      {:allow, state1} = RateLimiter.check(state)
      {:allow, state2} = RateLimiter.check(state1)
      {:allow, state3} = RateLimiter.check(state2)

      assert length(state3.data.timestamps) == 3
    end

    test "denies when limit reached" do
      now = 0
      state = RateLimiter.sliding_window(max_requests: 3, window_ms: 1000)

      {:allow, s1} = RateLimiter.check(state, now: now)
      {:allow, s2} = RateLimiter.check(s1, now: now + 10)
      {:allow, s3} = RateLimiter.check(s2, now: now + 20)
      {:deny, _s4, retry_after} = RateLimiter.check(s3, now: now + 30)

      # Should retry after oldest request expires
      assert retry_after > 0
      assert retry_after <= 1000
    end

    test "allows after window slides" do
      now = 0
      state = RateLimiter.sliding_window(max_requests: 2, window_ms: 100)

      {:allow, s1} = RateLimiter.check(state, now: now)
      {:allow, s2} = RateLimiter.check(s1, now: now + 10)
      {:deny, s3, _} = RateLimiter.check(s2, now: now + 20)

      # After window expires, should allow again
      {:allow, _s4} = RateLimiter.check(s3, now: now + 150)
    end
  end

  describe "leaky_bucket/1" do
    test "creates limiter with defaults" do
      state = RateLimiter.leaky_bucket()

      assert state.algorithm == :leaky_bucket
      assert state.config.capacity == 10
      assert state.config.leak_rate == 1.0
      assert state.data.level == 0.0
    end

    test "allows requests when bucket has room" do
      state = RateLimiter.leaky_bucket(capacity: 10)

      {:allow, state1} = RateLimiter.check(state)
      {:allow, state2} = RateLimiter.check(state1)

      assert state2.data.level == 2.0
    end

    test "denies when bucket full" do
      state = RateLimiter.leaky_bucket(capacity: 2, leak_rate: 1.0)

      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)
      {:deny, _s3, retry_after} = RateLimiter.check(s2)

      assert retry_after > 0
    end

    test "drains over time" do
      now = 0
      state = RateLimiter.leaky_bucket(capacity: 5, leak_rate: 10.0)

      # Fill bucket
      {:allow, s1} = RateLimiter.check(state, now: now)
      {:allow, s2} = RateLimiter.check(s1, now: now)
      {:allow, s3} = RateLimiter.check(s2, now: now)
      {:allow, s4} = RateLimiter.check(s3, now: now)
      {:allow, s5} = RateLimiter.check(s4, now: now)
      {:deny, s6, _} = RateLimiter.check(s5, now: now)

      # After 500ms, 5 should have leaked out (10/sec * 0.5s = 5)
      {:allow, _} = RateLimiter.check(s6, now: now + 500)
    end
  end

  describe "fixed_window/1" do
    test "creates limiter with defaults" do
      state = RateLimiter.fixed_window()

      assert state.algorithm == :fixed_window
      assert state.config.max_requests == 100
      assert state.config.window_ms == 60_000
      assert state.data.count == 0
    end

    test "allows requests under limit" do
      state = RateLimiter.fixed_window(max_requests: 5)

      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)
      {:allow, s3} = RateLimiter.check(s2)

      assert s3.data.count == 3
    end

    test "denies when limit reached" do
      # Use explicit timing to control window boundaries
      window_ms = 1000
      window_start = 0

      state = %{
        algorithm: :fixed_window,
        config: %{max_requests: 2, window_ms: window_ms},
        data: %{count: 0, window_start: window_start},
        last_update: window_start
      }

      {:allow, s1} = RateLimiter.check(state, now: 100)
      {:allow, s2} = RateLimiter.check(s1, now: 200)
      {:deny, _s3, retry_after} = RateLimiter.check(s2, now: 300)

      assert retry_after > 0
      # Window ends at 1000, so max wait is 700
      assert retry_after <= 1000
    end

    test "resets at window boundary" do
      # Use explicit times to control window boundaries
      window_ms = 1000
      window_start = 0

      state = %{
        algorithm: :fixed_window,
        config: %{max_requests: 2, window_ms: window_ms},
        data: %{count: 0, window_start: window_start},
        last_update: window_start
      }

      {:allow, s1} = RateLimiter.check(state, now: 100)
      {:allow, s2} = RateLimiter.check(s1, now: 200)
      {:deny, s3, _} = RateLimiter.check(s2, now: 300)

      # New window starts at 1000
      {:allow, s4} = RateLimiter.check(s3, now: 1100)
      assert s4.data.count == 1
      assert s4.data.window_start == 1000
    end
  end

  describe "would_allow?/2" do
    test "returns true when would allow" do
      state = RateLimiter.token_bucket(capacity: 10)
      assert RateLimiter.would_allow?(state)
    end

    test "returns false when would deny" do
      state = RateLimiter.token_bucket(capacity: 2, initial_tokens: 0)
      refute RateLimiter.would_allow?(state)
    end

    test "does not consume resources" do
      state = RateLimiter.token_bucket(capacity: 10)

      assert RateLimiter.would_allow?(state)
      assert RateLimiter.would_allow?(state)
      assert RateLimiter.would_allow?(state)

      # Tokens should still be at capacity
      status = RateLimiter.status(state)
      assert status.remaining == 10
    end
  end

  describe "status/2" do
    test "returns status for token bucket" do
      state = RateLimiter.token_bucket(capacity: 10, initial_tokens: 7)
      status = RateLimiter.status(state)

      assert status.remaining == 7
      assert status.limit == 10
      assert status.reset_ms >= 0
    end

    test "returns status for sliding window" do
      now = 0
      state = RateLimiter.sliding_window(max_requests: 10, window_ms: 1000)

      {:allow, s1} = RateLimiter.check(state, now: now)
      {:allow, s2} = RateLimiter.check(s1, now: now + 10)

      status = RateLimiter.status(s2, now: now + 20)

      assert status.remaining == 8
      assert status.limit == 10
    end

    test "returns status for leaky bucket" do
      state = RateLimiter.leaky_bucket(capacity: 10)
      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)

      status = RateLimiter.status(s2)

      assert status.remaining == 8
      assert status.limit == 10
    end

    test "returns status for fixed window" do
      state = RateLimiter.fixed_window(max_requests: 100)
      {:allow, s1} = RateLimiter.check(state)

      status = RateLimiter.status(s1)

      assert status.remaining == 99
      assert status.limit == 100
    end
  end

  describe "reset/1" do
    test "resets token bucket" do
      state = RateLimiter.token_bucket(capacity: 10, initial_tokens: 10)
      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)

      reset = RateLimiter.reset(s2)
      assert reset.data.tokens == 10.0
    end

    test "resets sliding window" do
      state = RateLimiter.sliding_window(max_requests: 10)
      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)

      reset = RateLimiter.reset(s2)
      assert reset.data.timestamps == []
    end

    test "resets leaky bucket" do
      state = RateLimiter.leaky_bucket(capacity: 10)
      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)

      reset = RateLimiter.reset(s2)
      assert reset.data.level == 0.0
    end

    test "resets fixed window" do
      state = RateLimiter.fixed_window(max_requests: 10)
      {:allow, s1} = RateLimiter.check(state)
      {:allow, s2} = RateLimiter.check(s1)

      reset = RateLimiter.reset(s2)
      assert reset.data.count == 0
    end
  end

  describe "check_result/2" do
    test "returns ok tuple on allow" do
      state = RateLimiter.token_bucket(capacity: 10)
      assert {:ok, _new_state} = RateLimiter.check_result(state)
    end

    test "returns error tuple on deny" do
      state = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0)
      assert {:error, {:rate_limited, retry_after}} = RateLimiter.check_result(state)
      assert is_integer(retry_after)
    end
  end

  describe "with_limit/3" do
    test "executes action when allowed" do
      state = RateLimiter.token_bucket(capacity: 10)

      {:ok, result, _new_state} =
        RateLimiter.with_limit(state, fn ->
          :action_result
        end)

      assert result == :action_result
    end

    test "returns rate limited error when denied" do
      state = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0)

      {:error, {:rate_limited, retry_after}, _state} =
        RateLimiter.with_limit(state, fn ->
          :never_called
        end)

      assert is_integer(retry_after)
    end

    test "does not call action when denied" do
      state = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0)
      ref = make_ref()

      {:error, _, _} =
        RateLimiter.with_limit(state, fn ->
          send(self(), {:called, ref})
        end)

      refute_receive {:called, ^ref}
    end
  end

  describe "compose/1" do
    test "creates composite limiter" do
      l1 = RateLimiter.token_bucket(capacity: 10)
      l2 = RateLimiter.sliding_window(max_requests: 100)

      composite = RateLimiter.compose([l1, l2])

      assert composite.algorithm == :composite
      assert length(composite.data.limiters) == 2
    end

    test "allows when all limiters allow" do
      l1 = RateLimiter.token_bucket(capacity: 10)
      l2 = RateLimiter.sliding_window(max_requests: 100)
      composite = RateLimiter.compose([l1, l2])

      {:allow, new_composite} = RateLimiter.check(composite)

      # Both limiters should be updated
      [new_l1, new_l2] = new_composite.data.limiters
      assert new_l1.data.tokens < 10
      assert length(new_l2.data.timestamps) == 1
    end

    test "denies when any limiter denies" do
      l1 = RateLimiter.token_bucket(capacity: 10)
      # Empty
      l2 = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0)
      composite = RateLimiter.compose([l1, l2])

      {:deny, _new_composite, retry_after} = RateLimiter.check(composite)
      assert retry_after > 0
    end

    test "returns max retry_after from all denials" do
      # Both will deny with different retry times
      # ~1000ms
      l1 = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0, refill_rate: 1.0)
      # ~2000ms
      l2 = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0, refill_rate: 0.5)
      composite = RateLimiter.compose([l1, l2])

      {:deny, _new_composite, retry_after} = RateLimiter.check(composite)

      # Should return the longer wait time
      # ~2000ms from l2
      assert retry_after >= 1900
    end

    test "status returns minimum remaining" do
      l1 = RateLimiter.token_bucket(capacity: 100)
      # More restrictive
      l2 = RateLimiter.token_bucket(capacity: 5)
      composite = RateLimiter.compose([l1, l2])

      status = RateLimiter.status(composite)

      # Min of 100 and 5
      assert status.remaining == 5
    end

    test "would_allow? checks all limiters" do
      l1 = RateLimiter.token_bucket(capacity: 10)
      # Empty
      l2 = RateLimiter.token_bucket(capacity: 1, initial_tokens: 0)
      composite = RateLimiter.compose([l1, l2])

      refute RateLimiter.would_allow?(composite)
    end
  end

  describe "real-world scenarios" do
    test "API rate limiting - burst then sustain" do
      # Allow 10 burst, then 1/second sustained
      state = RateLimiter.token_bucket(capacity: 10, refill_rate: 1.0)
      now = 0

      # Burst of 10 requests
      state =
        Enum.reduce(1..10, state, fn _, s ->
          {:allow, new_s} = RateLimiter.check(s, now: now)
          new_s
        end)

      # 11th request denied
      {:deny, state, retry_after} = RateLimiter.check(state, now: now)
      assert retry_after > 0

      # After 1 second, 1 more allowed
      {:allow, _} = RateLimiter.check(state, now: now + 1000)
    end

    test "per-second and per-minute limits" do
      per_second = RateLimiter.token_bucket(capacity: 10, refill_rate: 10.0)
      per_minute = RateLimiter.sliding_window(max_requests: 100, window_ms: 60_000)
      composite = RateLimiter.compose([per_second, per_minute])

      now = 0

      # First 10 requests at t=0 succeed
      state =
        Enum.reduce(1..10, composite, fn _, s ->
          {:allow, new_s} = RateLimiter.check(s, now: now)
          new_s
        end)

      # 11th at t=0 denied (per-second limit)
      {:deny, _state, _} = RateLimiter.check(state, now: now)
    end

    test "traffic shaping with leaky bucket" do
      # Process max 10 requests/second
      state = RateLimiter.leaky_bucket(capacity: 20, leak_rate: 10.0)
      now = 0

      # Fill bucket with 20 requests instantly
      state =
        Enum.reduce(1..20, state, fn _, s ->
          {:allow, new_s} = RateLimiter.check(s, now: now)
          new_s
        end)

      # Bucket full, 21st denied
      {:deny, state, _} = RateLimiter.check(state, now: now)

      # After 1 second, 10 leaked, 10 more allowed
      state =
        Enum.reduce(1..10, state, fn i, s ->
          {:allow, new_s} = RateLimiter.check(s, now: now + 1000 + i)
          new_s
        end)

      # Bucket full again
      {:deny, _, _} = RateLimiter.check(state, now: now + 1010)
    end
  end
end
