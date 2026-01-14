defmodule OmPubSub do
  @moduledoc """
  Phoenix.PubSub wrapper with multiple adapters and automatic fallback.

  OmPubSub provides a unified PubSub interface with:
  - **Multiple adapters**: Redis, PostgreSQL, or local
  - **Automatic fallback**: Try adapters in order until one works
  - **Graceful degradation**: Works even when external services are down
  - **Convenience API**: Simple subscribe/broadcast functions
  - **Telemetry integration**: Built-in telemetry and Redis monitoring

  ## Adapters

  | Adapter | Use Case | Requirements |
  |---------|----------|--------------|
  | `:redis` | Multi-node, high throughput | Redis server |
  | `:postgres` | Shared database, DB-triggered events | PostgreSQL (already have it) |
  | `:local` | Single node, development | None |

  ## Quick Start

  ### 1. Add to Supervision Tree

      children = [
        {OmPubSub, name: MyApp.PubSub},
        # ...
      ]

  ### 2. Subscribe and Broadcast

      OmPubSub.subscribe(MyApp.PubSub, "room:123")
      OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hello"})

  ## Adapter Selection

  ### Force a Specific Adapter

      # Redis only
      {OmPubSub, name: MyApp.PubSub, adapter: :redis}

      # PostgreSQL (requires repo)
      {OmPubSub, name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo}

      # Local only
      {OmPubSub, name: MyApp.PubSub, adapter: :local}

  ### Auto-Detection (Default)

      # Tries Redis -> falls back to Local
      {OmPubSub, name: MyApp.PubSub, adapter: :auto}

  ### Custom Fallback Chain

      # Try Redis -> Postgres -> Local
      {OmPubSub, name: MyApp.PubSub,
        fallback_chain: [:redis, :postgres, :local],
        repo: MyApp.Repo}

  ## Environment Variables

  - `PUBSUB_ADAPTER` - Force adapter: "redis", "postgres", or "local"
  - `REDIS_HOST` - Redis host (default: "localhost")
  - `REDIS_PORT` - Redis port (default: 6379)

  ## PostgreSQL Adapter Notes

  - Uses LISTEN/NOTIFY (built into PostgreSQL)
  - Payload limit: 8KB (PostgreSQL limitation)
  - Great for DB-triggered events and simpler deployments
  - Requires `:repo` option or `:conn_opts`
  """

  use Supervisor
  require Logger

  alias FnTypes.Config, as: Cfg

  @type adapter :: :redis | :postgres | :local

  @type t :: %__MODULE__{
          name: atom(),
          server_name: atom(),
          adapter: adapter()
        }

  defstruct [:name, :server_name, :adapter]

  @default_fallback_chain [:redis, :local]

  # ==============================================================================
  # Supervisor API
  # ==============================================================================

  @doc """
  Starts the PubSub supervisor.

  ## Options

  - `:name` - Required. The name for this PubSub instance
  - `:adapter` - Force adapter: `:redis`, `:postgres`, `:local`, or `:auto` (default: `:auto`)
  - `:fallback_chain` - List of adapters to try in order (default: `[:redis, :local]`)
  - `:repo` - Ecto repo for Postgres adapter (required if using `:postgres`)
  - `:conn_opts` - Direct Postgrex connection opts (alternative to `:repo`)
  - `:redis_host` - Redis host (default: from REDIS_HOST env or "localhost")
  - `:redis_port` - Redis port (default: from REDIS_PORT env or 6379)

  ## Examples

      # Auto-detect adapter (tries Redis, falls back to local)
      OmPubSub.start_link(name: MyApp.PubSub)

      # Force local adapter
      OmPubSub.start_link(name: MyApp.PubSub, adapter: :local)

      # Force PostgreSQL adapter
      OmPubSub.start_link(name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo)

      # Custom fallback chain
      OmPubSub.start_link(name: MyApp.PubSub,
        fallback_chain: [:redis, :postgres, :local],
        repo: MyApp.Repo)

      # Custom Redis config
      OmPubSub.start_link(name: MyApp.PubSub, redis_host: "redis.local", redis_port: 6380)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    server_name = server_name(name)
    adapter = determine_adapter(opts)

    Logger.info("PubSub #{inspect(name)} starting with #{adapter} adapter")

    :persistent_term.put({__MODULE__, name}, %__MODULE__{
      name: name,
      server_name: server_name,
      adapter: adapter
    })

    children = [pubsub_child_spec(adapter, server_name, opts)]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # ==============================================================================
  # Public API
  # ==============================================================================

  @doc """
  Returns the name of the PubSub server.

  Use this when calling Phoenix.PubSub functions directly:

      Phoenix.PubSub.broadcast(OmPubSub.server(MyApp.PubSub), "topic", message)
  """
  @spec server(atom()) :: atom()
  def server(name), do: get_config(name).server_name

  @doc """
  Subscribe the current process to a topic.

  ## Examples

      OmPubSub.subscribe(MyApp.PubSub, "room:123")
      OmPubSub.subscribe(MyApp.PubSub, "user:\#{user_id}")
  """
  @spec subscribe(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe(name, topic, opts \\ []) do
    Phoenix.PubSub.subscribe(server(name), topic, opts)
  end

  @doc """
  Unsubscribe the current process from a topic.

  ## Examples

      OmPubSub.unsubscribe(MyApp.PubSub, "room:123")
  """
  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(name, topic) do
    Phoenix.PubSub.unsubscribe(server(name), topic)
  end

  @doc """
  Broadcast a message to all subscribers of a topic.

  ## Examples

      OmPubSub.broadcast(MyApp.PubSub, "room:123", :new_message, %{text: "Hello"})
      OmPubSub.broadcast(MyApp.PubSub, "user:notifications", :alert, %{level: :warning})
  """
  @spec broadcast(atom(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast(name, topic, event, payload) do
    Phoenix.PubSub.broadcast(server(name), topic, {event, payload})
  end

  @doc """
  Broadcast a raw message to all subscribers of a topic.

  Unlike `broadcast/4`, this sends the message as-is without wrapping in a tuple.

  ## Examples

      OmPubSub.broadcast_raw(MyApp.PubSub, "room:123", {:custom, :message})
  """
  @spec broadcast_raw(atom(), String.t(), term()) :: :ok | {:error, term()}
  def broadcast_raw(name, topic, message) do
    Phoenix.PubSub.broadcast(server(name), topic, message)
  end

  @doc """
  Broadcast a message to all subscribers except the sender.

  ## Examples

      OmPubSub.broadcast_from(MyApp.PubSub, self(), "room:123", :typing, %{user: "Alice"})
  """
  @spec broadcast_from(atom(), pid(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def broadcast_from(name, from_pid, topic, event, payload) do
    Phoenix.PubSub.broadcast_from(server(name), from_pid, topic, {event, payload})
  end

  @doc """
  Direct broadcast a message (only for local subscribers on this node).

  ## Examples

      OmPubSub.direct_broadcast(MyApp.PubSub, node(), "room:123", :ping, %{})
  """
  @spec direct_broadcast(atom(), node(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def direct_broadcast(name, target_node, topic, event, payload) do
    Phoenix.PubSub.direct_broadcast(target_node, server(name), topic, {event, payload})
  end

  @doc """
  Returns the current adapter type.
  """
  @spec adapter(atom()) :: adapter()
  def adapter(name), do: get_config(name).adapter

  @doc """
  Checks if Redis adapter is currently active.
  """
  @spec redis?(atom()) :: boolean()
  def redis?(name), do: adapter(name) == :redis

  @doc """
  Checks if PostgreSQL adapter is currently active.
  """
  @spec postgres?(atom()) :: boolean()
  def postgres?(name), do: adapter(name) == :postgres

  @doc """
  Checks if local adapter is currently active.
  """
  @spec local?(atom()) :: boolean()
  def local?(name), do: adapter(name) == :local

  # ==============================================================================
  # Private Functions
  # ==============================================================================

  defp get_config(name), do: :persistent_term.get({__MODULE__, name})

  defp server_name(name), do: :"#{name}.Server"

  defp determine_adapter(opts) do
    case Keyword.get(opts, :adapter, :auto) do
      :auto ->
        determine_adapter_from_env(opts)

      adapter when adapter in [:local, :redis, :postgres] ->
        Logger.debug("PubSub: Using #{adapter} adapter (forced via option)")
        adapter
    end
  end

  defp determine_adapter_from_env(opts) do
    case Cfg.string("PUBSUB_ADAPTER") do
      adapter when adapter in ["local", "redis", "postgres"] ->
        adapter_atom = String.to_existing_atom(adapter)
        Logger.debug("PubSub: Using #{adapter} adapter (forced via PUBSUB_ADAPTER)")
        adapter_atom

      _ ->
        fallback_chain = Keyword.get(opts, :fallback_chain, @default_fallback_chain)
        determine_adapter_from_chain(fallback_chain, opts)
    end
  end

  defp determine_adapter_from_chain([], _opts) do
    Logger.warning("PubSub: No adapters available in fallback chain, using local")
    :local
  end

  defp determine_adapter_from_chain([adapter | rest], opts) do
    case adapter_available?(adapter, opts) do
      true ->
        Logger.debug("PubSub: #{adapter} available, using #{adapter} adapter")
        adapter

      false ->
        Logger.debug("PubSub: #{adapter} unavailable, trying next in chain")
        determine_adapter_from_chain(rest, opts)
    end
  end

  defp adapter_available?(:local, _opts), do: true

  defp adapter_available?(:redis, opts) do
    host = get_redis_host(opts)
    port = get_redis_port(opts)

    case Redix.start_link(host: host, port: port, timeout: 5_000) do
      {:ok, conn} ->
        result = Redix.command(conn, ["PING"]) == {:ok, "PONG"}
        Redix.stop(conn)
        result

      {:error, reason} ->
        Logger.debug("PubSub: Redis connection failed: #{inspect(reason)}")
        false
    end
  end

  defp adapter_available?(:postgres, opts) do
    repo = Keyword.get(opts, :repo)
    conn_opts = Keyword.get(opts, :conn_opts, [])

    case {repo, conn_opts} do
      {nil, []} ->
        Logger.debug("PubSub: No Postgres config (need :repo or :conn_opts)")
        false

      {nil, conn_opts} ->
        check_postgres_connection(conn_opts)

      {repo, _} ->
        check_repo_available(repo)
    end
  end

  defp check_repo_available(repo) do
    case Process.whereis(repo) do
      nil ->
        Logger.debug("PubSub: Repo #{inspect(repo)} not started")
        false

      _pid ->
        true
    end
  end

  defp check_postgres_connection(conn_opts) do
    case Postgrex.start_link(conn_opts ++ [timeout: 5_000]) do
      {:ok, conn} ->
        GenServer.stop(conn)
        true

      {:error, reason} ->
        Logger.debug("PubSub: Postgres connection failed: #{inspect(reason)}")
        false
    end
  end

  defp pubsub_child_spec(:redis, server_name, opts) do
    {Phoenix.PubSub,
     name: server_name,
     adapter: Phoenix.PubSub.Redis,
     url: redis_url(opts),
     node_name: node_name()}
  end

  defp pubsub_child_spec(:postgres, server_name, opts) do
    {OmPubSub.Adapters.Postgres,
     name: server_name,
     repo: Keyword.get(opts, :repo),
     conn_opts: Keyword.get(opts, :conn_opts, [])}
  end

  defp pubsub_child_spec(:local, server_name, _opts) do
    {Phoenix.PubSub, name: server_name}
  end

  defp redis_url(opts) do
    host = get_redis_host(opts)
    port = get_redis_port(opts)
    "redis://#{host}:#{port}"
  end

  defp get_redis_host(opts) do
    Keyword.get(opts, :redis_host) || Cfg.string("REDIS_HOST", "localhost")
  end

  defp get_redis_port(opts) do
    Keyword.get(opts, :redis_port) || Cfg.integer("REDIS_PORT", 6379)
  end

  defp node_name do
    case node() do
      :nonode@nohost -> :"om_pubsub_#{System.unique_integer([:positive])}"
      named_node -> named_node
    end
  end
end
