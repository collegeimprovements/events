defmodule Events.SystemHealth.Display do
  @moduledoc """
  Clean tabular display for system health information.
  """

  @table_width 93

  @doc """
  Renders system health information in tabular format.
  """
  @spec render(map(), keyword()) :: :ok
  def render(health, opts \\ []) do
    color? = Keyword.get(opts, :color, true)

    IO.puts("\n")
    print_header(color?)

    # Environment section
    print_section_header("ENVIRONMENT", color?)
    print_environment(health.environment, color?)

    # Mise section (if active)
    if health.mise.active do
      print_section_header("MISE", color?)
      print_mise(health.mise, color?)
    end

    # Proxy section (if configured)
    if health.proxy.configured do
      print_section_header("PROXY", color?)
      print_proxy(health.proxy, color?)
    end

    # Services table
    print_section_header("SERVICES", color?)
    print_services_table(health.services, color?)

    # Infra connections table
    if health.infra && health.infra != [] do
      print_section_header("INFRA CONNECTIONS", color?)
      print_infra_table(health.infra, color?)
    end

    # Summary
    print_summary(health, color?)

    # Footer
    print_footer(health, color?)

    :ok
  end

  defp print_infra_table(connections, color?) do
    header =
      String.pad_trailing("INFRA", 16) <>
        " │ " <>
        String.pad_trailing("ENDPOINT", 32) <>
        " │ " <>
        String.pad_trailing("SOURCE", 20) <>
        " │ DETAILS"

    IO.puts(header)

    divider =
      String.duplicate("─", 16) <>
        "─┼─" <>
        String.duplicate("─", 32) <>
        "─┼─" <>
        String.duplicate("─", 20) <>
        "─┼─" <>
        String.duplicate("─", 20)

    IO.puts(divider)

    Enum.each(connections, fn conn ->
      endpoint = conn.url || conn.raw_url || "(not configured)"
      source = conn.source || "-"
      details = conn.details || "-"

      IO.puts(
        String.pad_trailing(conn.name, 16) <>
          " │ " <>
          String.pad_trailing(endpoint, 32) <>
          " │ " <>
          String.pad_trailing(source, 20) <>
          " │ " <>
          details
      )
    end)

    IO.puts(String.duplicate("═", @table_width))
    IO.puts("")
  end

  # Header

  defp print_header(color?) do
    line = String.duplicate("═", @table_width)
    title = "SYSTEM HEALTH STATUS"
    padding = div(@table_width - String.length(title), 2)
    centered_title = String.duplicate(" ", padding) <> title

    IO.puts(line)
    IO.puts(colorize(centered_title, :bright, color?))
    IO.puts(line)
    IO.puts("")
  end

  # Environment

  defp print_environment(env, color?) do
    IO.puts(
      "  Mix Environment : #{colorize(to_string(env.mix_env), env_color(env.mix_env), color?)}"
    )

    IO.puts(
      "  Elixir / OTP    : #{colorize("#{env.elixir_version} / #{env.otp_release}", :cyan, color?)}"
    )

    IO.puts("  Node            : #{colorize(to_string(env.node_name), :light_black, color?)}")
    IO.puts("  Hostname        : #{colorize(env.hostname, :light_black, color?)}")

    if env.in_docker do
      IO.puts("  Container       : #{colorize("✓ Docker", :cyan, color?)}")
    end

    if env.mix_env == :dev and length(env.watchers) > 0 do
      IO.puts("")
      IO.puts("  Development:")

      IO.puts(
        "    Live Reload : #{if env.live_reload == :enabled, do: colorize("✓ Enabled", :green, color?), else: colorize("Disabled", :light_black, color?)}"
      )

      IO.puts("    Watchers    : #{colorize(Enum.join(env.watchers, ", "), :cyan, color?)}")
    end

    print_separator()
  end

  # Mise

  defp print_mise(mise, color?) do
    IO.puts("  Shell           : #{colorize(mise.shell, :cyan, color?)}")

    if length(mise.tools) > 0 do
      IO.puts("")
      IO.puts("  Managed Tools:")

      Enum.each(mise.tools, fn {tool, version} ->
        IO.puts("    #{String.pad_trailing(tool, 12)}: #{colorize(version, :cyan, color?)}")
      end)
    end

    if length(mise.env_vars) > 0 do
      IO.puts("")
      IO.puts("  Environment Variables:")

      Enum.each(mise.env_vars, fn {label, _key, value} ->
        display_value =
          if String.length(value) > 40, do: String.slice(value, 0, 37) <> "...", else: value

        IO.puts(
          "    #{String.pad_trailing(label, 18)}: #{colorize(display_value, :light_black, color?)}"
        )
      end)
    end

    print_separator()
  end

  # Proxy

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
        IO.puts("    • #{service}")
      end)
    end

    print_separator()
  end

  # Services Table

  defp print_services_table(services, color?) do
    # Table header
    header =
      String.pad_trailing("SERVICE", 12) <>
        " │ " <>
        String.pad_trailing("STATUS", 10) <>
        " │ " <>
        String.pad_trailing("ADAPTER", 18) <>
        " │ " <>
        String.pad_trailing("LEVEL", 8) <>
        " │ INFO"

    IO.puts(header)

    divider =
      String.duplicate("─", 12) <>
        "─┼─" <>
        String.duplicate("─", 10) <>
        "─┼─" <>
        String.duplicate("─", 18) <>
        "─┼─" <>
        String.duplicate("─", 8) <>
        "─┼─" <>
        String.duplicate("─", 30)

    IO.puts(divider)

    # Table rows
    Enum.each(services, fn service ->
      print_service_row(service, color?)
    end)

    IO.puts(String.duplicate("═", @table_width))
    IO.puts("")
  end

  defp print_service_row(service, color?) do
    status_text = if service.status == :ok, do: "✓ Running", else: "✗ Failed"

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
        " │ " <>
        pad_colored(status_text, status_colored, 10) <>
        " │ " <>
        String.pad_trailing(service.adapter, 18) <>
        " │ " <>
        pad_colored(level_text, level_colored, 8) <>
        " │ " <>
        info_text
    )
  end

  # Summary

  defp print_summary(health, color?) do
    services = health.services
    ok_count = Enum.count(services, &(&1.status == :ok))
    total_count = length(services)
    critical_failed = Enum.filter(services, &(&1.critical and &1.status != :ok))
    optional_failed = Enum.filter(services, &(not &1.critical and &1.status != :ok))

    cond do
      ok_count == total_count ->
        IO.puts(
          colorize("✓ ALL SYSTEMS OPERATIONAL (#{ok_count}/#{total_count})", :green_bright, color?)
        )

      length(critical_failed) > 0 ->
        IO.puts(
          colorize(
            "✗ CRITICAL: #{length(critical_failed)} critical service(s) failed!",
            :red_bright,
            color?
          )
        )

        IO.puts(colorize("  Application may not function correctly", :red, color?))

        Enum.each(critical_failed, fn service ->
          IO.puts(colorize("  • #{service.name}: #{service.info}", :red, color?))
        end)

      length(optional_failed) > 0 ->
        IO.puts(
          colorize(
            "⚠ DEGRADED: #{length(optional_failed)} optional service(s) unavailable",
            :yellow,
            color?
          )
        )

        IO.puts(colorize("  Application running with reduced functionality", :light_black, color?))

        Enum.each(optional_failed, fn service ->
          IO.puts(colorize("  • #{service.name}: #{service.impact}", :yellow, color?))
        end)

      true ->
        IO.puts(colorize("✓ All services running (#{ok_count}/#{total_count})", :green, color?))
    end

    IO.puts("")
  end

  # Footer

  defp print_footer(health, color?) do
    # Migration status
    if health.migrations.status == :pending do
      IO.puts(
        colorize(
          "⚠ Migrations: #{health.migrations.applied}/#{health.migrations.total} applied, #{health.migrations.pending} pending",
          :yellow,
          color?
        )
      )

      IO.puts(colorize("  Run: mix ecto.migrate", :yellow, color?))
      IO.puts("")
    else
      if health.migrations.total > 0 do
        IO.puts(
          colorize(
            "✓ Migrations: #{health.migrations.applied}/#{health.migrations.total} applied, up to date",
            :green,
            color?
          )
        )

        if health.migrations.last_migration do
          IO.puts(colorize("  Last: #{health.migrations.last_migration}", :light_black, color?))
        end

        IO.puts("")
      end
    end

    # Timestamp and duration
    timestamp = Calendar.strftime(health.timestamp, "%Y-%m-%d %H:%M:%S UTC")
    IO.puts(colorize("Checked at #{timestamp} (#{health.duration_ms}ms)", :light_black, color?))
    IO.puts("")
  end

  # Utilities

  defp print_section_header(title, color?) do
    IO.puts(colorize(title, :bright, color?))
    IO.puts("")
  end

  defp print_separator do
    IO.puts(String.duplicate("─", @table_width))
    IO.puts("")
  end

  defp env_color(:prod), do: :red
  defp env_color(:test), do: :yellow
  defp env_color(:dev), do: :green
  defp env_color(_), do: :white

  defp pad_colored(text, colored_text, width) do
    # Calculate actual text length (without ANSI codes)
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
