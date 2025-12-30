defmodule OmPubSub.Adapters.Postgres do
  @moduledoc """
  PostgreSQL LISTEN/NOTIFY adapter for OmPubSub.

  Uses PostgreSQL's built-in pub/sub mechanism via `Postgrex.Notifications`.
  No additional infrastructure required beyond your existing database.

  ## How It Works

  1. Maintains a dedicated Postgrex connection for LISTEN/NOTIFY
  2. Subscribers register with this GenServer
  3. On broadcast, sends NOTIFY to Postgres
  4. Postgres notifies all listeners, which dispatch to subscribers

  ## Limitations

  - **Payload size**: 8000 bytes max (Postgres limitation)
  - **Same database**: Only works across connections to the same DB
  - **Serialization**: Payloads are JSON-encoded strings

  ## Usage

  This adapter is used internally by OmPubSub when configured with `:postgres` adapter.

      {OmPubSub, name: MyApp.PubSub, adapter: :postgres, repo: MyApp.Repo}
  """

  use GenServer
  require Logger

  @behaviour OmPubSub.Adapter

  defstruct [
    :name,
    :notifications_pid,
    :repo,
    :conn_opts,
    subscribers: %{}
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc false
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl OmPubSub.Adapter
  def subscribe(server, topic, opts \\ []) do
    GenServer.call(server, {:subscribe, topic, self(), opts})
  end

  @impl OmPubSub.Adapter
  def unsubscribe(server, topic) do
    GenServer.call(server, {:unsubscribe, topic, self()})
  end

  @impl OmPubSub.Adapter
  def broadcast(server, topic, message) do
    GenServer.call(server, {:broadcast, topic, message})
  end

  @impl OmPubSub.Adapter
  def broadcast_from(server, from_pid, topic, message) do
    GenServer.call(server, {:broadcast_from, from_pid, topic, message})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    repo = Keyword.get(opts, :repo)
    conn_opts = Keyword.get(opts, :conn_opts, [])

    # Get connection opts from repo config if repo provided
    final_conn_opts = resolve_conn_opts(repo, conn_opts)

    case Postgrex.Notifications.start_link(final_conn_opts) do
      {:ok, notifications_pid} ->
        Logger.info("OmPubSub Postgres adapter started: #{inspect(name)}")

        state = %__MODULE__{
          name: name,
          notifications_pid: notifications_pid,
          repo: repo,
          conn_opts: final_conn_opts,
          subscribers: %{}
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start Postgres notifications: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:subscribe, topic, pid, _opts}, _from, state) do
    # Monitor the subscriber process
    Process.monitor(pid)

    # Listen to the channel in Postgres
    channel = topic_to_channel(topic)

    case Postgrex.Notifications.listen(state.notifications_pid, channel) do
      {:ok, _ref} ->
        # Add subscriber to our registry
        subscribers = Map.update(state.subscribers, topic, [pid], fn pids ->
          if pid in pids, do: pids, else: [pid | pids]
        end)

        {:reply, :ok, %{state | subscribers: subscribers}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unsubscribe, topic, pid}, _from, state) do
    subscribers = Map.update(state.subscribers, topic, [], fn pids ->
      List.delete(pids, pid)
    end)

    # Unlisten if no more subscribers for this topic
    if subscribers[topic] == [] do
      channel = topic_to_channel(topic)
      Postgrex.Notifications.unlisten(state.notifications_pid, channel)
    end

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:broadcast, topic, message}, _from, state) do
    result = do_broadcast(state, topic, message, nil)
    {:reply, result, state}
  end

  def handle_call({:broadcast_from, from_pid, topic, message}, _from, state) do
    result = do_broadcast(state, topic, message, from_pid)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info({:notification, _connection_pid, _ref, channel, payload}, state) do
    topic = channel_to_topic(channel)

    case decode_payload(payload) do
      {:ok, %{"from" => from_pid_str, "message" => message}} ->
        from_pid = decode_pid(from_pid_str)
        dispatch_to_subscribers(state, topic, message, from_pid)

      {:ok, message} ->
        dispatch_to_subscribers(state, topic, message, nil)

      {:error, _} ->
        # Raw string payload, dispatch as-is
        dispatch_to_subscribers(state, topic, payload, nil)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead subscriber from all topics
    subscribers =
      Map.new(state.subscribers, fn {topic, pids} ->
        {topic, List.delete(pids, pid)}
      end)

    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp resolve_conn_opts(nil, conn_opts), do: conn_opts

  defp resolve_conn_opts(repo, conn_opts) do
    # Try to get connection config from repo
    repo_config = repo.config()

    base_opts = [
      hostname: Keyword.get(repo_config, :hostname, "localhost"),
      port: Keyword.get(repo_config, :port, 5432),
      database: Keyword.get(repo_config, :database),
      username: Keyword.get(repo_config, :username),
      password: Keyword.get(repo_config, :password)
    ]

    # Handle URL-based config
    base_opts =
      case Keyword.get(repo_config, :url) do
        nil -> base_opts
        url -> parse_database_url(url) ++ base_opts
      end

    Keyword.merge(base_opts, conn_opts)
  end

  defp parse_database_url(url) do
    uri = URI.parse(url)
    userinfo = uri.userinfo || ""

    [username, password] =
      case String.split(userinfo, ":") do
        [u, p] -> [u, p]
        [u] -> [u, nil]
        _ -> [nil, nil]
      end

    [
      hostname: uri.host,
      port: uri.port || 5432,
      database: String.trim_leading(uri.path || "", "/"),
      username: username,
      password: password
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp do_broadcast(state, topic, message, from_pid) do
    channel = topic_to_channel(topic)
    payload = encode_payload(message, from_pid)

    # Check payload size (Postgres limit is ~8000 bytes)
    if byte_size(payload) > 7999 do
      {:error, :payload_too_large}
    else
      case notify(state, channel, payload) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp notify(state, channel, payload) do
    # Use a separate connection for NOTIFY to avoid blocking
    case Postgrex.query(
           state.notifications_pid,
           "SELECT pg_notify($1, $2)",
           [channel, payload]
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    # If notifications connection doesn't support query, use a new connection
    _ ->
      with {:ok, conn} <- Postgrex.start_link(state.conn_opts),
           {:ok, _} <- Postgrex.query(conn, "SELECT pg_notify($1, $2)", [channel, payload]) do
        GenServer.stop(conn)
        :ok
      else
        {:error, reason} -> {:error, reason}
      end
  end

  defp dispatch_to_subscribers(state, topic, message, from_pid) do
    subscribers = Map.get(state.subscribers, topic, [])

    Enum.each(subscribers, fn pid ->
      # Skip sender if from_pid is set
      if is_nil(from_pid) or pid != from_pid do
        send(pid, message)
      end
    end)
  end

  defp topic_to_channel(topic) do
    # Sanitize topic for Postgres channel name
    # Channels can't have spaces or special chars
    topic
    |> String.replace(~r/[^a-zA-Z0-9_:]/, "_")
    |> String.slice(0, 63)
  end

  defp channel_to_topic(channel) do
    # Channel is the sanitized topic, return as-is
    channel
  end

  defp encode_payload(message, from_pid) do
    payload = %{
      "message" => message,
      "from" => encode_pid(from_pid)
    }

    JSON.encode!(payload)
  end

  defp decode_payload(payload) do
    {:ok, JSON.decode!(payload)}
  rescue
    _ -> {:error, :invalid_json}
  end

  defp encode_pid(nil), do: nil
  defp encode_pid(pid) when is_pid(pid), do: :erlang.pid_to_list(pid) |> to_string()

  defp decode_pid(nil), do: nil
  defp decode_pid(str) when is_binary(str) do
    try do
      str |> to_charlist() |> :erlang.list_to_pid()
    rescue
      _ -> nil
    end
  end
end
