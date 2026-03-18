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
          no_proxy: [String.t()],
          connect_timeout: pos_integer(),
          receive_timeout: pos_integer(),
          pool_timeout: pos_integer(),
          max_retries: non_neg_integer(),
          transfer_acceleration: boolean(),
          path_style: boolean()
        }

  @enforce_keys [:access_key_id, :secret_access_key, :region]
  defstruct [
    :access_key_id,
    :secret_access_key,
    :region,
    :endpoint,
    :proxy,
    :proxy_auth,
    no_proxy: [],
    connect_timeout: 30_000,
    receive_timeout: 60_000,
    pool_timeout: 5_000,
    max_retries: 3,
    transfer_acceleration: false,
    path_style: false
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
  - `:transfer_acceleration` - Enable S3 Transfer Acceleration (AWS-only, default: false)
  - `:path_style` - Use path-style URLs instead of virtual-hosted-style.
    Defaults to `true` when `:endpoint` is set (recommended for non-AWS providers),
    `false` otherwise (AWS virtual-hosted-style). Override explicitly if needed.

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
    {proxy_host, proxy_auth, no_proxy} = normalize_proxy_opts(opts)
    # Support both :timeout and :connect_timeout for consistency with other libs
    connect_timeout = Keyword.get(opts, :connect_timeout) || Keyword.get(opts, :timeout, 30_000)
    connect_timeout = validate_timeout!(connect_timeout, :connect_timeout)
    receive_timeout = validate_timeout!(Keyword.get(opts, :receive_timeout, 60_000), :receive_timeout)
    pool_timeout = validate_timeout!(Keyword.get(opts, :pool_timeout, 5_000), :pool_timeout)
    max_retries = validate_max_retries!(Keyword.get(opts, :max_retries, 3))

    endpoint = Keyword.get(opts, :endpoint)
    is_custom_endpoint = endpoint != nil and not String.contains?(endpoint || "", "amazonaws.com")
    transfer_acceleration = Keyword.get(opts, :transfer_acceleration, false)

    # Transfer Acceleration is AWS-only — raise for non-AWS endpoints instead of
    # silently generating broken s3-accelerate.amazonaws.com URLs
    if transfer_acceleration && is_custom_endpoint do
      raise ArgumentError,
        "transfer_acceleration is AWS-only and cannot be used with endpoint #{inspect(endpoint)}"
    end

    # Default to path-style for custom endpoints (MinIO, RustFS, R2, LocalStack, etc.)
    # Virtual-hosted-style requires DNS support (bucket.endpoint) which most non-AWS
    # providers don't offer. Users can explicitly set path_style: false to override.
    path_style = Keyword.get_lazy(opts, :path_style, fn -> is_custom_endpoint end)

    %__MODULE__{
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, "us-east-1"),
      endpoint: endpoint,
      proxy: proxy_host,
      proxy_auth: proxy_auth,
      no_proxy: no_proxy,
      connect_timeout: connect_timeout,
      receive_timeout: receive_timeout,
      pool_timeout: pool_timeout,
      max_retries: max_retries,
      transfer_acceleration: transfer_acceleration,
      path_style: path_style
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
    no_proxy = Keyword.get(opts, :no_proxy, [])

    case proxy do
      nil ->
        # Fallback to env vars
        case OmHttp.Proxy.from_env() do
          {:ok, %OmHttp.Proxy{host: host, auth: auth, no_proxy: env_no_proxy}} ->
            {host, auth, env_no_proxy}

          :no_proxy ->
            {nil, nil, []}
        end

      url when is_binary(url) ->
        # Parse URL format using OmHttp.Proxy
        case OmHttp.Proxy.parse(url) do
          {:ok, %OmHttp.Proxy{host: host, auth: url_auth}} ->
            # Explicit proxy_auth takes precedence over URL-embedded auth
            {host, proxy_auth || url_auth, no_proxy}

          {:error, _} ->
            {nil, nil, []}
        end

      {host, port} when is_binary(host) and is_integer(port) ->
        {{:http, host, port, []}, proxy_auth, no_proxy}

      {:http, _host, _port, _opts} = full_proxy ->
        {full_proxy, proxy_auth, no_proxy}
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

  Checks `S3_*` vars first (provider-agnostic), then falls back to `AWS_*`:

  - `S3_ACCESS_KEY_ID` / `AWS_ACCESS_KEY_ID` - Access key (required)
  - `S3_SECRET_ACCESS_KEY` / `AWS_SECRET_ACCESS_KEY` - Secret key (required)
  - `S3_REGION` / `AWS_REGION` / `AWS_DEFAULT_REGION` - Region (default: "us-east-1")
  - `S3_ENDPOINT` / `AWS_ENDPOINT_URL_S3` / `AWS_ENDPOINT` - Custom endpoint
  - `HTTP_PROXY` or `HTTPS_PROXY` - Proxy URL (optional, fallback)

  Proxy is resolved in priority order: app config > env vars (HTTP_PROXY/HTTPS_PROXY)

  ## Examples

      # AWS:
      # AWS_ACCESS_KEY_ID=AKIA...
      # AWS_SECRET_ACCESS_KEY=...
      # AWS_REGION=us-east-1

      # R2/MinIO (provider-agnostic):
      # S3_ACCESS_KEY_ID=...
      # S3_SECRET_ACCESS_KEY=...
      # S3_ENDPOINT=https://account.r2.cloudflarestorage.com

      config = Config.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    alias FnTypes.Config, as: Cfg

    new(
      access_key_id: Cfg.string!(["S3_ACCESS_KEY_ID", "AWS_ACCESS_KEY_ID"]),
      secret_access_key: Cfg.string!(["S3_SECRET_ACCESS_KEY", "AWS_SECRET_ACCESS_KEY"]),
      region: Cfg.string(["S3_REGION", "AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1"),
      endpoint: Cfg.string(["S3_ENDPOINT", "AWS_ENDPOINT_URL_S3", "AWS_ENDPOINT"])
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

    # Only add proxy if the S3 endpoint should not bypass it (respects NO_PROXY)
    s3_host = extract_s3_host(config)
    proxy_config = %OmHttp.Proxy{host: config.proxy, auth: config.proxy_auth, no_proxy: config.no_proxy}

    case OmHttp.Proxy.should_bypass?(proxy_config, s3_host) do
      true -> opts
      false -> maybe_add_proxy(opts, config.proxy, config.proxy_auth)
    end
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

    # Custom endpoint takes precedence; acceleration only applies to AWS
    case config.endpoint do
      nil -> maybe_add_acceleration(opts, config.transfer_acceleration, bucket)
      endpoint -> maybe_add_endpoint(opts, endpoint)
    end
  end

  @doc """
  Returns the S3 endpoint URL for the given configuration and bucket.

  Handles Transfer Acceleration endpoints when enabled.

  ## Examples

      Config.endpoint_url(config, "my-bucket")
      #=> "https://my-bucket.s3.us-east-1.amazonaws.com"

      # With Transfer Acceleration
      Config.endpoint_url(%{config | transfer_acceleration: true}, "my-bucket")
      #=> "https://my-bucket.s3-accelerate.amazonaws.com"
  """
  @spec endpoint_url(t(), String.t()) :: String.t()
  def endpoint_url(%__MODULE__{endpoint: endpoint, path_style: true}, bucket)
      when not is_nil(endpoint) do
    String.trim_trailing(endpoint, "/") <> "/#{bucket}"
  end

  def endpoint_url(%__MODULE__{endpoint: endpoint}, _bucket) when not is_nil(endpoint) do
    endpoint
  end

  def endpoint_url(%__MODULE__{transfer_acceleration: true}, bucket) do
    "https://#{bucket}.s3-accelerate.amazonaws.com"
  end

  def endpoint_url(%__MODULE__{region: region, path_style: true}, bucket) do
    "https://s3.#{region}.amazonaws.com/#{bucket}"
  end

  def endpoint_url(%__MODULE__{region: region}, bucket) do
    "https://#{bucket}.s3.#{region}.amazonaws.com"
  end

  @doc """
  Checks if Transfer Acceleration is enabled for this configuration.
  """
  @spec transfer_acceleration?(t()) :: boolean()
  def transfer_acceleration?(%__MODULE__{transfer_acceleration: accel}), do: accel

  @doc """
  Checks if the configuration targets an AWS S3 endpoint.

  Returns `true` when no custom endpoint is set (defaults to AWS) or when the
  endpoint contains `amazonaws.com`. Returns `false` for non-AWS endpoints
  like R2, MinIO, or DigitalOcean Spaces.
  """
  @spec aws_endpoint?(t()) :: boolean()
  def aws_endpoint?(%__MODULE__{endpoint: nil}), do: true
  def aws_endpoint?(%__MODULE__{endpoint: ep}), do: String.contains?(ep, "amazonaws.com")

  # ============================================
  # Private Helpers
  # ============================================

  defp extract_s3_host(%__MODULE__{endpoint: nil, region: region}) do
    "s3.#{region}.amazonaws.com"
  end

  defp extract_s3_host(%__MODULE__{endpoint: endpoint}) do
    case URI.parse(endpoint) do
      %{host: host} when is_binary(host) -> host
      _ -> "s3.amazonaws.com"
    end
  end

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

  defp maybe_add_acceleration(opts, false, _bucket), do: opts

  defp maybe_add_acceleration(opts, true, bucket) do
    # Use Transfer Acceleration endpoint for presigned URLs
    accel_endpoint = "https://#{bucket}.s3-accelerate.amazonaws.com"
    Keyword.put(opts, :aws_endpoint_url_s3, accel_endpoint)
  end
end
