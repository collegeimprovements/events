defmodule Events.StartupChecker do
  @moduledoc """
  Checks the status of all critical services on application startup
  and displays a formatted table showing their health, adapters, and criticality.

  ## Criticality Levels
  - `:critical` - Application cannot start without this service (e.g., Repo, Endpoint)
  - `:optional` - Application can function without this service (e.g., Redis for rate limiting)
  """

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
  Returns a list of maps with :name, :status, and :details keys.
  """
  def check_all do
    Enum.map(@services, &check_service/1)
  end

  @doc """
  Displays a formatted table of all service statuses.
  """
  def display_table do
    start_time = System.monotonic_time(:millisecond)

    statuses = check_all()
    proxy_info = check_proxy_config()
    mise_info = get_mise_info()
    env_info = get_environment_info()
    migration_info = check_migration_status()

    IO.puts("\n")

    IO.puts(
      "═════════════════════════════════════════════════════════════════════════════════════════"
    )

    IO.puts("                                   SERVICE STATUS")

    IO.puts(
      "═════════════════════════════════════════════════════════════════════════════════════════"
    )

    IO.puts("")

    # Display environment info
    display_environment_info(env_info)

    # Display mise info if available
    display_mise_info(mise_info)

    # Display proxy info if configured
    display_proxy_info(proxy_info, statuses)

    # Header
    IO.puts(
      String.pad_trailing("SERVICE", 12) <>
        " │ " <>
        String.pad_trailing("STATUS", 10) <>
        " │ " <>
        String.pad_trailing("ADAPTER", 20) <>
        " │ " <>
        String.pad_trailing("IMPACT", 10) <>
        " │ INFO"
    )

    IO.puts(
      String.duplicate("─", 12) <>
        "─┼─" <>
        String.duplicate("─", 10) <>
        "─┼─" <>
        String.duplicate("─", 20) <>
        "─┼─" <>
        String.duplicate("─", 10) <>
        "─┼─" <>
        String.duplicate("─", 30)
    )

    # Rows
    Enum.each(statuses, fn %{
                             name: name,
                             status: status,
                             adapter: adapter,
                             critical: critical,
                             info: info,
                             impact: impact
                           } ->
      status_icon = if status == :ok, do: "✓", else: "✗"
      status_text = if status == :ok, do: "Running", else: "Failed"

      status_colored =
        if status == :ok do
          IO.ANSI.green() <> status_icon <> " " <> status_text <> IO.ANSI.reset()
        else
          if critical do
            IO.ANSI.red() <> status_icon <> " " <> status_text <> IO.ANSI.reset()
          else
            IO.ANSI.yellow() <> status_icon <> " " <> status_text <> IO.ANSI.reset()
          end
        end

      impact_colored =
        if critical do
          if status == :ok do
            IO.ANSI.cyan() <> "Critical" <> IO.ANSI.reset()
          else
            IO.ANSI.red() <> IO.ANSI.bright() <> "CRITICAL" <> IO.ANSI.reset()
          end
        else
          if status == :ok do
            IO.ANSI.light_black() <> "Optional" <> IO.ANSI.reset()
          else
            IO.ANSI.yellow() <> "Degraded" <> IO.ANSI.reset()
          end
        end

      impact_text = if critical, do: "Critical", else: "Optional"

      IO.puts(
        String.pad_trailing(name, 12) <>
          " │ " <>
          status_colored <>
          String.duplicate(" ", max(0, 10 - String.length(status_text) - 2)) <>
          " │ " <>
          String.pad_trailing(adapter, 20) <>
          " │ " <>
          impact_colored <>
          String.duplicate(" ", max(0, 10 - String.length(impact_text))) <>
          " │ " <>
          if(status != :ok and impact, do: impact, else: info)
      )
    end)

    IO.puts(
      "═════════════════════════════════════════════════════════════════════════════════════════"
    )

    IO.puts("")

    # Summary
    ok_count = Enum.count(statuses, &(&1.status == :ok))
    total_count = length(statuses)
    critical_failed = Enum.filter(statuses, &(&1.critical and &1.status != :ok))
    optional_failed = Enum.filter(statuses, &(not &1.critical and &1.status != :ok))

    cond do
      ok_count == total_count ->
        IO.puts(
          IO.ANSI.green() <>
            "✓ All services operational (#{ok_count}/#{total_count})" <> IO.ANSI.reset()
        )

      length(critical_failed) > 0 ->
        IO.puts(
          IO.ANSI.red() <>
            IO.ANSI.bright() <>
            "✗ CRITICAL: #{length(critical_failed)} critical service(s) failed!" <> IO.ANSI.reset()
        )

        IO.puts(IO.ANSI.red() <> "  Application may not function correctly." <> IO.ANSI.reset())

      length(optional_failed) > 0 ->
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠ #{length(optional_failed)} optional service(s) degraded (#{ok_count}/#{total_count} running)" <>
            IO.ANSI.reset()
        )

        IO.puts(
          IO.ANSI.light_black() <>
            "  Application will continue with reduced functionality." <> IO.ANSI.reset()
        )

      true ->
        IO.puts(
          IO.ANSI.green() <>
            "✓ All services running (#{ok_count}/#{total_count})" <> IO.ANSI.reset()
        )
    end

    IO.puts("")

    # Display migration status and startup time
    display_footer_info(migration_info, start_time)
  end

  # Private functions for checking each service type

  defp check_service(%{name: name, module: module, type: :repo, critical: critical}) do
    adapter = get_repo_adapter(module)

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
          impact: "App cannot function"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :cache, critical: critical}) do
    adapter = get_cache_adapter(module)

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
    adapter = get_redis_adapter()

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
    case check_pubsub(module) do
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
          impact: "Live updates broken"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :endpoint, critical: critical}) do
    adapter = get_endpoint_adapter(module)

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
          impact: "No HTTP requests"
        }
    end
  end

  defp check_service(%{name: name, module: module, type: :telemetry, critical: critical}) do
    case check_generic_process(module) do
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

  # Check if Repo is running and can query
  defp check_repo(module) do
    if Process.whereis(module) do
      try do
        module.query("SELECT 1", [])
        :ok
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Process not started"}
    end
  end

  # Check if Cache is running
  defp check_cache(module) do
    if Process.whereis(module) do
      try do
        # Try a simple cache operation
        test_key = :__startup_check__
        module.put(test_key, true, ttl: :timer.seconds(1))
        module.get(test_key)
        module.delete(test_key)
        :ok
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "Process not started"}
    end
  end

  # Check if Redis is accessible via Hammer
  defp check_redis do
    case Hammer.check_rate("startup_check", 60_000, 1) do
      {:allow, _} -> :ok
      # Still connected, just rate limited
      {:deny, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Check if PubSub is running
  defp check_pubsub(module) do
    if Process.whereis(module) do
      :ok
    else
      {:error, "Process not started"}
    end
  end

  # Check if Endpoint is running
  defp check_endpoint(module) do
    if Process.whereis(module) do
      try do
        config = module.config(:http)
        port = config[:port]
        if port, do: {:ok, port}, else: :ok
      rescue
        _ -> :ok
      end
    else
      {:error, "Process not started"}
    end
  end

  # Generic process check
  defp check_generic_process(module) do
    if Process.whereis(module) do
      :ok
    else
      {:error, "Process not started"}
    end
  end

  # Format error messages
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # Adapter detection functions

  defp get_repo_adapter(module) do
    try do
      config = module.__adapter__()
      adapter_name = config |> Module.split() |> List.last()
      "Ecto.#{adapter_name}"
    rescue
      _ -> "Ecto.Postgres"
    end
  end

  defp get_cache_adapter(module) do
    try do
      # Nebulex stores adapter in __adapter__ macro
      adapter = module.__adapter__()

      # Get the last part (e.g., "Local" from "Nebulex.Adapters.Local")
      adapter_type = adapter |> Module.split() |> List.last()
      "Nebulex.#{adapter_type}"
    rescue
      _ -> "Nebulex.Local"
    end
  end

  defp get_redis_adapter do
    try do
      case Application.get_env(:hammer, :backend) do
        {backend_module, _opts} ->
          # Get the backend type (e.g., "Redis" from "Hammer.Backend.Redis")
          backend_type = backend_module |> Module.split() |> List.last()
          "Hammer.#{backend_type}"

        _ ->
          "Hammer.Redis"
      end
    rescue
      _ -> "Hammer.Redis"
    end
  end

  defp get_endpoint_adapter(module) do
    try do
      adapter = module.config(:adapter)

      if adapter do
        # Extract adapter name (e.g., "Bandit" from "Bandit.PhoenixAdapter")
        adapter_parts = adapter |> Module.split()

        case adapter_parts do
          ["Bandit" | _] -> "Bandit"
          ["Cowboy" | _] -> "Cowboy"
          _ -> adapter |> Module.split() |> List.first() || "Phoenix"
        end
      else
        "Bandit"
      end
    rescue
      _ -> "Bandit"
    end
  end

  # Mise environment detection

  @doc """
  Gets mise environment information from .mise.toml [env] section.
  Only shows environment variables that are actually defined in .mise.toml.
  """
  def get_mise_info do
    # Variables defined in .mise.toml [env] section
    mise_toml_vars = [
      {"DB_POOL_SIZE", "DB Pool Size"},
      {"DB_QUEUE_TARGET", "DB Queue Target"},
      {"DB_QUEUE_INTERVAL", "DB Queue Interval"},
      {"DB_LOG_LEVEL", "DB Log Level"},
      {"ECTO_IPV6", "Ecto IPv6"},
      {"DB_SSL", "DB SSL"},
      {"PORT", "Phoenix Port"},
      {"SECRET_KEY_BASE", "Secret Key Base"},
      {"PHX_HOST", "Phoenix Host"},
      {"PHX_SERVER", "Phoenix Server"},
      {"MIX_TEST_PARTITION", "Mix Test Partition"},
      {"DNS_CLUSTER_QUERY", "DNS Cluster Query"},
      {"MAILGUN_API_KEY", "Mailgun API Key"},
      {"MAILGUN_DOMAIN", "Mailgun Domain"}
    ]

    vars =
      Enum.map(mise_toml_vars, fn {key, label} ->
        case get_env_var(key) do
          nil -> nil
          value -> {label, key, value}
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Also show which tools are managed by mise
    tools = get_mise_tools()

    %{
      mise_shell: get_env_var("MISE_SHELL"),
      vars: vars,
      tools: tools
    }
  end

  defp get_mise_tools do
    tools = []

    # Check for mise-managed tool paths in PATH
    tools =
      if get_env_var("MIX_HOME") do
        elixir_version = extract_mise_version(get_env_var("MIX_HOME"), "elixir")
        tools ++ [{"Elixir", elixir_version}]
      else
        tools
      end

    tools =
      if get_env_var("GOROOT") do
        go_version = extract_mise_version(get_env_var("GOROOT"), "go")
        tools ++ [{"Go", go_version}]
      else
        tools
      end

    tools =
      if get_env_var("PGDATA") do
        pg_version = extract_mise_version(get_env_var("PGDATA"), "postgres")
        tools ++ [{"PostgreSQL", pg_version}]
      else
        tools
      end

    tools
  end

  defp extract_mise_version(path, _tool) when is_nil(path), do: "unknown"

  defp extract_mise_version(path, tool) do
    # Extract version from path like: /Users/arpit/.local/share/mise/installs/elixir/1.19.2-otp-28/
    case Regex.run(~r{/mise/installs/#{tool}/([^/]+)}, path) do
      [_, version] -> version
      _ -> "unknown"
    end
  end

  defp display_mise_info(%{mise_shell: nil}) do
    # Mise not detected
    :ok
  end

  defp display_mise_info(%{mise_shell: shell, vars: vars, tools: tools}) do
    IO.puts(IO.ANSI.magenta() <> "MISE ENVIRONMENT" <> IO.ANSI.reset())
    IO.puts("")
    IO.puts("  Shell: #{IO.ANSI.cyan()}#{shell}#{IO.ANSI.reset()}")

    # Show mise-managed tools
    if length(tools) > 0 do
      IO.puts("")
      IO.puts("  Managed Tools:")

      Enum.each(tools, fn {tool, version} ->
        IO.puts(
          "    #{String.pad_trailing(tool, 18)}: " <>
            IO.ANSI.cyan() <> version <> IO.ANSI.reset()
        )
      end)
    end

    # Show environment variables from .mise.toml
    if length(vars) > 0 do
      IO.puts("")
      IO.puts("  Environment Variables (.mise.toml):")

      Enum.each(vars, fn {label, _key, value} ->
        # Truncate long values (like SECRET_KEY_BASE)
        display_value =
          if String.length(value) > 50 do
            String.slice(value, 0, 47) <> "..."
          else
            value
          end

        # Mask sensitive values
        display_value =
          if String.contains?(String.downcase(label), ["secret", "key", "api"]) do
            mask_sensitive_value(value)
          else
            display_value
          end

        IO.puts(
          "    #{String.pad_trailing(label, 20)}: " <>
            IO.ANSI.light_black() <> display_value <> IO.ANSI.reset()
        )
      end)
    end

    IO.puts("")
    IO.puts(String.duplicate("─", 93))
    IO.puts("")
  end

  defp mask_sensitive_value(value) when is_binary(value) do
    len = String.length(value)

    cond do
      len <= 8 -> "••••••••"
      len <= 16 -> String.slice(value, 0, 4) <> "••••••••"
      true -> String.slice(value, 0, 8) <> "••••••••" <> String.slice(value, -4, 4)
    end
  end

  defp mask_sensitive_value(_), do: "••••••••"

  # Proxy configuration detection

  @doc """
  Checks for proxy configuration in environment variables and system config.
  """
  def check_proxy_config do
    %{
      http_proxy: get_env_var("HTTP_PROXY") || get_env_var("http_proxy"),
      https_proxy: get_env_var("HTTPS_PROXY") || get_env_var("https_proxy"),
      no_proxy: get_env_var("NO_PROXY") || get_env_var("no_proxy"),
      services_using_proxy: [:req, :aws_s3]
    }
  end

  defp get_env_var(key) do
    System.get_env(key)
  end

  defp display_proxy_info(%{http_proxy: nil, https_proxy: nil}, _statuses) do
    # No proxy configured, don't display anything
    :ok
  end

  defp display_proxy_info(proxy_info, statuses) do
    IO.puts(IO.ANSI.cyan() <> "PROXY CONFIGURATION" <> IO.ANSI.reset())
    IO.puts("")

    if proxy_info.http_proxy do
      status = check_proxy_connectivity(proxy_info.http_proxy, :http)
      display_proxy_line("HTTP Proxy", proxy_info.http_proxy, status)
    end

    if proxy_info.https_proxy do
      status = check_proxy_connectivity(proxy_info.https_proxy, :https)
      display_proxy_line("HTTPS Proxy", proxy_info.https_proxy, status)
    end

    if proxy_info.no_proxy do
      IO.puts("  No Proxy: #{IO.ANSI.light_black()}#{proxy_info.no_proxy}#{IO.ANSI.reset()}")
    end

    IO.puts("")

    # Show which services will actually use the proxy
    active_services = get_active_proxy_services(proxy_info, statuses)

    if length(active_services) > 0 do
      IO.puts("  #{IO.ANSI.green()}✓ Services using proxy:#{IO.ANSI.reset()}")

      Enum.each(active_services, fn service ->
        IO.puts("    • #{service}")
      end)
    else
      IO.puts("  #{IO.ANSI.yellow()}⚠ No services currently using proxy#{IO.ANSI.reset()}")
    end

    IO.puts("")
    IO.puts(String.duplicate("─", 93))
    IO.puts("")
  end

  defp get_active_proxy_services(proxy_info, _statuses) do
    services = []

    # Check if AWS S3 / Req would use proxy (based on if services are running)
    services =
      if proxy_info.http_proxy || proxy_info.https_proxy do
        services ++ ["Req (HTTP client) - for AWS S3, external APIs"]
      else
        services
      end

    # Redis doesn't use HTTP proxy by default, so we don't list it
    # unless it's specifically configured with SOCKS proxy

    services
  end

  defp display_proxy_line(label, url, status) do
    {icon, color, status_text} =
      case status do
        :ok -> {"✓", IO.ANSI.green(), "Reachable"}
        :error -> {"✗", IO.ANSI.red(), "Unreachable"}
        :unknown -> {"?", IO.ANSI.yellow(), "Not tested"}
      end

    IO.puts(
      "  #{String.pad_trailing(label, 12)}: " <>
        color <>
        icon <>
        " " <>
        status_text <>
        IO.ANSI.reset() <>
        " │ " <> IO.ANSI.light_black() <> url <> IO.ANSI.reset()
    )
  end

  defp check_proxy_connectivity(_proxy_url, _type) do
    # Basic connectivity check - you can enhance this
    # For now, we'll just assume it's reachable if configured
    # A real check would try to connect through the proxy
    :unknown
  end

  # Environment information

  @doc """
  Gets current environment information.
  """
  def get_environment_info do
    %{
      mix_env: Mix.env(),
      elixir_version: System.version(),
      otp_release: System.otp_release(),
      node_name: node(),
      live_reload: check_live_reload_status(),
      watchers: get_active_watchers()
    }
  end

  defp check_live_reload_status do
    case Mix.env() do
      :dev ->
        # Check if Phoenix.LiveReloader is configured
        case Application.get_env(:events, EventsWeb.Endpoint, [])[:live_reload] do
          nil -> :disabled
          _ -> :enabled
        end

      _ ->
        :not_applicable
    end
  end

  defp get_active_watchers do
    case Mix.env() do
      :dev ->
        watchers = Application.get_env(:events, EventsWeb.Endpoint, [])[:watchers] || []

        Enum.map(watchers, fn
          {name, _} -> name
          other -> other
        end)

      _ ->
        []
    end
  end

  defp display_environment_info(info) do
    IO.puts(IO.ANSI.blue() <> "ENVIRONMENT" <> IO.ANSI.reset())
    IO.puts("")

    # Environment and versions
    env_color =
      case info.mix_env do
        :prod -> IO.ANSI.red()
        :test -> IO.ANSI.yellow()
        :dev -> IO.ANSI.green()
      end

    IO.puts("  Mix Env           : #{env_color}#{info.mix_env}#{IO.ANSI.reset()}")

    IO.puts(
      "  Elixir/OTP        : #{IO.ANSI.cyan()}#{info.elixir_version}#{IO.ANSI.reset()} / " <>
        "#{IO.ANSI.cyan()}#{info.otp_release}#{IO.ANSI.reset()}"
    )

    IO.puts("  Node              : #{IO.ANSI.light_black()}#{info.node_name}#{IO.ANSI.reset()}")

    # Development tools status
    if info.mix_env == :dev do
      IO.puts("")
      IO.puts("  Development Tools:")

      case info.live_reload do
        :enabled ->
          IO.puts("    Live Reload     : #{IO.ANSI.green()}✓ Enabled#{IO.ANSI.reset()}")

        :disabled ->
          IO.puts("    Live Reload     : #{IO.ANSI.light_black()}Disabled#{IO.ANSI.reset()}")

        _ ->
          :ok
      end

      if length(info.watchers) > 0 do
        watcher_names = Enum.map_join(info.watchers, ", ", &to_string/1)
        IO.puts("    Watchers        : #{IO.ANSI.cyan()}#{watcher_names}#{IO.ANSI.reset()}")
      end
    end

    IO.puts("")
    IO.puts(String.duplicate("─", 93))
    IO.puts("")
  end

  # Migration status

  @doc """
  Checks migration status.
  """
  def check_migration_status do
    try do
      # Get all migrations from the repo
      migrations_path = Application.app_dir(:events, "priv/repo/migrations")

      all_migrations =
        case File.ls(migrations_path) do
          {:ok, files} ->
            files
            |> Enum.filter(&String.ends_with?(&1, ".exs"))
            |> Enum.map(fn file ->
              [version | _] = String.split(file, "_")
              String.to_integer(version)
            end)
            |> Enum.sort()

          {:error, _} ->
            []
        end

      # Get applied migrations
      applied_migrations =
        try do
          case Events.Repo.query("SELECT version FROM schema_migrations ORDER BY version", []) do
            {:ok, result} -> Enum.map(result.rows, fn [version] -> String.to_integer(version) end)
            _ -> []
          end
        rescue
          _ -> []
        end

      pending = length(all_migrations) - length(applied_migrations)

      %{
        total: length(all_migrations),
        applied: length(applied_migrations),
        pending: max(0, pending),
        last_migration: List.last(applied_migrations)
      }
    rescue
      _ ->
        %{total: 0, applied: 0, pending: 0, last_migration: nil, error: true}
    end
  end

  defp display_footer_info(migration_info, start_time) do
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Migration status
    if not Map.get(migration_info, :error, false) and migration_info.total > 0 do
      if migration_info.pending > 0 do
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠ Migrations: #{migration_info.applied}/#{migration_info.total} applied, " <>
            "#{migration_info.pending} pending" <> IO.ANSI.reset()
        )

        IO.puts(IO.ANSI.yellow() <> "  Run: mix ecto.migrate" <> IO.ANSI.reset())
      else
        IO.puts(
          IO.ANSI.green() <>
            "✓ Migrations: #{migration_info.applied}/#{migration_info.total} applied, up to date" <>
            IO.ANSI.reset()
        )
      end

      if migration_info.last_migration do
        IO.puts(
          "  Last migration: #{IO.ANSI.light_black()}#{migration_info.last_migration}#{IO.ANSI.reset()}"
        )
      end

      IO.puts("")
    end

    # Startup time
    IO.puts("#{IO.ANSI.light_black()}Startup checks completed in #{duration}ms#{IO.ANSI.reset()}")
    IO.puts("")
  end
end
