defmodule OmS3.Config do
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

  ## Proxy Configuration

  Proxy is resolved in priority order:

  1. Explicit `:proxy` option in `new/1`
  2. Application config: `config :om_s3, proxy: "..."`
  3. Environment variables: `HTTP_PROXY`/`HTTPS_PROXY`

  ### Application Config Example

      # config/runtime.exs
      config :om_s3,
        proxy: System.get_env("HTTP_PROXY"),
        proxy_auth: {System.get_env("PROXY_USER"), System.get_env("PROXY_PASS")}
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
          receive_timeout: pos_integer(),
          pool_timeout: pos_integer(),
          max_retries: non_neg_integer()
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
    receive_timeout: 60_000,
    pool_timeout: 5_000,
    max_retries: 3
  ]

  @doc """
  Creates a new S3 configuration.

  ## Options

  - `:access_key_id` - AWS access key ID (required)
  - `:secret_access_key` - AWS secret access key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:endpoint` - Custom endpoint URL for S3-compatible services
  - `:proxy` - HTTP proxy as URL string `"http://user:pass@proxy:8080"`, tuple `{host, port}`, or `{:http, host, port, opts}`
  - `:proxy_auth` - Proxy authentication as `{username, password}` (if not embedded in URL)
  - `:connect_timeout` - Connection timeout in ms (default: 30000). Alias: `:timeout`
  - `:receive_timeout` - Receive timeout in ms (default: 60000)
  - `:pool_timeout` - Connection pool checkout timeout in ms (default: 5000)
  - `:max_retries` - Maximum retry attempts for failed requests (default: 3)

  ## Examples

      Config.new(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "eu-west-1"
      )

      # With proxy URL (credentials embedded)
      Config.new(
        access_key_id: "AKIA...",
        secret_access_key: "...",
        region: "eu-west-1",
        proxy: "http://user:pass@proxy.example.com:8080"
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {proxy_host, proxy_auth} = normalize_proxy_opts(opts)
    # Support both :timeout and :connect_timeout for consistency with other libs
    connect_timeout = Keyword.get(opts, :connect_timeout) || Keyword.get(opts, :timeout, 30_000)
    connect_timeout = validate_timeout!(connect_timeout, :connect_timeout)
    receive_timeout = validate_timeout!(Keyword.get(opts, :receive_timeout, 60_000), :receive_timeout)
    pool_timeout = validate_timeout!(Keyword.get(opts, :pool_timeout, 5_000), :pool_timeout)
    max_retries = validate_max_retries!(Keyword.get(opts, :max_retries, 3))

    %__MODULE__{
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, "us-east-1"),
      endpoint: Keyword.get(opts, :endpoint),
      proxy: proxy_host,
      proxy_auth: proxy_auth,
      connect_timeout: connect_timeout,
      receive_timeout: receive_timeout,
      pool_timeout: pool_timeout,
      max_retries: max_retries
    }
  end

  defp validate_timeout!(ms, _field) when is_integer(ms) and ms > 0, do: ms

  defp validate_timeout!(ms, field) do
    raise ArgumentError, "#{field} must be a positive integer, got: #{inspect(ms)}"
  end

  defp validate_max_retries!(n) when is_integer(n) and n >= 0, do: n

  defp validate_max_retries!(n) do
    raise ArgumentError, "max_retries must be a non-negative integer, got: #{inspect(n)}"
  end

  defp normalize_proxy_opts(opts) do
    # Priority: explicit option > app config > env vars
    proxy = Keyword.get(opts, :proxy) || get_app_config_proxy()
    proxy_auth = Keyword.get(opts, :proxy_auth) || get_app_config_proxy_auth()

    case proxy do
      nil ->
        # Fallback to env vars
        case OmHttp.Proxy.from_env() do
          {:ok, %OmHttp.Proxy{host: host, auth: auth}} -> {host, auth}
          :no_proxy -> {nil, nil}
        end

      url when is_binary(url) ->
        # Parse URL format using OmHttp.Proxy
        case OmHttp.Proxy.parse(url) do
          {:ok, %OmHttp.Proxy{host: host, auth: url_auth}} ->
            # Explicit proxy_auth takes precedence over URL-embedded auth
            {host, proxy_auth || url_auth}

          {:error, _} ->
            {nil, nil}
        end

      {host, port} when is_binary(host) and is_integer(port) ->
        {{:http, host, port, []}, proxy_auth}

      {:http, _host, _port, _opts} = full_proxy ->
        {full_proxy, proxy_auth}
    end
  end

  defp get_app_config_proxy do
    Application.get_env(:om_s3, :proxy) ||
      Application.get_env(:om_s3, OmS3)[:proxy]
  end

  defp get_app_config_proxy_auth do
    Application.get_env(:om_s3, :proxy_auth) ||
      Application.get_env(:om_s3, OmS3)[:proxy_auth]
  end

  @doc """
  Creates configuration from environment variables.

  ## Environment Variables

  - `AWS_ACCESS_KEY_ID` - AWS access key (required)
  - `AWS_SECRET_ACCESS_KEY` - AWS secret key (required)
  - `AWS_REGION` or `AWS_DEFAULT_REGION` - Region (default: "us-east-1")
  - `AWS_ENDPOINT_URL_S3` or `AWS_ENDPOINT` - Custom endpoint
  - `HTTP_PROXY` or `HTTPS_PROXY` - Proxy URL (optional, fallback)

  Proxy is resolved in priority order: app config > env vars (HTTP_PROXY/HTTPS_PROXY)

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

    new(
      access_key_id: Cfg.string!("AWS_ACCESS_KEY_ID"),
      secret_access_key: Cfg.string!("AWS_SECRET_ACCESS_KEY"),
      region: Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1"),
      endpoint: Cfg.string(["AWS_ENDPOINT_URL_S3", "AWS_ENDPOINT"])
      # proxy is resolved automatically via normalize_proxy_opts/1 in new/1
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

  defp maybe_add_proxy(opts, nil, _auth), do: opts

  defp maybe_add_proxy(opts, proxy, proxy_auth) do
    # Use OmHttp.Proxy to generate consistent Req options
    proxy_config = %OmHttp.Proxy{host: proxy, auth: proxy_auth}
    proxy_opts = OmHttp.Proxy.to_req_options(proxy_config)

    Keyword.merge(opts, proxy_opts)
  end

  defp maybe_add_endpoint(opts, nil), do: opts

  defp maybe_add_endpoint(opts, endpoint) do
    Keyword.put(opts, :aws_endpoint_url_s3, endpoint)
  end
end
