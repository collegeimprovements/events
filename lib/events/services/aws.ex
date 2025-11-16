defmodule Events.Services.Aws do
  @moduledoc """
  Clean, simple AWS service client.

  A radically simplified API for AWS services with focus on:
  - **Zero configuration** - Works with ENV variables out of the box
  - **Clear naming** - Obvious function names, no acronyms
  - **Minimal setup** - One-line initialization
  - **Pipeline friendly** - All operations support `|>` operator
  - **Error handling** - Consistent {:ok, result} | {:error, reason} pattern

  ## Quick Start

      # Zero config - uses ENV variables
      AWS.S3.list("my-bucket")
      AWS.S3.upload("my-bucket", "photo.jpg", file_content)
      AWS.S3.download("my-bucket", "photo.jpg")

      # With explicit credentials (optional)
      aws = AWS.connect(
        key: "AKIAIOSFODNN7EXAMPLE",
        secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
      )

      AWS.S3.list(aws, "my-bucket")

  ## Philosophy

  1. **Simple beats complex** - No context structs, no adapter pattern complexity
  2. **Obvious naming** - `list` not `list_objects`, `upload` not `put_object`
  3. **Sensible defaults** - Common use cases work with minimal options
  4. **Progressive disclosure** - Simple things simple, complex things possible

  ## Environment Variables

  The client automatically uses these ENV variables:

  - `AWS_ACCESS_KEY_ID` - Your AWS access key
  - `AWS_SECRET_ACCESS_KEY` - Your AWS secret key
  - `AWS_REGION` - Default region (default: "us-east-1")
  - `AWS_DEFAULT_REGION` - Alternative region variable
  - `S3_BUCKET` - Default bucket name
  - `AWS_ENDPOINT_URL` - Custom endpoint (for LocalStack, MinIO)
  """

  alias Events.Services.Aws.Context

  @type connection :: %{
          key: String.t(),
          secret: String.t(),
          region: String.t(),
          endpoint: String.t() | nil
        }

  @type connection_or_nil :: connection() | nil

  @doc """
  Connects to AWS with explicit credentials.

  Returns a connection struct that can be passed to AWS service functions.
  If not provided, functions will use ENV variables automatically.

  ## Options

  - `:key` - AWS access key ID (required)
  - `:secret` - AWS secret access key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:endpoint` - Custom endpoint for LocalStack/MinIO (optional)

  ## Examples

      # Production credentials
      aws = AWS.connect(
        key: "AKIAIOSFODNN7EXAMPLE",
        secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
      )

      # LocalStack for development
      aws = AWS.connect(
        key: "test",
        secret: "test",
        region: "us-east-1",
        endpoint: "http://localhost:4566"
      )

      # Use with S3
      AWS.S3.list(aws, "my-bucket")
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

  Looks for credentials in ENV variables or provided connection.

  ## Examples

      AWS.configured?()
      #=> true if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set

      AWS.configured?(aws)
      #=> true if connection is valid
  """
  @spec configured?(connection_or_nil()) :: boolean()
  def configured?(nil) do
    not is_nil(System.get_env("AWS_ACCESS_KEY_ID")) and
      not is_nil(System.get_env("AWS_SECRET_ACCESS_KEY"))
  end

  def configured?(%{key: key, secret: secret}) do
    not is_nil(key) and not is_nil(secret)
  end

  @doc """
  Gets the current AWS region.

  ## Examples

      AWS.region()
      #=> "us-east-1"

      AWS.region(aws)
      #=> "us-west-2"
  """
  @spec region(connection_or_nil()) :: String.t()
  def region(nil) do
    System.get_env("AWS_REGION") ||
      System.get_env("AWS_DEFAULT_REGION") ||
      "us-east-1"
  end

  def region(%{region: region}), do: region

  # Internal: Convert simple connection to Context for adapter compatibility
  @doc false
  def to_context(conn_or_nil, opts \\ [])

  def to_context(nil, opts) do
    Context.new(
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: region(nil),
      bucket: Keyword.get(opts, :bucket),
      endpoint: System.get_env("AWS_ENDPOINT_URL")
    )
  end

  def to_context(%{key: key, secret: secret, region: region, endpoint: endpoint}, opts) do
    Context.new(
      access_key_id: key,
      secret_access_key: secret,
      region: region,
      bucket: Keyword.get(opts, :bucket),
      endpoint: endpoint
    )
  end
end
