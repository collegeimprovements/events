defmodule OmHealth do
  @moduledoc """
  System health monitoring and status reporting framework.

  Provides a framework for building health check dashboards with:
  - Service health checks
  - Environment detection
  - Proxy configuration
  - Migration status
  - Formatted display output

  ## Quick Start

  Define a health module using the DSL:

      defmodule MyApp.Health do
        use OmHealth

        config do
          app_name :my_app
          repo MyApp.Repo
          endpoint MyApp.Endpoint
        end

        services do
          service :database,
            module: MyApp.Repo,
            type: :repo,
            critical: true

          service :cache,
            module: MyApp.Cache,
            type: :cache,
            critical: false
        end
      end

      # Usage
      MyApp.Health.check_all()
      MyApp.Health.display()

  ## Manual Usage

      # Environment info
      OmHealth.Environment.get_info()

      # Proxy config
      OmHealth.Proxy.get_config()

      # Display formatting
      OmHealth.Display.render(health_data)
  """

  @status_healthy :healthy
  @status_degraded :degraded
  @status_unhealthy :unhealthy

  @type health_result :: %{
          services: [service_result()],
          environment: map(),
          proxy: map(),
          timestamp: DateTime.t(),
          duration_ms: non_neg_integer()
        }

  @type service_result :: %{
          name: String.t(),
          status: :ok | :error,
          adapter: String.t(),
          critical: boolean(),
          info: String.t(),
          impact: String.t() | nil
        }

  @type overall_status :: :healthy | :degraded | :unhealthy

  # ============================================
  # DSL Macros
  # ============================================

  @doc """
  Uses the OmHealth DSL in a module.

  Provides `config/1`, `services/1` macros and defines health check functions.
  """
  defmacro __using__(_opts) do
    quote do
      import OmHealth, only: [config: 1, services: 1, service: 2, app_name: 1, repo: 1, endpoint: 1, cache: 1]

      Module.register_attribute(__MODULE__, :health_config, accumulate: false)
      Module.register_attribute(__MODULE__, :health_services, accumulate: true)

      @health_config %{
        app_name: :app,
        repo: nil,
        endpoint: nil,
        cache: nil
      }

      @before_compile OmHealth
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :health_config)
    services = Module.get_attribute(env.module, :health_services) |> Enum.reverse()

    quote do
      @config unquote(Macro.escape(config))
      @services unquote(Macro.escape(services))

      @doc "Returns the health check configuration."
      def __config__, do: @config

      @doc "Returns all registered services."
      def __services__, do: @services

      @doc "Performs all health checks."
      def check_all do
        OmHealth.run_checks(@services, @config)
      end

      @doc "Displays formatted health status."
      def display(opts \\ []) do
        health = check_all()
        OmHealth.Display.render(health, opts)
      end

      @doc "Returns overall system health status."
      def overall_status do
        check_all()
        |> OmHealth.compute_overall_status()
      end
    end
  end

  @doc """
  Defines health check configuration.
  """
  defmacro config(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Sets the application name.
  """
  defmacro app_name(name) do
    quote do
      @health_config Map.put(@health_config, :app_name, unquote(name))
    end
  end

  @doc """
  Sets the Ecto repo module.
  """
  defmacro repo(module) do
    quote do
      @health_config Map.put(@health_config, :repo, unquote(module))
    end
  end

  @doc """
  Sets the Phoenix endpoint module.
  """
  defmacro endpoint(module) do
    quote do
      @health_config Map.put(@health_config, :endpoint, unquote(module))
    end
  end

  @doc """
  Sets the cache module.
  """
  defmacro cache(module) do
    quote do
      @health_config Map.put(@health_config, :cache, unquote(module))
    end
  end

  @doc """
  Defines the services block.
  """
  defmacro services(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a service health check.

  ## Options

  - `:module` - The module to check (required for some types)
  - `:type` - Service type (:repo, :cache, :redis, :pubsub, :endpoint, :telemetry, :custom)
  - `:critical` - Whether the service is critical (default: false)
  - `:check` - Custom check function as {module, function} tuple or &Mod.fun/0
  """
  defmacro service(name, opts) do
    check = opts[:check]

    # Convert function capture to MFA if it's a remote function
    check_ast =
      case check do
        {:&, _, [{:/, _, [{{:., _, [mod, fun]}, _, _}, arity]}]} ->
          # Remote function capture like &Mod.fun/0
          quote do: {unquote(mod), unquote(fun), unquote(arity)}

        {mod, fun} when is_atom(mod) and is_atom(fun) ->
          # MFA tuple
          quote do: {unquote(mod), unquote(fun)}

        nil ->
          nil

        _ ->
          # For anonymous functions, we'll store a reference that gets evaluated at runtime
          # This requires the function to be defined in the module
          check
      end

    quote do
      @health_services %{
        name: unquote(to_string(name) |> String.capitalize()),
        module: unquote(opts[:module]),
        type: unquote(opts[:type] || :custom),
        critical: unquote(Keyword.get(opts, :critical, false)),
        check: unquote(check_ast)
      }
    end
  end

  # ============================================
  # Core Functions
  # ============================================

  @doc """
  Runs all health checks with the given services and config.
  """
  @spec run_checks([map()], map()) :: health_result()
  def run_checks(services, config) do
    start_time = System.monotonic_time(:millisecond)

    result = %{
      services: Enum.map(services, &run_service_check(&1, config)),
      environment: OmHealth.Environment.get_info(config),
      proxy: OmHealth.Proxy.get_config(),
      timestamp: DateTime.utc_now(),
      duration_ms: nil
    }

    end_time = System.monotonic_time(:millisecond)
    Map.put(result, :duration_ms, end_time - start_time)
  end

  @doc """
  Computes overall health status from check results.
  """
  @spec compute_overall_status(health_result()) :: overall_status()
  def compute_overall_status(%{services: services}) do
    critical_failed =
      Enum.any?(services, fn service ->
        service.critical and service.status != :ok
      end)

    optional_failed =
      Enum.any?(services, fn service ->
        not service.critical and service.status != :ok
      end)

    cond do
      critical_failed -> @status_unhealthy
      optional_failed -> @status_degraded
      true -> @status_healthy
    end
  end

  # ============================================
  # Service Check Runner
  # ============================================

  defp run_service_check(%{type: :custom, check: check} = service, _config) do
    result = execute_custom_check(check)
    handle_custom_check_result(service, result)
  end

  defp run_service_check(%{type: :repo, module: module} = service, _config) do
    case check_repo(module) do
      :ok -> build_ok_result(service, get_repo_adapter(module), "Connected & ready")
      {:error, reason} -> build_error_result(service, "Ecto.Postgres", reason, "Database unavailable")
    end
  end

  defp run_service_check(%{type: :cache, module: module} = service, _config) do
    case check_cache(module) do
      :ok -> build_ok_result(service, get_cache_adapter(module), "Operational")
      {:error, reason} -> build_error_result(service, "Cache", reason, "Cache unavailable")
    end
  end

  defp run_service_check(%{type: :pubsub, module: module} = service, _config) do
    case check_process(module) do
      :ok -> build_ok_result(service, "Phoenix.PubSub", "Running")
      {:error, reason} -> build_error_result(service, "Phoenix.PubSub", reason, "Live updates unavailable")
    end
  end

  defp run_service_check(%{type: :endpoint, module: module} = service, _config) do
    case check_process(module) do
      :ok -> build_ok_result(service, get_endpoint_adapter(module), endpoint_info(module))
      {:error, reason} -> build_error_result(service, "Bandit", reason, "HTTP requests failing")
    end
  end

  defp run_service_check(%{type: :telemetry, module: module} = service, _config) do
    case check_process(module) do
      :ok -> build_ok_result(service, "Telemetry", "Monitoring active")
      {:error, reason} -> build_error_result(service, "Telemetry", reason, "No metrics")
    end
  end

  defp run_service_check(%{type: type} = service, _config) do
    build_error_result(service, "Unknown", "Unknown service type: #{type}", "Check configuration")
  end

  # ============================================
  # Custom Check Execution
  # ============================================

  defp execute_custom_check({mod, fun}) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, [])
  end

  defp execute_custom_check({mod, fun, _arity}) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, [])
  end

  defp execute_custom_check(check_fn) when is_function(check_fn, 0) do
    check_fn.()
  end

  defp handle_custom_check_result(service, :ok) do
    build_ok_result(service, "Custom", "Healthy")
  end

  defp handle_custom_check_result(service, {:ok, info}) do
    build_ok_result(service, "Custom", info)
  end

  defp handle_custom_check_result(service, {:error, reason}) do
    build_error_result(service, "Custom", reason, "Service unavailable")
  end

  # ============================================
  # Health Checks
  # ============================================

  defp check_repo(module) do
    with true <- process_alive?(module),
         {:ok, _} <- safe_query(module) do
      :ok
    else
      false -> {:error, "Process not running"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp safe_query(module) do
    module.query("SELECT 1", [], timeout: 5_000)
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp check_cache(module) do
    case process_alive?(module) do
      true -> safe_cache_roundtrip(module)
      false -> {:error, "Process not running"}
    end
  end

  defp safe_cache_roundtrip(module) do
    test_key = {:__health_check__, System.unique_integer()}
    module.put(test_key, true, ttl: :timer.seconds(1))
    module.get(test_key)
    module.delete(test_key)
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp check_process(module) do
    case process_alive?(module) do
      true -> :ok
      false -> {:error, "Process not running"}
    end
  end

  defp process_alive?(module) when is_atom(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _ -> false
    end
  end

  # ============================================
  # Adapter Detection
  # ============================================

  defp get_repo_adapter(module) do
    try do
      module.__adapter__()
      |> Module.split()
      |> List.last()
      |> then(&"Ecto.#{&1}")
    rescue
      _ -> "Ecto.Postgres"
    end
  end

  defp get_cache_adapter(module) do
    try do
      adapter = module.__adapter__()
      format_cache_adapter(adapter)
    rescue
      _ -> "Nebulex"
    end
  end

  defp format_cache_adapter(NebulexRedisAdapter), do: "Nebulex.Redis"

  defp format_cache_adapter(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> List.last()
    |> then(&"Nebulex.#{&1}")
  end

  defp get_endpoint_adapter(module) do
    try do
      case module.config(:adapter) do
        nil -> "Bandit"
        adapter ->
          adapter
          |> Module.split()
          |> hd()
      end
    rescue
      _ -> "Bandit"
    end
  end

  defp endpoint_info(module) do
    try do
      case module.config(:http) do
        config when is_list(config) ->
          case Keyword.get(config, :port) do
            port when is_integer(port) -> "Port #{port}"
            _ -> "Running"
          end
        _ -> "Running"
      end
    rescue
      _ -> "Running"
    end
  end

  # ============================================
  # Result Builders
  # ============================================

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

  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 50)
  defp format_error(reason), do: reason |> inspect() |> String.slice(0, 50)
end
