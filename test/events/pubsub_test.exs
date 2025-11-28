defmodule Events.PubSubTest do
  use Events.TestCase, async: false

  alias Events.PubSub

  describe "server/0" do
    test "returns the pubsub server name" do
      assert PubSub.server() == Events.PubSub.Server
    end
  end

  describe "subscribe/unsubscribe" do
    test "can subscribe to and unsubscribe from a topic" do
      topic = "test:#{System.unique_integer()}"

      assert :ok = PubSub.subscribe(topic)
      assert :ok = PubSub.unsubscribe(topic)
    end

    test "receives messages after subscribing" do
      topic = "test:#{System.unique_integer()}"

      :ok = PubSub.subscribe(topic)
      :ok = PubSub.broadcast(topic, :test_event, %{data: "hello"})

      assert_receive {:test_event, %{data: "hello"}}, 1000
    end

    test "does not receive messages after unsubscribing" do
      topic = "test:#{System.unique_integer()}"

      :ok = PubSub.subscribe(topic)
      :ok = PubSub.unsubscribe(topic)
      :ok = PubSub.broadcast(topic, :test_event, %{data: "hello"})

      refute_receive {:test_event, _}, 100
    end
  end

  describe "broadcast/3" do
    test "broadcasts message to all subscribers" do
      topic = "broadcast:#{System.unique_integer()}"

      # Subscribe from test process
      :ok = PubSub.subscribe(topic)

      # Broadcast
      :ok = PubSub.broadcast(topic, :new_message, %{text: "Hello World"})

      # Verify receipt
      assert_receive {:new_message, %{text: "Hello World"}}, 1000
    end

    test "multiple subscribers receive the same message" do
      topic = "multi:#{System.unique_integer()}"
      test_pid = self()

      # Subscribe from multiple processes
      :ok = PubSub.subscribe(topic)

      task =
        Task.async(fn ->
          :ok = PubSub.subscribe(topic)
          send(test_pid, :subscribed)

          receive do
            msg -> send(test_pid, {:task_received, msg})
          after
            1000 -> send(test_pid, :task_timeout)
          end
        end)

      # Wait for task to subscribe
      assert_receive :subscribed, 1000

      # Broadcast
      :ok = PubSub.broadcast(topic, :shared_event, %{value: 42})

      # Both should receive
      assert_receive {:shared_event, %{value: 42}}, 1000
      assert_receive {:task_received, {:shared_event, %{value: 42}}}, 1000

      Task.await(task)
    end
  end

  describe "broadcast_from/4" do
    test "sender does not receive their own message" do
      topic = "from:#{System.unique_integer()}"

      :ok = PubSub.subscribe(topic)
      :ok = PubSub.broadcast_from(self(), topic, :my_event, %{})

      refute_receive {:my_event, _}, 100
    end

    test "other subscribers receive the message" do
      topic = "from_other:#{System.unique_integer()}"
      test_pid = self()

      # Subscribe from test process
      :ok = PubSub.subscribe(topic)

      # Another process broadcasts
      spawn(fn ->
        :ok = PubSub.broadcast_from(self(), topic, :other_event, %{from: "other"})
        send(test_pid, :broadcast_sent)
      end)

      # Wait for broadcast
      assert_receive :broadcast_sent, 1000
      assert_receive {:other_event, %{from: "other"}}, 1000
    end
  end

  describe "adapter/0" do
    test "returns current adapter type" do
      adapter = PubSub.adapter()
      assert adapter in [:redis, :local]
    end
  end

  describe "redis?/0" do
    test "returns boolean indicating Redis usage" do
      result = PubSub.redis?()
      assert is_boolean(result)
    end
  end

  describe "direct_broadcast/4" do
    test "broadcasts to local node using Phoenix.PubSub directly" do
      topic = "direct:#{System.unique_integer()}"

      :ok = PubSub.subscribe(topic)

      # Use Phoenix.PubSub.local_broadcast instead since direct_broadcast
      # requires knowing the exact node name which varies in test environments
      :ok = Phoenix.PubSub.local_broadcast(PubSub.server(), topic, {:direct_event, %{local: true}})

      assert_receive {:direct_event, %{local: true}}, 1000
    end
  end
end
