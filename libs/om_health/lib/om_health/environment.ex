defmodule OmHealth.Environment do
  @moduledoc """
  Environment information and runtime configuration.

  Provides system environment detection including:
  - Mix environment
  - Elixir/OTP versions
  - Node and hostname
  - Docker/container detection
  - Live reload status
  - Active watchers

  ## Usage

      OmHealth.Environment.get_info()
      #=> %{
      #     mix_env: :dev,
      #     elixir_version: "1.15.0",
      #     otp_release: "26",
      #     node_name: :nonode@nohost,
      #     hostname: "myhost",
      #     in_docker: false,
      #     live_reload: :enabled,
      #     watchers: [:esbuild, :tailwind]
      #   }
  """

  alias FnTypes.Config, as: Cfg

  @type env_info :: %{
          mix_env: atom(),
          elixir_version: String.t(),
          otp_release: String.t(),
          node_name: atom(),
          hostname: String.t(),
          in_docker: boolean(),
          live_reload: :enabled | :disabled | :not_applicable | :unknown,
          watchers: [atom()]
        }

  @doc """
  Gets current environment information.

  ## Options

  - `:app_name` - Application name for config lookup (default: nil)
  - `:endpoint` - Phoenix endpoint module for dev info (default: nil)
  """
  @spec get_info(map() | keyword()) :: env_info()
  def get_info(opts \\ %{})

  def get_info(opts) when is_map(opts) do
    get_info(Map.to_list(opts))
  end

  def get_info(opts) when is_list(opts) do
    app_name = Keyword.get(opts, :app_name)
    endpoint = Keyword.get(opts, :endpoint)

    %{
      mix_env: safe_mix_env(),
      elixir_version: System.version(),
      otp_release: System.otp_release(),
      node_name: node(),
      hostname: safe_hostname(),
      in_docker: in_docker?(),
      live_reload: check_live_reload_status(app_name, endpoint),
      watchers: get_active_watchers(app_name, endpoint)
    }
  end

  @doc """
  Checks if running inside a Docker container.
  """
  @spec in_docker?() :: boolean()
  def in_docker? do
    File.exists?("/.dockerenv") or
      File.exists?("/run/.containerenv") or
      Cfg.boolean("DOCKER_CONTAINER", false)
  end

  @doc """
  Gets the current Mix environment safely.
  """
  @spec safe_mix_env() :: atom()
  def safe_mix_env do
    try do
      Mix.env()
    rescue
      _ -> :unknown
    end
  end

  @doc """
  Gets the system hostname safely.
  """
  @spec safe_hostname() :: String.t()
  def safe_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      _ -> "unknown"
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp check_live_reload_status(app_name, endpoint) do
    try do
      case safe_mix_env() do
        :dev -> get_live_reload_config(app_name, endpoint)
        _ -> :not_applicable
      end
    rescue
      _ -> :unknown
    end
  end

  defp get_live_reload_config(nil, _endpoint), do: :unknown
  defp get_live_reload_config(_app_name, nil), do: :unknown

  defp get_live_reload_config(app_name, endpoint) do
    Application.get_env(app_name, endpoint, [])
    |> Keyword.get(:live_reload)
    |> case do
      nil -> :disabled
      _ -> :enabled
    end
  end

  defp get_active_watchers(app_name, endpoint) do
    try do
      case safe_mix_env() do
        :dev -> get_watchers_for_env(app_name, endpoint)
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  defp get_watchers_for_env(nil, _endpoint), do: []
  defp get_watchers_for_env(_app_name, nil), do: []

  defp get_watchers_for_env(app_name, endpoint) do
    Application.get_env(app_name, endpoint, [])
    |> Keyword.get(:watchers, [])
    |> Enum.map(&extract_watcher_name/1)
  end

  defp extract_watcher_name({name, _}), do: name
  defp extract_watcher_name(other), do: other
end
