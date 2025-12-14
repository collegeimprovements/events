defmodule Events.Services.Aws do
  @moduledoc """
  AWS service helpers.

  **Note:** For S3 operations, use `Events.Services.S3` directly which provides
  a clean, unified API with pipeline support.

  ## S3 Usage

      alias Events.Services.S3

      # From environment
      S3.from_env()
      |> S3.bucket("my-bucket")
      |> S3.get("file.txt")

      # Or direct API
      config = S3.Config.from_env()
      S3.get("s3://bucket/file.txt", config)

  ## Environment Variables

  - `AWS_ACCESS_KEY_ID` - Your AWS access key
  - `AWS_SECRET_ACCESS_KEY` - Your AWS secret key
  - `AWS_REGION` - Default region (default: "us-east-1")
  - `S3_BUCKET` - Default bucket name
  - `AWS_ENDPOINT_URL_S3` - Custom S3 endpoint (for LocalStack, MinIO)
  """

  @type connection :: %{
          key: String.t(),
          secret: String.t(),
          region: String.t(),
          endpoint: String.t() | nil
        }

  @type connection_or_nil :: connection() | nil

  @doc """
  Connects to AWS with explicit credentials.

  Returns a connection map. For S3 operations, prefer using
  `Events.Services.S3.Config.new/1` directly.

  ## Options

  - `:key` - AWS access key ID (required)
  - `:secret` - AWS secret access key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:endpoint` - Custom endpoint for LocalStack/MinIO (optional)
  """
  @spec connect(keyword()) :: connection()
  def connect(opts) do
    %{
      key: Keyword.fetch!(opts, :key),
      secret: Keyword.fetch!(opts, :secret),
      region: Keyword.get(opts, :region, "us-east-1"),
      endpoint: Keyword.get(opts, :endpoint)
    }
  end

  @doc """
  Checks if AWS credentials are configured.
  """
  @spec configured?(connection_or_nil()) :: boolean()
  def configured?(nil) do
    alias FnTypes.Config, as: Cfg
    Cfg.present?("AWS_ACCESS_KEY_ID") and Cfg.present?("AWS_SECRET_ACCESS_KEY")
  end

  def configured?(%{key: key, secret: secret}) do
    not is_nil(key) and not is_nil(secret)
  end

  @doc """
  Gets the current AWS region.
  """
  @spec region(connection_or_nil()) :: String.t()
  def region(nil) do
    alias FnTypes.Config, as: Cfg
    Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"], "us-east-1")
  end

  def region(%{region: region}), do: region

  @doc """
  Converts connection to S3 Config.

  ## Examples

      conn = Aws.connect(key: "...", secret: "...")
      config = Aws.to_s3_config(conn)
      S3.get("s3://bucket/file.txt", config)
  """
  @spec to_s3_config(connection_or_nil()) :: Events.Services.S3.Config.t()
  def to_s3_config(nil) do
    Events.Services.S3.Config.from_env()
  end

  def to_s3_config(%{key: key, secret: secret, region: region, endpoint: endpoint}) do
    Events.Services.S3.Config.new(
      access_key_id: key,
      secret_access_key: secret,
      region: region,
      endpoint: endpoint
    )
  end
end
