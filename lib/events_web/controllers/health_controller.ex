defmodule EventsWeb.HealthController do
  @moduledoc """
  Health check endpoints for Docker Swarm and load balancers.

  Provides three endpoints:
  - `/health` - Basic liveness check (is the app running?)
  - `/health/ready` - Readiness check (is the app ready to serve traffic?)
  - `/health/cluster` - Cluster status (which nodes are connected?)
  """

  use EventsWeb, :controller

  @doc """
  Basic liveness check. Returns 200 if the application is running.
  Used by Docker HEALTHCHECK and load balancers.
  """
  def index(conn, _params) do
    json(conn, %{status: "ok", node: node_name()})
  end

  @doc """
  Readiness check. Verifies the app can handle requests.
  Checks database and Redis connectivity.
  """
  def ready(conn, _params) do
    checks = %{
      database: check_database(),
      cache: check_cache(),
      pubsub: check_pubsub()
    }

    all_healthy = Enum.all?(checks, fn {_k, v} -> v.status == :ok end)

    status = if all_healthy, do: :ok, else: :degraded
    http_status = if all_healthy, do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(%{
      status: status,
      node: node_name(),
      checks: checks
    })
  end

  @doc """
  Cluster status. Shows connected Erlang nodes.
  Useful for debugging clustering issues.
  """
  def cluster(conn, _params) do
    connected_nodes = Node.list()

    json(conn, %{
      status: "ok",
      node: node_name(),
      connected_nodes: Enum.map(connected_nodes, &Atom.to_string/1),
      connected_count: length(connected_nodes),
      cluster_size: length(connected_nodes) + 1
    })
  end

  # Private functions

  defp node_name do
    node() |> Atom.to_string()
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Events.Core.Repo, "SELECT 1", []) do
      {:ok, _} ->
        %{status: :ok}

      {:error, reason} ->
        %{status: :error, message: inspect(reason)}
    end
  rescue
    e ->
      %{status: :error, message: Exception.message(e)}
  end

  defp check_cache do
    case Events.Infra.KillSwitch.check(:cache) do
      :enabled ->
        # Try a simple cache operation
        test_key = {:health_check, System.unique_integer()}

        case Events.Core.Cache.put(test_key, "ok", ttl: 1000) do
          :ok -> %{status: :ok, adapter: cache_adapter()}
          _ -> %{status: :error, message: "Cache write failed"}
        end

      {:disabled, reason} ->
        %{status: :disabled, message: reason}
    end
  rescue
    e ->
      %{status: :error, message: Exception.message(e)}
  end

  defp check_pubsub do
    %{
      status: :ok,
      adapter: Events.Infra.PubSub.adapter(),
      server: Events.Infra.PubSub.server() |> Atom.to_string()
    }
  rescue
    e ->
      %{status: :error, message: Exception.message(e)}
  end

  defp cache_adapter do
    case Application.get_env(:events, Events.Core.Cache)[:adapter] do
      NebulexRedisAdapter -> :redis
      Nebulex.Adapters.Local -> :local
      Nebulex.Adapters.Nil -> nil
      other -> other
    end
  end
end
