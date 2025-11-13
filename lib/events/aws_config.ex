defmodule Events.AWSConfig do
  @moduledoc """
  AWS configuration for services.

  This struct holds all necessary AWS configuration for making API calls.
  It should be passed to all AWS service functions.

  ## Fields

  - `:access_key_id` - AWS access key ID
  - `:secret_access_key` - AWS secret access key
  - `:region` - AWS region (e.g., "us-east-1")
  - `:bucket` - Default S3 bucket (optional)
  - `:endpoint` - Custom endpoint URL (optional, for LocalStack, Minio, etc.)
  - `:scheme` - HTTP scheme ("https" or "http")
  - `:port` - Custom port (optional)
  - `:metadata` - Additional metadata

  ## Usage

      # From application config
      config = AWSConfig.from_config()

      # Manual construction
      config = AWSConfig.new(
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        bucket: "my-bucket"
      )

      # With custom endpoint (LocalStack)
      config = AWSConfig.new(
        access_key_id: "test",
        secret_access_key: "test",
        region: "us-east-1",
        endpoint: "http://localhost:4566",
        scheme: "http"
      )
  """

  @type t :: %__MODULE__{
          access_key_id: String.t(),
          secret_access_key: String.t(),
          region: String.t(),
          bucket: String.t() | nil,
          endpoint: String.t() | nil,
          endpoint_url: String.t() | nil,
          scheme: String.t(),
          port: integer() | nil,
          metadata: map()
        }

  @enforce_keys [:access_key_id, :secret_access_key, :region]
  defstruct access_key_id: nil,
            secret_access_key: nil,
            region: nil,
            bucket: nil,
            endpoint: nil,
            endpoint_url: nil,
            scheme: "https",
            port: nil,
            metadata: %{}

  @doc """
  Creates a new AWS configuration.

  ## Options

  - `:access_key_id` - AWS access key ID (required)
  - `:secret_access_key` - AWS secret access key (required)
  - `:region` - AWS region (required)
  - `:bucket` - Default S3 bucket
  - `:endpoint` - Custom endpoint URL
  - `:scheme` - HTTP scheme (default: "https")
  - `:port` - Custom port

  ## Examples

      iex> AWSConfig.new(
      ...>   access_key_id: "key",
      ...>   secret_access_key: "secret",
      ...>   region: "us-east-1"
      ...> )
      %AWSConfig{...}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    config = struct!(__MODULE__, opts)

    # Build endpoint_url if endpoint is provided
    if config.endpoint do
      %{config | endpoint_url: build_endpoint_url(config)}
    else
      config
    end
  end

  @doc """
  Creates configuration from application config.

  Reads from `:events, :aws` configuration.

  ## Examples

      # In config.exs:
      config :events, :aws,
        access_key_id: "...",
        secret_access_key: "...",
        region: "us-east-1",
        bucket: "my-bucket"

      # In code:
      config = AWSConfig.from_config()
  """
  @spec from_config() :: t()
  def from_config do
    Application.get_env(:events, :aws, [])
    |> new()
  end

  @doc """
  Creates configuration from environment variables.

  Reads from:
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - AWS_DEFAULT_REGION or AWS_REGION
  - AWS_S3_BUCKET
  - AWS_ENDPOINT

  ## Examples

      config = AWSConfig.from_env()
  """
  @spec from_env() :: t()
  def from_env do
    opts =
      [
        access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
        region: System.get_env("AWS_DEFAULT_REGION") || System.get_env("AWS_REGION"),
        bucket: System.get_env("AWS_S3_BUCKET"),
        endpoint: System.get_env("AWS_ENDPOINT")
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    new(opts)
  end

  @doc """
  Updates the configuration with a specific bucket.

  ## Examples

      config
      |> AWSConfig.with_bucket("other-bucket")
      |> S3.upload("file.txt", content)
  """
  @spec with_bucket(t(), String.t()) :: t()
  def with_bucket(%__MODULE__{} = config, bucket) when is_binary(bucket) do
    %{config | bucket: bucket}
  end

  @doc """
  Updates the configuration with a specific region.

  ## Examples

      config
      |> AWSConfig.with_region("eu-west-1")
      |> S3.upload("file.txt", content)
  """
  @spec with_region(t(), String.t()) :: t()
  def with_region(%__MODULE__{} = config, region) when is_binary(region) do
    %{config | region: region}
  end

  @doc """
  Validates the configuration.

  Returns `{:ok, config}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> AWSConfig.validate(config)
      {:ok, config}

      iex> AWSConfig.validate(%AWSConfig{})
      {:error, :missing_access_key_id}
  """
  @spec validate(t()) :: {:ok, t()} | {:error, atom()}
  def validate(%__MODULE__{} = config) do
    cond do
      is_nil(config.access_key_id) or config.access_key_id == "" ->
        {:error, :missing_access_key_id}

      is_nil(config.secret_access_key) or config.secret_access_key == "" ->
        {:error, :missing_secret_access_key}

      is_nil(config.region) or config.region == "" ->
        {:error, :missing_region}

      true ->
        {:ok, config}
    end
  end

  @doc """
  Validates the configuration, raising on error.

  ## Examples

      config = AWSConfig.validate!(config)
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    case validate(config) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid AWS config: #{reason}"
    end
  end

  ## Private Functions

  defp build_endpoint_url(%{endpoint: endpoint, scheme: scheme, port: port}) do
    uri = URI.parse(endpoint)

    uri = %{uri | scheme: scheme || uri.scheme || "https"}

    if port do
      %{uri | port: port}
    else
      uri
    end
    |> URI.to_string()
  end
end
