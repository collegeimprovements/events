defmodule OmHealth.Display do
  @moduledoc """
  Clean tabular display for system health information.

  Provides formatted console output for health check results with:
  - Colored status indicators
  - Environment information
  - Service status tables
  - Summary and warnings

  ## Usage

      health = MyApp.Health.check_all()
      OmHealth.Display.render(health)

      # With options
      OmHealth.Display.render(health, color: false)

  ## Output Format

  The display includes sections for:
  - Header with title
  - Environment information (Mix env, Elixir/OTP versions, hostname)
  - Proxy configuration (if any)
  - Services table with status, adapter, and info
  - Summary (healthy/degraded/unhealthy)
  - Footer with timestamp
  """

  @table_width 93

  @doc """
  Renders system health information in tabular format.

  ## Options

  - `:color` - Enable color output (default: true)
  - `:title` - Custom title for the header (default: "SYSTEM HEALTH STATUS")
  """
  @spec render(map(), keyword()) :: :ok
  def render(health, opts \\ []) do
    color? = Keyword.get(opts, :color, true)
    title = Keyword.get(opts, :title, "SYSTEM HEALTH STATUS")

    IO.puts("\n")
    print_header(title, color?)

    # Environment section
    if Map.has_key?(health, :environment) do
      print_section_header("ENVIRONMENT", color?)
      print_environment(health.environment, color?)
    end

    # Proxy section (if configured)
    if Map.has_key?(health, :proxy) and health.proxy.configured do
      print_section_header("PROXY", color?)
      print_proxy(health.proxy, color?)
    end

    # Services table
    if Map.has_key?(health, :services) do
      print_section_header("SERVICES", color?)
      print_services_table(health.services, color?)

      # Summary
      print_summary(health.services, color?)
    end

    # Footer
    print_footer(health, color?)

    :ok
  end

  # ============================================
  # Header
  # ============================================

  defp print_header(title, color?) do
    line = String.duplicate("=", @table_width)
    padding = div(@table_width - String.length(title), 2)
    centered_title = String.duplicate(" ", padding) <> title

    IO.puts(line)
    IO.puts(colorize(centered_title, :bright, color?))
    IO.puts(line)
    IO.puts("")
  end

  # ============================================
  # Environment
  # ============================================

  defp print_environment(env, color?) do
    mix_env = Map.get(env, :mix_env, :unknown)
    elixir = Map.get(env, :elixir_version, "unknown")
    otp = Map.get(env, :otp_release, "unknown")
    node_name = Map.get(env, :node_name, :nonode@nohost)
    hostname = Map.get(env, :hostname, "unknown")
    in_docker = Map.get(env, :in_docker, false)
    live_reload = Map.get(env, :live_reload, :unknown)
    watchers = Map.get(env, :watchers, [])

    IO.puts(
      "  Mix Environment : #{colorize(to_string(mix_env), env_color(mix_env), color?)}"
    )

    IO.puts(
      "  Elixir / OTP    : #{colorize("#{elixir} / #{otp}", :cyan, color?)}"
    )

    IO.puts("  Node            : #{colorize(to_string(node_name), :light_black, color?)}")
    IO.puts("  Hostname        : #{colorize(hostname, :light_black, color?)}")

    if in_docker do
      IO.puts("  Container       : #{colorize("Docker", :cyan, color?)}")
    end

    if mix_env == :dev and length(watchers) > 0 do
      IO.puts("")
      IO.puts("  Development:")
      reload_status = if live_reload == :enabled, do: colorize("Enabled", :green, color?), else: colorize("Disabled", :light_black, color?)
      IO.puts("    Live Reload : #{reload_status}")
      IO.puts("    Watchers    : #{colorize(Enum.join(watchers, ", "), :cyan, color?)}")
    end

    print_separator()
  end

  # ============================================
  # Proxy
  # ============================================

  defp print_proxy(proxy, color?) do
    if proxy.http_proxy do
      IO.puts("  HTTP Proxy      : #{colorize(proxy.http_proxy, :light_black, color?)}")
    end

    if proxy.https_proxy do
      IO.puts("  HTTPS Proxy     : #{colorize(proxy.https_proxy, :light_black, color?)}")
    end

    if proxy.no_proxy do
      IO.puts("  No Proxy        : #{colorize(proxy.no_proxy, :light_black, color?)}")
    end

    if length(proxy.services_using_proxy) > 0 do
      IO.puts("")
      IO.puts("  Services Using Proxy:")

      Enum.each(proxy.services_using_proxy, fn service ->
        IO.puts("    * #{service}")
      end)
    end

    print_separator()
  end

  # ============================================
  # Services Table
  # ============================================

  defp print_services_table(services, color?) do
    # Table header
    header =
      String.pad_trailing("SERVICE", 12) <>
        " | " <>
        String.pad_trailing("STATUS", 10) <>
        " | " <>
        String.pad_trailing("ADAPTER", 18) <>
        " | " <>
        String.pad_trailing("LEVEL", 8) <>
        " | INFO"

    IO.puts(header)

    divider =
      String.duplicate("-", 12) <>
        "-+-" <>
        String.duplicate("-", 10) <>
        "-+-" <>
        String.duplicate("-", 18) <>
        "-+-" <>
        String.duplicate("-", 8) <>
        "-+-" <>
        String.duplicate("-", 30)

    IO.puts(divider)

    # Table rows
    Enum.each(services, fn service ->
      print_service_row(service, color?)
    end)

    IO.puts(String.duplicate("=", @table_width))
    IO.puts("")
  end

  defp print_service_row(service, color?) do
    status_text = if service.status == :ok, do: "Running", else: "Failed"

    status_colored =
      if service.status == :ok do
        colorize(status_text, :green, color?)
      else
        if service.critical do
          colorize(status_text, :red, color?)
        else
          colorize(status_text, :yellow, color?)
        end
      end

    level_text = if service.critical, do: "Critical", else: "Optional"

    level_colored =
      if service.critical do
        if service.status == :ok do
          colorize(level_text, :cyan, color?)
        else
          colorize("CRITICAL", :red_bright, color?)
        end
      else
        if service.status == :ok do
          colorize(level_text, :light_black, color?)
        else
          colorize("Degraded", :yellow, color?)
        end
      end

    info_text = if service.status != :ok and service.impact, do: service.impact, else: service.info

    IO.puts(
      String.pad_trailing(service.name, 12) <>
        " | " <>
        pad_colored(status_text, status_colored, 10) <>
        " | " <>
        String.pad_trailing(service.adapter || "-", 18) <>
        " | " <>
        pad_colored(level_text, level_colored, 8) <>
        " | " <>
        to_string(info_text)
    )
  end

  # ============================================
  # Summary
  # ============================================

  defp print_summary(services, color?) do
    ok_count = Enum.count(services, &(&1.status == :ok))
    total_count = length(services)
    critical_failed = Enum.filter(services, &(&1.critical and &1.status != :ok))
    optional_failed = Enum.filter(services, &(not &1.critical and &1.status != :ok))

    cond do
      ok_count == total_count ->
        IO.puts(
          colorize("ALL SYSTEMS OPERATIONAL (#{ok_count}/#{total_count})", :green_bright, color?)
        )

      length(critical_failed) > 0 ->
        IO.puts(
          colorize(
            "CRITICAL: #{length(critical_failed)} critical service(s) failed!",
            :red_bright,
            color?
          )
        )

        IO.puts(colorize("  Application may not function correctly", :red, color?))

        Enum.each(critical_failed, fn service ->
          IO.puts(colorize("  * #{service.name}: #{service.info}", :red, color?))
        end)

      length(optional_failed) > 0 ->
        IO.puts(
          colorize(
            "DEGRADED: #{length(optional_failed)} optional service(s) unavailable",
            :yellow,
            color?
          )
        )

        IO.puts(colorize("  Application running with reduced functionality", :light_black, color?))

        Enum.each(optional_failed, fn service ->
          IO.puts(colorize("  * #{service.name}: #{service.impact}", :yellow, color?))
        end)

      true ->
        IO.puts(colorize("All services running (#{ok_count}/#{total_count})", :green, color?))
    end

    IO.puts("")
  end

  # ============================================
  # Footer
  # ============================================

  defp print_footer(health, color?) do
    timestamp =
      case Map.get(health, :timestamp) do
        %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
        _ -> "unknown"
      end

    duration = Map.get(health, :duration_ms, 0)
    IO.puts(colorize("Checked at #{timestamp} (#{duration}ms)", :light_black, color?))
    IO.puts("")
  end

  # ============================================
  # Utilities
  # ============================================

  defp print_section_header(title, color?) do
    IO.puts(colorize(title, :bright, color?))
    IO.puts("")
  end

  defp print_separator do
    IO.puts(String.duplicate("-", @table_width))
    IO.puts("")
  end

  defp env_color(:prod), do: :red
  defp env_color(:test), do: :yellow
  defp env_color(:dev), do: :green
  defp env_color(_), do: :white

  defp pad_colored(text, colored_text, width) do
    padding = max(0, width - String.length(text))
    colored_text <> String.duplicate(" ", padding)
  end

  defp colorize(text, _color, false), do: text

  defp colorize(text, color, true) do
    case color do
      :green -> IO.ANSI.green() <> text <> IO.ANSI.reset()
      :green_bright -> IO.ANSI.green() <> IO.ANSI.bright() <> text <> IO.ANSI.reset()
      :red -> IO.ANSI.red() <> text <> IO.ANSI.reset()
      :red_bright -> IO.ANSI.red() <> IO.ANSI.bright() <> text <> IO.ANSI.reset()
      :yellow -> IO.ANSI.yellow() <> text <> IO.ANSI.reset()
      :cyan -> IO.ANSI.cyan() <> text <> IO.ANSI.reset()
      :blue -> IO.ANSI.blue() <> text <> IO.ANSI.reset()
      :magenta -> IO.ANSI.magenta() <> text <> IO.ANSI.reset()
      :light_black -> IO.ANSI.light_black() <> text <> IO.ANSI.reset()
      :bright -> IO.ANSI.bright() <> text <> IO.ANSI.reset()
      :white -> text
    end
  end
end
