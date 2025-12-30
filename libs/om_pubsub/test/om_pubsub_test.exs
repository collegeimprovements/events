defmodule OmPubSubTest do
  use ExUnit.Case, async: false

  describe "OmPubSub with local adapter" do
    setup do
      # Start PubSub with local adapter for tests
      name = :"TestPubSub#{System.unique_integer([:positive])}"
      {:ok, pid} = OmPubSub.start_link(name: name, adapter: :local)

      on_exit(fn ->
        try do
          if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{name: name, pid: pid}
    end

    test "starts with local adapter when specified", %{name: name} do
      assert OmPubSub.adapter(name) == :local
      assert OmPubSub.local?(name)
      refute OmPubSub.redis?(name)
      refute OmPubSub.postgres?(name)
    end

    test "server/1 returns the server name", %{name: name} do
      server = OmPubSub.server(name)
      assert is_atom(server)
      assert server == :"#{name}.Server"
    end

    test "subscribe and broadcast work", %{name: name} do
      topic = "test:topic"

      # Subscribe
      assert :ok = OmPubSub.subscribe(name, topic)

      # Broadcast
      assert :ok = OmPubSub.broadcast(name, topic, :test_event, %{data: "hello"})

      # Should receive the message
      assert_receive {:test_event, %{data: "hello"}}, 1000
    end

    test "broadcast_raw sends message as-is", %{name: name} do
      topic = "test:raw"

      assert :ok = OmPubSub.subscribe(name, topic)
      assert :ok = OmPubSub.broadcast_raw(name, topic, {:custom, :message})

      assert_receive {:custom, :message}, 1000
    end

    test "unsubscribe stops receiving messages", %{name: name} do
      topic = "test:unsub"

      assert :ok = OmPubSub.subscribe(name, topic)
      assert :ok = OmPubSub.unsubscribe(name, topic)
      assert :ok = OmPubSub.broadcast(name, topic, :event, %{})

      refute_receive {:event, _}, 100
    end

    test "broadcast_from excludes sender", %{name: name} do
      topic = "test:from"

      assert :ok = OmPubSub.subscribe(name, topic)
      assert :ok = OmPubSub.broadcast_from(name, self(), topic, :event, %{})

      # Should NOT receive because we're the sender
      refute_receive {:event, _}, 100
    end
  end

  describe "OmPubSub.Telemetry" do
    test "attach_logger/1 and detach_logger/1 work" do
      handler_id = :test_pubsub_handler

      assert :ok = OmPubSub.Telemetry.attach_logger(handler_id)
      assert :ok = OmPubSub.Telemetry.detach_logger(handler_id)
    end

    test "emit functions don't raise" do
      assert :ok = OmPubSub.Telemetry.emit_subscribe_start(:test, "topic", :local)
      assert :ok = OmPubSub.Telemetry.emit_subscribe_stop(:test, "topic", :local, 1000)
      assert :ok = OmPubSub.Telemetry.emit_broadcast_start(:test, "topic", :event, :local)
      assert :ok = OmPubSub.Telemetry.emit_broadcast_stop(:test, "topic", :event, :local, 1000)
    end
  end
end
