defmodule FnDecorator.TelemetryTest do
  use ExUnit.Case, async: false

  # ============================================
  # Test Module with Telemetry Decorators
  # ============================================

  defmodule TelemetryFunctions do
    use FnDecorator

    @decorate telemetry_span(event: [:test, :users, :get])
    def get_user(id) do
      %{id: id, name: "User #{id}"}
    end

    @decorate telemetry_span(event: [:test, :users, :slow])
    def slow_operation do
      Process.sleep(10)
      :done
    end

    @decorate telemetry_span(event: [:test, :users, :error])
    def failing_operation do
      {:error, :not_found}
    end

    @decorate log_if_slow(threshold: 5)
    def maybe_slow(sleep_ms) do
      Process.sleep(sleep_ms)
      :done
    end
  end

  # ============================================
  # Telemetry Handler Module
  # ============================================
  # Using a module function instead of anonymous function
  # to avoid telemetry warnings about local functions

  defmodule TelemetryHandler do
    @moduledoc false

    def handle_event(event, measurements, metadata, test_pid) do
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end
  end

  # ============================================
  # Test Setup
  # ============================================

  setup do
    test_pid = self()
    handler_id = "test-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:test, :users, :get, :start],
        [:test, :users, :get, :stop],
        [:test, :users, :get, :exception],
        [:test, :users, :slow, :start],
        [:test, :users, :slow, :stop],
        [:test, :users, :error, :start],
        [:test, :users, :error, :stop]
      ],
      &TelemetryHandler.handle_event/4,
      test_pid
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    {:ok, handler_id: handler_id}
  end

  # Helper to collect all events from the mailbox
  defp collect_events(timeout \\ 50) do
    collect_events_acc([], timeout)
  end

  defp collect_events_acc(acc, timeout) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_events_acc([{event, measurements, metadata} | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  # ============================================
  # @telemetry_span tests
  # ============================================

  describe "@telemetry_span decorator" do
    test "emits start and stop events", _context do
      result = TelemetryFunctions.get_user(1)
      assert result == %{id: 1, name: "User 1"}

      all_events = collect_events()

      # Should have start event
      start_events = Enum.filter(all_events, fn {event, _, _} -> event == [:test, :users, :get, :start] end)
      assert length(start_events) == 1

      # Should have stop event
      stop_events = Enum.filter(all_events, fn {event, _, _} -> event == [:test, :users, :get, :stop] end)
      assert length(stop_events) == 1
    end

    test "includes duration in stop event measurements", _context do
      TelemetryFunctions.slow_operation()

      all_events = collect_events()
      stop_events = Enum.filter(all_events, fn {event, _, _} -> event == [:test, :users, :slow, :stop] end)

      [{_, measurements, _}] = stop_events
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
    end

    test "includes metadata with function and module info", _context do
      TelemetryFunctions.slow_operation()

      all_events = collect_events()
      start_events = Enum.filter(all_events, fn {event, _, _} -> event == [:test, :users, :slow, :start] end)

      assert length(start_events) == 1
    end

    test "handles error results", _context do
      result = TelemetryFunctions.failing_operation()
      assert result == {:error, :not_found}

      all_events = collect_events()
      stop_events = Enum.filter(all_events, fn {event, _, _} -> event == [:test, :users, :error, :stop] end)

      assert length(stop_events) == 1
    end
  end

  # ============================================
  # @log_if_slow tests
  # ============================================

  describe "@log_if_slow decorator" do
    import ExUnit.CaptureLog

    test "fast operations complete normally" do
      result = TelemetryFunctions.maybe_slow(1)
      assert result == :done
    end

    test "slow operations log warning and complete normally" do
      log =
        capture_log(fn ->
          result = TelemetryFunctions.maybe_slow(10)
          assert result == :done
        end)

      assert log =~ "Slow operation detected"
    end
  end
end
