defmodule Events.Observability.HealthChecks.Mise do
  @moduledoc """
  Mise environment manager integration.
  """

  alias FnTypes.Config, as: Cfg

  @mise_env_vars [
    {"DB_POOL_SIZE", "DB Pool Size"},
    {"DB_QUEUE_TARGET", "DB Queue Target"},
    {"DB_QUEUE_INTERVAL", "DB Queue Interval"},
    {"DB_LOG_LEVEL", "DB Log Level"},
    {"PORT", "Phoenix Port"},
    {"SECRET_KEY_BASE", "Secret Key Base"}
  ]

  @doc """
  Gets mise environment information.
  """
  @spec get_info() :: map()
  def get_info do
    Cfg.string("MISE_SHELL")
    |> build_mise_info()
  end

  defp build_mise_info(nil), do: %{active: false}

  defp build_mise_info(mise_shell) do
    %{
      active: true,
      shell: mise_shell,
      tools: get_tools(),
      env_vars: get_env_vars()
    }
  end

  defp get_tools do
    [
      {"MIX_HOME", "Elixir", "elixir"},
      {"GOROOT", "Go", "go"},
      {"PGDATA", "PostgreSQL", "postgres"}
    ]
    |> Enum.map(&extract_tool_info/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_tool_info({env_var, tool_name, tool_key}) do
    Cfg.string(env_var)
    |> case do
      nil -> nil
      path -> {tool_name, extract_version(path, tool_key)}
    end
  end

  defp get_env_vars do
    @mise_env_vars
    |> Enum.map(&extract_env_var/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_env_var({key, label}) do
    Cfg.string(key)
    |> build_env_var(label, key)
  end

  defp build_env_var(nil, _label, _key), do: nil
  defp build_env_var(value, label, key), do: {label, key, mask_if_sensitive(label, value)}

  defp extract_version(path, tool) when is_binary(path) do
    ~r{/mise/installs/#{tool}/([^/]+)}
    |> Regex.run(path)
    |> parse_version_match()
  end

  defp extract_version(_, _), do: "unknown"

  defp parse_version_match([_, version]), do: version
  defp parse_version_match(_), do: "unknown"

  defp mask_if_sensitive(label, value) do
    label
    |> String.downcase()
    |> is_sensitive?()
    |> mask_value(value)
  end

  defp is_sensitive?(label) do
    String.contains?(label, ["secret", "key", "password"])
  end

  defp mask_value(false, value), do: value

  defp mask_value(true, value) do
    value
    |> String.length()
    |> build_mask(value)
  end

  defp build_mask(len, value) when len > 16 do
    String.slice(value, 0, 8) <> "••••••••" <> String.slice(value, -4, 4)
  end

  defp build_mask(len, value) when len > 8 do
    String.slice(value, 0, 4) <> "••••••••"
  end

  defp build_mask(_, _), do: "••••••••"
end
