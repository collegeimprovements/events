defmodule OmHealth.Proxy do
  @moduledoc """
  Proxy configuration detection and status.

  Detects proxy settings from environment variables:
  - `HTTP_PROXY` / `http_proxy`
  - `HTTPS_PROXY` / `https_proxy`
  - `NO_PROXY` / `no_proxy`

  ## Usage

      OmHealth.Proxy.get_config()
      #=> %{
      #     configured: true,
      #     http_proxy: "http://proxy.example.com:8080",
      #     https_proxy: "http://proxy.example.com:8080",
      #     no_proxy: "localhost,127.0.0.1",
      #     services_using_proxy: ["Req", "AWS S3"]
      #   }
  """

  alias FnTypes.Config, as: Cfg

  @type proxy_config :: %{
          configured: boolean(),
          http_proxy: String.t() | nil,
          https_proxy: String.t() | nil,
          no_proxy: String.t() | nil,
          services_using_proxy: [String.t()]
        }

  @default_proxy_services ["Req", "AWS S3"]

  @doc """
  Gets proxy configuration from environment variables.

  ## Options

  - `:services` - List of service names that use the proxy (default: ["Req", "AWS S3"])
  """
  @spec get_config(keyword()) :: proxy_config()
  def get_config(opts \\ []) do
    http_proxy = Cfg.string(["HTTP_PROXY", "http_proxy"])
    https_proxy = Cfg.string(["HTTPS_PROXY", "https_proxy"])
    no_proxy = Cfg.string(["NO_PROXY", "no_proxy"])

    proxy_services = Keyword.get(opts, :services, @default_proxy_services)
    configured = not is_nil(http_proxy) or not is_nil(https_proxy)

    %{
      configured: configured,
      http_proxy: http_proxy,
      https_proxy: https_proxy,
      no_proxy: no_proxy,
      services_using_proxy: if(configured, do: proxy_services, else: [])
    }
  end

  @doc """
  Checks if any proxy is configured.
  """
  @spec configured?() :: boolean()
  def configured? do
    not is_nil(Cfg.string(["HTTP_PROXY", "http_proxy"])) or
      not is_nil(Cfg.string(["HTTPS_PROXY", "https_proxy"]))
  end
end
