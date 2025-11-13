defmodule Events.SystemHealth.Proxy do
  @moduledoc """
  Proxy configuration detection and status.
  """

  @doc """
  Gets proxy configuration from environment variables.
  """
  @spec get_config() :: map()
  def get_config do
    http_proxy = get_env("HTTP_PROXY") || get_env("http_proxy")
    https_proxy = get_env("HTTPS_PROXY") || get_env("https_proxy")
    no_proxy = get_env("NO_PROXY") || get_env("no_proxy")

    %{
      configured: not is_nil(http_proxy) or not is_nil(https_proxy),
      http_proxy: http_proxy,
      https_proxy: https_proxy,
      no_proxy: no_proxy,
      services_using_proxy: if(http_proxy || https_proxy, do: ["Req", "AWS S3"], else: [])
    }
  end

  defp get_env(key), do: System.get_env(key)
end
