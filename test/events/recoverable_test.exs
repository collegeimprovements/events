defmodule Events.RecoverableTest do
  use ExUnit.Case, async: true

  alias Events.Recoverable
  alias Events.Recoverable.Backoff
  alias Events.Recoverable.Helpers
  alias Events.Errors.Error

  # ============================================
  # Backoff Module Tests
  # ============================================

  describe "Backoff.exponential/2" do
    test "calculates exponential delays" do
      # Without jitter for predictable testing
      delay1 = Backoff.exponential(1, jitter: 0.0)
      delay2 = Backoff.exponential(2, jitter: 0.0)
      delay3 = Backoff.exponential(3, jitter: 0.0)

      assert delay1 == 1000
      assert delay2 == 2000
      assert delay3 == 4000
    end

    test "respects max delay cap" do
      delay = Backoff.exponential(10, jitter: 0.0, max: 5000)
      assert delay == 5000
    end

    test "respects custom base delay" do
      delay = Backoff.exponential(1, jitter: 0.0, base: 500)
      assert delay == 500
    end

    test "applies jitter within expected range" do
      delays =
        for _ <- 1..100 do
          Backoff.exponential(1, base: 1000, jitter: 0.25)
        end

      assert Enum.all?(delays, fn d -> d >= 750 and d <= 1250 end)
    end
  end

  describe "Backoff.linear/2" do
    test "calculates linear delays" do
      assert Backoff.linear(1) == 1000
      assert Backoff.linear(2) == 2000
      assert Backoff.linear(3) == 3000
    end

    test "respects max delay" do
      assert Backoff.linear(100, max: 5000) == 5000
    end
  end

  describe "Backoff.fixed/2" do
    test "returns constant delay" do
      assert Backoff.fixed(1) == 1000
      assert Backoff.fixed(5) == 1000
      assert Backoff.fixed(100) == 1000
    end

    test "respects custom delay" do
      assert Backoff.fixed(1, delay: 5000) == 5000
    end
  end

  describe "Backoff.decorrelated/2" do
    test "calculates decorrelated jitter delays" do
      delays =
        for _ <- 1..50 do
          Backoff.decorrelated(2, base: 1000, max: 30_000)
        end

      # Should have variation
      assert length(Enum.uniq(delays)) > 1
      # Should be within bounds
      assert Enum.all?(delays, fn d -> d >= 1000 and d <= 30_000 end)
    end
  end

  describe "Backoff.parse_delay/1" do
    test "parses integer seconds" do
      assert Backoff.parse_delay(5) == 5000
      assert Backoff.parse_delay(0) == 0
    end

    test "parses string seconds" do
      assert Backoff.parse_delay("5") == 5000
      assert Backoff.parse_delay("0") == 0
    end

    test "parses tuple formats" do
      assert Backoff.parse_delay({500, :milliseconds}) == 500
      assert Backoff.parse_delay({5, :seconds}) == 5000
      assert Backoff.parse_delay({2, :minutes}) == 120_000
    end

    test "returns nil for invalid input" do
      assert Backoff.parse_delay("invalid") == nil
      assert Backoff.parse_delay(:atom) == nil
      assert Backoff.parse_delay(%{}) == nil
    end
  end

  # ============================================
  # Events.Errors.Error Implementation Tests
  # ============================================

  describe "Recoverable for Events.Errors.Error" do
    test "timeout errors are recoverable" do
      error = Error.new(:timeout, :connection_timeout)

      assert Recoverable.recoverable?(error) == true
      assert Recoverable.strategy(error) == :retry
      assert Recoverable.max_attempts(error) == 3
      assert Recoverable.trips_circuit?(error) == true
      assert Recoverable.severity(error) == :degraded
    end

    test "rate_limit errors use wait_until strategy" do
      error = Error.new(:rate_limit, :too_many_requests)

      assert Recoverable.recoverable?(error) == true
      assert Recoverable.strategy(error) == :wait_until
      assert Recoverable.max_attempts(error) == 5
      assert Recoverable.trips_circuit?(error) == false
      assert Recoverable.severity(error) == :degraded
    end

    test "rate_limit respects retry_after in metadata" do
      error =
        Error.new(:rate_limit, :too_many_requests, metadata: %{retry_after: 30})

      delay = Recoverable.retry_delay(error, 1)
      assert delay == 30_000
    end

    test "service_unavailable errors use circuit_break strategy" do
      error = Error.new(:service_unavailable, :service_down)

      assert Recoverable.recoverable?(error) == true
      assert Recoverable.strategy(error) == :circuit_break
      assert Recoverable.max_attempts(error) == 2
      assert Recoverable.trips_circuit?(error) == true
      assert Recoverable.severity(error) == :critical
    end

    test "network errors use retry_with_backoff strategy" do
      error = Error.new(:network, :connection_refused)

      assert Recoverable.recoverable?(error) == true
      assert Recoverable.strategy(error) == :retry_with_backoff
      assert Recoverable.max_attempts(error) == 3
      assert Recoverable.trips_circuit?(error) == false
      assert Recoverable.severity(error) == :transient
    end

    test "external errors use retry_with_backoff strategy" do
      error = Error.new(:external, :upstream_failure)

      assert Recoverable.recoverable?(error) == true
      assert Recoverable.strategy(error) == :retry_with_backoff
      assert Recoverable.max_attempts(error) == 3
      assert Recoverable.trips_circuit?(error) == true
      assert Recoverable.severity(error) == :critical
    end

    test "validation errors are not recoverable" do
      error = Error.new(:validation, :invalid_email)

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
      assert Recoverable.max_attempts(error) == 1
      assert Recoverable.trips_circuit?(error) == false
      assert Recoverable.severity(error) == :permanent
    end

    test "not_found errors are not recoverable" do
      error = Error.new(:not_found, :user_not_found)

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
      assert Recoverable.max_attempts(error) == 1
    end

    test "unauthorized errors are not recoverable" do
      error = Error.new(:unauthorized, :invalid_token)

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
    end

    test "conflict errors are not recoverable" do
      error = Error.new(:conflict, :duplicate_entry)

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
    end

    test "internal errors are not recoverable" do
      error = Error.new(:internal, :unexpected_error)

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
      assert Recoverable.severity(error) == :critical
    end

    test "retry_delay increases with attempts for network errors" do
      error = Error.new(:network, :connection_reset)

      delay1 = Recoverable.retry_delay(error, 1)
      delay2 = Recoverable.retry_delay(error, 2)
      delay3 = Recoverable.retry_delay(error, 3)

      # Exponential backoff should increase
      assert delay2 > delay1
      assert delay3 > delay2
    end

    test "fallback returns nil for Error struct" do
      error = Error.new(:timeout, :request_timeout)
      assert Recoverable.fallback(error) == nil
    end
  end

  # ============================================
  # Ecto Error Implementation Tests
  # ============================================

  describe "Recoverable for Ecto errors" do
    test "StaleEntryError is not recoverable" do
      error = %Ecto.StaleEntryError{message: "stale"}

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
      assert Recoverable.max_attempts(error) == 1
      assert Recoverable.trips_circuit?(error) == false
      assert Recoverable.severity(error) == :permanent
    end

    test "NoResultsError is not recoverable" do
      error = %Ecto.NoResultsError{message: "not found"}

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
    end

    test "MultipleResultsError is not recoverable" do
      error = %Ecto.MultipleResultsError{message: "expected one result, got multiple"}

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
    end
  end

  # ============================================
  # Any (Fallback) Implementation Tests
  # ============================================

  describe "Recoverable for Any (fallback)" do
    # Note: @fallback_to_any is enabled on the protocol, so unknown types
    # get the default non-recoverable behavior. However, protocol consolidation
    # at compile time means we can't test this directly in tests without
    # disabling consolidation. These tests verify the fallback behavior.

    test "unknown struct uses fallback - not recoverable" do
      # RuntimeError is not explicitly implemented, uses Any fallback
      error = %RuntimeError{message: "boom"}

      # With @fallback_to_any true, this should not raise
      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
      assert Recoverable.max_attempts(error) == 1
      assert Recoverable.trips_circuit?(error) == false
      assert Recoverable.severity(error) == :permanent
    end

    test "plain map uses fallback - not recoverable" do
      error = %{type: :unknown, message: "something went wrong"}

      assert Recoverable.recoverable?(error) == false
      assert Recoverable.strategy(error) == :fail_fast
    end

    test "atom uses fallback - not recoverable" do
      assert Recoverable.recoverable?(:error) == false
      assert Recoverable.strategy(:not_found) == :fail_fast
    end

    test "string uses fallback - not recoverable" do
      assert Recoverable.recoverable?("error message") == false
    end

    test "tuple uses fallback - not recoverable" do
      assert Recoverable.recoverable?({:error, :reason}) == false
    end
  end

  # Note: @derive tests are skipped because protocol consolidation happens
  # at compile time. To test derived implementations, they must be defined
  # in the lib/ directory, not in tests. See the Any implementation for
  # the derive macro.

  # ============================================
  # Helpers Module Tests
  # ============================================

  describe "Helpers.recovery_decision/2" do
    test "returns :retry for recoverable timeout" do
      error = Error.new(:timeout, :request_timeout)

      assert {:retry, opts} = Helpers.recovery_decision(error, attempt: 1)
      assert opts[:delay] > 0
      assert opts[:remaining] == 2
    end

    test "returns :wait for rate limit" do
      error = Error.new(:rate_limit, :too_many_requests)

      assert {:wait, opts} = Helpers.recovery_decision(error, attempt: 1)
      assert opts[:delay] > 0
      assert opts[:remaining] == 4
    end

    test "returns :circuit_break for service unavailable" do
      error = Error.new(:service_unavailable, :down)

      assert {:circuit_break, opts} = Helpers.recovery_decision(error, attempt: 1)
      assert opts[:reason] == error
    end

    test "returns :fail for validation errors" do
      error = Error.new(:validation, :invalid)

      assert {:fail, opts} = Helpers.recovery_decision(error)
      assert opts[:reason] == error
    end

    test "returns :fail when max attempts exhausted" do
      error = Error.new(:timeout, :request_timeout)

      # Timeout has max_attempts of 3
      assert {:fail, opts} = Helpers.recovery_decision(error, attempt: 3)
      assert opts[:exhausted] == true
    end
  end

  describe "Helpers.should_retry?/2" do
    test "returns true for recoverable errors within attempts" do
      error = Error.new(:timeout, :request_timeout)

      assert Helpers.should_retry?(error, attempt: 1) == true
      assert Helpers.should_retry?(error, attempt: 2) == true
    end

    test "returns false when max attempts reached" do
      error = Error.new(:timeout, :request_timeout)

      assert Helpers.should_retry?(error, attempt: 3) == false
    end

    test "returns false for non-recoverable errors" do
      error = Error.new(:validation, :invalid)

      assert Helpers.should_retry?(error, attempt: 1) == false
    end
  end

  describe "Helpers.with_retry/2" do
    test "returns success immediately on first try" do
      result = Helpers.with_retry(fn -> {:ok, 42} end)
      assert result == {:ok, 42}
    end

    test "retries on recoverable error and succeeds" do
      # Track attempts
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Helpers.with_retry(fn ->
          count = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)

          if count < 2 do
            {:error, Error.new(:timeout, :request_timeout)}
          else
            {:ok, :success}
          end
        end)

      assert result == {:ok, :success}
      assert Agent.get(counter, & &1) == 2
      Agent.stop(counter)
    end

    test "fails after max attempts" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Helpers.with_retry(fn ->
          Agent.update(counter, &(&1 + 1))
          {:error, Error.new(:timeout, :request_timeout)}
        end)

      assert {:error, %Error{type: :timeout}} = result
      # Should try 3 times (max_attempts for timeout)
      assert Agent.get(counter, & &1) == 3
      Agent.stop(counter)
    end

    test "does not retry non-recoverable errors" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      result =
        Helpers.with_retry(fn ->
          Agent.update(counter, &(&1 + 1))
          {:error, Error.new(:validation, :invalid)}
        end)

      assert {:error, %Error{type: :validation}} = result
      # Should only try once
      assert Agent.get(counter, & &1) == 1
      Agent.stop(counter)
    end

    test "calls on_retry callback" do
      {:ok, callbacks} = Agent.start_link(fn -> [] end)

      Helpers.with_retry(
        fn ->
          {:error, Error.new(:network, :failed)}
        end,
        max_attempts: 2,
        on_retry: fn error, attempt, delay ->
          Agent.update(callbacks, fn list ->
            [{error.type, attempt, delay} | list]
          end)
        end
      )

      events = Agent.get(callbacks, & &1) |> Enum.reverse()
      assert length(events) == 1
      assert [{:network, 1, _delay}] = events
      Agent.stop(callbacks)
    end
  end

  describe "Helpers.recovery_info/1" do
    test "returns complete recovery information" do
      error = Error.new(:timeout, :request_timeout)
      info = Helpers.recovery_info(error)

      assert info.recoverable == true
      assert info.strategy == :retry
      assert info.max_attempts == 3
      assert info.trips_circuit == true
      assert info.severity == :degraded
      assert info.initial_delay > 0
    end
  end

  describe "Helpers.group_by_strategy/1" do
    test "groups errors by their strategy" do
      errors = [
        Error.new(:timeout, :t1),
        Error.new(:validation, :v1),
        Error.new(:rate_limit, :r1),
        Error.new(:not_found, :n1),
        Error.new(:network, :net1)
      ]

      grouped = Helpers.group_by_strategy(errors)

      assert length(grouped[:retry]) == 1
      assert length(grouped[:fail_fast]) == 2
      assert length(grouped[:wait_until]) == 1
      assert length(grouped[:retry_with_backoff]) == 1
    end
  end

  describe "Helpers.partition_recoverable/1" do
    test "partitions errors into recoverable and permanent" do
      errors = [
        Error.new(:timeout, :t1),
        Error.new(:validation, :v1),
        Error.new(:rate_limit, :r1),
        Error.new(:not_found, :n1)
      ]

      {recoverable, permanent} = Helpers.partition_recoverable(errors)

      assert length(recoverable) == 2
      assert length(permanent) == 2
      assert Enum.all?(recoverable, &Recoverable.recoverable?/1)
      refute Enum.any?(permanent, &Recoverable.recoverable?/1)
    end
  end
end
