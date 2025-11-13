# IEx configuration file
# This file is loaded automatically when starting IEx

# Display system health status when IEx loads
if Code.ensure_loaded?(Events.SystemHealth) do
  # Give services a moment to fully initialize
  Process.sleep(500)
  Events.SystemHealth.display()
end

# Convenient aliases for common modules
alias Events.{Repo, Cache, SystemHealth}
alias EventsWeb.{Endpoint, Router}

# Custom IEx helpers
defmodule IExHelpers do
  @moduledoc """
  Helper functions for IEx sessions.
  """

  @doc """
  Display system health status.
  """
  def health do
    Events.SystemHealth.display()
  end

  @doc """
  Get raw health data.
  """
  def health_data do
    Events.SystemHealth.check_all()
  end

  @doc """
  Quick database check.
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
  Quick cache check.
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
  Quick Redis check via Hammer.
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
  Check proxy configuration.
  """
  def proxy_check do
    proxy_info = Events.SystemHealth.proxy_config()

    IO.puts("\nProxy Configuration:")
    IO.puts("══════════════════════════════════════════════════════════")

    if proxy_info.http_proxy do
      IO.puts("  HTTP_PROXY:  ✓ #{IO.ANSI.green()}SET#{IO.ANSI.reset()}")
      IO.puts("               #{proxy_info.http_proxy}")
    else
      IO.puts("  HTTP_PROXY:  #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
    end

    if proxy_info.https_proxy do
      IO.puts("  HTTPS_PROXY: ✓ #{IO.ANSI.green()}SET#{IO.ANSI.reset()}")
      IO.puts("               #{proxy_info.https_proxy}")
    else
      IO.puts("  HTTPS_PROXY: #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
    end

    if proxy_info.no_proxy do
      IO.puts("  NO_PROXY:    #{proxy_info.no_proxy}")
    else
      IO.puts("  NO_PROXY:    #{IO.ANSI.light_black()}(not set)#{IO.ANSI.reset()}")
    end

    IO.puts("")

    if proxy_info.http_proxy || proxy_info.https_proxy do
      IO.puts("#{IO.ANSI.cyan()}Services Using Proxy:#{IO.ANSI.reset()}")
      IO.puts("  • Req (HTTP client) - for AWS S3, external HTTP/HTTPS calls")
      IO.puts("")
      IO.puts("#{IO.ANSI.light_black()}Note: PostgreSQL, Redis, and other TCP services")
      IO.puts("      do not use HTTP proxies by default.#{IO.ANSI.reset()}")
    else
      IO.puts("#{IO.ANSI.yellow()}No proxy configured#{IO.ANSI.reset()}")
      IO.puts("All HTTP/HTTPS requests will go directly to their destinations.")
    end

    IO.puts("")
  end

  @doc """
  Check mise environment.
  """
  def mise_check do
    mise_info = Events.SystemHealth.mise_info()

    if mise_info.active do
      IO.puts("\n#{IO.ANSI.magenta()}Mise Environment#{IO.ANSI.reset()}")
      IO.puts("══════════════════════════════════════════════════════════")
      IO.puts("  Shell: #{IO.ANSI.cyan()}#{mise_info.shell}#{IO.ANSI.reset()}")
      IO.puts("")

      if length(mise_info.tools) > 0 do
        IO.puts("  #{IO.ANSI.cyan()}Managed Tools:#{IO.ANSI.reset()}")

        Enum.each(mise_info.tools, fn {tool, version} ->
          IO.puts("    • #{tool}: #{IO.ANSI.green()}#{version}#{IO.ANSI.reset()}")
        end)

        IO.puts("")
      end

      if length(mise_info.env_vars) > 0 do
        IO.puts("  #{IO.ANSI.cyan()}Environment Variables (.mise.toml):#{IO.ANSI.reset()}")

        Enum.each(mise_info.env_vars, fn {label, key, value} ->
          # Mask sensitive values
          display_value =
            if String.contains?(String.downcase(label), ["secret", "key", "api"]) do
              "********"
            else
              value
            end

          IO.puts("    • #{key}: #{display_value}")
        end)

        IO.puts("")
      end

      IO.puts(
        "#{IO.ANSI.light_black()}Tip: Edit .mise.toml to add more environment variables#{IO.ANSI.reset()}"
      )

      IO.puts("")
    else
      IO.puts("\n#{IO.ANSI.yellow()}Mise not detected#{IO.ANSI.reset()}")
      IO.puts("Mise environment manager is not active in this session.")
      IO.puts("")
    end
  end
end

import IExHelpers

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
