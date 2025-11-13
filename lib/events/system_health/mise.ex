defmodule Events.SystemHealth.Mise do
  @moduledoc """
  Mise environment manager integration.
  """

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
    mise_shell = System.get_env("MISE_SHELL")

    if mise_shell do
      %{
        active: true,
        shell: mise_shell,
        tools: get_tools(),
        env_vars: get_env_vars()
      }
    else
      %{active: false}
    end
  end

  defp get_tools do
    tools = []

    tools =
      if path = System.get_env("MIX_HOME") do
        tools ++ [{"Elixir", extract_version(path, "elixir")}]
      else
        tools
      end

    tools =
      if path = System.get_env("GOROOT") do
        tools ++ [{"Go", extract_version(path, "go")}]
      else
        tools
      end

    tools =
      if path = System.get_env("PGDATA") do
        tools ++ [{"PostgreSQL", extract_version(path, "postgres")}]
      else
        tools
      end

    tools
  end

  defp get_env_vars do
    @mise_env_vars
    |> Enum.map(fn {key, label} ->
      case System.get_env(key) do
        nil -> nil
        value -> {label, key, mask_if_sensitive(label, value)}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_version(path, tool) when is_binary(path) do
    case Regex.run(~r{/mise/installs/#{tool}/([^/]+)}, path) do
      [_, version] -> version
      _ -> "unknown"
    end
  end

  defp extract_version(_, _), do: "unknown"

  defp mask_if_sensitive(label, value) do
    if String.contains?(String.downcase(label), ["secret", "key", "password"]) do
      case String.length(value) do
        len when len > 16 ->
          String.slice(value, 0, 8) <> "••••••••" <> String.slice(value, -4, 4)

        len when len > 8 ->
          String.slice(value, 0, 4) <> "••••••••"

        _ ->
          "••••••••"
      end
    else
      value
    end
  end
end
