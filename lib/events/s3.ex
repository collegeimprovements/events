defmodule Events.S3 do
  @moduledoc """
  S3 storage service with a simplified, flat API.

  This module provides S3 operations with automatic adapter selection.
  Use Production adapter by default, or configure alternatives for testing.

  ## Usage

      # Create config
      config = AWSConfig.new(
        access_key_id: "...",
        secret_access_key: "...",
        region: "us-east-1",
        bucket: "my-bucket"
      )

      # Upload file
      S3.upload(config, "path/to/file.txt", "Hello, World!")

      # Generate signed URL
      {:ok, url} = S3.presigned_url(config, :get, "path/to/file.txt", expires_in: 3600)

      # List files
      {:ok, files} = S3.list_objects(config, prefix: "uploads/")

      # Download file
      {:ok, content} = S3.get_object(config, "path/to/file.txt")

  ## Configuration

  Set the adapter in config:

      config :events, :s3_adapter, Events.S3.Mock  # For testing
      config :events, :s3_adapter, Events.S3.Production  # Default
  """

  @behaviour Events.Behaviours.Service

  alias Events.AWSConfig

  @type config :: AWSConfig.t()
  @type key :: String.t()
  @type content :: binary() | iodata()
  @type metadata :: %{optional(String.t()) => String.t()}

  @type upload_opts :: [
          content_type: String.t(),
          metadata: metadata(),
          acl: String.t(),
          storage_class: String.t()
        ]

  @type presign_opts :: [
          expires_in: pos_integer(),
          query_params: keyword(),
          virtual_host: boolean()
        ]

  @type list_opts :: [
          prefix: String.t(),
          max_keys: pos_integer(),
          continuation_token: String.t(),
          sort_by: :last_modified | :size | :key,
          sort_order: :asc | :desc
        ]

  @type object_info :: %{
          key: key(),
          size: non_neg_integer(),
          last_modified: DateTime.t(),
          etag: String.t(),
          storage_class: String.t()
        }

  ## Behaviour Callbacks

  @doc """
  Uploads an object to S3.

  ## Options

  - `:content_type` - MIME type (default: "application/octet-stream")
  - `:metadata` - Custom metadata map
  - `:acl` - Access control ("private", "public-read", etc.)
  - `:storage_class` - Storage class ("STANDARD", "GLACIER", etc.)
  """
  @callback upload(config(), key(), content(), upload_opts()) :: :ok | {:error, term()}

  @doc """
  Downloads an object from S3.
  """
  @callback get_object(config(), key()) :: {:ok, binary()} | {:error, term()}

  @doc """
  Deletes an object from S3.
  """
  @callback delete_object(config(), key()) :: :ok | {:error, term()}

  @doc """
  Checks if an object exists in S3.
  """
  @callback object_exists?(config(), key()) :: {:ok, boolean()} | {:error, term()}

  @doc """
  Lists objects in a bucket with optional prefix filtering and sorting.
  """
  @callback list_objects(config(), list_opts()) ::
              {:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}
              | {:error, term()}

  @doc """
  Generates a presigned URL for uploading or downloading.
  """
  @callback presigned_url(config(), :get | :put, key(), presign_opts()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Copies an object within S3.
  """
  @callback copy_object(config(), source_key :: key(), dest_key :: key()) ::
              :ok | {:error, term()}

  @doc """
  Gets object metadata without downloading the content.
  """
  @callback head_object(config(), key()) :: {:ok, map()} | {:error, term()}

  ## Public API

  @doc """
  Gets the configured adapter module.

  Defaults to the Production adapter if not configured.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:events, :s3_adapter, Events.S3.Production)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec upload(config(), key(), content(), upload_opts()) :: :ok | {:error, term()}
  def upload(config, key, content, opts \\ []) do
    adapter().upload(config, key, content, opts)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec get_object(config(), key()) :: {:ok, binary()} | {:error, term()}
  def get_object(config, key) do
    adapter().get_object(config, key)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec delete_object(config(), key()) :: :ok | {:error, term()}
  def delete_object(config, key) do
    adapter().delete_object(config, key)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec object_exists?(config(), key()) :: {:ok, boolean()} | {:error, term()}
  def object_exists?(config, key) do
    adapter().object_exists?(config, key)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec list_objects(config(), list_opts()) ::
          {:ok, %{objects: [object_info()], continuation_token: String.t() | nil}}
          | {:error, term()}
  def list_objects(config, opts \\ []) do
    adapter().list_objects(config, opts)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec presigned_url(config(), :get | :put, key(), presign_opts()) ::
          {:ok, String.t()} | {:error, term()}
  def presigned_url(config, method, key, opts \\ []) do
    adapter().presigned_url(config, method, key, opts)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec copy_object(config(), key(), key()) :: :ok | {:error, term()}
  def copy_object(config, source_key, dest_key) do
    adapter().copy_object(config, source_key, dest_key)
  end

  @doc "Delegates to adapter - see callback documentation"
  @spec head_object(config(), key()) :: {:ok, map()} | {:error, term()}
  def head_object(config, key) do
    adapter().head_object(config, key)
  end

  ## Helper Functions

  @doc """
  Uploads a file from the filesystem.

  ## Examples

      S3.upload_file(config, "document.pdf", "/tmp/report.pdf")
  """
  @spec upload_file(config(), key(), Path.t(), upload_opts()) :: :ok | {:error, term()}
  def upload_file(config, key, file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path) do
      content_type = opts[:content_type] || MIME.from_path(file_path)
      upload(config, key, content, Keyword.put(opts, :content_type, content_type))
    end
  end

  @doc """
  Downloads an object and writes it to a file.

  ## Examples

      S3.download_to_file(config, "document.pdf", "/tmp/downloaded.pdf")
  """
  @spec download_to_file(config(), key(), Path.t()) :: :ok | {:error, term()}
  def download_to_file(config, key, file_path) do
    with {:ok, content} <- get_object(config, key) do
      File.write(file_path, content)
    end
  end

  @doc """
  Normalizes a file name for S3 storage.

  ## Examples

      iex> S3.normalize_filename("User's Photo (1).jpg")
      "users-photo-1.jpg"

      iex> S3.normalize_filename("file.txt", prefix: "uploads", add_timestamp: true)
      "uploads/file-20240112-143022.txt"
  """
  @spec normalize_filename(String.t(), keyword()) :: String.t()
  def normalize_filename(filename, opts \\ []) do
    Events.S3.FileNameNormalizer.normalize(filename, opts)
  end

  @doc """
  Validates required S3 configuration fields.
  """
  @spec validate_config(config()) :: :ok | {:error, atom()}
  def validate_config(%AWSConfig{} = config) do
    with {:ok, _} <- AWSConfig.validate(config) do
      if config.bucket do
        :ok
      else
        {:error, :missing_bucket}
      end
    end
  end
end