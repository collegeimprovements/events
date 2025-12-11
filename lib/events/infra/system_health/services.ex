defmodule Events.Infra.SystemHealth.Services do
  @moduledoc """
  Service health checks for all application components.

  Checks are production-safe and Docker-compatible.

  ## Configuration

  The services list is configurable via:

      config :events, Events.Infra.SystemHealth.Services,
        app_name: :my_app,
        services: [
          %{name: "Repo", module: MyApp.Repo, type: :repo, critical: true},
          %{name: "Cache", module: MyApp.Cache, type: :cache, critical: false}
        ],
        s3_module: MyApp.S3

  Default services include: Repo, Cache, Redis, S3, PubSub, Endpoint, Telemetry
  """

  alias Redix

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)
  @s3_module Application.compile_env(:events, [__MODULE__, :s3_module], Events.Services.S3)

  @default_services [
    %{name: "Repo", module: Events.Core.Repo, type: :repo, critical: true},
    %{name: "Cache", module: Events.Core.Cache, type: :cache, critical: false},
    %{name: "Redis", module: nil, type: :redis, critical: false},
    %{name: "S3", module: nil, type: :s3, critical: false},
    %{name: "PubSub", module: Events.Infra.PubSub, type: :pubsub, critical: true},
    %{name: "Endpoint", module: EventsWeb.Endpoint, type: :endpoint, critical: true},
    %{name: "Telemetry", module: EventsWeb.Telemetry, type: :telemetry, critical: false}
  ]

  @services Application.compile_env(:events, [__MODULE__, :services], @default_services)

  @doc """
  Checks all services and returns their status.
  """
  @spec check_all() :: list(map())
  def check_all do
    @services
    |> Enum.map(&check_service/1)
  end

  # Service checks

  defp check_service(%{type: :repo} = service) do
    service
    |> perform_check(&check_repo/1, &safe_get_adapter(&1, "Ecto.Postgres"))
    |> build_result(ok: "Connected & ready", error: "Database unavailable")
  end

  defp check_service(%{type: :cache} = service) do
    service
    |> perform_check(&check_cache/1, &safe_get_cache_adapter/1)
    |> build_result(ok: "Operational", error: "Performance degraded")
  end

  defp check_service(%{type: :redis} = service) do
    service
    |> perform_check(fn _ -> check_redis() end, fn _ -> safe_get_redis_adapter() end)
    |> build_result(ok: "Connected", error: "Rate limiting disabled")
  end

  defp check_service(%{type: :s3} = service) do
    service
    |> perform_check(fn _ -> check_s3() end, fn _ -> safe_get_s3_adapter() end)
    |> build_result(ok: &s3_info/1, error: "File uploads unavailable")
  end

  defp check_service(%{type: :pubsub} = service) do
    service
    |> perform_check(&check_process/1, fn _ -> "Phoenix.PubSub" end)
    |> build_result(ok: "Running", error: "Live updates unavailable")
  end

  defp check_service(%{type: :endpoint} = service) do
    service
    |> perform_check(&check_endpoint/1, &safe_get_endpoint_adapter/1)
    |> build_result(ok: &endpoint_info/1, error: "HTTP requests failing")
  end

  defp check_service(%{type: :telemetry} = service) do
    service
    |> perform_check(&check_process/1, fn _ -> "Telemetry" end)
    |> build_result(ok: "Monitoring active", error: "No metrics")
  end

  # Result builders

  defp perform_check(%{module: module} = service, check_fn, adapter_fn) do
    %{
      service: service,
      result: check_fn.(module),
      adapter: adapter_fn.(module)
    }
  end

  defp build_result(%{service: service, result: result, adapter: adapter}, opts) do
    case result do
      :ok ->
        build_ok_result(service, adapter, opts[:ok])

      {:ok, data} ->
        build_ok_result(service, adapter, opts[:ok], data)

      {:error, reason} ->
        build_error_result(service, adapter, reason, opts[:error])
    end
  end

  defp build_ok_result(service, adapter, info_fn, data) when is_function(info_fn) do
    build_ok_result(service, adapter, info_fn.(data))
  end

  defp build_ok_result(service, adapter, info_fn) when is_function(info_fn) do
    build_ok_result(service, adapter, info_fn.(nil))
  end

  defp build_ok_result(service, adapter, info) do
    %{
      name: service.name,
      status: :ok,
      adapter: adapter,
      critical: service.critical,
      info: info,
      impact: nil
    }
  end

  defp build_error_result(service, adapter, reason, impact) do
    %{
      name: service.name,
      status: :error,
      adapter: adapter,
      critical: service.critical,
      info: format_error(reason),
      impact: impact
    }
  end

  defp s3_info(bucket), do: "Bucket: #{bucket}"
  defp endpoint_info({:ok, port}), do: "Port #{port}"
  defp endpoint_info(port) when is_integer(port), do: "Port #{port}"
  defp endpoint_info(:ok), do: "Running"
  defp endpoint_info(_), do: "Running"

  # Health check implementations

  defp check_repo(module) do
    module
    |> verify_process_alive()
    |> perform_repo_query()
  end

  defp check_cache(module) do
    module
    |> verify_process_alive()
    |> perform_cache_test()
  end

  defp verify_process_alive(module) do
    if process_alive?(module), do: {:ok, module}, else: {:error, "Process not running"}
  end

  defp perform_repo_query({:ok, module}) do
    module.query("SELECT 1", [], timeout: 5_000)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp perform_repo_query(error), do: error

  defp perform_cache_test({:ok, module}) do
    {:__health_check__, System.unique_integer()}
    |> then(fn test_key ->
      module.put(test_key, true, ttl: :timer.seconds(1))
      module.get(test_key)
      module.delete(test_key)
      :ok
    end)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp perform_cache_test(error), do: error

  defp check_redis do
    with {:ok, redix_opts} <- redis_redix_config(),
         {:ok, conn} <- Redix.start_link(redix_opts) do
      conn
      |> perform_redis_ping()
      |> tap(fn _ -> Redix.stop(conn) end)
    else
      {:error, :not_configured} -> {:error, "Redis backend not configured"}
      {:error, {:unsupported_backend, backend}} -> format_unsupported_backend(backend)
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp check_s3 do
    s3_context()
    |> perform_s3_list()
  end

  defp check_endpoint(module) do
    module
    |> verify_process_alive()
    |> extract_endpoint_config()
  end

  defp check_process(module) do
    if process_alive?(module), do: :ok, else: {:error, "Process not running"}
  end

  defp perform_redis_ping(conn) do
    Redix.command(conn, ["PING"])
    |> case do
      {:ok, "PONG"} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
      other -> {:error, inspect(other)}
    end
  end

  defp format_unsupported_backend(backend) do
    backend
    |> Module.split()
    |> List.last()
    |> then(&{:error, "Unsupported Redis backend #{&1}"})
  end

  defp perform_s3_list({:ok, config, bucket}) do
    uri = "s3://#{bucket}/"

    case @s3_module.list(uri, config, limit: 1) do
      {:ok, _result} -> {:ok, bucket}
      {:error, {:s3_error, status, _body}} -> {:error, "S3 error (HTTP #{status})"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp perform_s3_list(error), do: error

  defp extract_endpoint_config({:ok, module}) do
    module.config(:http)
    |> extract_port_from_config()
  rescue
    _ -> :ok
  end

  defp extract_endpoint_config(error), do: error

  defp extract_port_from_config(config) when is_list(config) do
    case Keyword.get(config, :port) do
      port when is_integer(port) -> {:ok, port}
      _ -> :ok
    end
  end

  defp extract_port_from_config(_), do: :ok

  # Helper functions

  defp process_alive?(module) when is_atom(module) do
    module
    |> Process.whereis()
    |> case do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  defp safe_get_adapter(module, default) do
    module.__adapter__()
    |> Module.split()
    |> List.last()
    |> then(&"Ecto.#{&1}")
  rescue
    _ -> default
  end

  defp safe_get_cache_adapter(module) do
    # First try to get the runtime adapter from the running process
    try do
      module.__adapter__()
      |> format_adapter_name()
    rescue
      _ ->
        # Fallback to configured adapter from application environment
        Application.get_env(@app_name, module, [])
        |> Keyword.get(:adapter)
        |> case do
          nil -> "Nebulex (not configured)"
          adapter -> format_adapter_name(adapter)
        end
    end
  end

  defp format_adapter_name(adapter) when is_atom(adapter) do
    case adapter do
      NebulexRedisAdapter ->
        "Nebulex.Redis"

      _ ->
        adapter
        |> Module.split()
        |> List.last()
        |> then(&"Nebulex.#{&1}")
    end
  end

  defp safe_get_redis_adapter do
    Application.get_env(:hammer, :backend)
    |> extract_backend_type()
  rescue
    _ -> "Hammer.Redis"
  end

  defp extract_backend_type({backend_module, _opts}) do
    backend_module
    |> Module.split()
    |> List.last()
    |> then(&"Hammer.#{&1}")
  end

  defp extract_backend_type(_), do: "Hammer.Redis"

  defp redis_redix_config do
    Application.get_env(:hammer, :backend)
    |> parse_redis_backend()
  end

  defp parse_redis_backend({Hammer.Backend.Redis, opts}) do
    {:ok, Keyword.get(opts, :redix_config, [])}
  end

  defp parse_redis_backend({backend, _opts}), do: {:error, {:unsupported_backend, backend}}
  defp parse_redis_backend(_), do: {:error, :not_configured}

  defp safe_get_endpoint_adapter(module) do
    module.config(:adapter)
    |> parse_endpoint_adapter()
  rescue
    _ -> "Bandit"
  end

  defp parse_endpoint_adapter(nil), do: "Bandit"

  defp parse_endpoint_adapter(adapter) do
    adapter
    |> Module.split()
    |> detect_adapter_type()
  end

  defp detect_adapter_type(["Bandit" | _]), do: "Bandit"
  defp detect_adapter_type(["Cowboy" | _]), do: "Cowboy"
  defp detect_adapter_type([first | _]) when is_binary(first), do: first
  defp detect_adapter_type(_), do: "Phoenix"

  defp safe_get_s3_adapter do
    "ReqS3"
  end

  defp s3_context do
    # Check required env vars
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")
    bucket = System.get_env("S3_BUCKET")

    cond do
      is_nil(access_key) ->
        {:error, "AWS_ACCESS_KEY_ID not set"}

      is_nil(secret_key) ->
        {:error, "AWS_SECRET_ACCESS_KEY not set"}

      is_nil(bucket) ->
        {:error, "S3 bucket not configured"}

      true ->
        config = @s3_module.Config.from_env()
        {:ok, config, bucket}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp format_error(reason) when is_binary(reason) do
    String.slice(reason, 0, 50)
  end

  defp format_error(reason) do
    reason
    |> inspect()
    |> String.slice(0, 50)
  end
end
