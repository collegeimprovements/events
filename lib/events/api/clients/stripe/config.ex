defmodule Events.Api.Clients.Stripe.Config do
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
  - `:timeout` - Request timeout in ms (default: 30000)
  - `:max_retries` - Maximum retry attempts (default: 3)
  """

  @type t :: %__MODULE__{
          api_key: String.t(),
          api_version: String.t(),
          connect_account: String.t() | nil,
          idempotency_key_prefix: String.t() | nil,
          timeout: pos_integer(),
          max_retries: non_neg_integer()
        }

  @default_api_version "2024-10-28.acacia"
  @default_timeout 30_000
  @default_max_retries 3

  @enforce_keys [:api_key]
  defstruct [
    :api_key,
    :connect_account,
    :idempotency_key_prefix,
    api_version: @default_api_version,
    timeout: @default_timeout,
    max_retries: @default_max_retries
  ]

  @doc """
  Creates a new Stripe configuration.

  ## Examples

      Config.new(api_key: "sk_test_...")
      Config.new(api_key: "sk_test_...", api_version: "2023-10-16")
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      api_key: Keyword.fetch!(opts, :api_key),
      api_version: Keyword.get(opts, :api_version, @default_api_version),
      connect_account: Keyword.get(opts, :connect_account),
      idempotency_key_prefix: Keyword.get(opts, :idempotency_key_prefix),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries)
    }
  end

  @doc """
  Creates configuration from environment variables.

  ## Environment Variables

  - `STRIPE_API_KEY` or `STRIPE_SECRET_KEY` - API key (required)
  - `STRIPE_API_VERSION` - API version (optional)
  - `STRIPE_CONNECT_ACCOUNT` - Connected account ID (optional)

  ## Examples

      config = Config.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    api_key =
      System.get_env("STRIPE_API_KEY") ||
        System.get_env("STRIPE_SECRET_KEY") ||
        raise "STRIPE_API_KEY or STRIPE_SECRET_KEY must be set"

    new(
      api_key: api_key,
      api_version: System.get_env("STRIPE_API_VERSION") || @default_api_version,
      connect_account: System.get_env("STRIPE_CONNECT_ACCOUNT")
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
