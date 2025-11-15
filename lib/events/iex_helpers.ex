defmodule Events.IExHelpers do
  @moduledoc """
  Convenience helpers that are automatically imported inside `.iex.exs`.
  """

  alias Events.{Repo, Cache, SystemHealth}

  @doc """
  Runs when IEx boots so we can show the health dashboard and helper list.
  """
  def on_startup do
    if Code.ensure_loaded?(SystemHealth) do
      Process.sleep(500)
      SystemHealth.display()
    end

    print_available_helpers()
  end

  @doc """
  Prints the helper overview banner.
  """
  def print_available_helpers do
    IO.puts("""
    Available helpers:
      - health()       : Display system health status
      - health_data()  : Get raw health data
      - db_check()     : Quick database check
      - cache_check()  : Quick cache check
      - redis_check()  : Quick Redis check
      - proxy_check()  : Show proxy configuration
      - mise_check()   : Show mise environment

    Common aliases loaded:
      - Repo, Cache, SystemHealth
      - Endpoint, Router
    """)
  end

  @doc """
  Display system health status.
  """
  def health do
    SystemHealth.display()
  end

  @doc """
  Get raw system health data.
  """
  def health_data do
    SystemHealth.check_all()
  end

  @doc """
  Quick database connectivity check.
  """
  def db_check do
    case Repo.query("SELECT version()", []) do
      {:ok, result} ->
        version = result.rows |> List.first() |> List.first()
        IO.puts("✓ PostgreSQL connected: #{version}")

      {:error, error} ->
        IO.puts("✗ Database error: #{inspect(error)}")
    end
  end

  @doc """
  Quick cache health check.
  """
  def cache_check do
    try do
      Cache.put(:test, "hello", ttl: :timer.seconds(5))
      value = Cache.get(:test)
      Cache.delete(:test)

      if value == "hello" do
        IO.puts("✓ Cache operational")
      else
        IO.puts("✗ Cache returned unexpected value: #{inspect(value)}")
      end
    rescue
      e -> IO.puts("✗ Cache error: #{Exception.message(e)}")
    end
  end

  @doc """
  Quick Redis connectivity via Hammer.
  """
  def redis_check do
    case Hammer.check_rate("iex_check", 60_000, 1) do
      {:allow, _} -> IO.puts("✓ Redis connected via Hammer")
      {:deny, _} -> IO.puts("✓ Redis connected (rate limited)")
      {:error, reason} -> IO.puts("✗ Redis error: #{inspect(reason)}")
    end
  rescue
    e -> IO.puts("✗ Redis error: #{Exception.message(e)}")
  end

  @doc """
  Show proxy configuration summary.
  """
  def proxy_check do
    proxy_info = SystemHealth.proxy_config()

    IO.puts("\nProxy Configuration:")
    IO.puts("══════════════════════════════════════════════════════════")

    print_proxy_line("HTTP_PROXY", proxy_info.http_proxy)
    print_proxy_line("HTTPS_PROXY", proxy_info.https_proxy)
    print_proxy_line("NO_PROXY", proxy_info.no_proxy, allow_empty?: true)

    IO.puts("")

    if proxy_info.http_proxy || proxy_info.https_proxy do
      IO.puts("#{IO.ANSI.cyan()}Services Using Proxy:#{IO.ANSI.reset()}")

      Enum.each(proxy_info.services_using_proxy, fn service ->
        IO.puts("  • #{service}")
      end)

      IO.puts("")

      IO.puts(
        "#{IO.ANSI.light_black()}Note: PostgreSQL and Redis do not use HTTP proxies#{IO.ANSI.reset()}"
      )
    else
      IO.puts("#{IO.ANSI.yellow()}No proxy configured#{IO.ANSI.reset()}")
      IO.puts("All HTTP/HTTPS requests go directly to their destinations.\n")
    end
  end

  defp print_proxy_line(label, nil, opts \\ []) do
    if Keyword.get(opts, :allow_empty?, false) do
      IO.puts("  #{label}: #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
    else
      IO.puts("  #{label}: #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
    end
  end

  defp print_proxy_line(label, value, _opts) do
    IO.puts("  #{label}: #{IO.ANSI.green()}SET#{IO.ANSI.reset()}")
    IO.puts("             #{value}")
  end

  @doc """
  Show mise environment status.
  """
  def mise_check do
    mise_info = SystemHealth.mise_info()

    if mise_info.active do
      IO.puts("\n#{IO.ANSI.magenta()}Mise Environment#{IO.ANSI.reset()}")
      IO.puts("══════════════════════════════════════════════════════════")
      IO.puts("  Shell: #{IO.ANSI.cyan()}#{mise_info.shell}#{IO.ANSI.reset()}")

      if length(mise_info.tools) > 0 do
        IO.puts("")
        IO.puts("  #{IO.ANSI.cyan()}Managed Tools:#{IO.ANSI.reset()}")

        Enum.each(mise_info.tools, fn {tool, version} ->
          IO.puts("    • #{tool}: #{IO.ANSI.green()}#{version}#{IO.ANSI.reset()}")
        end)
      end

      if length(mise_info.env_vars) > 0 do
        IO.puts("")
        IO.puts("  #{IO.ANSI.cyan()}Environment Variables#{IO.ANSI.reset()}")

        Enum.each(mise_info.env_vars, fn {label, key, value} ->
          display_value =
            if String.contains?(String.downcase(label), ["secret", "key", "api"]) do
              "********"
            else
              value
            end

          IO.puts("    • #{key}: #{display_value}")
        end)
      end

      IO.puts("")
    else
      IO.puts("\n#{IO.ANSI.yellow()}Mise not detected#{IO.ANSI.reset()}")
      IO.puts("Mise environment manager is not active in this session.\n")
    end
  end
end
