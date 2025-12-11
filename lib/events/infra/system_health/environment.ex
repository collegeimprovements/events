defmodule Events.Infra.SystemHealth.Environment do
  @moduledoc """
  Environment information and runtime configuration.
  """

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)

  @doc """
  Gets current environment information.
  """
  @spec get_info() :: map()
  def get_info do
    %{
      mix_env: safe_mix_env(),
      elixir_version: System.version(),
      otp_release: System.otp_release(),
      node_name: node(),
      hostname: safe_hostname(),
      in_docker: in_docker?(),
      live_reload: check_live_reload_status(),
      watchers: get_active_watchers()
    }
  end

  defp safe_mix_env do
    try do
      Mix.env()
    rescue
      _ -> :unknown
    end
  end

  defp safe_hostname do
    :inet.gethostname()
    |> case do
      {:ok, hostname} -> to_string(hostname)
      _ -> "unknown"
    end
  end

  defp in_docker? do
    File.exists?("/.dockerenv") or
      File.exists?("/run/.containerenv") or
      System.get_env("DOCKER_CONTAINER") == "true"
  end

  defp check_live_reload_status do
    safe_mix_env()
    |> get_live_reload_config()
  rescue
    _ -> :unknown
  end

  defp get_live_reload_config(:dev) do
    Application.get_env(@app_name, EventsWeb.Endpoint, [])
    |> Keyword.get(:live_reload)
    |> case do
      nil -> :disabled
      _ -> :enabled
    end
  end

  defp get_live_reload_config(_), do: :not_applicable

  defp get_active_watchers do
    safe_mix_env()
    |> get_watchers_for_env()
  rescue
    _ -> []
  end

  defp get_watchers_for_env(:dev) do
    Application.get_env(@app_name, EventsWeb.Endpoint, [])
    |> Keyword.get(:watchers, [])
    |> Enum.map(&extract_watcher_name/1)
  end

  defp get_watchers_for_env(_), do: []

  defp extract_watcher_name({name, _}), do: name
  defp extract_watcher_name(other), do: other
end
