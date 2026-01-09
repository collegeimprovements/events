defmodule OmStripe.Config do
  @moduledoc """
  Configuration for the Stripe API client.

  ## Usage

      config = Config.new(api_key: "sk_test_...")
      config = Config.new(api_key: "sk_test_...", api_version: "2023-10-16")
      config = Config.from_env()

  ## Options

  - `:api_key` - Stripe API key (required)
  - `:api_version` - Stripe API version (default: "2024-10-28.acacia")
  - `:connect_account` - Connected account ID for Stripe Connect
  - `:idempotency_key` - Default idempotency key prefix
  - `:timeout` - Connect timeout in ms (default: 30000)
  - `:receive_timeout` - Receive timeout in ms (default: 60000)
  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:proxy` - Proxy URL (e.g., `"http://user:pass@proxy:8080"`) or tuple
  - `:proxy_auth` - Proxy auth as `{username, password}` (if not in URL)

  ## Proxy Configuration

  Proxy is resolved in priority order:

  1. Explicit `:proxy` option in `new/1`
  2. Application config: `config :om_stripe, proxy: "..."`
  3. Fallback to OmApiClient config or HTTP_PROXY env var
  """

  @type t :: %__MODULE__{
          api_key: String.t(),
          api_version: String.t(),
          connect_account: String.t() | nil,
          idempotency_key_prefix: String.t() | nil,
          timeout: pos_integer(),
          receive_timeout: pos_integer(),
          max_retries: non_neg_integer(),
          proxy: String.t() | {String.t(), pos_integer()} | nil,
          proxy_auth: {String.t(), String.t()} | nil
        }

  @default_api_version "2024-10-28.acacia"
  @default_timeout 30_000
  @default_receive_timeout 60_000
  @default_max_retries 3

  @enforce_keys [:api_key]
  defstruct [
    :api_key,
    :connect_account,
    :idempotency_key_prefix,
    :proxy,
    :proxy_auth,
    api_version: @default_api_version,
    timeout: @default_timeout,
    receive_timeout: @default_receive_timeout,
    max_retries: @default_max_retries
  ]

  @doc """
  Creates a new Stripe configuration.

  ## Examples

      Config.new(api_key: "sk_test_...")
      Config.new(api_key: "sk_test_...", api_version: "2023-10-16")
      Config.new(api_key: "sk_test_...", proxy: "http://proxy:8080")
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    {proxy, proxy_auth} = resolve_proxy(opts)
    timeout = validate_timeout!(Keyword.get(opts, :timeout, @default_timeout), :timeout)
    receive_timeout = validate_timeout!(Keyword.get(opts, :receive_timeout, @default_receive_timeout), :receive_timeout)

    %__MODULE__{
      api_key: Keyword.fetch!(opts, :api_key),
      api_version: Keyword.get(opts, :api_version, @default_api_version),
      connect_account: Keyword.get(opts, :connect_account),
      idempotency_key_prefix: Keyword.get(opts, :idempotency_key_prefix),
      timeout: timeout,
      receive_timeout: receive_timeout,
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      proxy: proxy,
      proxy_auth: proxy_auth
    }
  end

  defp validate_timeout!(ms, _field) when is_integer(ms) and ms > 0, do: ms

  defp validate_timeout!(ms, field) do
    raise ArgumentError, "#{field} must be a positive integer, got: #{inspect(ms)}"
  end

  defp resolve_proxy(opts) do
    # Priority: explicit option > app config > env vars
    proxy = Keyword.get(opts, :proxy) || get_app_config_proxy()
    proxy_auth = Keyword.get(opts, :proxy_auth) || get_app_config_proxy_auth()

    case {proxy, proxy_auth} do
      {nil, _} ->
        # Try env vars via OmHttp.Proxy
        case OmHttp.Proxy.from_env() do
          {:ok, %OmHttp.Proxy{host: host, auth: auth}} -> {host, auth}
          :no_proxy -> {nil, nil}
        end

      {url, nil} when is_binary(url) ->
        # Parse URL to extract embedded auth
        case OmHttp.Proxy.parse(url) do
          {:ok, %OmHttp.Proxy{host: host, auth: auth}} -> {host, auth}
          {:error, _} -> {nil, nil}
        end

      {proxy, auth} ->
        {proxy, auth}
    end
  end

  defp get_app_config_proxy do
    Application.get_env(:om_stripe, :proxy) ||
      Application.get_env(:om_stripe, OmStripe)[:proxy]
  end

  defp get_app_config_proxy_auth do
    Application.get_env(:om_stripe, :proxy_auth) ||
      Application.get_env(:om_stripe, OmStripe)[:proxy_auth]
  end

  @doc """
  Creates configuration from environment variables.

  ## Environment Variables

  - `STRIPE_API_KEY` or `STRIPE_SECRET_KEY` - API key (required)
  - `STRIPE_API_VERSION` - API version (optional)
  - `STRIPE_CONNECT_ACCOUNT` - Connected account ID (optional)
  - `HTTP_PROXY` or `HTTPS_PROXY` - Proxy URL (optional, fallback)

  Proxy is resolved in priority order: app config > env vars (HTTP_PROXY/HTTPS_PROXY)

  ## Examples

      config = Config.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    alias FnTypes.Config, as: Cfg

    new(
      api_key:
        Cfg.string!(["STRIPE_API_KEY", "STRIPE_SECRET_KEY"],
          message: "STRIPE_API_KEY or STRIPE_SECRET_KEY must be set"
        ),
      api_version: Cfg.string("STRIPE_API_VERSION", @default_api_version),
      connect_account: Cfg.string("STRIPE_CONNECT_ACCOUNT")
      # proxy is resolved automatically via resolve_proxy/1 in new/1
    )
  end

  @doc """
  Creates a config for a specific connected account.

  ## Examples

      config
      |> Config.for_account("acct_123")
  """
  @spec for_account(t(), String.t()) :: t()
  def for_account(%__MODULE__{} = config, account_id) when is_binary(account_id) do
    %{config | connect_account: account_id}
  end

  @doc """
  Checks if running in test mode based on API key prefix.

  ## Examples

      Config.test_mode?(config)
      #=> true  # if api_key starts with "sk_test_"
  """
  @spec test_mode?(t()) :: boolean()
  def test_mode?(%__MODULE__{api_key: "sk_test_" <> _}), do: true
  def test_mode?(%__MODULE__{api_key: "rk_test_" <> _}), do: true
  def test_mode?(%__MODULE__{}), do: false

  @doc """
  Checks if running in live mode based on API key prefix.

  ## Examples

      Config.live_mode?(config)
      #=> true  # if api_key starts with "sk_live_"
  """
  @spec live_mode?(t()) :: boolean()
  def live_mode?(%__MODULE__{api_key: "sk_live_" <> _}), do: true
  def live_mode?(%__MODULE__{api_key: "rk_live_" <> _}), do: true
  def live_mode?(%__MODULE__{}), do: false
end
