defmodule OmCache.CircuitBreakerTest do
  use ExUnit.Case

  @moduletag capture_log: true

  alias OmCache.CircuitBreaker

  # Use unique module names per test to avoid GenServer name conflicts
  defmodule CB1 do
    @moduledoc false
  end

  defmodule CB2 do
    @moduledoc false
  end

  defmodule CB3 do
    @moduledoc false
  end

  defmodule CB4 do
    @moduledoc false
  end

  defmodule CB5 do
    @moduledoc false
  end

  defmodule CB6 do
    @moduledoc false
  end

  defmodule CB7 do
    @moduledoc false
  end

  defmodule CB8 do
    @moduledoc false
  end

  describe "start_link/2" do
    test "starts with closed state" do
      {:ok, _pid} = CircuitBreaker.start_link(CB1)
      assert CircuitBreaker.get_state(CB1) == :closed
      assert CircuitBreaker.open?(CB1) == false
    end
  end

  describe "state transitions" do
    test "opens after error threshold exceeded" do
      # Trap exits so Task crashes don't kill the test process
      Process.flag(:trap_exit, true)
      {:ok, _pid} = CircuitBreaker.start_link(CB2, error_threshold: 3)

      for _ <- 1..3 do
        CircuitBreaker.call(CB2, fn _cache -> raise "boom" end,
          fallback: fn -> :fallback end
        )
      end

      assert CircuitBreaker.get_state(CB2) == :open
      assert CircuitBreaker.open?(CB2) == true
    end

    test "transitions open -> half_open after timeout" do
      Process.flag(:trap_exit, true)
      {:ok, _pid} = CircuitBreaker.start_link(CB3, error_threshold: 1, open_timeout: 50)

      CircuitBreaker.call(CB3, fn _cache -> raise "boom" end,
        fallback: fn -> :fallback end
      )

      assert CircuitBreaker.get_state(CB3) == :open

      Process.sleep(60)
      assert CircuitBreaker.get_state(CB3) == :half_open
    end

    test "closes from half_open after successful call" do
      Process.flag(:trap_exit, true)
      {:ok, _pid} = CircuitBreaker.start_link(CB4, error_threshold: 1, open_timeout: 50)

      CircuitBreaker.call(CB4, fn _cache -> raise "boom" end,
        fallback: fn -> :fallback end
      )

      assert CircuitBreaker.get_state(CB4) == :open

      Process.sleep(60)
      assert CircuitBreaker.get_state(CB4) == :half_open

      result =
        CircuitBreaker.call(CB4, fn _cache -> :success end,
          fallback: fn -> :fallback end
        )

      assert result == :success
      assert CircuitBreaker.get_state(CB4) == :closed
    end
  end

  describe "call/3" do
    test "returns cache result when circuit closed" do
      {:ok, _pid} = CircuitBreaker.start_link(CB5)

      result =
        CircuitBreaker.call(CB5, fn _cache -> :cached end,
          fallback: fn -> :fallback end
        )

      assert result == :cached
    end

    test "returns fallback when circuit open" do
      Process.flag(:trap_exit, true)
      {:ok, _pid} = CircuitBreaker.start_link(CB6, error_threshold: 1)

      CircuitBreaker.call(CB6, fn _cache -> raise "boom" end,
        fallback: fn -> :fallback end
      )

      result =
        CircuitBreaker.call(CB6, fn _cache -> :cached end,
          fallback: fn -> :fallback end
        )

      assert result == :fallback
    end
  end

  describe "reset/1" do
    test "resets circuit to closed" do
      Process.flag(:trap_exit, true)
      {:ok, _pid} = CircuitBreaker.start_link(CB7, error_threshold: 1)

      CircuitBreaker.call(CB7, fn _cache -> raise "boom" end,
        fallback: fn -> :ok end
      )

      assert CircuitBreaker.get_state(CB7) == :open
      assert :ok = CircuitBreaker.reset(CB7)
      assert CircuitBreaker.get_state(CB7) == :closed
    end
  end

  describe "stats/1" do
    test "returns stats map" do
      {:ok, _pid} = CircuitBreaker.start_link(CB8)
      stats = CircuitBreaker.stats(CB8)

      assert stats.state == :closed
      assert stats.error_count == 0
      assert is_number(stats.avg_latency_ms)
      assert is_integer(stats.uptime_seconds)
    end
  end
end
