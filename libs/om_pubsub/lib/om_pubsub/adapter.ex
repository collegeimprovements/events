defmodule OmPubSub.Adapter do
  @moduledoc """
  Behaviour for OmPubSub adapters.

  Adapters implement the core pub/sub operations. Built-in adapters:

  - `:local` - Phoenix.PubSub with PG2 (single node)
  - `:redis` - Phoenix.PubSub with Redis (multi-node)
  - `:postgres` - PostgreSQL LISTEN/NOTIFY (shared database)

  ## Implementing a Custom Adapter

      defmodule MyApp.CustomAdapter do
        @behaviour OmPubSub.Adapter

        @impl true
        def subscribe(server, topic, opts \\\\ []) do
          # Subscribe current process to topic
          :ok
        end

        @impl true
        def unsubscribe(server, topic) do
          # Unsubscribe current process from topic
          :ok
        end

        @impl true
        def broadcast(server, topic, message) do
          # Send message to all subscribers
          :ok
        end

        @impl true
        def broadcast_from(server, from_pid, topic, message) do
          # Send message to all subscribers except from_pid
          :ok
        end
      end
  """

  @doc """
  Subscribes the current process to a topic.

  ## Parameters

  - `server` - The adapter server (pid or name)
  - `topic` - The topic to subscribe to
  - `opts` - Adapter-specific options

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @callback subscribe(server :: GenServer.server(), topic :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @doc """
  Unsubscribes the current process from a topic.

  ## Parameters

  - `server` - The adapter server (pid or name)
  - `topic` - The topic to unsubscribe from

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @callback unsubscribe(server :: GenServer.server(), topic :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Broadcasts a message to all subscribers of a topic.

  ## Parameters

  - `server` - The adapter server (pid or name)
  - `topic` - The topic to broadcast to
  - `message` - The message to send

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @callback broadcast(server :: GenServer.server(), topic :: String.t(), message :: term()) ::
              :ok | {:error, term()}

  @doc """
  Broadcasts a message to all subscribers except the sender.

  ## Parameters

  - `server` - The adapter server (pid or name)
  - `from_pid` - The sender's pid (will not receive the message)
  - `topic` - The topic to broadcast to
  - `message` - The message to send

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @callback broadcast_from(
              server :: GenServer.server(),
              from_pid :: pid(),
              topic :: String.t(),
              message :: term()
            ) :: :ok | {:error, term()}
end
