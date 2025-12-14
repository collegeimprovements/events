defmodule Events.Services.S3.Config do
  @moduledoc """
  S3 configuration with AWS credentials and HTTP options.

  Supports:
  - AWS credentials (access key, secret key, region)
  - Custom endpoints (LocalStack, MinIO, DigitalOcean Spaces)
  - HTTP proxy configuration
  - Connection pooling options

  ## Examples

      # Basic configuration
      config = Config.new(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "us-east-1"
      )

      # With proxy
      config = Config.new(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "us-east-1",
        proxy: {"proxy.company.com", 8080},
        proxy_auth: {"user", "password"}
      )

      # LocalStack
      config = Config.new(
        access_key_id: "test",
        secret_access_key: "test",
        region: "us-east-1",
        endpoint: "http://localhost:4566"
      )

      # From environment
      config = Config.from_env()
  """

  @type proxy :: {String.t(), pos_integer()} | {:http, String.t(), pos_integer(), keyword()}
  @type proxy_auth :: {String.t(), String.t()}

  @type t :: %__MODULE__{
          access_key_id: String.t(),
          secret_access_key: String.t(),
          region: String.t(),
          endpoint: String.t() | nil,
          proxy: proxy() | nil,
          proxy_auth: proxy_auth() | nil,
          connect_timeout: pos_integer(),
          receive_timeout: pos_integer()
        }

  @enforce_keys [:access_key_id, :secret_access_key, :region]
  defstruct [
    :access_key_id,
    :secret_access_key,
    :region,
    :endpoint,
    :proxy,
    :proxy_auth,
    connect_timeout: 30_000,
    receive_timeout: 60_000
  ]

  @doc """
  Creates a new S3 configuration.

  ## Options

  - `:access_key_id` - AWS access key ID (required)
  - `:secret_access_key` - AWS secret access key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:endpoint` - Custom endpoint URL for S3-compatible services
  - `:proxy` - HTTP proxy as `{host, port}` or `{:http, host, port, opts}`
  - `:proxy_auth` - Proxy authentication as `{username, password}`
  - `:connect_timeout` - Connection timeout in ms (default: 30000)
  - `:receive_timeout` - Receive timeout in ms (default: 60000)

  ## Examples

      Config.new(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "eu-west-1"
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, "us-east-1"),
      endpoint: Keyword.get(opts, :endpoint),
      proxy: normalize_proxy(Keyword.get(opts, :proxy)),
      proxy_auth: Keyword.get(opts, :proxy_auth),
      connect_timeout: Keyword.get(opts, :connect_timeout, 30_000),
      receive_timeout: Keyword.get(opts, :receive_timeout, 60_000)
    }
  end

  @doc """
  Creates configuration from environment variables.

  ## Environment Variables

  - `AWS_ACCESS_KEY_ID` - AWS access key (required)
  - `AWS_SECRET_ACCESS_KEY` - AWS secret key (required)
  - `AWS_REGION` or `AWS_DEFAULT_REGION` - Region (default: "us-east-1")
  - `AWS_ENDPOINT_URL_S3` or `AWS_ENDPOINT` - Custom endpoint
  - `HTTP_PROXY` or `HTTPS_PROXY` - Proxy URL (e.g., "http://user:pass@proxy:8080")

  ## Examples

      # Set ENV vars:
      # AWS_ACCESS_KEY_ID=AKIA...
      # AWS_SECRET_ACCESS_KEY=...
      # AWS_REGION=us-east-1

      config = Config.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    alias FnTypes.Config, as: Cfg

    proxy = parse_proxy_from_env()
    {proxy_host, proxy_auth} = proxy || {nil, nil}

    new(
      access_key_id: Cfg.string!("AWS_ACCESS_KEY_ID"),
      secret_access_key: Cfg.string!("AWS_SECRET_ACCESS_KEY"),
      region: Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1"),
      endpoint: Cfg.string(["AWS_ENDPOINT_URL_S3", "AWS_ENDPOINT"]),
      proxy: proxy_host,
      proxy_auth: proxy_auth
    )
  end

  @doc """
  Builds Req connect_options for this configuration.

  Used internally by the Client module.
  """
  @spec connect_options(t()) :: keyword()
  def connect_options(%__MODULE__{} = config) do
    opts = [timeout: config.connect_timeout]

    opts
    |> maybe_add_proxy(config.proxy, config.proxy_auth)
  end

  @doc """
  Builds AWS SigV4 options for this configuration.

  Used internally by the Client module.
  """
  @spec aws_sigv4_options(t()) :: keyword()
  def aws_sigv4_options(%__MODULE__{} = config) do
    [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    ]
  end

  @doc """
  Builds ReqS3 presign options for this configuration.

  Used internally by the Client module.
  """
  @spec presign_options(t(), String.t(), String.t()) :: keyword()
  def presign_options(%__MODULE__{} = config, bucket, key) do
    opts = [
      bucket: bucket,
      key: key,
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    ]

    maybe_add_endpoint(opts, config.endpoint)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_proxy(nil), do: nil
  defp normalize_proxy({:http, _host, _port, _opts} = proxy), do: proxy

  defp normalize_proxy({host, port}) when is_binary(host) and is_integer(port) do
    {:http, host, port, []}
  end

  defp parse_proxy_from_env do
    alias FnTypes.Config, as: Cfg

    case Cfg.string(["HTTPS_PROXY", "HTTP_PROXY"]) do
      nil -> nil
      url -> parse_proxy_url(url)
    end
  end

  defp parse_proxy_url(url) do
    uri = URI.parse(url)

    host = uri.host
    port = uri.port || 8080

    auth =
      case uri.userinfo do
        nil ->
          nil

        userinfo ->
          case String.split(userinfo, ":", parts: 2) do
            [user, pass] -> {user, pass}
            [user] -> {user, ""}
          end
      end

    {{:http, host, port, []}, auth}
  end

  defp maybe_add_proxy(opts, nil, _auth), do: opts

  defp maybe_add_proxy(opts, proxy, nil) do
    Keyword.put(opts, :proxy, proxy)
  end

  defp maybe_add_proxy(opts, proxy, {user, pass}) do
    auth_header = "Basic " <> Base.encode64("#{user}:#{pass}")

    opts
    |> Keyword.put(:proxy, proxy)
    |> Keyword.put(:proxy_headers, [{"proxy-authorization", auth_header}])
  end

  defp maybe_add_endpoint(opts, nil), do: opts

  defp maybe_add_endpoint(opts, endpoint) do
    Keyword.put(opts, :aws_endpoint_url_s3, endpoint)
  end
end
