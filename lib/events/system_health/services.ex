defmodule Events.SystemHealth.Services do
  @moduledoc """
  Service health checks for all application components.

  Checks are production-safe and Docker-compatible.
  """

  alias Redix

  @services [
    %{name: "Repo", module: Events.Repo, type: :repo, critical: true},
    %{name: "Cache", module: Events.Cache, type: :cache, critical: false},
    %{name: "Redis", module: nil, type: :redis, critical: false},
    %{name: "PubSub", module: Events.PubSub, type: :pubsub, critical: true},
    %{name: "Endpoint", module: EventsWeb.Endpoint, type: :endpoint, critical: true},
    %{name: "Telemetry", module: EventsWeb.Telemetry, type: :telemetry, critical: false}
  ]

  @doc """
  Checks all services and returns their status.
  """
  @spec check_all() :: list(map())
  def check_all do
    Enum.map(@services, &check_service/1)
  end

  # Service checks

  defp check_service(%{name: name, module: module, type: :repo, critical: critical}) do
    adapter = safe_get_adapter(module, "Ecto.Postgres")

    case check_repo(module) do
      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: adapter,
          critical: critical,
          info: "Connected & ready",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: adapter,
          critical: critical,
          info: format_error(reason),
          impact: "Database unavailable"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :cache, critical: critical}) do
    adapter = safe_get_cache_adapter(module)

    case check_cache(module) do
      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: adapter,
          critical: critical,
          info: "Operational",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: adapter,
          critical: critical,
          info: format_error(reason),
          impact: "Performance degraded"
        }
    end
  end

  defp check_service(%{name: name, type: :redis, critical: critical}) do
    adapter = safe_get_redis_adapter()

    case check_redis() do
      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: adapter,
          critical: critical,
          info: "Connected",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: adapter,
          critical: critical,
          info: format_error(reason),
          impact: "Rate limiting disabled"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :pubsub, critical: critical}) do
    case check_process(module) do
      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: "Phoenix.PubSub",
          critical: critical,
          info: "Running",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: "Phoenix.PubSub",
          critical: critical,
          info: format_error(reason),
          impact: "Live updates unavailable"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :endpoint, critical: critical}) do
    adapter = safe_get_endpoint_adapter(module)

    case check_endpoint(module) do
      {:ok, port} ->
        %{
          name: name,
          status: :ok,
          adapter: adapter,
          critical: critical,
          info: "Port #{port}",
          impact: nil
        }

      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: adapter,
          critical: critical,
          info: "Running",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: adapter,
          critical: critical,
          info: format_error(reason),
          impact: "HTTP requests failing"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :telemetry, critical: critical}) do
    case check_process(module) do
      :ok ->
        %{
          name: name,
          status: :ok,
          adapter: "Telemetry",
          critical: critical,
          info: "Monitoring active",
          impact: nil
        }

      {:error, reason} ->
        %{
          name: name,
          status: :error,
          adapter: "Telemetry",
          critical: critical,
          info: format_error(reason),
          impact: "No metrics"
        }
    end
  end

  # Health check implementations

  defp check_repo(module) do
    if process_alive?(module) do
      try do
        # Use a simple query with timeout
        case module.query("SELECT 1", [], timeout: 5_000) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Process not running"}
    end
  end

  defp check_cache(module) do
    if process_alive?(module) do
      try do
        test_key = {:__health_check__, System.unique_integer()}
        module.put(test_key, true, ttl: :timer.seconds(1))
        module.get(test_key)
        module.delete(test_key)
        :ok
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Process not running"}
    end
  end

  defp check_redis do
    with {:ok, redix_opts} <- redis_redix_config(),
         {:ok, conn} <- Redix.start_link(redix_opts) do
      try do
        case Redix.command(conn, ["PING"]) do
          {:ok, "PONG"} -> :ok
          {:error, reason} -> {:error, inspect(reason)}
          other -> {:error, inspect(other)}
        end
      after
        Redix.stop(conn)
      end
    else
      {:error, :not_configured} ->
        {:error, "Redis backend not configured"}

      {:error, {:unsupported_backend, backend}} ->
        backend_name = backend |> Module.split() |> List.last()
        {:error, "Unsupported Redis backend #{backend_name}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp check_endpoint(module) do
    if process_alive?(module) do
      try do
        config = module.config(:http)

        if config && config[:port] do
          {:ok, config[:port]}
        else
          :ok
        end
      rescue
        _ -> :ok
      end
    else
      {:error, "Process not running"}
    end
  end

  defp check_process(module) do
    if process_alive?(module) do
      :ok
    else
      {:error, "Process not running"}
    end
  end

  # Helper functions

  defp process_alive?(module) when is_atom(module) do
    case Process.whereis(module) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  defp safe_get_adapter(module, default) do
    try do
      adapter = module.__adapter__()
      adapter |> Module.split() |> List.last() |> then(&"Ecto.#{&1}")
    rescue
      _ -> default
    end
  end

  defp safe_get_cache_adapter(module) do
    try do
      adapter = module.__adapter__()
      adapter_type = adapter |> Module.split() |> List.last()
      "Nebulex.#{adapter_type}"
    rescue
      _ -> "Nebulex.Local"
    end
  end

  defp safe_get_redis_adapter do
    try do
      case Application.get_env(:hammer, :backend) do
        {backend_module, _opts} ->
          backend_type = backend_module |> Module.split() |> List.last()
          "Hammer.#{backend_type}"

        _ ->
          "Hammer.Redis"
      end
    rescue
      _ -> "Hammer.Redis"
    end
  end

  defp redis_redix_config do
    case Application.get_env(:hammer, :backend) do
      {Hammer.Backend.Redis, opts} ->
        {:ok, Keyword.get(opts, :redix_config, [])}

      {backend, _opts} ->
        {:error, {:unsupported_backend, backend}}

      _ ->
        {:error, :not_configured}
    end
  end

  defp safe_get_endpoint_adapter(module) do
    try do
      adapter = module.config(:adapter)

      if adapter do
        adapter_parts = adapter |> Module.split()

        case adapter_parts do
          ["Bandit" | _] -> "Bandit"
          ["Cowboy" | _] -> "Cowboy"
          _ -> List.first(adapter_parts) || "Phoenix"
        end
      else
        "Bandit"
      end
    rescue
      _ -> "Bandit"
    end
  end

  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 50)
  defp format_error(reason), do: reason |> inspect() |> String.slice(0, 50)
end
