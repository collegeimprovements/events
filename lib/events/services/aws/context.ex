defmodule Events.Services.Aws.Context do
  @moduledoc """
  AWS service context containing credentials and configuration.

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
      context = Context.from_config()

      # Manual construction
      context = Context.new(
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        bucket: "my-bucket"
      )

      # With custom endpoint (LocalStack)
      context = Context.new(
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

  defstruct [
    :access_key_id,
    :secret_access_key,
    :region,
    :bucket,
    :endpoint,
    :endpoint_url,
    :port,
    scheme: "https",
    metadata: %{}
  ]

  @doc """
  Creates a new AWS context.

  ## Options

  - `:access_key_id` - AWS access key ID (required)
  - `:secret_access_key` - AWS secret access key (required)
  - `:region` - AWS region (default: "us-east-1")
  - `:bucket` - Default S3 bucket (optional)
  - `:endpoint` - Custom endpoint URL (optional)
  - `:scheme` - HTTP scheme (default: "https")
  - `:port` - Custom port (optional)

  ## Examples

      iex> Context.new(
      ...>   access_key_id: "AKIAIOSFODNN7EXAMPLE",
      ...>   secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      ...> )
      %Context{...}
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    endpoint = Keyword.get(opts, :endpoint)
    endpoint_url = Keyword.get(opts, :endpoint_url, endpoint)

    %__MODULE__{
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, "us-east-1"),
      bucket: Keyword.get(opts, :bucket),
      endpoint: endpoint,
      endpoint_url: endpoint_url,
      scheme: Keyword.get(opts, :scheme, "https"),
      port: Keyword.get(opts, :port),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a context from application configuration.

  Reads configuration from `:events, :aws` application env.

  ## Configuration

      config :events, :aws,
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        bucket: "my-bucket"

  ## Examples

      iex> Context.from_config()
      %Context{...}
  """
  @spec from_config() :: t()
  def from_config do
    opts = Application.get_env(:events, :aws, [])
    new(opts)
  end

  @doc """
  Creates a context from system environment variables.

  Reads from:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION` (default: "us-east-1")
  - `AWS_S3_BUCKET` (optional)
  - `AWS_ENDPOINT` (optional)

  ## Examples

      iex> Context.from_env()
      %Context{...}
  """
  @spec from_env() :: t()
  def from_env do
    new(
      access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "us-east-1"),
      bucket: System.get_env("AWS_S3_BUCKET"),
      endpoint: System.get_env("AWS_ENDPOINT")
    )
  end

  @doc """
  Sets the default bucket for this context.

  ## Examples

      iex> context |> Context.with_bucket("my-bucket")
      %Context{bucket: "my-bucket", ...}
  """
  @spec with_bucket(t(), String.t()) :: t()
  def with_bucket(%__MODULE__{} = context, bucket) do
    %{context | bucket: bucket}
  end

  @doc """
  Sets the region for this context.

  ## Examples

      iex> context |> Context.with_region("eu-west-1")
      %Context{region: "eu-west-1", ...}
  """
  @spec with_region(t(), String.t()) :: t()
  def with_region(%__MODULE__{} = context, region) do
    %{context | region: region}
  end

  @doc """
  Adds metadata to the context.

  ## Examples

      iex> context |> Context.with_metadata(%{request_id: "123"})
      %Context{metadata: %{request_id: "123"}, ...}
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = context, metadata) do
    %{context | metadata: Map.merge(context.metadata, metadata)}
  end

  @doc """
  Validates that the context has all required fields.

  Returns {:ok, context} if valid, {:error, reason} if invalid.

  ## Examples

      iex> context |> Context.validate()
      {:ok, context}

      iex> %Context{} |> Context.validate()
      {:error, :missing_access_key_id}
  """
  @spec validate(t()) :: {:ok, t()} | {:error, atom()}
  def validate(%__MODULE__{access_key_id: nil}), do: {:error, :missing_access_key_id}
  def validate(%__MODULE__{secret_access_key: nil}), do: {:error, :missing_secret_access_key}
  def validate(%__MODULE__{region: nil}), do: {:error, :missing_region}
  def validate(%__MODULE__{} = context), do: {:ok, context}
end
