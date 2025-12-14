defmodule Events.Infra.SystemHealth.Proxy do
  @moduledoc """
  Proxy configuration detection and status.
  """

  alias FnTypes.Config, as: Cfg

  @doc """
  Gets proxy configuration from environment variables.
  """
  @spec get_config() :: map()
  def get_config do
    http_proxy = Cfg.string(["HTTP_PROXY", "http_proxy"])
    https_proxy = Cfg.string(["HTTPS_PROXY", "https_proxy"])
    no_proxy = Cfg.string(["NO_PROXY", "no_proxy"])

    %{
      configured: not is_nil(http_proxy) or not is_nil(https_proxy),
      http_proxy: http_proxy,
      https_proxy: https_proxy,
      no_proxy: no_proxy,
      services_using_proxy: if(http_proxy || https_proxy, do: ["Req", "AWS S3"], else: [])
    }
  end
end
