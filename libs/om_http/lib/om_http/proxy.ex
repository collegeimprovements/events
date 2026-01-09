defmodule OmHttp.Proxy do
  @moduledoc """
  Unified proxy configuration for HTTP clients.

  Supports multiple input formats and provides consistent output
  for Req/Finch/Mint HTTP clients.

  ## Input Formats

  ### URL with embedded credentials
      "http://user:password@proxy.example.com:8080"
      "https://proxy.example.com:3128"

  ### Separate proxy and auth
      proxy: "http://proxy.example.com:8080"
      proxy_auth: {"username", "password"}

  ### Tuple format
      proxy: {"proxy.example.com", 8080}
      proxy_auth: {"username", "password"}

  ### Full Mint format
      proxy: {:http, "proxy.example.com", 8080, []}

  ## Environment Variables

  Automatically reads from (in order of precedence):
  - `HTTPS_PROXY` / `https_proxy`
  - `HTTP_PROXY` / `http_proxy`

  Respects `NO_PROXY` / `no_proxy` for exclusions.

  ## Usage

      # Parse from various inputs
      {:ok, config} = OmHttp.Proxy.parse("http://user:pass@proxy:8080")
      {:ok, config} = OmHttp.Proxy.parse(proxy: {"proxy.com", 8080}, proxy_auth: {"user", "pass"})

      # Get Req connect_options
      connect_opts = OmHttp.Proxy.to_req_options(config)
      Req.get!(url, connect_options: connect_opts)

      # Or get from environment
      case OmHttp.Proxy.from_env() do
        {:ok, config} -> OmHttp.Proxy.to_req_options(config)
        :no_proxy -> []
      end
  """

  @type proxy_host :: {:http, String.t(), pos_integer(), keyword()}
  @type proxy_auth :: {String.t(), String.t()}

  @type t :: %__MODULE__{
          host: proxy_host() | nil,
          auth: proxy_auth() | nil,
          no_proxy: [String.t()]
        }

  defstruct [:host, :auth, no_proxy: []]

  # ============================================
  # Parsing
  # ============================================

  @doc """
  Parses proxy configuration from various input formats.

  ## Examples

      # From URL with credentials
      {:ok, config} = OmHttp.Proxy.parse("http://user:pass@proxy.example.com:8080")

      # From URL without credentials
      {:ok, config} = OmHttp.Proxy.parse("http://proxy.example.com:8080")

      # From keyword options
      {:ok, config} = OmHttp.Proxy.parse(proxy: "http://proxy.example.com:8080")
      {:ok, config} = OmHttp.Proxy.parse(proxy: {"proxy.example.com", 8080})
      {:ok, config} = OmHttp.Proxy.parse(
        proxy: "http://proxy.example.com:8080",
        proxy_auth: {"user", "pass"}
      )

      # Nil returns empty config
      {:ok, config} = OmHttp.Proxy.parse(nil)
      config.host #=> nil
  """
  @spec parse(String.t() | keyword() | map() | nil) :: {:ok, t()} | {:error, term()}
  def parse(nil), do: {:ok, %__MODULE__{}}

  def parse(url) when is_binary(url) do
    parse_url(url)
  end

  def parse(opts) when is_list(opts) or is_map(opts) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    proxy = Keyword.get(opts, :proxy)
    proxy_auth = Keyword.get(opts, :proxy_auth)
    no_proxy = Keyword.get(opts, :no_proxy, [])

    with {:ok, host, url_auth} <- parse_proxy_value(proxy) do
      # Explicit proxy_auth takes precedence over URL-embedded auth
      auth = proxy_auth || url_auth
      no_proxy_list = parse_no_proxy(no_proxy)

      {:ok, %__MODULE__{host: host, auth: auth, no_proxy: no_proxy_list}}
    end
  end

  @doc """
  Parses proxy configuration from environment variables.

  Checks in order:
  1. `HTTPS_PROXY` / `https_proxy`
  2. `HTTP_PROXY` / `http_proxy`

  Also reads `NO_PROXY` / `no_proxy` for exclusions.

  ## Examples

      case OmHttp.Proxy.from_env() do
        {:ok, %OmHttp.Proxy{} = config} ->
          # Proxy configured
          OmHttp.Proxy.to_req_options(config)

        :no_proxy ->
          # No proxy configured
          []
      end
  """
  @spec from_env() :: {:ok, t()} | :no_proxy
  def from_env do
    proxy_url = get_env_proxy()
    no_proxy = get_env_no_proxy()

    case proxy_url do
      nil ->
        :no_proxy

      url ->
        case parse_url(url) do
          {:ok, config} ->
            {:ok, %{config | no_proxy: no_proxy}}

          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Gets proxy configuration, preferring explicit config over environment.

  ## Examples

      # Uses explicit config if provided
      config = OmHttp.Proxy.get_config(proxy: "http://proxy:8080")

      # Falls back to environment if no explicit config
      config = OmHttp.Proxy.get_config([])

      # Returns nil if no proxy anywhere
      config = OmHttp.Proxy.get_config(nil)  # and no env vars
  """
  @spec get_config(keyword() | map() | String.t() | nil) :: t() | nil
  def get_config(nil) do
    case from_env() do
      {:ok, config} -> config
      :no_proxy -> nil
    end
  end

  def get_config(opts) when is_list(opts) or is_map(opts) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    case Keyword.get(opts, :proxy) do
      nil ->
        get_config(nil)

      _ ->
        case parse(opts) do
          {:ok, config} -> config
          {:error, _} -> nil
        end
    end
  end

  def get_config(url) when is_binary(url) do
    case parse(url) do
      {:ok, config} -> config
      {:error, _} -> nil
    end
  end

  # ============================================
  # Output Formats
  # ============================================

  @doc """
  Converts proxy config to Req connect_options format.

  Returns a keyword list suitable for Req's `connect_options` parameter.

  ## Examples

      config = OmHttp.Proxy.get_config(proxy: "http://user:pass@proxy:8080")
      opts = OmHttp.Proxy.to_req_options(config)

      Req.get!(url, connect_options: opts)

      # Or merge with other options
      Req.new(connect_options: opts ++ [timeout: 30_000])
  """
  @spec to_req_options(t() | nil) :: keyword()
  def to_req_options(nil), do: []
  def to_req_options(%__MODULE__{host: nil}), do: []

  def to_req_options(%__MODULE__{host: host, auth: nil}) do
    [proxy: host]
  end

  def to_req_options(%__MODULE__{host: host, auth: {user, pass}}) do
    auth_header = "Basic " <> Base.encode64("#{user}:#{pass}")

    [
      proxy: host,
      proxy_headers: [{"proxy-authorization", auth_header}]
    ]
  end

  @doc """
  Checks if a host should bypass the proxy based on NO_PROXY settings.

  ## Examples

      config = %OmHttp.Proxy{no_proxy: ["localhost", ".internal.com"]}

      OmHttp.Proxy.should_bypass?(config, "localhost")
      #=> true

      OmHttp.Proxy.should_bypass?(config, "api.internal.com")
      #=> true

      OmHttp.Proxy.should_bypass?(config, "api.external.com")
      #=> false
  """
  @spec should_bypass?(t(), String.t()) :: boolean()
  def should_bypass?(%__MODULE__{no_proxy: no_proxy}, host) when is_binary(host) do
    Enum.any?(no_proxy, fn pattern ->
      cond do
        # Exact match
        pattern == host -> true
        # Wildcard suffix match (e.g., ".example.com" matches "api.example.com")
        String.starts_with?(pattern, ".") and String.ends_with?(host, pattern) -> true
        # Suffix match without dot (e.g., "example.com" matches "api.example.com")
        String.ends_with?(host, "." <> pattern) -> true
        # No match
        true -> false
      end
    end)
  end

  def should_bypass?(nil, _host), do: false
  def should_bypass?(%__MODULE__{no_proxy: []}, _host), do: false

  @doc """
  Returns Req options only if the target host should not bypass proxy.

  ## Examples

      config = OmHttp.Proxy.get_config(proxy: "http://proxy:8080", no_proxy: "localhost")

      # Returns proxy options for external hosts
      OmHttp.Proxy.to_req_options_for(config, "api.stripe.com")
      #=> [proxy: {:http, "proxy", 8080, []}]

      # Returns empty for bypassed hosts
      OmHttp.Proxy.to_req_options_for(config, "localhost")
      #=> []
  """
  @spec to_req_options_for(t() | nil, String.t()) :: keyword()
  def to_req_options_for(nil, _host), do: []

  def to_req_options_for(%__MODULE__{} = config, host) do
    if should_bypass?(config, host) do
      []
    else
      to_req_options(config)
    end
  end

  # ============================================
  # Introspection
  # ============================================

  @doc """
  Checks if proxy is configured.

  ## Examples

      OmHttp.Proxy.configured?(%OmHttp.Proxy{host: {:http, "proxy", 8080, []}})
      #=> true

      OmHttp.Proxy.configured?(%OmHttp.Proxy{host: nil})
      #=> false

      OmHttp.Proxy.configured?(nil)
      #=> false
  """
  @spec configured?(t() | nil) :: boolean()
  def configured?(nil), do: false
  def configured?(%__MODULE__{host: nil}), do: false
  def configured?(%__MODULE__{}), do: true

  @doc """
  Returns proxy URL as a string for display/logging.

  Masks credentials if present.

  ## Examples

      config = OmHttp.Proxy.get_config(proxy: "http://user:pass@proxy:8080")
      OmHttp.Proxy.to_string(config)
      #=> "http://***:***@proxy:8080"
  """
  @spec to_string(t() | nil) :: String.t() | nil
  def to_string(nil), do: nil
  def to_string(%__MODULE__{host: nil}), do: nil

  def to_string(%__MODULE__{host: {:http, host, port, _}, auth: nil}) do
    "http://#{host}:#{port}"
  end

  def to_string(%__MODULE__{host: {:http, host, port, _}, auth: {_user, _pass}}) do
    "http://***:***@#{host}:#{port}"
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp parse_url(url) do
    uri = URI.parse(url)

    case uri.host do
      nil ->
        {:error, {:invalid_proxy_url, url}}

      host ->
        port = uri.port || default_port(uri.scheme)
        scheme = normalize_scheme(uri.scheme)

        proxy_host = {scheme, host, port, []}
        auth = parse_userinfo(uri.userinfo)

        {:ok, %__MODULE__{host: proxy_host, auth: auth}}
    end
  end

  defp parse_proxy_value(nil), do: {:ok, nil, nil}

  defp parse_proxy_value(url) when is_binary(url) do
    case parse_url(url) do
      {:ok, %{host: host, auth: auth}} -> {:ok, host, auth}
      {:error, _} = error -> error
    end
  end

  defp parse_proxy_value({host, port}) when is_binary(host) and is_integer(port) do
    {:ok, {:http, host, port, []}, nil}
  end

  defp parse_proxy_value({:http, _host, _port, _opts} = proxy) do
    {:ok, proxy, nil}
  end

  defp parse_proxy_value(invalid) do
    {:error, {:invalid_proxy_format, invalid}}
  end

  defp parse_userinfo(nil), do: nil

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {URI.decode_www_form(user), URI.decode_www_form(pass)}
      [user] -> {URI.decode_www_form(user), ""}
    end
  end

  defp parse_no_proxy(nil), do: []
  defp parse_no_proxy(list) when is_list(list), do: list

  defp parse_no_proxy(string) when is_binary(string) do
    string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp default_port("https"), do: 443
  defp default_port(_), do: 8080

  defp normalize_scheme("https"), do: :https
  defp normalize_scheme(_), do: :http

  defp get_env_proxy do
    System.get_env("HTTPS_PROXY") ||
      System.get_env("https_proxy") ||
      System.get_env("HTTP_PROXY") ||
      System.get_env("http_proxy")
  end

  defp get_env_no_proxy do
    (System.get_env("NO_PROXY") || System.get_env("no_proxy") || "")
    |> parse_no_proxy()
  end
end
