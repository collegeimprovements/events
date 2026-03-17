defmodule OmS3.TelemetryTest do
  use ExUnit.Case, async: true

  alias OmS3.Telemetry

  setup do
    # Capture telemetry events
    test_pid = self()

    handler_id = "test-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:om_s3, :request, :start],
        [:om_s3, :request, :stop],
        [:om_s3, :request, :exception],
        [:om_s3, :batch, :start],
        [:om_s3, :batch, :stop],
        [:om_s3, :stream, :start],
        [:om_s3, :stream, :chunk],
        [:om_s3, :stream, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "emit_start/3" do
    test "emits request start event" do
      _start_time = Telemetry.emit_start(:get, "test-bucket", "test-key")

      assert_receive {:telemetry_event, [:om_s3, :request, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.operation == :get
      assert metadata.bucket == "test-bucket"
      assert metadata.key == "test-key"
    end

    test "includes extra metadata" do
      _start_time = Telemetry.emit_start(:put, "bucket", "key", %{custom: "value"})

      assert_receive {:telemetry_event, [:om_s3, :request, :start], _measurements, metadata}
      assert metadata.custom == "value"
    end
  end

  describe "emit_stop/4" do
    test "emits request stop event with duration" do
      start_time = System.monotonic_time()
      Process.sleep(10)
      Telemetry.emit_stop(start_time, :get, "bucket", "key", %{status: 200})

      assert_receive {:telemetry_event, [:om_s3, :request, :stop], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.operation == :get
      assert metadata.status == 200
    end
  end

  describe "emit_exception/6" do
    test "emits exception event" do
      start_time = System.monotonic_time()
      Telemetry.emit_exception(start_time, :get, "bucket", "key", :error, :timeout)

      assert_receive {:telemetry_event, [:om_s3, :request, :exception], measurements, metadata}
      assert measurements.duration >= 0
      assert metadata.operation == :get
      assert metadata.kind == :error
      assert metadata.reason == :timeout
    end
  end

  describe "emit_batch_start/2" do
    test "emits batch start event with count" do
      _start_time = Telemetry.emit_batch_start(:put_all, 10)

      assert_receive {:telemetry_event, [:om_s3, :batch, :start], measurements, metadata}
      assert measurements.count == 10
      assert metadata.operation == :put_all
    end
  end

  describe "emit_batch_stop/4" do
    test "emits batch stop event with results" do
      start_time = System.monotonic_time()
      Telemetry.emit_batch_stop(start_time, :put_all, 8, 2)

      assert_receive {:telemetry_event, [:om_s3, :batch, :stop], measurements, metadata}
      assert measurements.duration >= 0
      assert measurements.succeeded == 8
      assert measurements.failed == 2
      assert metadata.operation == :put_all
    end
  end

  describe "emit_stream_start/3" do
    test "emits stream start event" do
      _start_time = Telemetry.emit_stream_start(:download, "bucket", "key")

      assert_receive {:telemetry_event, [:om_s3, :stream, :start], _measurements, metadata}
      assert metadata.direction == :download
      assert metadata.bucket == "bucket"
      assert metadata.key == "key"
    end
  end

  describe "emit_stream_chunk/5" do
    test "emits chunk event with bytes" do
      Telemetry.emit_stream_chunk(:download, "bucket", "key", 5_242_880, 1)

      assert_receive {:telemetry_event, [:om_s3, :stream, :chunk], measurements, metadata}
      assert measurements.bytes == 5_242_880
      assert measurements.chunk_number == 1
      assert metadata.direction == :download
    end
  end

  describe "emit_stream_stop/5" do
    test "emits stream stop event" do
      start_time = System.monotonic_time()
      Telemetry.emit_stream_stop(start_time, :download, "bucket", "key", 100_000_000)

      assert_receive {:telemetry_event, [:om_s3, :stream, :stop], measurements, metadata}
      assert measurements.duration >= 0
      assert measurements.total_bytes == 100_000_000
      assert metadata.direction == :download
    end
  end

  describe "span/4" do
    test "wraps successful operation" do
      result =
        Telemetry.span(:get, "bucket", "key", fn ->
          {:ok, "content"}
        end)

      assert result == {:ok, "content"}

      assert_receive {:telemetry_event, [:om_s3, :request, :start], _, _}
      assert_receive {:telemetry_event, [:om_s3, :request, :stop], _, metadata}
      assert metadata.status == 200
    end

    test "wraps operation with error result" do
      result =
        Telemetry.span(:get, "bucket", "key", fn ->
          {:error, :not_found}
        end)

      assert result == {:error, :not_found}

      assert_receive {:telemetry_event, [:om_s3, :request, :stop], _, metadata}
      assert metadata.status == 404
    end

    test "handles exceptions" do
      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span(:get, "bucket", "key", fn ->
          raise "boom"
        end)
      end

      assert_receive {:telemetry_event, [:om_s3, :request, :exception], _, metadata}
      assert metadata.kind == :error
    end
  end

  describe "batch_span/3" do
    test "wraps batch operation" do
      results =
        Telemetry.batch_span(:put_all, 3, fn ->
          [
            {:ok, "s3://bucket/a.txt"},
            {:ok, "s3://bucket/b.txt"},
            {:error, "s3://bucket/c.txt", :timeout}
          ]
        end)

      assert length(results) == 3

      assert_receive {:telemetry_event, [:om_s3, :batch, :start], measurements, _}
      assert measurements.count == 3

      assert_receive {:telemetry_event, [:om_s3, :batch, :stop], measurements, _}
      assert measurements.succeeded == 2
      assert measurements.failed == 1
    end
  end
end
