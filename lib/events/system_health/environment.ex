defmodule Events.SystemHealth.Environment do
  @moduledoc """
  Environment information and runtime configuration.
  """

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
    case :inet.gethostname() do
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
    try do
      case safe_mix_env() do
        :dev ->
          case Application.get_env(:events, EventsWeb.Endpoint, [])[:live_reload] do
            nil -> :disabled
            _ -> :enabled
          end

        _ ->
          :not_applicable
      end
    rescue
      _ -> :unknown
    end
  end

  defp get_active_watchers do
    try do
      case safe_mix_env() do
        :dev ->
          watchers = Application.get_env(:events, EventsWeb.Endpoint, [])[:watchers] || []

          Enum.map(watchers, fn
            {name, _} -> name
            other -> other
          end)

        _ ->
          []
      end
    rescue
      _ -> []
    end
  end
end
