defmodule Events.PubSub do
  @moduledoc """
  PubSub wrapper with Redis adapter and local fallback.

  Uses Redis for cross-node communication when available,
  automatically falls back to local PG2 when Redis is unavailable.

  ## Configuration

  Uses the same Redis configuration as the cache system:
  - `REDIS_HOST` - Redis host (default: "localhost")
  - `REDIS_PORT` - Redis port (default: 6379)
  - `PUBSUB_ADAPTER` - Force adapter: "redis" or "local" (optional)

  ## Usage

  The module starts a Phoenix.PubSub server named `Events.PubSub.Server`.
  You can use the standard Phoenix.PubSub functions or the convenience
  wrappers provided by this module:

      # Subscribe to a topic
      Events.PubSub.subscribe("room:123")

      # Broadcast to a topic
      Events.PubSub.broadcast("room:123", :new_message, %{text: "Hello"})

      # Or use Phoenix.PubSub directly
      Phoenix.PubSub.broadcast(Events.PubSub.Server, "room:123", {:new_message, payload})

  ## Adapter Selection

  At startup, the module checks Redis availability:
  1. If `PUBSUB_ADAPTER=local` is set, uses local adapter directly
  2. If `PUBSUB_ADAPTER=redis` is set, uses Redis adapter (fails if unavailable)
  3. Otherwise, attempts Redis connection and falls back to local if unavailable
  """

  use Supervisor
  require Logger

  @pubsub_name Events.PubSub.Server

  # ==============================================================================
  # Supervisor API
  # ==============================================================================

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    adapter = determine_adapter()
    Logger.info("PubSub starting with #{adapter} adapter")

    children = [pubsub_child_spec(adapter)]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ==============================================================================
  # Public API
  # ==============================================================================

  @doc """
  Returns the name of the PubSub server.

  Use this when calling Phoenix.PubSub functions directly:

      Phoenix.PubSub.broadcast(Events.PubSub.server(), "topic", message)
  """
  @spec server() :: atom()
  def server, do: @pubsub_name

  @doc """
  Subscribe the current process to a topic.

  ## Examples

      Events.PubSub.subscribe("room:123")
      Events.PubSub.subscribe("user:\#{user_id}")
  """
  @spec subscribe(String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe(topic, opts \\ []) do
    Phoenix.PubSub.subscribe(@pubsub_name, topic, opts)
  end

  @doc """
  Unsubscribe the current process from a topic.

  ## Examples

      Events.PubSub.unsubscribe("room:123")
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub_name, topic)
  end

  @doc """
  Broadcast a message to all subscribers of a topic.

  ## Examples

      Events.PubSub.broadcast("room:123", :new_message, %{text: "Hello"})
      Events.PubSub.broadcast("user:notifications", :alert, %{level: :warning})
  """
  @spec broadcast(String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(@pubsub_name, topic, {event, payload})
  end

  @doc """
  Broadcast a message to all subscribers except the sender.

  ## Examples

      Events.PubSub.broadcast_from(self(), "room:123", :typing, %{user: "Alice"})
  """
  @spec broadcast_from(pid(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast_from(from_pid, topic, event, payload) do
    Phoenix.PubSub.broadcast_from(@pubsub_name, from_pid, topic, {event, payload})
  end

  @doc """
  Direct broadcast a message (only for local subscribers on this node).

  ## Examples

      Events.PubSub.direct_broadcast(node(), "room:123", :ping, %{})
  """
  @spec direct_broadcast(node(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def direct_broadcast(node, topic, event, payload) do
    Phoenix.PubSub.direct_broadcast(node, @pubsub_name, topic, {event, payload})
  end

  @doc """
  Returns the current adapter type (:redis or :local).
  """
  @spec adapter() :: :redis | :local
  def adapter do
    # Check which adapter is actually running by examining the supervisor children
    case Supervisor.which_children(__MODULE__) do
      [{_, pid, _, _}] when is_pid(pid) ->
        case :sys.get_state(pid) do
          %{adapter: Phoenix.PubSub.Redis} -> :redis
          _ -> :local
        end

      _ ->
        :local
    end
  rescue
    _ -> :local
  end

  @doc """
  Checks if Redis adapter is currently active.
  """
  @spec redis?() :: boolean()
  def redis?, do: adapter() == :redis

  # ==============================================================================
  # Private Functions
  # ==============================================================================

  defp determine_adapter do
    case System.get_env("PUBSUB_ADAPTER") do
      "local" ->
        Logger.debug("PubSub: Using local adapter (forced via PUBSUB_ADAPTER)")
        :local

      "redis" ->
        Logger.debug("PubSub: Using Redis adapter (forced via PUBSUB_ADAPTER)")
        :redis

      _ ->
        if redis_available?() do
          Logger.debug("PubSub: Redis available, using Redis adapter")
          :redis
        else
          Logger.warning("PubSub: Redis unavailable, falling back to local adapter")
          :local
        end
    end
  end

  defp redis_available? do
    host = get_redis_host()
    port = get_redis_port()

    case Redix.start_link(host: host, port: port, timeout: 5_000) do
      {:ok, conn} ->
        result =
          case Redix.command(conn, ["PING"]) do
            {:ok, "PONG"} -> true
            _ -> false
          end

        Redix.stop(conn)
        result

      {:error, reason} ->
        Logger.debug("PubSub: Redis connection failed: #{inspect(reason)}")
        false
    end
  end

  defp pubsub_child_spec(:redis) do
    {Phoenix.PubSub,
     name: @pubsub_name, adapter: Phoenix.PubSub.Redis, url: redis_url(), node_name: node_name()}
  end

  defp pubsub_child_spec(:local) do
    {Phoenix.PubSub, name: @pubsub_name}
  end

  defp redis_url do
    host = get_redis_host()
    port = get_redis_port()
    "redis://#{host}:#{port}"
  end

  defp get_redis_host do
    System.get_env("REDIS_HOST", "localhost")
  end

  defp get_redis_port do
    case System.get_env("REDIS_PORT") do
      nil ->
        6379

      port ->
        case Integer.parse(port) do
          {parsed, ""} -> parsed
          _ ->
            Logger.warning("Invalid REDIS_PORT value '#{port}', using default 6379")
            6379
        end
    end
  end

  defp node_name do
    # For named nodes, use the actual node name
    # For unnamed nodes (like in tests), generate a unique name
    case node() do
      :nonode@nohost ->
        # Generate a unique node name for unnamed nodes
        :"events_pubsub_#{System.unique_integer([:positive])}"

      named_node ->
        named_node
    end
  end
end
