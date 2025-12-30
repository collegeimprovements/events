defmodule Events.Infra.PubSub do
  @moduledoc """
  PubSub wrapper with Redis adapter and local fallback.

  Wraps `OmPubSub` with Events-specific defaults. See `OmPubSub` for full documentation.

  ## Usage

      # Subscribe to a topic
      Events.Infra.PubSub.subscribe("room:123")

      # Broadcast to a topic
      Events.Infra.PubSub.broadcast("room:123", :new_message, %{text: "Hello"})

      # Or use Phoenix.PubSub directly
      Phoenix.PubSub.broadcast(Events.Infra.PubSub.server(), "room:123", {:new_message, payload})

  ## Adapter Selection

  - `PUBSUB_ADAPTER=local` - Uses local adapter directly
  - `PUBSUB_ADAPTER=redis` - Uses Redis adapter
  - Otherwise, auto-detects Redis availability
  """

  @pubsub_name __MODULE__

  # ==============================================================================
  # Child Spec for Supervision Tree
  # ==============================================================================

  @doc """
  Returns the child spec for starting the PubSub supervisor.

  Add to your application supervision tree:

      children = [
        Events.Infra.PubSub,
        # ...
      ]
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {OmPubSub, :start_link, [Keyword.merge([name: @pubsub_name], opts)]},
      type: :supervisor
    }
  end

  # ==============================================================================
  # Public API
  # ==============================================================================

  @doc """
  Returns the name of the PubSub server.

  Use this when calling Phoenix.PubSub functions directly:

      Phoenix.PubSub.broadcast(Events.Infra.PubSub.server(), "topic", message)
  """
  @spec server() :: atom()
  def server, do: OmPubSub.server(@pubsub_name)

  @doc """
  Subscribe the current process to a topic.

  ## Examples

      Events.Infra.PubSub.subscribe("room:123")
      Events.Infra.PubSub.subscribe("user:\#{user_id}")
  """
  @spec subscribe(String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe(topic, opts \\ []) do
    OmPubSub.subscribe(@pubsub_name, topic, opts)
  end

  @doc """
  Unsubscribe the current process from a topic.

  ## Examples

      Events.Infra.PubSub.unsubscribe("room:123")
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic) do
    OmPubSub.unsubscribe(@pubsub_name, topic)
  end

  @doc """
  Broadcast a message to all subscribers of a topic.

  ## Examples

      Events.Infra.PubSub.broadcast("room:123", :new_message, %{text: "Hello"})
      Events.Infra.PubSub.broadcast("user:notifications", :alert, %{level: :warning})
  """
  @spec broadcast(String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast(topic, event, payload) do
    OmPubSub.broadcast(@pubsub_name, topic, event, payload)
  end

  @doc """
  Broadcast a message to all subscribers except the sender.

  ## Examples

      Events.Infra.PubSub.broadcast_from(self(), "room:123", :typing, %{user: "Alice"})
  """
  @spec broadcast_from(pid(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast_from(from_pid, topic, event, payload) do
    OmPubSub.broadcast_from(@pubsub_name, from_pid, topic, event, payload)
  end

  @doc """
  Direct broadcast a message (only for local subscribers on this node).

  ## Examples

      Events.Infra.PubSub.direct_broadcast(node(), "room:123", :ping, %{})
  """
  @spec direct_broadcast(node(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def direct_broadcast(node, topic, event, payload) do
    OmPubSub.direct_broadcast(@pubsub_name, node, topic, event, payload)
  end

  @doc """
  Returns the current adapter type (:redis or :local).
  """
  @spec adapter() :: :redis | :local
  def adapter do
    OmPubSub.adapter(@pubsub_name)
  end

  @doc """
  Checks if Redis adapter is currently active.
  """
  @spec redis?() :: boolean()
  def redis?, do: OmPubSub.redis?(@pubsub_name)

  @doc """
  Checks if local adapter is currently active.
  """
  @spec local?() :: boolean()
  def local?, do: OmPubSub.local?(@pubsub_name)
end
